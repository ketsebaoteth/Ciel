cmake_minimum_required(VERSION 3.21)

project(ciel-browser VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Quick Qml WebEngineQuick WebEngineCore WebChannel Network Concurrent DBus Sql)
find_package(Qt6Keychain REQUIRED)


qt_policy(SET QTP0001 NEW)
qt_policy(SET QTP0004 NEW)

qt_standard_project_setup()

set(CIEL_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")

add_executable(ciel-browser
    src/main.cpp
)

target_include_directories(ciel-browser PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/core
    ${CIEL_ROOT}/ciel-ui/include
    ${CIEL_ROOT}/system-daemon/include
    ${CMAKE_CURRENT_BINARY_DIR}
)

target_link_directories(ciel-browser PRIVATE
    ${CIEL_ROOT}/ciel-ui/build
)

target_link_libraries(ciel-browser PRIVATE
    ciel-ui
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::WebEngineQuick
    Qt6::WebEngineCore
    Qt6::WebChannel
    Qt6Keychain::Qt6Keychain
    Qt6::Network
    Qt6::Concurrent
    Qt6::DBus
    Qt6::Sql
)

set_target_properties(ciel-browser PROPERTIES
    BUILD_RPATH "${CIEL_ROOT}/ciel-ui/build"
    INSTALL_RPATH "${CIEL_ROOT}/ciel-ui/build"
)

target_compile_definitions(ciel-browser PRIVATE
    CIEL_UI_IMPORT_PATH="${CIEL_ROOT}/ciel-ui/build"
)

qt_add_qml_module(ciel-browser
    URI "Ciel.Browser"
    VERSION 1.0
    OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/Ciel/Browser"

    SOURCES
        src/core/Database.hpp
        src/core/Database.cpp
        src/core/ProfileManager.hpp
        src/core/ProfileManager.cpp
        src/core/WorkspaceModel.hpp
        src/core/WorkspaceModel.cpp
        src/core/BrowserConfig.hpp
        src/core/BrowserConfig.cpp
        src/core/TabModel.hpp
        src/core/TabModel.cpp
        src/core/SwipeGestureFilter.hpp
        src/core/SwipeGestureFilter.cpp
        src/core/PasswordManager.hpp
        src/core/PasswordManager.cpp
        src/core/ExtensionManager.cpp
        src/core/ExtensionManager.cpp
        src/core/SitePermissionManager.cpp
        src/core/SitePermissionManager.cpp

    QML_FILES
        qml/Main.qml
        qml/ui/tabs/TabBar.qml
        qml/ui/navigation/NavigationBar.qml
        qml/ui/startpage/StartPage.qml
        qml/ui/tabs/TabDelegateVertical.qml
        qml/ui/tabs/TabNavRowHorizontal.qml
        qml/ui/tabs/TabDelegateHorizontal.qml
        qml/ui/tabs/BrowserSettingsMenu.qml
        qml/ui/tabs/TabHeaderVertical.qml
        qml/ui/downloads/BrowserDownloadItem.qml
        qml/ui/downloads/BrowserDownloadsPopup.qml
        qml/ui/history/HistoryPage.qml
        qml/ui/profilePage/ProfilePage.qml
        qml/ui/profilePage/ProfileMutateDialog.qml
        qml/ui/bookmark/BookmarkPage.qml
        qml/ui/password/PasswordPage.qml
        qml/ui/window/BrowserWindow.qml
        qml/ui/window/UrlCompletionList.qml
        qml/ui/window/UrlGhostText.qml
        qml/ui/window/SettingsPage.qml
        qml/ui/window/BrowserSettings.qml
        qml/ui/window/SitePermissionsPage.qml
        qml/ui/window/ExtensionsPage.qml
)
