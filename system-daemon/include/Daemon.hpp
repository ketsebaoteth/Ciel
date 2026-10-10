#pragma once

#include "DownloadService.hpp"
#include "NotificationService.hpp"
#include "SystemStatsService.hpp"
#include "ThemeService.hpp"
#include "mountService/MountService.hpp"
#include <QObject>
#include <memory>

class Daemon : public QObject {
  Q_OBJECT
public:
  explicit Daemon(QObject *parent = nullptr);
  bool init();

private:
  std::unique_ptr<ThemeService> m_themeService;
  std::unique_ptr<NotificationService> m_notificationService;
  std::unique_ptr<SystemStatsService> m_systemStatsService;
  std::unique_ptr<DownloadService> m_downloadService;
  std::unique_ptr<MountService> m_mountService;
};
