#include "MountService.hpp"
#include "MountManager.hpp"

#include <QAbstractEventDispatcher>
#include <QRegularExpression>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDebug>
#include <QTimer>

#include <glib.h>

namespace {

constexpr const char *kObjectPath = "/org/ciel/Mount";
constexpr const char *kInterface = "org.ciel.Mount";

QString q(const std::string &s)
{
    return QString::fromStdString(s);
}

QString tr_(const char *s)
{
    return QString::fromUtf8(s);
}

/* Route GLib/GIO/GVfs log output into Qt's logging. */
void glibLogForwarder(const gchar *domain, GLogLevelFlags level, const gchar *message, gpointer)
{
    const QString text = QStringLiteral("[%1] %2")
                             .arg(QString::fromUtf8(domain ? domain : "glib"),
                                  QString::fromUtf8(message ? message : ""));
    if (level & (G_LOG_LEVEL_ERROR | G_LOG_LEVEL_CRITICAL))
        qCritical().noquote() << text;
    else if (level & G_LOG_LEVEL_WARNING)
        qWarning().noquote() << text;
    else if (level & (G_LOG_LEVEL_MESSAGE | G_LOG_LEVEL_INFO))
        qInfo().noquote() << text;
    else
        qDebug().noquote() << text;
}

ciel::MountManager::Options makeOptions()
{
    ciel::MountManager::Options o;
    o.includeInternal = qEnvironmentVariableIsSet("CIEL_MOUNT_INCLUDE_INTERNAL");
    return o;
}

} // namespace

MountService::MountService(QObject *parent)
    : QObject(parent), m_manager(std::make_unique<ciel::MountManager>(makeOptions()))
{
    m_notify = qEnvironmentVariable("CIEL_MOUNT_NOTIFY", QStringLiteral("1")) != QLatin1String("0");

    qDBusRegisterMetaType<MountedVolume>();
    qDBusRegisterMetaType<QList<MountedVolume>>();

    ciel::MountManager::Events ev;

ev.inserted = [this](const std::string &dev, const std::string &label) {
    const QString key = q(dev);
    if (!label.empty())
        m_labels.insert(key, q(label));          // store the friendly name early
    notify(key, tr_("Device connected"), nameFor(key),
           QStringLiteral("drive-removable-media-usb"));
    Q_EMIT DeviceInserted(key);
};

    ev.mounted = [this](const std::string &dev, const std::string &label, const std::string &mp) {
        const QString key = q(dev);
        if (!label.empty())
            m_labels.insert(key, q(label));
        notify(key, tr_("%1 mounted").arg(nameFor(key)), q(mp),
               QStringLiteral("drive-removable-media"));
        Q_EMIT DeviceMounted(key, q(label), q(mp));
    };
    ev.mountFailed = [this](const std::string &dev, const std::string &reason) {
        const QString key = q(dev);
        notify(key, tr_("Could not mount %1").arg(nameFor(key)), q(reason),
               QStringLiteral("dialog-error"), 2, true);
        Q_EMIT MountFailed(key, q(reason));
    };
    ev.unmounted = [this](const std::string &dev) {
        const QString key = q(dev);
        notify(key, tr_("%1 unmounted").arg(nameFor(key)), key,
               QStringLiteral("drive-removable-media"));
        Q_EMIT DeviceUnmounted(key);
    };
    ev.ejected = [this](const std::string &dev) {
        const QString key = q(dev);
        if (m_pendingEjects > 0)
            notify(key, tr_("%1 ejected").arg(nameFor(key)), tr_("It is safe to remove the device."),
                   QStringLiteral("media-eject"), 1, true);
        else
            notify(key, tr_("%1 disconnected").arg(nameFor(key)), tr_("The device was removed."),
                   QStringLiteral("drive-removable-media-usb"), 1, true);
        m_labels.remove(key);
        Q_EMIT DeviceEjected(key);
    };
    ev.ejectFailed = [this](const std::string &dev, const std::string &reason) {
        const QString key = q(dev);
        notify(key, tr_("Cannot eject %1").arg(nameFor(key)), q(reason),
               QStringLiteral("dialog-warning"), 2, true);
        Q_EMIT EjectFailed(key, q(reason));
    };
    ev.volumesChanged = [this]() {
        emitPropertiesChanged({{QStringLiteral("MountedDevices"), QVariant::fromValue(mountedDevices())}});
    };
    ev.autoMountChanged = [this](bool enabled) {
        emitPropertiesChanged({{QStringLiteral("AutoMount"), enabled}});
    };

    m_manager->setEvents(std::move(ev));
}

MountService::~MountService() = default;

void MountService::start()
{
    g_log_set_default_handler(glibLogForwarder, nullptr);

    /*
     * GIO's async callbacks run on the default GMainContext. Qt's GLib event
     * dispatcher (the Linux default) iterates it for us. If Qt was built or
     * started without GLib (QT_NO_GLIB=1), pump the context from a timer.
     */
    auto *dispatcher = QAbstractEventDispatcher::instance();
    const bool glibDispatcher =
        dispatcher && QString::fromLatin1(dispatcher->metaObject()->className()).contains(QLatin1String("Glib"));

    if (!glibDispatcher) {
        qWarning() << "[MountService] Qt event dispatcher is not GLib-based; pumping GMainContext from a timer";
        m_pump = new QTimer(this);
        m_pump->setInterval(20);
        connect(m_pump, &QTimer::timeout, this, [] {
            while (g_main_context_iteration(nullptr, FALSE)) {
            }
        });
        m_pump->start();
    }

    m_manager->start();
}

