#pragma once

#include <glib-object.h>
#include <glib.h>

#include <memory>
#include <string>

namespace ciel {

struct GObjectDeleter {
    void operator()(void *p) const
    {
        if (p)
            g_object_unref(p);
    }
};

/* Owning reference to any GObject-derived type (GVolume, GMount, GFile, ...). */
template <typename T>
using GRef = std::unique_ptr<T, GObjectDeleter>;

/* Take an additional reference and own it. */
template <typename T>
GRef<T> refOf(T *p)
{
    g_object_ref(p);
    return GRef<T>(p);
}

/* Copy a newly allocated C string into std::string and free it. */
inline std::string takeString(char *s)
{
    std::string r = s ? s : "";
    g_free(s);
    return r;
}

/* Scoped GError. */
class GErr {
public:
    GErr() = default;
    GErr(const GErr &) = delete;
    GErr &operator=(const GErr &) = delete;
    ~GErr() { g_clear_error(&err_); }

    GError **out() { return &err_; }
    explicit operator bool() const { return err_ != nullptr; }

    bool is(GQuark domain, int code) const
    {
        return err_ && g_error_matches(err_, domain, code);
    }

    std::string message() const
    {
        return (err_ && err_->message) ? err_->message : "unknown error";
    }

private:
    GError *err_ = nullptr;
};

} // namespace ciel
