#pragma once

#include <QDBusArgument>
#include <QMetaType>
#include <QString>

/* Wire type (sssb): devicePath, label, mountPoint, readOnly */
struct MountedVolume {
    QString devicePath;
    QString label;
    QString mountPoint;
    bool readOnly = false;
};

Q_DECLARE_METATYPE(MountedVolume)

inline QDBusArgument &operator<<(QDBusArgument &arg, const MountedVolume &v)
{
    arg.beginStructure();
    arg << v.devicePath << v.label << v.mountPoint << v.readOnly;
    arg.endStructure();
    return arg;
}

inline const QDBusArgument &operator>>(const QDBusArgument &arg, MountedVolume &v)
{
    arg.beginStructure();
    arg >> v.devicePath >> v.label >> v.mountPoint >> v.readOnly;
    arg.endStructure();
    return arg;
}
