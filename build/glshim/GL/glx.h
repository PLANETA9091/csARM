/* csARM shim: Android has no GLX.  togl's glentrypoints.cpp includes
 * <GL/glx.h> under _LINUX only to declare function-pointer types for
 * glXGetCurrentDisplay / glXQueryExtensionsString (HasOpenGLExtension
 * fallback).  Those symbols resolve to NULL through SDL_GL_GetProcAddress
 * on Android and are NULL-guarded at runtime, so a type-only header is
 * enough to compile. */
#ifndef CSARM_SHIM_GLX_H
#define CSARM_SHIM_GLX_H

typedef struct _XDisplay Display;

#endif /* CSARM_SHIM_GLX_H */
