cmake_minimum_required(VERSION 3.21)

project(ciel-system-daemon VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core DBus Network)

# GIO/GVfs backend for the mount service
find_package(PkgConfig REQUIRED)
pkg_check_modules(GIO REQUIRED IMPORTED_TARGET gio-2.0)

qt_standard_project_setup()

qt_add_dbus_adaptor(THEME_DBUS
    org.ciel.Theme.xml
    ThemeService.hpp
    ThemeService
    ThemeAdaptor
    ThemeAdaptor
)

qt_add_dbus_adaptor(FDO_NOTIF_DBUS
    org.freedesktop.Notifications.xml
    NotificationService.hpp
    NotificationService
    NotificationsAdaptor
    NotificationsAdaptor
)

qt_add_dbus_adaptor(CIEL_NOTIF_DBUS
    org.ciel.Notifications.xml
    NotificationService.hpp
    NotificationService
    CielNotificationsAdaptor
    CielNotificationsAdaptor
)

qt_add_dbus_adaptor(STATS_DBUS
    org.ciel.SystemStats.xml
    SystemStatsService.hpp
    SystemStatsService
    SystemStatsAdaptor
    SystemStatsAdaptor
)

qt_add_dbus_adaptor(DOWNLOADS_DBUS
    org.ciel.Downloads.xml
    DownloadService.hpp
    DownloadService
    DownloadsAdaptor
    DownloadsAdaptor
)

qt_add_dbus_adaptor(MOUNT_DBUS
    org.ciel.Mount.xml
    MountService.hpp
    MountService
    MountAdaptor
    MountAdaptor
)

add_executable(ciel-system-daemon
    src/main.cpp
    src/Daemon.cpp
    src/ThemeService.cpp
    src/NotificationService.cpp
    src/SystemStatsService.cpp
    src/DownloadService.cpp
    src/mountService/MountService.cpp
    src/mountService/MountManager.cpp
    include/Daemon.hpp
    include/ThemeService.hpp
    include/NotificationService.hpp
    include/SystemStatsService.hpp
    include/SystemStatsTypes.hpp
    include/DownloadService.hpp
    include/mountService/MountService.hpp
    include/mountService/MountedVolume.hpp
    include/mountService/MountManager.hpp
    include/mountService/gobj.hpp
    include/mountService/log.hpp
    ${THEME_DBUS}
    ${FDO_NOTIF_DBUS}
    ${CIEL_NOTIF_DBUS}
    ${STATS_DBUS}
    ${DOWNLOADS_DBUS}
    ${MOUNT_DBUS}
)

# GIO headers and Qt's "signals"/"slots" keywords clash: build the two files
# that include GIO with QT_NO_KEYWORDS (the code uses Q_SIGNALS/Q_EMIT).
set_source_files_properties(
    src/mountService/MountService.cpp
    src/mountService/MountManager.cpp
    PROPERTIES COMPILE_DEFINITIONS QT_NO_KEYWORDS
)

target_compile_definitions(ciel-system-daemon PRIVATE G_LOG_DOMAIN="ciel-mount")

target_include_directories(ciel-system-daemon PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/include/mountService
    ${CMAKE_CURRENT_BINARY_DIR}
)

target_link_libraries(ciel-system-daemon PRIVATE
    Qt6::Core
    Qt6::DBus
    Qt6::Network
    PkgConfig::GIO
)
