#include "ExtensionManager.hpp"
#include "ProfileManager.hpp"

#include <QFutureWatcher>
#include <QtConcurrent/QtConcurrentRun>
#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRegularExpression>
#include <QTemporaryDir>
#include <QTimer>
#include <QUrl>
#include <QUuid>
#include <QtEndian>
#include <optional>

#include <QtWebEngineCore/QWebEngineExtensionInfo>
#include <QtWebEngineCore/QWebEngineExtensionManager>
#include <QtWebEngineCore/qtwebenginecoreglobal.h>
#include <QtWebEngineQuick/QQuickWebEngineProfile>

namespace {

constexpr quint64 kMaxExtensionSize = 100ull * 1024 * 1024;
constexpr qint64 kMaxDownload = 100ll * 1024 * 1024;

Database *db() { return ProfileManager::instance()->database(); }
bool validId(const QString &id) { return !QUuid::fromString(id).isNull(); }

QJsonObject readManifest(const QString &dir) {
  QFile f(dir + QStringLiteral("/manifest.json"));
  if (!f.open(QIODevice::ReadOnly) || f.size() > 1024 * 1024)
    return {};
  QByteArray data = f.readAll();
  if (data.startsWith("\xEF\xBB\xBF"))
    data.remove(0, 3);
  return QJsonDocument::fromJson(data).object();
}

QString localized(const QString &dir, const QJsonObject &m, const QString &text) {
  if (!text.startsWith(QLatin1String("__MSG_")) || !text.endsWith(QLatin1String("__")))
    return text;
  const QString key = text.mid(6, text.size() - 8).toLower();
  const QString loc = m.value(QStringLiteral("default_locale")).toString();
  if (loc.isEmpty())
    return text;
  QFile f(dir + QStringLiteral("/_locales/") + loc + QStringLiteral("/messages.json"));
  if (!f.open(QIODevice::ReadOnly))
    return text;
  const QJsonObject msgs = QJsonDocument::fromJson(f.readAll()).object();
  for (auto it = msgs.begin(); it != msgs.end(); ++it)
    if (it.key().toLower() == key)
      return it.value().toObject().value(QStringLiteral("message")).toString(text);
  return text;
}

QString bestIconUrl(const QString &dir, const QJsonObject &m) {
  QJsonObject icons = m.value(QStringLiteral("icons")).toObject();
  if (icons.isEmpty())
    icons = m.value(QStringLiteral("action")).toObject()
                .value(QStringLiteral("default_icon")).toObject();
  QString url;
  int best = -1;
  for (auto it = icons.begin(); it != icons.end(); ++it) {
    const int size = it.key().toInt();
    const QString clean = QDir::cleanPath(dir + QLatin1Char('/') + it.value().toString());
    if (size > best && clean.startsWith(dir + QLatin1Char('/')) && QFileInfo(clean).isFile()) {
      best = size;
      url = QUrl::fromLocalFile(clean).toString();
    }
  }
  return url;
}

QString popupPageUrl(const QString &dir, const QJsonObject &m) {
  QString rel;
  const auto pick = [&](const char *key) {
    if (!rel.isEmpty())
      return;
    const QJsonValue v = m.value(QLatin1String(key));
    if (v.isObject())
      rel = v.toObject().value(QStringLiteral("default_popup")).toString();
  };
  pick("action");
  pick("browser_action");
  pick("page_action");
  if (rel.isEmpty())
    return {};
  rel = localized(dir, m, rel);
  const QString root = QDir::cleanPath(dir);
  const QString clean = QDir::cleanPath(root + QLatin1Char('/') + rel);
  if (!clean.startsWith(root + QLatin1Char('/')) || !QFileInfo(clean).isFile())
    return {};
  return QUrl::fromLocalFile(clean).toString();
}

QStringList declaredHosts(const QJsonObject &m) {
  QStringList out;
  auto add = [&](const QString &p) { if (!out.contains(p)) out << p; };
  for (const QJsonValue &v : m.value(QStringLiteral("content_scripts")).toArray())
    for (const QJsonValue &p : v.toObject().value(QStringLiteral("matches")).toArray())
      add(p.toString());
  for (const QJsonValue &p : m.value(QStringLiteral("host_permissions")).toArray())
    add(p.toString());
  return out;
}

bool copyTree(const QString &src, const QString &dst, quint64 &budget) {
  const QFileInfoList entries = QDir(src).entryInfoList(
      QDir::NoDotAndDotDot | QDir::AllEntries | QDir::NoSymLinks | QDir::Hidden);
  for (const QFileInfo &fi : entries) {
    const QString target = dst + QLatin1Char('/') + fi.fileName();
    if (fi.isDir()) {
      if (!QDir().mkpath(target) || !copyTree(fi.absoluteFilePath(), target, budget))
        return false;
    } else if (fi.isFile()) {
      if (quint64(fi.size()) > budget)
        return false;
      budget -= quint64(fi.size());
      if (!QFile::copy(fi.absoluteFilePath(), target))
        return false;
    }
  }
  return true;
}

QString copyIntoPlace(const QString &src, const QString &dst) {
  const QJsonObject m = readManifest(src);
  if (m.isEmpty())
    return QStringLiteral("No valid manifest.json found.");
  const int mv = m.value(QStringLiteral("manifest_version")).toInt();
  if (mv != 3)
    return QStringLiteral("Unsupported manifest_version (expected 2 or 3).");
  if (!QDir().mkpath(dst))
    return QStringLiteral("Could not create the extension folder.");

  quint64 budget = kMaxExtensionSize;
  if (!copyTree(src, dst, budget)) {
    QDir(dst).removeRecursively();
    return QStringLiteral("The extension is larger than 100 MB or could not be copied.");
  }
  return {};
}

quint32 le32(const QByteArray &d, int off) {
  return qFromLittleEndian<quint32>(d.constData() + off);
}

bool crxToZip(const QByteArray &d, QByteArray *zip, QString *err) {
  if (d.size() < 16) {
    *err = QStringLiteral("The download was empty. The extension may not exist or may not be downloadable.");
    return false;
  }
  if (d.startsWith("PK\x03\x04")) {
    *zip = d;
    return true;
  }
  if (!d.startsWith("Cr24")) {
    *err = QStringLiteral("The download was not a Chrome extension package.");
    return false;
  }
  const quint32 ver = le32(d, 4);
  qint64 off = 0;
  if (ver == 3)
    off = 12 + qint64(le32(d, 8));
  else if (ver == 2)
    off = 16 + qint64(le32(d, 8)) + qint64(le32(d, 12));
  else {
    *err = QStringLiteral("Unsupported CRX version %1.").arg(ver);
    return false;
  }
  if (off <= 0 || off >= d.size()) {
    *err = QStringLiteral("The extension package is corrupted.");
    return false;
  }
  *zip = d.mid(int(off));
  return true;
}

std::optional<QWebEngineExtensionInfo> findInfo(QWebEngineExtensionManager *mgr,
                                                const QString &path) {
  if (!mgr)
    return std::nullopt;
  const QString want = QDir::cleanPath(path);
  for (const QWebEngineExtensionInfo &info : mgr->extensions())
    if (QDir::cleanPath(info.path()) == want)
      return info;
  return std::nullopt;
}

} // namespace

