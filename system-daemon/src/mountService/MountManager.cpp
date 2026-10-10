#include "MountManager.hpp"
#include "log.hpp"

#include <glib/gstdio.h>

#include <memory>

namespace ciel {

namespace {

/* ------------------------------------------------------------------ */
/* Config (persisted AutoMount setting)                                */
/* ------------------------------------------------------------------ */

std::string configPath()
{
    return takeString(g_build_filename(g_get_user_config_dir(), "ciel-mountd", "config.ini", nullptr));
}

bool loadAutoMount()
{
    bool value = true; /* default: ON */
    GKeyFile *kf = g_key_file_new();
    if (g_key_file_load_from_file(kf, configPath().c_str(), G_KEY_FILE_NONE, nullptr)) {
        GErr err;
        gboolean b = g_key_file_get_boolean(kf, "General", "auto_mount", err.out());
        if (!err)
            value = b;
    }
    g_key_file_unref(kf);
    return value;
}

void saveAutoMount(bool value)
{
    std::string path = configPath();
    std::string dir = takeString(g_path_get_dirname(path.c_str()));
    g_mkdir_with_parents(dir.c_str(), 0700);

    GKeyFile *kf = g_key_file_new();
    g_key_file_set_boolean(kf, "General", "auto_mount", value);
    GErr err;
    if (!g_key_file_save_to_file(kf, path.c_str(), err.out()))
        LOG_WARN("Could not save config %s: %s", path.c_str(), err.message().c_str());
    g_key_file_unref(kf);
}

/* ------------------------------------------------------------------ */
/* Identification helpers                                              */
/* ------------------------------------------------------------------ */

bool isRemovableScheme(const std::string &s)
{
    return s == "mtp" || s == "gphoto2" || s == "afc";
}

std::string schemeOf(GFile *f)
{
    return takeString(g_file_get_uri_scheme(f));
}

/* Local files -> path, everything else -> URI. */
std::string fileKey(GFile *f)
{
    if (schemeOf(f) == "file") {
        if (char *p = g_file_get_path(f))
            return takeString(p);
    }
    return takeString(g_file_get_uri(f));
}

std::string mountPointOf(GFile *root)
{
    if (char *p = g_file_get_path(root)) /* gvfs-fuse path for MTP etc. */
        return takeString(p);
    return takeString(g_file_get_uri(root));
}

/* "" if the volume has no unix-device identifier. For gvfs MTP/PTP volumes this
 * is the USB node (/dev/bus/usb/BBB/DDD), for disks it is /dev/sdXN. */
std::string unixDeviceOf(GVolume *v)
{
    return takeString(g_volume_get_identifier(v, G_VOLUME_IDENTIFIER_KIND_UNIX_DEVICE));
}

/* Stable identity used as the "devicePath" on D-Bus. */
std::string volumeKey(GVolume *v)
{
    if (char *id = g_volume_get_identifier(v, G_VOLUME_IDENTIFIER_KIND_UNIX_DEVICE))
        return takeString(id);

    if (GFile *root = g_volume_get_activation_root(v)) {
        GRef<GFile> r(root);
        return fileKey(r.get());
    }

    if (char *uuid = g_volume_get_uuid(v))
        return takeString(uuid);

    return takeString(g_volume_get_name(v));
}

/* Operation that never prompts: password/question/busy dialogs are refused. */
GMountOperation *makeAbortingOperation()
{
    GMountOperation *op = g_mount_operation_new();

    g_signal_connect(op, "ask-password",
        G_CALLBACK(+[](GMountOperation *o, const char *, const char *, const char *,
                       GAskPasswordFlags, gpointer) {
            g_mount_operation_reply(o, G_MOUNT_OPERATION_ABORTED);
        }), nullptr);

    g_signal_connect(op, "ask-question",
        G_CALLBACK(+[](GMountOperation *o, const char *, const char *const *, gpointer) {
            g_mount_operation_reply(o, G_MOUNT_OPERATION_ABORTED);
        }), nullptr);

    g_signal_connect(op, "show-processes",
        G_CALLBACK(+[](GMountOperation *o, const char *, GArray *, const char *const *, gpointer) {
            g_mount_operation_reply(o, G_MOUNT_OPERATION_ABORTED);
        }), nullptr);

    return op;
}

/* Async call contexts */
struct MountCtx {
    MountManager *self;
    std::string key;
    MountManager::DoneCb cb;
    GRef<GVolume> vol; /* keeps the volume alive during the operation */
};

struct EjectCtx {
    MountManager *self;
    std::string key;
    MountManager::DoneCb cb;
    GRef<GMount> mount;
};

struct RoCtx {
    MountManager *self;
    std::string key;
};

struct ProbeCtx {
    MountManager *self;
    std::string key;
    GRef<GFileEnumerator> enumerator;
};

struct TimerCtx {
    MountManager *self;
    std::string key;
};

constexpr guint kProbeIntervalSec = 2;
constexpr gint64 kProbeTimeoutSec = 60;
constexpr int kRemountEveryEmptyProbes = 3;

} // namespace

/* ------------------------------------------------------------------ */
/* Lifecycle                                                           */
/* ------------------------------------------------------------------ */

MountManager::MountManager() : MountManager(Options{}) {}

MountManager::MountManager(Options opts)
    : opts_(opts), autoMount_(loadAutoMount())
{
}

MountManager::~MountManager()
{
    for (auto &kv : probes_) {
        if (kv.second.timer)
            g_source_remove(kv.second.timer);
    }
    if (cancel_)
        g_cancellable_cancel(cancel_.get());
    if (monitor_) {
        for (gulong id : handlers_)
            g_signal_handler_disconnect(monitor_.get(), id);
    }
}

void MountManager::start()
{
    cancel_.reset(g_cancellable_new());
    monitor_.reset(g_volume_monitor_get());

    auto connect = [this](const char *sig, GCallback cb) {
        handlers_.push_back(g_signal_connect(monitor_.get(), sig, cb, this));
    };

    connect("volume-added", G_CALLBACK(+[](GVolumeMonitor *, GVolume *v, gpointer d) {
        static_cast<MountManager *>(d)->handleVolumeAdded(v);
    }));
    connect("volume-removed", G_CALLBACK(+[](GVolumeMonitor *, GVolume *v, gpointer d) {
        static_cast<MountManager *>(d)->handleVolumeRemoved(v);
    }));
    connect("mount-added", G_CALLBACK(+[](GVolumeMonitor *, GMount *m, gpointer d) {
        static_cast<MountManager *>(d)->handleMountAdded(m, true);
    }));
    connect("mount-removed", G_CALLBACK(+[](GVolumeMonitor *, GMount *m, gpointer d) {
        static_cast<MountManager *>(d)->handleMountRemoved(m);
    }));
    connect("mount-pre-unmount", G_CALLBACK(+[](GVolumeMonitor *, GMount *m, gpointer) {
        GRef<GFile> root(g_mount_get_root(m));
        if (root)
            LOG_DEBUG("About to unmount %s", mountPointOf(root.get()).c_str());
    }));

    /* Devices that were already present when the daemon started. */
    GList *vols = g_volume_monitor_get_volumes(monitor_.get());
    for (GList *l = vols; l; l = l->next)
        handleVolumeAdded(static_cast<GVolume *>(l->data));
    g_list_free_full(vols, g_object_unref);

    GList *mounts = g_volume_monitor_get_mounts(monitor_.get());
    for (GList *l = mounts; l; l = l->next)
        handleMountAdded(static_cast<GMount *>(l->data), false);
    g_list_free_full(mounts, g_object_unref);

    LOG_INFO("Mount manager started (auto-mount %s)", autoMount_ ? "on" : "off");
}

/* ------------------------------------------------------------------ */
/* Classification                                                      */
/* ------------------------------------------------------------------ */

bool MountManager::isRelevantVolume(GVolume *v) const
{
    if (opts_.includeInternal)
        return true;

    GRef<GDrive> drive(g_volume_get_drive(v));
    if (!drive) {
        /*
         * No drive: MTP / PTP / iOS volumes qualify, loop devices etc. do not.
         * gvfs reports these with a USB node as unix-device, so a plain
         * "has no unix-device" test would wrongly reject them.
         */
        const std::string dev = unixDeviceOf(v);
        if (dev.empty() || dev.rfind("/dev/bus/usb/", 0) == 0)
            return true;
        if (GFile *root = g_volume_get_activation_root(v)) {
            GRef<GFile> r(root);
            if (isRemovableScheme(schemeOf(r.get())))
                return true;
        }
        return false;
    }
    return g_drive_is_removable(drive.get()) || g_drive_is_media_removable(drive.get());
}

bool MountManager::describeMount(GMount *m, MountInfo &out)
{
    if (g_mount_is_shadowed(m))
        return false;

    GRef<GFile> root(g_mount_get_root(m));
    if (!root)
        return false;

    GRef<GVolume> vol(g_mount_get_volume(m));
    std::string key;
    if (vol) {
        auto it = volumes_.find(vol.get());
        if (it != volumes_.end())
            key = it->second.key;
        else if (isRelevantVolume(vol.get()))
            key = volumeKey(vol.get());
        else
            return false;
    } else {
        if (!opts_.includeInternal && !isRemovableScheme(schemeOf(root.get())))
            return false;
        key = fileKey(root.get());
    }

    out.ref = refOf(m);
    out.key = key;
    out.label = takeString(g_mount_get_name(m));
    out.mountPoint = mountPointOf(root.get());
    out.readOnly = false;
    return true;
}

bool MountManager::volumePresent(const std::string &key) const
{
    for (const auto &kv : volumes_) {
        if (kv.second.key == key)
            return true;
    }
    return false;
}

/* ------------------------------------------------------------------ */
/* Monitor event handlers                                              */
/* ------------------------------------------------------------------ */

void MountManager::handleVolumeAdded(GVolume *v)
{
    if (volumes_.count(v))
        return;
    if (!isRelevantVolume(v)) {
        LOG_INFO("Ignoring volume '%s' (unix-device '%s'): not removable",
                 takeString(g_volume_get_name(v)).c_str(), unixDeviceOf(v).c_str());
        return;
    }

    std::string key = volumeKey(v);
    volumes_.emplace(v, VolumeInfo{refOf(v), key});
    ejected_.erase(key); /* device came back */

    GRef<GMount> existing(g_volume_get_mount(v));
    if (existing)
        return; /* already mounted by someone else; mount-added handles it */

    std::string label = takeString(g_volume_get_name(v));
    LOG_INFO("Device inserted: %s (%s)", key.c_str(), label.c_str());
    if (events_.inserted)
        events_.inserted(key, label);

    if (!autoMount_) {
        LOG_INFO("Auto-mount disabled, not mounting %s", key.c_str());
        return;
    }
    if (!g_volume_should_automount(v) || !g_volume_can_mount(v)) {
        LOG_INFO("%s not auto-mounted (should_automount=%d, can_mount=%d)", key.c_str(),
                 (int)g_volume_should_automount(v), (int)g_volume_can_mount(v));
        return;
    }
    startMount(v, key, nullptr);
}

void MountManager::handleVolumeRemoved(GVolume *v)
{
    auto it = volumes_.find(v);
    if (it == volumes_.end())
        return;

    std::string key = it->second.key;
    volumes_.erase(it);
    pendingMounts_.erase(key);
    cancelProbe(key);

    if (ejecting_.count(key)) {
        LOG_DEBUG("%s disappeared during user eject", key.c_str());
        return; /* finishEject() will emit DeviceEjected */
    }
    if (ejected_.erase(key)) {
        LOG_DEBUG("%s unplugged after eject", key.c_str());
        return;
    }

    LOG_WARN("Device %s was removed (unplugged)", key.c_str());
    if (events_.ejected)
        events_.ejected(key);
}

void MountManager::handleMountAdded(GMount *m, bool announce)
{
    if (mounts_.count(m))
        return;

    MountInfo info;
    if (!describeMount(m, info))
        return;

    const std::string key = info.key;
    GRef<GFile> root(g_mount_get_root(m));
    const bool isMtp = root && schemeOf(root.get()) == "mtp";

    ejected_.erase(key);
    info.announced = !announce; /* mounts that existed at startup are listed silently */
    auto ins = mounts_.emplace(m, std::move(info));

    if (root)
        queryReadOnly(root.get(), key);

    if (!announce)
        return;

    if (isMtp) {
        /* Mounted does not mean usable: wait until the phone exposes storage. */
        if (!probes_.count(key)) {
            ProbeState st;
            st.startUs = g_get_monotonic_time();
            probes_.emplace(key, st);
        }
        LOG_INFO("MTP device %s mounted, waiting for storage to become visible "
                 "(unlock the phone and tap \"Allow\")", key.c_str());
        scheduleProbe(key, 1);
        return;
    }

    announceMount(ins.first->second);
}

void MountManager::announceMount(MountInfo &mi)
{
    mi.announced = true;
    LOG_INFO("Mounted %s (%s) at %s", mi.key.c_str(), mi.label.c_str(), mi.mountPoint.c_str());
    if (events_.mounted)
        events_.mounted(mi.key, mi.label, mi.mountPoint);
    if (events_.volumesChanged)
        events_.volumesChanged();
}

void MountManager::handleMountRemoved(GMount *m)
{
    auto it = mounts_.find(m);
    if (it == mounts_.end())
        return;

    const std::string key = it->second.key;
    const std::string mp = it->second.mountPoint;
    const bool wasAnnounced = it->second.announced;
    mounts_.erase(it);

    if (!wasAnnounced) {
        /* Never reported as mounted (probe in progress / gave up): stay silent. */
        LOG_INFO("Unannounced mount of %s went away", key.c_str());
        return;
    }

if (refreshing_.erase(key)) {
    LOG_DEBUG("Controlled remount of %s", key.c_str());
    return;   // do not emit unmounted / do not treat as failure
}
    if (!ejecting_.count(key))
        LOG_WARN("%s was unmounted unexpectedly (unplugged or unmounted by another program); "
                 "GVfs cleans up %s", key.c_str(), mp.c_str());
    else
        LOG_INFO("Unmounted %s", key.c_str());

    if (events_.unmounted)
        events_.unmounted(key);
    if (events_.volumesChanged)
        events_.volumesChanged();
}

/* ------------------------------------------------------------------ */
/* Read-only detection                                                 */
/* ------------------------------------------------------------------ */

void MountManager::queryReadOnly(GFile *root, const std::string &key)
{
    auto *ctx = new RoCtx{this, key};
    g_file_query_filesystem_info_async(
        root, G_FILE_ATTRIBUTE_FILESYSTEM_READONLY, G_PRIORITY_LOW, cancel_.get(),
        +[](GObject *src, GAsyncResult *res, gpointer d) {
            std::unique_ptr<RoCtx> c(static_cast<RoCtx *>(d));
            GErr err;
            GRef<GFileInfo> info(g_file_query_filesystem_info_finish(G_FILE(src), res, err.out()));
            if (err.is(G_IO_ERROR, G_IO_ERROR_CANCELLED))
                return;
            bool ro = info &&
                g_file_info_get_attribute_boolean(info.get(), G_FILE_ATTRIBUTE_FILESYSTEM_READONLY);
            c->self->setReadOnly(c->key, ro);
        },
        ctx);
}

void MountManager::setReadOnly(const std::string &key, bool ro)
{
    bool changed = false;
    for (auto &kv : mounts_) {
        if (kv.second.key == key && kv.second.readOnly != ro) {
            kv.second.readOnly = ro;
            changed = true;
        }
    }
    if (changed && events_.volumesChanged)
        events_.volumesChanged();
}

/* ------------------------------------------------------------------ */
/* Mounting                                                            */
/* ------------------------------------------------------------------ */

void MountManager::startMount(GVolume *v, const std::string &key, DoneCb cb)
{
    if (pendingMounts_.count(key)) {
        if (cb)
            cb(false, "Mount already in progress");
        return;
    }
    pendingMounts_.insert(key);

    auto *ctx = new MountCtx{this, key, std::move(cb), refOf(v)};
    GMountOperation *op = makeAbortingOperation();

    LOG_INFO("Mounting %s ...", key.c_str());
    g_volume_mount(
        v, G_MOUNT_MOUNT_NONE, op, cancel_.get(),
        +[](GObject *src, GAsyncResult *res, gpointer d) {
            std::unique_ptr<MountCtx> c(static_cast<MountCtx *>(d));
            GErr err;
            gboolean ok = g_volume_mount_finish(G_VOLUME(src), res, err.out());
            if (err.is(G_IO_ERROR, G_IO_ERROR_CANCELLED))
                return;

            bool success = ok;
            std::string msg;
            if (!ok) {
                if (err.is(G_IO_ERROR, G_IO_ERROR_ALREADY_MOUNTED))
                    success = true;
                else
                    msg = err.message();
            }
            c->self->finishMount(c->key, success, msg, c->cb);
        },
        ctx);
    g_object_unref(op);
}

void MountManager::finishMount(const std::string &key, bool ok, const std::string &msg, DoneCb &cb)
{
    pendingMounts_.erase(key);

    if (!ok && probes_.count(key)) {
        LOG_INFO("Remount of %s failed (%s), will retry", key.c_str(), msg.c_str());
        scheduleProbe(key, kProbeIntervalSec);
        if (cb)
            cb(false, msg);
        return;
    }

    if (!ok) {
        LOG_WARN("Mount of %s failed: %s", key.c_str(), msg.c_str());
        if (events_.mountFailed)
            events_.mountFailed(key, msg);
    }
    /* On success DeviceMounted comes from the monitor's mount-added signal. */
    if (cb)
        cb(ok, msg);
}

void MountManager::mountDevice(const std::string &devicePath, DoneCb cb)
{
    auto fail = [&](const std::string &reason) {
        LOG_WARN("MountDevice(%s) failed: %s", devicePath.c_str(), reason.c_str());
        if (events_.mountFailed)
            events_.mountFailed(devicePath, reason);
        if (cb)
            cb(false, reason);
    };

    for (auto &kv : volumes_) {
        if (kv.second.key != devicePath)
            continue;

        GVolume *v = kv.second.ref.get();
        GRef<GMount> existing(g_volume_get_mount(v));
        if (existing) {
            const bool waiting = probes_.count(devicePath) > 0;
            if (cb)
                cb(!waiting, waiting ? "Still waiting for the phone to grant access" : "");
            return;
        }
        if (!g_volume_can_mount(v)) {
            fail("Volume cannot be mounted");
            return;
        }
        startMount(v, devicePath, std::move(cb)); /* manual mount ignores AutoMount */
        return;
    }

    fail("Unknown or non-removable device");
}

/* ------------------------------------------------------------------ */
/* Ejecting                                                            */
/* ------------------------------------------------------------------ */

void MountManager::ejectDevice(const std::string &id, DoneCb cb)
{
    auto fail = [&](const std::string &reportKey, const std::string &reason) {
        LOG_WARN("Eject of %s failed: %s", reportKey.c_str(), reason.c_str());
        if (events_.ejectFailed)
            events_.ejectFailed(reportKey, reason);
        if (cb)
            cb(false, reason);
    };

    const MountInfo *mi = nullptr;
    for (const auto &kv : mounts_) {
        if (kv.second.key == id || kv.second.mountPoint == id) {
            mi = &kv.second;
            break;
        }
    }
    if (!mi) {
        fail(id, "Device not tracked by mount manager");
        return;
    }

    const std::string key = mi->key;
    cancelProbe(key);
    if (ejecting_.count(key)) {
        fail(key, "Eject already in progress");
        return;
    }

    GRef<GMount> mount = refOf(mi->ref.get());
    GRef<GVolume> vol(g_mount_get_volume(mount.get()));

    const bool viaVolume = vol && g_volume_can_eject(vol.get());
    if (!viaVolume && !g_mount_can_unmount(mount.get())) {
        fail(key, "Device cannot be unmounted");
        return;
    }

    ejecting_.insert(key);
    auto *ctx = new EjectCtx{this, key, std::move(cb), refOf(mount.get())};
    GMountOperation *op = makeAbortingOperation();

    LOG_INFO("Ejecting %s (%s) ...", key.c_str(), viaVolume ? "volume eject" : "unmount");

    /* No G_MOUNT_UNMOUNT_FORCE: a busy device is reported, never yanked. */
    if (viaVolume) {
        g_volume_eject_with_operation(
            vol.get(), G_MOUNT_UNMOUNT_NONE, op, cancel_.get(),
            +[](GObject *src, GAsyncResult *res, gpointer d) {
                std::unique_ptr<EjectCtx> c(static_cast<EjectCtx *>(d));
                GErr err;
                gboolean ok = g_volume_eject_with_operation_finish(G_VOLUME(src), res, err.out());
                if (err.is(G_IO_ERROR, G_IO_ERROR_CANCELLED))
                    return;
                c->self->finishEject(c->key, ok, ok ? "" : err.message(), c->cb);
            },
            ctx);
    } else {
        g_mount_unmount_with_operation(
            mount.get(), G_MOUNT_UNMOUNT_NONE, op, cancel_.get(),
            +[](GObject *src, GAsyncResult *res, gpointer d) {
                std::unique_ptr<EjectCtx> c(static_cast<EjectCtx *>(d));
                GErr err;
                gboolean ok = g_mount_unmount_with_operation_finish(G_MOUNT(src), res, err.out());
                if (err.is(G_IO_ERROR, G_IO_ERROR_CANCELLED))
                    return;
                c->self->finishEject(c->key, ok, ok ? "" : err.message(), c->cb);
            },
            ctx);
    }
    g_object_unref(op);
}

void MountManager::finishEject(const std::string &key, bool ok, const std::string &msg, DoneCb &cb)
{
    ejecting_.erase(key);

    if (ok) {
        /* Still plugged in (e.g. MTP unmount)? Swallow the later unplug event. */
        if (volumePresent(key))
            ejected_.insert(key);

        LOG_INFO("Ejected %s", key.c_str());
        if (events_.ejected)
            events_.ejected(key);
        if (cb)
            cb(true, "");
        return;
    }

    LOG_WARN("Eject of %s failed: %s", key.c_str(), msg.c_str());
    if (events_.ejectFailed)
        events_.ejectFailed(key, msg);
    if (cb)
        cb(false, msg);
}

/* ------------------------------------------------------------------ */
/* MTP access probing                                                  */
/* ------------------------------------------------------------------ */

MountManager::MountInfo *MountManager::findMountByKey(const std::string &key)
{
    for (auto &kv : mounts_) {
        if (kv.second.key == key)
            return &kv.second;
    }
    return nullptr;
}

MountManager::VolumeInfo *MountManager::findVolumeByKey(const std::string &key)
{
    for (auto &kv : volumes_) {
        if (kv.second.key == key)
            return &kv.second;
    }
    return nullptr;
}

void MountManager::cancelProbe(const std::string &key)
{
    auto it = probes_.find(key);
    if (it == probes_.end())
        return;
    if (it->second.timer)
        g_source_remove(it->second.timer);
    probes_.erase(it);
}

void MountManager::scheduleProbe(const std::string &key, guint seconds)
{
    auto it = probes_.find(key);
    if (it == probes_.end())
        return;
    if (it->second.timer)
        g_source_remove(it->second.timer);

    auto *ctx = new TimerCtx{this, key};
    it->second.timer = g_timeout_add_seconds_full(
        G_PRIORITY_DEFAULT, seconds,
        +[](gpointer d) -> gboolean {
            auto *c = static_cast<TimerCtx *>(d);
            c->self->runProbe(c->key);
            return G_SOURCE_REMOVE;
        },
        ctx, +[](gpointer d) { delete static_cast<TimerCtx *>(d); });
}

/* Looks for at least one entry in the MTP root (= one visible storage). */
void MountManager::runProbe(const std::string &key)
{
    auto pit = probes_.find(key);
    if (pit == probes_.end())
        return;
    pit->second.timer = 0; /* the timer source is finished */

    const gint64 elapsed = (g_get_monotonic_time() - pit->second.startUs) / G_USEC_PER_SEC;
    if (elapsed >= kProbeTimeoutSec) {
        giveUpProbe(key);
        return;
    }

    MountInfo *mi = findMountByKey(key);
    if (!mi) {
        /* Mount vanished (remount cycle or failed remount): bring it back. */
        VolumeInfo *vi = findVolumeByKey(key);
        if (vi && !pendingMounts_.count(key) && g_volume_can_mount(vi->ref.get()))
            startMount(vi->ref.get(), key, nullptr);
        scheduleProbe(key, kProbeIntervalSec);
        return;
    }

    GRef<GFile> root(g_mount_get_root(mi->ref.get()));
    if (!root) {
        probeResult(key, false);
        return;
    }

    auto *ctx = new ProbeCtx{this, key, nullptr};
    g_file_enumerate_children_async(
        root.get(), G_FILE_ATTRIBUTE_STANDARD_NAME, G_FILE_QUERY_INFO_NONE, G_PRIORITY_DEFAULT,
        cancel_.get(),
        +[](GObject *src, GAsyncResult *res, gpointer d) {
            std::unique_ptr<ProbeCtx> c(static_cast<ProbeCtx *>(d));
            GErr err;
            GFileEnumerator *e = g_file_enumerate_children_finish(G_FILE(src), res, err.out());
            if (err.is(G_IO_ERROR, G_IO_ERROR_CANCELLED))
                return;
            if (!e) {
                LOG_INFO("Listing %s failed: %s", c->key.c_str(), err.message().c_str());
                c->self->probeResult(c->key, false);
                return;
            }

            ProbeCtx *next = c.release();
            next->enumerator.reset(e);
            g_file_enumerator_next_files_async(
                e, 1, G_PRIORITY_DEFAULT, next->self->cancel_.get(),
                +[](GObject *src2, GAsyncResult *res2, gpointer d2) {
                    std::unique_ptr<ProbeCtx> c2(static_cast<ProbeCtx *>(d2));
                    GErr err2;
                    GList *files = g_file_enumerator_next_files_finish(
                        G_FILE_ENUMERATOR(src2), res2, err2.out());
                    if (err2.is(G_IO_ERROR, G_IO_ERROR_CANCELLED))
                        return;
                    const bool has = files != nullptr;
                    g_list_free_full(files, g_object_unref);
                    g_file_enumerator_close_async(c2->enumerator.get(), G_PRIORITY_LOW, nullptr,
                                                  nullptr, nullptr);
                    c2->self->probeResult(c2->key, has);
                },
                next);
        },
        ctx);
}

void MountManager::probeResult(const std::string &key, bool hasStorage)
{
    auto pit = probes_.find(key);
    if (pit == probes_.end())
        return;

    MountInfo *mi = findMountByKey(key);
    if (!mi)
        return; /* remount in progress; handleMountAdded restarts probing */

    if (hasStorage) {
        LOG_INFO("%s: storage is visible, access granted", key.c_str());
        probes_.erase(pit);
        announceMount(*mi);
        return;
    }

    pit->second.emptyCount++;
    LOG_INFO("%s: no storage yet (phone locked or waiting for permission), attempt %d",
             key.c_str(), pit->second.emptyCount);

    /* The storage list of an MTP mount is read once at mount time, so after
     * the user taps "Allow" the old mount may stay empty: refresh by remounting. */
    if (pit->second.emptyCount % kRemountEveryEmptyProbes == 0) {
        remountForProbe(key);
        return;
    }
    scheduleProbe(key, kProbeIntervalSec);
}

// void MountManager::remountForProbe(const std::string &key)
// {
//     // Disabled for now – the force-unmount races with GVfs remote-volume-monitor
//     // and causes a SIGSEGV (null function pointer). Just keep probing the
//     // existing mount instead.
//     LOG_INFO("%s: skipping remount (disabled), will keep probing", key.c_str());
//     scheduleProbe(key, kProbeIntervalSec);
// }
// void MountManager::remountForProbe(const std::string &key)
// {
//     MountInfo *mi = findMountByKey(key);
//     if (!mi) {
//         scheduleProbe(key, kProbeIntervalSec);
//         return;
//     }
//
//     // Mark that we are doing a controlled refresh so handleMountRemoved
//     // does not treat it as an unexpected disappearance.
//     refreshing_.insert(key);          // new set similar to ejecting_
//
//     auto *ctx = new TimerCtx{this, key};
//     GMountOperation *op = makeAbortingOperation();
//
//     g_mount_unmount_with_operation(
//         mi->ref.get(), G_MOUNT_UNMOUNT_NONE, op, cancel_.get(),
//         +[](GObject *src, GAsyncResult *res, gpointer d) {
//             std::unique_ptr<TimerCtx> c(static_cast<TimerCtx *>(d));
//             GErr err;
//             g_mount_unmount_with_operation_finish(G_MOUNT(src), res, err.out());
//
//             // Only schedule the next probe *after* we know the unmount
//             // finished (or failed). The mount-removed handler will
//             // have cleaned the map by now.
//             if (!err.is(G_IO_ERROR, G_IO_ERROR_CANCELLED))
//                 c->self->scheduleProbe(c->key, 1);
//         },
//         ctx);
//     g_object_unref(op);
// }
void MountManager::remountForProbe(const std::string &key)
{
    MountInfo *mi = findMountByKey(key);
    if (!mi) {
        scheduleProbe(key, kProbeIntervalSec);
        return;
    }

    LOG_INFO("%s: remounting to refresh the storage list", key.c_str());
    auto *ctx = new TimerCtx{this, key};
    GMountOperation *op = makeAbortingOperation();
    g_mount_unmount_with_operation(
        mi->ref.get(), G_MOUNT_UNMOUNT_NONE, op, cancel_.get(),
        +[](GObject *src, GAsyncResult *res, gpointer d) {
            std::unique_ptr<TimerCtx> c(static_cast<TimerCtx *>(d));
            GErr err;
            g_mount_unmount_with_operation_finish(G_MOUNT(src), res, err.out());
            if (err.is(G_IO_ERROR, G_IO_ERROR_CANCELLED))
                return;
            if (err)
                LOG_INFO("Unmount for refresh of %s failed: %s", c->key.c_str(),
                         err.message().c_str());
            /* runProbe() remounts the volume if the mount is gone, else re-probes. */
            c->self->scheduleProbe(c->key, 1);
        },
        ctx);
    g_object_unref(op);
}

void MountManager::giveUpProbe(const std::string &key)
{
    LOG_WARN("%s: no storage after %d s, giving up", key.c_str(), (int)kProbeTimeoutSec);
    cancelProbe(key);

    if (events_.mountFailed)
        events_.mountFailed(key, "Phone did not grant access: unlock it, select File transfer "
                                 "and tap Allow, then call MountDevice again");

    /* Do NOT force-unmount here.
     * A fire-and-forget unmount races with the remote-volume-monitor
     * and causes a null-function-pointer crash inside
     * libgioremote-volume-monitor.so (call *0x8(%rbx) with a null callback).
     *
     * Leave the empty mount alone; it will disappear when the phone is
     * unplugged or the user calls EjectDevice / MountDevice later.
     */
}
// void MountManager::giveUpProbe(const std::string &key)
// {
//     LOG_WARN("%s: no storage after %d s, giving up", key.c_str(), (int)kProbeTimeoutSec);
//     cancelProbe(key);
//
//     if (events_.mountFailed)
//         events_.mountFailed(key, "Phone did not grant access: unlock it, select File transfer "
//                                  "and tap Allow, then call MountDevice again");
//
//     /* Clean up the empty, never-announced mount. */
//     if (MountInfo *mi = findMountByKey(key)) {
//         GMountOperation *op = makeAbortingOperation();
//         g_mount_unmount_with_operation(mi->ref.get(), G_MOUNT_UNMOUNT_NONE, op, cancel_.get(),
//                                        nullptr, nullptr);
//         g_object_unref(op);
//     }
// }

/* ------------------------------------------------------------------ */
/* Queries and settings                                                */
/* ------------------------------------------------------------------ */

std::vector<MountManager::Volume> MountManager::mounted() const
{
    std::vector<Volume> out;
    out.reserve(mounts_.size());
    for (const auto &kv : mounts_) {
        const MountInfo &i = kv.second;
        if (!i.announced)
            continue;
        out.push_back(Volume{i.key, i.label, i.mountPoint, i.readOnly});
    }
    return out;
}

void MountManager::setAutoMount(bool enabled)
{
    if (autoMount_ == enabled)
        return;
    autoMount_ = enabled;
    saveAutoMount(enabled);
    LOG_INFO("Auto-mount %s", enabled ? "enabled" : "disabled");
    if (events_.autoMountChanged)
        events_.autoMountChanged(enabled);
}

} // namespace ciel
