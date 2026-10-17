#pragma once

#include <functional>
#include <QHash>
#include <QJSEngine>
#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QSet>
#include <QSharedPointer>
#include <QString>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

class QWebEngineExtensionManager;
class QWebEngineExtensionInfo;
class QNetworkAccessManager;
class QTemporaryDir;

class ExtensionManager : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON
  Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
  static ExtensionManager *create(QQmlEngine *, QJSEngine *);
  static ExtensionManager *instance();

  bool busy() const { return m_busy; }

  Q_INVOKABLE void attachProfile(const QString &profileId, QObject *profile);
  Q_INVOKABLE void loadEnabled();          // call once the first WebEngineView exists
  Q_INVOKABLE QVariantList list();
  Q_INVOKABLE void installFromFolder(const QString &folder);
  Q_INVOKABLE void installFromStore(const QString &urlOrId);
  Q_INVOKABLE bool isStoreInstalled(const QString &storeId);
  Q_INVOKABLE QString storeIdFromUrl(const QString &url) const;
  Q_INVOKABLE void setEnabled(const QString &id, bool enabled);
  Q_INVOKABLE void remove(const QString &id);
	
  // void enableIfNeeded(const QWebEngineExtensionInfo &info);

signals:
  void extensionsChanged();
  void installFailed(const QString &message);
  void installSucceeded();
  void busyChanged();

private:
  explicit ExtensionManager(QObject *parent = nullptr);
  QWebEngineExtensionManager *active() const;
  QString rootDir() const;
  QString pathFor(const QString &id) const;
  void installDir(const QString &src, std::function<void(const QString &)> done);
  void loadById(const QString &id);
  void finishInstall(const QString &error);
  void setBusy(bool b);
  void extractZip(QSharedPointer<QTemporaryDir> tmp, const QString &zip,
                  const QString &out, int tool);

  QHash<QString, QPointer<QWebEngineExtensionManager>> m_managers;
  QSet<QString> m_loadedProfiles;
  QSet<QString> m_pendingDelete;
  QNetworkAccessManager *m_net = nullptr;
  QString m_pendingStoreId;
  bool m_busy = false;
};