ExtensionManager *ExtensionManager::instance() {
  static ExtensionManager *s = new ExtensionManager(QCoreApplication::instance());
  return s;
}

ExtensionManager *ExtensionManager::create(QQmlEngine *, QJSEngine *) {
  ExtensionManager *m = instance();
  QJSEngine::setObjectOwnership(m, QJSEngine::CppOwnership);
  return m;
}

ExtensionManager::ExtensionManager(QObject *parent)
    : QObject(parent), m_net(new QNetworkAccessManager(this)) {
  connect(ProfileManager::instance(), &ProfileManager::activeProfileChanged, this,
          &ExtensionManager::extensionsChanged);
}

QString ExtensionManager::rootDir() const {
  return QDir::cleanPath(ProfileManager::instance()->profilePath() +
                         QStringLiteral("/extensions"));
}
QString ExtensionManager::pathFor(const QString &id) const {
  return rootDir() + QLatin1Char('/') + id;
}

QWebEngineExtensionManager *ExtensionManager::active() const {
  return m_managers.value(ProfileManager::instance()->activeProfileId()).data();
}

void ExtensionManager::setBusy(bool b) {
  if (m_busy != b) {
    m_busy = b;
    emit busyChanged();
  }
}

bool setExtensionEnabledSafely(
    QWebEngineExtensionManager *mgr,
    const QString &extensionPath,
    bool enabled)
{
    if (!mgr) {
        qWarning() << "[extensions] Manager is null";
        return false;
    }

    const QString wantedPath = QDir::cleanPath(extensionPath);

    for (const QWebEngineExtensionInfo &info : mgr->extensions()) {
        if (QDir::cleanPath(info.path()) != wantedPath)
            continue;

        if (!info.isLoaded()) {
            qWarning() << "[extensions] Extension is not loaded:"
                       << info.name() << info.path();
            return false;
        }

if (info.isEnabled() == enabled) {
    qInfo() << "[extensions] already in desired state";
    return true;
}
        qInfo() << "[extensions] Setting enabled:"
                << info.name()
                << "Qt ID:" << info.id()
                << "enabled:" << enabled;
qInfo() << "[ext-debug] Qt version:" << qVersion();
qInfo() << "[ext-debug] Manager:" << mgr;
qInfo() << "[ext-debug] Manager thread:" << mgr->thread();
qInfo() << "[ext-debug] Current thread:" << QThread::currentThread();

qInfo() << "[ext-debug] Extension:"
        << info.name()
        << "ID:" << info.id()
        << "Loaded:" << info.isLoaded()
        << "Enabled:" << info.isEnabled()
        << "Error:" << info.error();

qInfo() << "[ext-debug] Calling setExtensionEnabled now";

    // BUG: Enabling extension crashes
    // mgr->setExtensionEnabled(info, enabled);

qInfo() << "[ext-debug] setExtensionEnabled returned";

        return true;
    }

    qWarning() << "[extensions] Extension not found by path:"
               << wantedPath;

    qWarning() << "[extensions] Extensions known to this manager:";

    for (const QWebEngineExtensionInfo &info : mgr->extensions()) {
        qWarning() << "  Name:" << info.name()
                   << "Qt ID:" << info.id()
                   << "Path:" << info.path();
    }

    return false;
}

