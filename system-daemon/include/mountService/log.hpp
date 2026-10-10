#pragma once

#include <glib.h>

/*
 * Thin wrappers over GLib logging (G_LOG_DOMAIN is set by CMake).
 * Debug output is shown with:  G_MESSAGES_DEBUG=ciel-mountd ciel-mountd
 * Under systemd --user everything lands in the journal.
 */
#define LOG_DEBUG(...) g_debug(__VA_ARGS__)
#define LOG_INFO(...)  g_message(__VA_ARGS__)
#define LOG_WARN(...)  g_warning(__VA_ARGS__)
#define LOG_ERROR(...) g_critical(__VA_ARGS__)
