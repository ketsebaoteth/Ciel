#pragma once

#include "MountedVolume.hpp"

#include <QDBusContext>
#include <QHash>
#include <QList>
#include <QObject>
#include <QString>
#include <QVariantMap>

#include <memory>

class QTimer;

namespace ciel {
class MountManager; /* GIO core; kept out of this header on purpose */
}

/*
 * org.ciel.Mount service object. Register it like the other services:
 *   new MountAdaptor(service);
 *   connection.registerObject("/org/ciel/Mount", service);
 * The adaptor (generated from dbus/org.ciel.Mount.xml) forwards methods,
 * properties and signals to this object.
 */
class MountService : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_PROPERTY(QList<MountedVolume> MountedDevices READ mountedDevices)
    Q_PROPERTY(bool AutoMount READ autoMount WRITE setAutoMount)

public:
    explicit MountService(QObject *parent = nullptr);
    ~MountService() override;

    /* Call after the object is registered on the bus. */
    void start();

    QList<MountedVolume> mountedDevices() const;
    bool autoMount() const;
    void setAutoMount(bool enabled);

public Q_SLOTS:
    QList<MountedVolume> ListMounted();
    bool EjectDevice(const QString &devicePath, QString &errorMessage);
    bool MountDevice(const QString &devicePath);

Q_SIGNALS:
    void DeviceMounted(const QString &devicePath, const QString &label, const QString &mountPoint);
    void DeviceUnmounted(const QString &devicePath);
    void EjectFailed(const QString &devicePath, const QString &reason);
    void DeviceInserted(const QString &devicePath);
    void DeviceEjected(const QString &devicePath);
    void MountFailed(const QString &devicePath, const QString &reason);

private:
    void emitPropertiesChanged(const QVariantMap &changed);

    /* Desktop notification through org.freedesktop.Notifications. Notifications of
     * the same device replace each other (inserted -> mounted -> removed). */
    void notify(const QString &key, const QString &summary, const QString &body,
                const QString &icon, uchar urgency = 1, bool terminal = false);
    QString nameFor(const QString &key) const;

    bool m_notify = true;                 /* CIEL_MOUNT_NOTIFY=0 disables          */
    int m_pendingEjects = 0;              /* user-requested ejects in flight       */
    QHash<QString, uint> m_notifIds;      /* device key -> notification id         */
    QHash<QString, QString> m_labels;     /* device key -> friendly name           */

    std::unique_ptr<ciel::MountManager> m_manager;
    QTimer *m_pump = nullptr; /* only used if Qt has no GLib event dispatcher */
};