QList<MountedVolume> MountService::mountedDevices() const
{
    QList<MountedVolume> out;
    for (const auto &v : m_manager->mounted())
        out.append(MountedVolume{q(v.devicePath), q(v.label), q(v.mountPoint), v.readOnly});
    return out;
}

bool MountService::autoMount() const
{
    return m_manager->autoMount();
}

void MountService::setAutoMount(bool enabled)
{
    m_manager->setAutoMount(enabled); /* emits PropertiesChanged via event */
}

QList<MountedVolume> MountService::ListMounted()
{
    return mountedDevices();
}

/*
 * Ejecting can take seconds (sync + power off), so the reply is delayed and
 * sent from GIO's completion callback instead of blocking the daemon.
 */
bool MountService::EjectDevice(const QString &devicePath, QString &errorMessage)
{
    if (!calledFromDBus()) {
        errorMessage = QStringLiteral("EjectDevice must be called over D-Bus");
        return false;
    }

    setDelayedReply(true);
    const QDBusMessage msg = message();
    const QDBusConnection bus = connection();

    m_pendingEjects++;
    m_manager->ejectDevice(devicePath.toStdString(), [this, msg, bus](bool ok, const std::string &err) {
        if (m_pendingEjects > 0)
            m_pendingEjects--;
        QDBusMessage reply = msg.createReply();
        reply << ok << q(err);
        bus.send(reply);
    });
    return false; /* ignored: reply is delayed */
}

bool MountService::MountDevice(const QString &devicePath)
{
    if (!calledFromDBus())
        return false;

    setDelayedReply(true);
    const QDBusMessage msg = message();
    const QDBusConnection bus = connection();

    m_manager->mountDevice(devicePath.toStdString(), [msg, bus](bool ok, const std::string &) {
        QDBusMessage reply = msg.createReply();
        reply << ok;
        bus.send(reply);
    });
    return false; /* ignored: reply is delayed */
}

void MountService::emitPropertiesChanged(const QVariantMap &changed)
{
    QDBusMessage sig = QDBusMessage::createSignal(QString::fromLatin1(kObjectPath),
                                                  QStringLiteral("org.freedesktop.DBus.Properties"),
                                                  QStringLiteral("PropertiesChanged"));
    sig << QString::fromLatin1(kInterface) << changed << QStringList();
    QDBusConnection::sessionBus().send(sig);
}

QString MountService::nameFor(const QString &key) const
{
    const QString label = m_labels.value(key);
    if (!label.isEmpty())
        return label;

    // Make the raw key more human-readable when we have no label yet
    if (key.startsWith(QLatin1String("mtp://"))) {
        // mtp://SAMSUNG_SAMSUNG_Android_R3CM60C5Q1R/  →  Samsung Android
        QString name = key.mid(6);                     // strip "mtp://"
        name.remove(QRegularExpression(QStringLiteral("/$")));  // trailing /
        name.replace(QLatin1Char('_'), QLatin1Char(' '));
        // Drop the long serial if present
        const int lastSpace = name.lastIndexOf(QLatin1Char(' '));
        if (lastSpace > 0 && name.mid(lastSpace + 1).length() > 8)
            name = name.left(lastSpace);
        return name.isEmpty() ? tr_("Phone") : name;
    }

    if (key.startsWith(QLatin1String("/dev/bus/usb/")))
        return tr_("USB device");

    if (key.startsWith(QLatin1String("/dev/")))
        return tr_("Removable drive");

    // Fallback: just the last component of the path/URI
    const int slash = key.lastIndexOf(QLatin1Char('/'));
    return slash >= 0 ? key.mid(slash + 1) : key;
}
// QString MountService::nameFor(const QString &key) const
// {
//     const QString label = m_labels.value(key);
//     return label.isEmpty() ? key : label;
// }

void MountService::notify(const QString &key, const QString &summary, const QString &body,
                          const QString &icon, uchar urgency, bool terminal)
{
    if (!m_notify)
        return;

    const uint replaces = terminal ? m_notifIds.take(key) : m_notifIds.value(key, 0);

    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("/org/freedesktop/Notifications"),
        QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("Notify"));

    const QVariantMap hints{{QStringLiteral("urgency"), QVariant::fromValue<uchar>(urgency)},
                            {QStringLiteral("category"), QStringLiteral("device")}};
    msg << QStringLiteral("Ciel Mount") << replaces << icon << summary << body << QStringList()
        << hints << (urgency >= 2 ? 10000 : 5000);

    /* Async on purpose: the notification server lives in this same process. */
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, key, terminal] {
        QDBusPendingReply<uint> reply = *watcher;
        if (reply.isValid() && !terminal)
            m_notifIds.insert(key, reply.value());
        else if (reply.isError())
            qWarning() << "[MountService] Notify failed:" << reply.error().message();
        watcher->deleteLater();
    });
}
