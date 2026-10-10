#pragma once

#include "gobj.hpp"

#include <gio/gio.h>

#include <functional>
#include <map>
#include <set>
#include <string>
#include <vector>

namespace ciel {

/*
 * Tracks removable media (USB sticks, SD cards, optical discs), MTP phones,
 * PTP cameras, iOS devices ... through GIO's GVolumeMonitor. The actual
 * mounting is done by UDisks2 / GVfs, entirely in the user session.
 *
 * Everything runs on the GLib main loop; no threads, no locking.
 */
class MountManager {
public:
    struct Options {
        /* Also manage internal / non-removable volumes. */
        bool includeInternal = false;
    };

    struct Volume {
        std::string devicePath; /* /dev/sdb1, mtp://..., gphoto2://... */
        std::string label;
        std::string mountPoint; /* FUSE path if available, else URI */
        bool readOnly = false;
    };

    /* One callback per D-Bus signal; any may be left empty. */
    struct Events {
        // std::function<void(const std::string &dev)> inserted;
        std::function<void(const std::string &devicePath, const std::string &label)> inserted;
        std::function<void(const std::string &dev, const std::string &label,
                           const std::string &mountPoint)> mounted;
        std::function<void(const std::string &dev, const std::string &reason)> mountFailed;
        std::function<void(const std::string &dev)> unmounted;
        std::function<void(const std::string &dev)> ejected;
        std::function<void(const std::string &dev, const std::string &reason)> ejectFailed;

        /* Property change notifications. */
        std::function<void()> volumesChanged;
        std::function<void(bool enabled)> autoMountChanged;
    };

    using DoneCb = std::function<void(bool ok, const std::string &error)>;

    MountManager();
    explicit MountManager(Options opts);
    ~MountManager();
    MountManager(const MountManager &) = delete;
    MountManager &operator=(const MountManager &) = delete;

    void setEvents(Events ev) { events_ = std::move(ev); }

    /* Connects to the volume monitor and scans devices already present. */
    void start();

    std::vector<Volume> mounted() const;

    /* Asynchronous; the callback is always invoked exactly once. */
    void mountDevice(const std::string &devicePath, DoneCb cb);
    void ejectDevice(const std::string &devicePathOrMountPoint, DoneCb cb);

    bool autoMount() const { return autoMount_; }
    void setAutoMount(bool enabled);

private:
    struct VolumeInfo {
        GRef<GVolume> ref;
        std::string key;
    };
    struct MountInfo {
        GRef<GMount> ref;
        std::string key;
        std::string label;
        std::string mountPoint;
        bool readOnly = false;
        bool announced = false; /* DeviceMounted sent / visible in MountedDevices */
    };

    /* MTP phones: the mount exists before the user taps "Allow access", but the
     * storage list stays empty until then. We probe until storage shows up. */
    struct ProbeState {
        gint64 startUs = 0;
        int emptyCount = 0;
        guint timer = 0;
    };

    bool isRelevantVolume(GVolume *v) const;
    bool describeMount(GMount *m, MountInfo &out);

    void handleVolumeAdded(GVolume *v);
    void handleVolumeRemoved(GVolume *v);
    void handleMountAdded(GMount *m, bool announce);
    void handleMountRemoved(GMount *m);

    void startMount(GVolume *v, const std::string &key, DoneCb cb);
    void finishMount(const std::string &key, bool ok, const std::string &msg, DoneCb &cb);
    void finishEject(const std::string &key, bool ok, const std::string &msg, DoneCb &cb);

    void announceMount(MountInfo &mi);
    MountInfo *findMountByKey(const std::string &key);
    VolumeInfo *findVolumeByKey(const std::string &key);

    void scheduleProbe(const std::string &key, guint seconds);
    void runProbe(const std::string &key);
    void probeResult(const std::string &key, bool hasStorage);
    void remountForProbe(const std::string &key);
    void giveUpProbe(const std::string &key);
    void cancelProbe(const std::string &key);

    void queryReadOnly(GFile *root, const std::string &key);
    void setReadOnly(const std::string &key, bool ro);

    bool volumePresent(const std::string &key) const;

    Options opts_;
    Events events_;
    bool autoMount_ = true;

    GRef<GVolumeMonitor> monitor_;
    GRef<GCancellable> cancel_;
    std::vector<gulong> handlers_;

    std::map<GVolume *, VolumeInfo> volumes_;
    std::map<GMount *, MountInfo> mounts_;

    std::set<std::string> pendingMounts_; /* mount in flight                       */
    std::set<std::string> ejecting_;      /* user eject in flight                  */
    std::set<std::string> refreshing_;      /* user refresh in flight                  */
    std::set<std::string> ejected_;       /* ejected by user, still plugged in     */
    std::map<std::string, ProbeState> probes_; /* MTP devices waiting for access   */
};

} // namespace ciel