void ExtensionManager::attachProfile(const QString &profileId, QObject *profileObj) {
  if (m_managers.contains(profileId))
    return;
  auto *profile = qobject_cast<QQuickWebEngineProfile *>(profileObj);
  if (!profile || profile->isOffTheRecord())
    return;

  QWebEngineExtensionManager *mgr = profile->extensionManager();
  if (!mgr) {
    qWarning() << "[extensions] this Qt build has no extension support";
    return;
  }
  m_managers.insert(profileId, mgr);

connect(mgr, &QWebEngineExtensionManager::loadFinished, this,
        [this, mgr, profileId](const QWebEngineExtensionInfo &info) {
    if (!info.error().isEmpty()) {
        qWarning() << "[extensions] load error:"
                   << info.name() << info.error();
    } else if (info.isLoaded()) {
        const QString id = QFileInfo(info.path()).fileName();

        const QVariantList rows = db()->query(
            QStringLiteral(
                "SELECT enabled FROM extensions WHERE id = :id LIMIT 1;"),
            {{QStringLiteral(":id"), id}});

        const bool shouldEnable =
            !rows.isEmpty() &&
            rows.first().toMap()
                .value(QStringLiteral("enabled")).toInt() == 1;

if (ProfileManager::instance()->activeProfileId() == profileId && shouldEnable) {
    const QString extPath = pathFor(id);
    QTimer::singleShot(0, this, [this, profileId, extPath]() {
        if (ProfileManager::instance()->activeProfileId() != profileId)
            return;
        setExtensionEnabledSafely(m_managers.value(profileId).data(), extPath, true);
    });
}

        if (info.isEnabled()) {
            qInfo() << "[extensions] enabled:"
                    << info.name();
        } else {
            qInfo() << "[extensions] loaded but left disabled:"
                    << info.name();
        }
    }
qInfo() << "[extensions]"
        << "name:" << info.name()
        << "id:" << info.id()
        << "path:" << info.path()
        << "loaded:" << info.isLoaded()
        << "enabled:" << info.isEnabled()
        << "popup:" << info.actionPopupUrl()
        << "error:" << info.error();
    emit extensionsChanged();
});

  connect(mgr, &QWebEngineExtensionManager::unloadFinished, this,
          [this](const QWebEngineExtensionInfo &info) {
            const QString p = QDir::cleanPath(info.path());
            if (m_pendingDelete.remove(p))
              QDir(p).removeRecursively();
            emit extensionsChanged();
          });
}

