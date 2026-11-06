/* csARM shim: bionic has no <sys/sysctl.h>.  togl's glmgrbasics.cpp
 * includes it unconditionally, but the sysctl() call itself sits inside
 * #ifdef OSX (GLMDetectGDB); non-macOS builds use Sys_IsDebuggerPresent().
 * An empty header satisfies the include. */
#ifndef CSARM_SHIM_SYS_SYSCTL_H
#define CSARM_SHIM_SYS_SYSCTL_H
#endif /* CSARM_SHIM_SYS_SYSCTL_H */
