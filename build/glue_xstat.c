/* csARM — glibc-compat shims for tier0/tier1 pathmatch.cpp.
 *
 * pathmatch.cpp wraps the libc file API (Valve: UTF-8 path massaging) and
 * declares __real___xstat/__real___lxstat(+64) via its WRAP macro.  On
 * glibc those exist (__xstat is the stat() implementation); bionic has NO
 * __xstat at all, so nothing can resolve the __real_ references and bionic
 * dlopen would fail.  bionic code never calls __xstat either (headers map
 * stat() directly), so these shims only need to exist — map them to the
 * plain bionic calls.
 */
#include <sys/stat.h>

#ifdef __cplusplus
extern "C" {
#endif

int __real___xstat(int ver, const char *path, struct stat *buf)
{ (void)ver; return stat(path, buf); }

int __real___xstat64(int ver, const char *path, struct stat64 *buf)
{ (void)ver; return stat64(path, buf); }

int __real___lxstat(int ver, const char *path, struct stat *buf)
{ (void)ver; return lstat(path, buf); }

int __real___lxstat64(int ver, const char *path, struct stat64 *buf)
{ (void)ver; return lstat64(path, buf); }

#ifdef __cplusplus
}
#endif