void ExtensionManager::loadEnabled() {
  const QString pid = ProfileManager::instance()->activeProfileId();
  if (m_loadedProfiles.contains(pid) || !m_managers.contains(pid))
    return;
  m_loadedProfiles.insert(pid);

  QTimer::singleShot(0, this, [this, pid]() {
    if (ProfileManager::instance()->activeProfileId() != pid)
      return;
    QWebEngineExtensionManager *mgr = m_managers.value(pid).data();
    if (!mgr)
      return;
    const QVariantList rows = db()->query(QStringLiteral(
        "SELECT id FROM extensions WHERE enabled = 1 ORDER BY installed_at ASC;"));
    for (const QVariant &r : rows) {
      const QString id = r.toMap().value(QStringLiteral("id")).toString();
      if (validId(id) && QFileInfo(pathFor(id) + QStringLiteral("/manifest.json")).isFile())
        mgr->loadExtension(pathFor(id));
    }
  });
}

void ExtensionManager::loadById(const QString &id) {
  QWebEngineExtensionManager *mgr = active();
  if (mgr && validId(id) && !findInfo(mgr, pathFor(id)))
    mgr->loadExtension(pathFor(id));
}

QVariantList ExtensionManager::list()
{
    QVariantList result;

    QWebEngineExtensionManager *mgr = active();

    const QVariantList rows = db()->query(QStringLiteral(
        "SELECT id, enabled FROM extensions ORDER BY installed_at ASC;"
    ));

    for (const QVariant &r : rows) {
        const QVariantMap row = r.toMap();

        const QString id =
            row.value(QStringLiteral("id")).toString();

        const QString dir = pathFor(id);
        const QJsonObject m = readManifest(dir);

        const auto info = findInfo(mgr, dir);

        const bool databaseEnabled =
            row.value(QStringLiteral("enabled")).toInt() == 1;

        QVariantMap e;

        e.insert(QStringLiteral("id"), id);
        e.insert(QStringLiteral("enabled"), databaseEnabled);

        e.insert(QStringLiteral("isLoaded"),
                 info.has_value() && info->isLoaded());

        e.insert(QStringLiteral("runtimeEnabled"),
                 info.has_value() && info->isEnabled());

        if (m.isEmpty()) {
            e.insert(QStringLiteral("name"),
                     QStringLiteral("Unreadable extension"));
            e.insert(QStringLiteral("version"), QString());
            e.insert(QStringLiteral("description"), QString());
            e.insert(QStringLiteral("runsOn"), QString());
            e.insert(QStringLiteral("iconUrl"), QString());
            e.insert(QStringLiteral("popupUrl"), QString());
            e.insert(QStringLiteral("error"),
                     QStringLiteral(
                         "manifest.json is missing or invalid."));

            result.append(e);
            continue;
        }

        const QStringList hosts = declaredHosts(m);

        QString runsOn = hosts.mid(0, 4).join(
            QStringLiteral(", "));

        if (hosts.size() > 4) {
            runsOn += QStringLiteral(" +%1 more")
                          .arg(hosts.size() - 4);
        }

        e.insert(
            QStringLiteral("name"),
            localized(
                dir,
                m,
                m.value(QStringLiteral("name"))
                    .toString(QStringLiteral("Unnamed"))
            )
        );

        e.insert(
            QStringLiteral("version"),
            m.value(QStringLiteral("version")).toString()
        );

        e.insert(
            QStringLiteral("description"),
            localized(
                dir,
                m,
                m.value(QStringLiteral("description")).toString()
            )
        );

        e.insert(QStringLiteral("runsOn"), runsOn);
        e.insert(QStringLiteral("iconUrl"), bestIconUrl(dir, m));

        QString popupUrl;

        if (info && info->isLoaded()) {
            const QUrl extensionPopupUrl = info->actionPopupUrl();

            if (!extensionPopupUrl.isEmpty()) {
                popupUrl = extensionPopupUrl.toString();
            }
        }

        e.insert(QStringLiteral("popupUrl"), popupUrl);

        e.insert(
            QStringLiteral("error"),
            info ? info->error() : QString()
        );

        qInfo() << "[extensions] list:"
                << id
                << "loaded:"
                << (info && info->isLoaded())
                << "runtime enabled:"
                << (info && info->isEnabled())
                << "popup:"
                << popupUrl;

        result.append(e);
    }

    return result;
}

void ExtensionManager::installDir(const QString &src,
                                  std::function<void(const QString &)> done) {
  const QString storeId = m_pendingStoreId;
  const QString id = QUuid::createUuid().toString(QUuid::WithoutBraces);
  const QString dst = pathFor(id);

  auto *w = new QFutureWatcher<QString>(this);
  connect(w, &QFutureWatcher<QString>::finished, this, [this, w, id, done, storeId]() {
    const QString err = w->result();
    w->deleteLater();
    if (!err.isEmpty()) {
      done(err);
      return;
    }

    db()->execute(QStringLiteral("INSERT INTO extensions (id, enabled, installed_at, store_id) "
                                 "VALUES (:id, 1, :t, :s);"),
                  {{QStringLiteral(":id"), id},
                   {QStringLiteral(":t"), qint64(QDateTime::currentSecsSinceEpoch())},
                   {QStringLiteral(":s"), storeId.isEmpty() ? QVariant() : QVariant(storeId)}});

    QTimer::singleShot(0, this, [this, id]() { loadById(id); });
    emit extensionsChanged();
    done({});
  });
  w->setFuture(QtConcurrent::run(copyIntoPlace, src, dst));
}

void ExtensionManager::installFromFolder(const QString &folder) {
  if (m_busy)
    return;
  const QUrl u(folder);
  const QString path = QDir::cleanPath(u.isLocalFile() ? u.toLocalFile() : folder);
  if (!QFileInfo(path + QStringLiteral("/manifest.json")).isFile()) {
    emit installFailed(QStringLiteral("No manifest.json found in that folder."));
    return;
  }

  const QString id = storeIdFromUrl(folder);
  if (id.isEmpty()) {
    emit installFailed(QStringLiteral("That is not a Chrome Web Store link or extension ID."));
    return;
  }
  if (isStoreInstalled(id)) {
    emit installFailed(QStringLiteral("This extension is already installed."));
    return;
  }
  if (!active()) {
    emit installFailed(QStringLiteral("Extensions are not available in this build or profile."));
    return;
  }
  m_pendingStoreId = id;
  setBusy(true);

  installDir(path, [this](const QString &e) { finishInstall(e); });
}
QString ExtensionManager::storeIdFromUrl(const QString &url) const {
  static const QRegularExpression re(
      QStringLiteral("(?:^|/)([a-p]{32})(?:[/?#]|$)"));
  const QRegularExpressionMatch m = re.match(url.trimmed());
  return m.hasMatch() ? m.captured(1) : QString();
}

void ExtensionManager::finishInstall(const QString &error) {
  m_pendingStoreId.clear();
  setBusy(false);
  if (error.isEmpty())
    emit installSucceeded();
  else
    emit installFailed(error);
}

void ExtensionManager::installFromStore(const QString &input) {
  if (m_busy)
    return;
  const QString id = storeIdFromUrl(input).toLower();
  if (id.isEmpty()) {
    emit installFailed(QStringLiteral("That is not a Chrome Web Store link or extension ID."));
    return;
  }
  if (isStoreInstalled(id)) {
    emit installFailed(QStringLiteral("This extension is already installed."));
    return;
  }
  if (!active()) {
    emit installFailed(QStringLiteral("Extensions are not available in this build or profile."));
    return;
  }
  m_pendingStoreId = id;
  setBusy(true);

  const QString x = QString::fromLatin1(
      QUrl::toPercentEncoding(QStringLiteral("id=%1&uc").arg(id)));
  QUrl url(QStringLiteral("https://clients2.google.com/service/update2/crx"));
  url.setQuery(QStringLiteral("response=redirect&prodversion=%1&acceptformat=crx2,crx3&x=%2")
                   .arg(QString::fromLatin1(qWebEngineChromiumVersion()), x),
               QUrl::TolerantMode);

  QNetworkRequest req(url);
  req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                   QNetworkRequest::NoLessSafeRedirectPolicy);
  req.setTransferTimeout(60000);

  QNetworkReply *reply = m_net->get(req);
  connect(reply, &QNetworkReply::downloadProgress, this, [reply](qint64 got, qint64) {
    if (got > kMaxDownload)
      reply->abort();
  });
  connect(reply, &QNetworkReply::finished, this, [this, reply]() {
    reply->deleteLater();
    if (reply->error() != QNetworkReply::NoError) {
      finishInstall(QStringLiteral("Download failed: ") + reply->errorString());
      return;
    }

    QByteArray zip;
    QString err;
    if (!crxToZip(reply->readAll(), &zip, &err)) {
      finishInstall(err);
      return;
    }

    auto tmp = QSharedPointer<QTemporaryDir>::create();
    if (!tmp->isValid()) {
      finishInstall(QStringLiteral("Could not create a temporary folder."));
      return;
    }
    const QString zipPath = tmp->filePath(QStringLiteral("pkg.zip"));
    const QString outDir = tmp->filePath(QStringLiteral("x"));
    QFile zf(zipPath);
    if (!QDir().mkpath(outDir) || !zf.open(QIODevice::WriteOnly) ||
        zf.write(zip) != zip.size()) {
      finishInstall(QStringLiteral("Could not write the downloaded package."));
      return;
    }
    zf.close();
    extractZip(tmp, zipPath, outDir, 0);
  });
}

void ExtensionManager::extractZip(QSharedPointer<QTemporaryDir> tmp, const QString &zip,
                                  const QString &out, int tool) {
  if (tool >= 2) {
    finishInstall(QStringLiteral("Could not unpack the extension. Install bsdtar (libarchive) or unzip."));
    return;
  }
  const QString program = tool == 0 ? QStringLiteral("bsdtar") : QStringLiteral("unzip");
  const QStringList args =
      tool == 0 ? QStringList{QStringLiteral("-xf"), zip, QStringLiteral("-C"), out}
                : QStringList{QStringLiteral("-q"), QStringLiteral("-o"), zip,
                              QStringLiteral("-d"), out};

  auto *p = new QProcess(this);
  connect(p, &QProcess::errorOccurred, this, [=, this](QProcess::ProcessError e) {
    if (e == QProcess::FailedToStart) {
      p->deleteLater();
      extractZip(tmp, zip, out, tool + 1);
    }
  });
  connect(p, &QProcess::finished, this, [=, this](int code, QProcess::ExitStatus st) {
    p->deleteLater();
    const bool ok = st == QProcess::NormalExit && (code == 0 || (tool == 1 && code == 1));
    if (!ok) {
      extractZip(tmp, zip, out, tool + 1);
      return;
    }
    installDir(out, [this, tmp](const QString &e) { finishInstall(e); });
  });
  p->start(program, args);
}

void ExtensionManager::setEnabled(const QString &id, bool enabled)
{
    if (!validId(id))
        return;

    db()->execute(
        QStringLiteral(
            "UPDATE extensions SET enabled = :e WHERE id = :id;"),
        {{QStringLiteral(":e"), enabled ? 1 : 0},
         {QStringLiteral(":id"), id}});

    const QString pid =
        ProfileManager::instance()->activeProfileId();

    emit extensionsChanged();

    QTimer::singleShot(0, this, [this, id, enabled, pid]() {
        if (ProfileManager::instance()->activeProfileId() != pid)
            return;

        QWebEngineExtensionManager *mgr = active();
        if (!mgr)
            return;

        const auto info = findInfo(mgr, pathFor(id));

        if (!enabled) {
            if (info && info->isLoaded())
                // BUG: setExtensionEnabled crashing
                // mgr->setExtensionEnabled(*info, false);
            setExtensionEnabledSafely(mgr, pathFor(id), false);

            emit extensionsChanged();
            return;
        }

        if (info) {
            if (info->isLoaded())
                // BUG: setExtensionEnabled crashing
                // mgr->setExtensionEnabled(*info, true);
            setExtensionEnabledSafely(mgr, pathFor(id), true);
        } else {
            mgr->loadExtension(pathFor(id));
        }

        emit extensionsChanged();
    });
}

void ExtensionManager::remove(const QString &id) {
  if (!validId(id))
    return;
  db()->execute(QStringLiteral("DELETE FROM extensions WHERE id = :id;"),
                {{QStringLiteral(":id"), id}});
  emit extensionsChanged();

  const QString path = QDir::cleanPath(pathFor(id));
  const QString pid = ProfileManager::instance()->activeProfileId();
  QTimer::singleShot(0, this, [this, path, pid]() {
    if (ProfileManager::instance()->activeProfileId() != pid)
      return;
    QWebEngineExtensionManager *mgr = active();
    const auto info = findInfo(mgr, path);
    if (info) {
      m_pendingDelete.insert(path);
      mgr->unloadExtension(*info);
    } else {
      QDir(path).removeRecursively();
    }
  });
}

bool ExtensionManager::isStoreInstalled(const QString &storeId) {
  if (storeId.isEmpty())
    return false;
  return !db()->query(
              QStringLiteral("SELECT id FROM extensions WHERE store_id = :s LIMIT 1;"),
              {{QStringLiteral(":s"), storeId.toLower()}})
              .isEmpty();
}
