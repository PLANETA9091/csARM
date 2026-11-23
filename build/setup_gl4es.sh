#!/bin/bash
# csARM — build gl4es (pinned bc4314d) for Android from one script.
# The patch sequence is the same one the CI gl4es job runs; it lives here so a
# developer can rebuild + debug the GL stack locally without a CI round trip.
#   usage: NDKROOT=/path/to/ndk build/setup_gl4es.sh [workspace_root] [abis]
#   out:   thirdparty/gl4es-<abi>/{libGL.so,libEGLgl4es.so}
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="$(cd "${1:-$SCRIPT_DIR/..}" && pwd)"
ABIS="${2:-x86_64 arm64-v8a}"
# NDKROOT is optional here (resolved per-ABI below, env > ANDROID_NDK_LATEST_HOME
# > $ANDROID_HOME/ndk/* > downloaded r27d); only prepend it when it is set.
if [ -n "${NDKROOT:-}" ] && [ -d "${NDKROOT:-/nonexistent}" ]; then
  export PATH="$NDKROOT/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
fi
mkdir -p "$R/.cache"

for ABI in $ABIS; do
  [ -f "$R/thirdparty/gl4es-$ABI/libGL.so" ] && [ "${FORCE:-0}" != "1" ] && {
    echo "gl4es-$ABI already built (FORCE=1 to rebuild)"; continue; }
  (
    set -euo pipefail
    cd "$R/.cache"
B="$R/thirdparty/gl4es-${ABI}"
if [ -n "${NDKROOT:-}" ] && [ -d "${NDKROOT:-/nonexistent}" ]; then
  echo "using NDKROOT from env: $NDKROOT"
elif [ -n "${ANDROID_NDK_LATEST_HOME:-}" ] && [ -d "${ANDROID_NDK_LATEST_HOME:-/nonexistent}" ]; then
  NDKROOT="$ANDROID_NDK_LATEST_HOME"
elif R27=$(ls -d "${ANDROID_HOME:-/nonexistent}"/ndk/* 2>/dev/null | sort -V | tail -1) && [ -n "$R27" ]; then
  NDKROOT="$R27"
else
  [ -f "$R/.cache/ndk.zip" ] || curl -sL -o "$R/.cache/ndk.zip" https://dl.google.com/android/repository/android-ndk-r27d-linux.zip
  unzip -q "$R/.cache/ndk.zip" -d "$R/.cache"
  NDKROOT="$R/.cache/android-ndk-r27d"
fi
echo "using NDK $NDKROOT ($(grep Pkg.Revision "$NDKROOT/source.properties" 2>/dev/null || echo unknown))"
rm -rf gl4es && git init -q gl4es && cd gl4es
git remote add origin https://github.com/ptitSeb/gl4es.git
git fetch -q --depth 1 origin bc4314d8369f169d3fa81c5ed1b46b3dba4e74a5
git checkout -q FETCH_HEAD
git config user.email csarm@local
git config user.name csarm
git rev-parse HEAD | tee ../gl4es_commit.txt

    for p in "$R"/patches/gl4es/*.patch; do
      [ -f "$p" ] || continue
      echo "applying $(basename "$p")"
      git apply --whitespace=nowarn "$p" || { echo "PATCH FAILED: $p"; exit 1; }
    done
# csARM round 65 fixup2: the NDK toolchain sets CMAKE_SYSTEM_NAME=Android,
# so src/CMakeLists.txt never takes the Linux GLX branch and libGL.so
# ships without glx/lookup.c - the EGL wrapper's gl4es_eglGetProcAddress
# then has no gl4es_glXGetProcAddress to link against (runs #208/#209
# ld.lld undefined-symbol failure).  Provide it as a local stub inside
# the wrapper TU: on Android the only correct answer for any glX name
# is NULL anyway.
sed -i 's|^void\* gl4es_eglGetProcAddress|void *gl4es_glXGetProcAddress(const char *name) { return NULL; }\nvoid* gl4es_eglGetProcAddress|' src/egl/lookup.c
grep -q "void \*gl4es_glXGetProcAddress" src/egl/lookup.c || { echo "::error::egl lookup stub patch failed"; exit 1; }
# csARM round 66: gl4es's constructor runs at dlopen (initialize_gl4es ->
# gl_init -> NewGLState(DEFAULT_STATE)) and glstate.c makes two contextless
# GLES queries (GL_VIEWPORT/GL_SCISSOR_BOX, GL_IMPLEMENTATION_COLOR_READ_*)
# unless built for AMIGAOS4/EMSCRIPTEN, whose guards read "if it's
# default_glstate, then there is probably no glcontext".  SwiftShader's
# es2::getContextLocked has no contextless tolerance and SEGVs (run #210:
# fault 0x140 in NewGLState -> glGetIntegerv).  Extend the same guards to
# ANDROID: the default state skips the queries (sane defaults pre-set),
# and per-context NewGLState(shared!=NULL) still queries with a live
# context.
# round 67: delimiter is @, NOT | - the pattern itself contains ||
# (sed -e #1 char 28 "unknown option to s" in run #211, both gl4es
# jobs died before building anything, no libEGLgl4es.so artifact,
# the map probe then pinned plain SwiftShader libEGL and togl got
# "OpenGL 0.0.0" / missing glGetError -> Sys_Error -> _exit(0)).
sed -i 's@#if defined(AMIGAOS4) || defined(__EMSCRIPTEN__)@#if defined(AMIGAOS4) || defined(__EMSCRIPTEN__) || defined(ANDROID)@' src/gl/glstate.c
[ "$(grep -c "defined(ANDROID)" src/gl/glstate.c)" -ge 6 ] || { echo "::error::glstate.c contextless-query guard patch failed"; exit 1; }
# csARM round 75: instrument the gl4es EGL passthrough + backend
# loader (tag CSARM_EGLW).  egl.c is a pure pass-through to the
# pinned SwiftShader backend and loader.c's open_lib decides WHICH
# .so actually backs gl4es - neither says anything under their own
# LOGD/nobanner gating, so the SDL -> libEGLgl4es.so -> gl4es ->
# SwiftShader chain was never attributed at runtime.  Log every
# load decision (override vs search, exact path) and every
# eglInitialize / eglCreateContext / eglCreateWindowSurface /
# eglMakeCurrent result UNCONDITIONALLY to logcat.  Cache key
# bumped egl4->egl5 so the instrumented libs actually rebuild.
sed -i 's@#include "../glx/hardext.h"@#include "../glx/hardext.h"\n\n#if defined(ANDROID) || defined(__ANDROID__)\n#include <android/log.h>\n/* csARM round 75: EGL-chain instrumentation (see ci.yml) */\n#define CSARM_EGLW_LOG(...) __android_log_print(ANDROID_LOG_INFO, "CSARM_EGLW", __VA_ARGS__)\n#else\n#define CSARM_EGLW_LOG(...) do {} while (0)\n#endif@' src/egl/egl.c
grep -q "CSARM_EGLW_LOG" src/egl/egl.c || { echo "::error::egl.c log macro patch failed"; exit 1; }
sed -i 's@    return egl_eglMakeCurrent(dpy, draw, read, ctx);@    EGLBoolean _csarm_rc = egl_eglMakeCurrent(dpy, draw, read, ctx);\n    CSARM_EGLW_LOG("eglMakeCurrent dpy=%p draw=%p read=%p ctx=%p -> %d", dpy, draw, read, ctx, (int)_csarm_rc);\n    return _csarm_rc;@' src/egl/egl.c
grep -q "eglMakeCurrent dpy=" src/egl/egl.c || { echo "::error::egl.c MakeCurrent patch failed"; exit 1; }
sed -i 's@    return egl_eglInitialize(dpy, major, minor);@    EGLBoolean _csarm_rc = egl_eglInitialize(dpy, major, minor);\n    CSARM_EGLW_LOG("eglInitialize dpy=%p -> %d ver=%d.%d", dpy, (int)_csarm_rc, major ? (int)*major : -1, minor ? (int)*minor : -1);\n    return _csarm_rc;@' src/egl/egl.c
grep -q "eglInitialize dpy=" src/egl/egl.c || { echo "::error::egl.c Initialize patch failed"; exit 1; }
sed -i 's@    return egl_eglCreateContext(dpy, config, share_context, (hardext.esversion == 1) ? egl_context_attrib : egl_context_attrib_es2);@    EGLContext _csarm_ctx = egl_eglCreateContext(dpy, config, share_context, (hardext.esversion == 1) ? egl_context_attrib : egl_context_attrib_es2);\n    CSARM_EGLW_LOG("eglCreateContext dpy=%p cfg=%p share=%p esver=%d -> %p", dpy, config, share_context, hardext.esversion, _csarm_ctx);\n    return _csarm_ctx;@' src/egl/egl.c
grep -q "eglCreateContext dpy=" src/egl/egl.c || { echo "::error::egl.c CreateContext patch failed"; exit 1; }
sed -i 's@    return egl_eglCreateWindowSurface(dpy, config, win, attrib_list);@    EGLSurface _csarm_surf = egl_eglCreateWindowSurface(dpy, config, win, attrib_list);\n    CSARM_EGLW_LOG("eglCreateWindowSurface dpy=%p cfg=%p win=%p -> %p", dpy, config, win, _csarm_surf);\n    return _csarm_surf;@' src/egl/egl.c
grep -q "eglCreateWindowSurface dpy=" src/egl/egl.c || { echo "::error::egl.c CreateWindowSurface patch failed"; exit 1; }
# csARM round 100: probe + MANUAL PRESENT inside the wrapper's swap.
# #256 verdict: EGL_CreateSurface=1 (single SDL surface, no second-surface
# theory), but SwapProbe=0 in every logcat although ANY path through the
# wrapper must hit gl4es_eglSwapBuffers => the ENGINE never swaps through
# SDL NOR through the wrapper: its own EGL (CSDLMgr::CreateHiddenGameWindow
# -> CEGL) dlopen()s "libEGL.so" by name and bionic resolves it to the
# SYSTEM goldfish EGL (the #202-era maps showed /system/lib64/libEGL.so).
# Its swap dies on "Surface::lock failed, already locked" (130x per map
# load, from the very first frame: render #1) - the stale holder from the
# SDL surface creation through the same window.  Two-part fix:
#   (a) the wrapper ships with SONAME "libEGL.so" (SUFFIX ".so" below) and
#       csarm_main preloads it RTLD_GLOBAL - every later dlopen of
#       "libEGL.so" (the engine's CEGL) returns the wrapper, so the
#       engine's create/MakeCurrent/swap ALL land here;
#   (b) gl4es_eglSwapBuffers presents the frame MANUALLY: lock the window
#       (libandroid via dlsym), glReadPixels the bound framebuffer, blit
#       it flipped into the locked buffer, unlockAndPost - the system
#       eglSwapBuffers is never called, so its broken lock state cannot
#       eat the frame.  Gate: blit once the probe sees non-black content;
#       until then (or if the window lock still fails) fall back to the
#       real passthrough swap, which is exactly today's behavior.
# The probe every 200 swaps gives the verdict either way:
#   rgb != 0 => content present => BLIT mode shows it on screen;
#   rgb == 0 after 2000 swaps => the render never drew.
# Verified locally on a pristine gl4es bc4314d clone (gcc -fsyntax-only).
sed -i 's@^EGLSurface gl4es_eglCreateWindowSurface(EGLDisplay dpy, EGLConfig config, EGLNativeWindowType win, const EGLint \*attrib_list) [{]@#include <dlfcn.h>\n#include <string.h>\n#include <stdlib.h>\n/* csARM round 100: manual present state (see the swap patch below) */\ntypedef struct { int width; int height; int stride; int format; void *bits; unsigned int reserved[6]; } CSARM_ANWB;\nstatic void *CSARM_lastWin = NULL;\nstatic int CSARM_gate = -1;\nstatic int CSARM_swapCount = 0;\nEGLSurface gl4es_eglCreateWindowSurface(EGLDisplay dpy, EGLConfig config, EGLNativeWindowType win, const EGLint *attrib_list) {@' src/egl/egl.c
grep -q "csARM round 100: manual present state" src/egl/egl.c || { echo "::error::egl.c r100 scope patch failed"; exit 1; }
sed -i 's@    return _csarm_surf;@    CSARM_lastWin = (void*)win;\n    return _csarm_surf;@' src/egl/egl.c
grep -q "CSARM_lastWin = (void\*)win;" src/egl/egl.c || { echo "::error::egl.c r100 win-cache patch failed"; exit 1; }
sed -i 's@    return egl_eglSwapBuffers(dpy, surface);@    /* csARM round 100: probe + manual present (see header comment) */\n    CSARM_swapCount++;\n    if ( ( CSARM_swapCount % 200 ) == 1 )\n    {\n        void ( *pGetIV )( unsigned int, int * ) = ( void ( * )( unsigned int, int * ) )dlsym( RTLD_DEFAULT, "glGetIntegerv" );\n        void ( *pReadPx )( int, int, int, int, unsigned int, unsigned int, void * ) = ( void ( * )( int, int, int, int, unsigned int, unsigned int, void * ) )dlsym( RTLD_DEFAULT, "glReadPixels" );\n        unsigned char px[3][9];\n        int vp[4];\n        vp[0] = vp[1] = vp[2] = vp[3] = 0;\n        if ( pGetIV ) pGetIV( 0x0BA2 /*GL_VIEWPORT*/, vp );\n        if ( pReadPx \&\& vp[2] > 0 \&\& vp[3] > 0 )\n        {\n            int i;\n            for ( i = 0; i < 3; i++ )\n                pReadPx( vp[0] + vp[2] * ( i + 1 ) / 4, vp[1] + vp[3] * ( i + 1 ) / 4, 3, 3, 0x1908 /*GL_RGBA*/, 0x1401 /*GL_UNSIGNED_BYTE*/, px[i] );\n            CSARM_EGLW_LOG( "SwapProbe #%d vp=%dx%d A=%02x%02x%02x B=%02x%02x%02x C=%02x%02x%02x", CSARM_swapCount, vp[2], vp[3], px[0][0], px[0][1], px[0][2], px[1][0], px[1][1], px[1][2], px[2][0], px[2][1], px[2][2] );\n            if ( CSARM_gate < 0 \&\& ( px[0][0] | px[0][1] | px[0][2] | px[1][0] | px[1][1] | px[1][2] | px[2][0] | px[2][1] | px[2][2] ) )\n            {\n                CSARM_gate = 1;\n                CSARM_EGLW_LOG( "present: BLIT mode ON (framebuffer has content)" );\n            }\n            else if ( CSARM_gate < 0 \&\& CSARM_swapCount > 2000 )\n            {\n                CSARM_gate = 0;\n                CSARM_EGLW_LOG( "present: framebuffer stayed empty - real swap fallback" );\n            }\n        }\n    }\n    if ( CSARM_gate == 1 \&\& CSARM_lastWin )\n    {\n        static int ( *pLock )( void *, CSARM_ANWB *, void * ) = NULL;\n        static int ( *pUnlock )( void * ) = NULL;\n        if ( !pLock )\n        {\n            void *hAn = dlopen( "libandroid.so", RTLD_NOW | RTLD_GLOBAL );\n            if ( hAn )\n            {\n                pLock = ( int ( * )( void *, CSARM_ANWB *, void * ) )dlsym( hAn, "ANativeWindow_lock" );\n                pUnlock = ( int ( * )( void * ) )dlsym( hAn, "ANativeWindow_unlockAndPost" );\n            }\n        }\n        if ( pLock \&\& pUnlock )\n        {\n            CSARM_ANWB buf;\n            memset( \&buf, 0, sizeof( buf ) );\n            if ( pLock( CSARM_lastWin, \&buf, NULL ) == 0 )\n            {\n                void ( *pGetIV )( unsigned int, int * ) = ( void ( * )( unsigned int, int * ) )dlsym( RTLD_DEFAULT, "glGetIntegerv" );\n                void ( *pReadPx )( int, int, int, int, unsigned int, unsigned int, void * ) = ( void ( * )( int, int, int, int, unsigned int, unsigned int, void * ) )dlsym( RTLD_DEFAULT, "glReadPixels" );\n                int vp[4];\n                vp[0] = vp[1] = vp[2] = vp[3] = 0;\n                if ( pGetIV ) pGetIV( 0x0BA2 /*GL_VIEWPORT*/, vp );\n                if ( pReadPx \&\& vp[2] > 0 \&\& vp[3] > 0 \&\& buf.format == 1 /*WINDOW_FORMAT_RGBA_8888*/ )\n                {\n                    static unsigned char *rb = NULL;\n                    static int rbW = 0, rbH = 0;\n                    if ( !rb || rbW != vp[2] || rbH != vp[3] )\n                    {\n                        void *n = realloc( rb, (size_t)vp[2] * vp[3] * 4 );\n                        if ( n ) { rb = (unsigned char*)n; rbW = vp[2]; rbH = vp[3]; }\n                    }\n                    if ( rb )\n                    {\n                        pReadPx( vp[0], vp[1], vp[2], vp[3], 0x1908, 0x1401, rb );\n                        int y;\n                        for ( y = 0; y < buf.height; y++ )\n                        {\n                            int sy = (int)( (long long)y * vp[3] / buf.height );\n                            const unsigned char *src = rb + (size_t)( vp[3] - 1 - sy ) * vp[2] * 4;\n                            unsigned char *dst = (unsigned char*)buf.bits + (size_t)y * buf.stride * 4;\n                            if ( vp[2] == buf.width )\n                                memcpy( dst, src, (size_t)vp[2] * 4 );\n                            else\n                            {\n                                int x;\n                                for ( x = 0; x < buf.width; x++ )\n                                {\n                                    const unsigned char *s = src + (size_t)( (int)( (long long)x * vp[2] / buf.width ) ) * 4;\n                                    dst[x*4+0] = s[0]; dst[x*4+1] = s[1]; dst[x*4+2] = s[2]; dst[x*4+3] = 255;\n                                }\n                            }\n                        }\n                        pUnlock( CSARM_lastWin );\n                        return EGL_TRUE;\n                    }\n                }\n                else if ( ( CSARM_swapCount % 200 ) == 1 )\n                {\n                    CSARM_EGLW_LOG( "blit skip: fmt=%d vp=%dx%d buf=%dx%d", buf.format, vp[2], vp[3], buf.width, buf.height );\n                }\n                pUnlock( CSARM_lastWin );\n            }\n            else if ( ( CSARM_swapCount % 200 ) == 1 )\n            {\n                CSARM_EGLW_LOG( "blit lock FAILED win=%p (stale holder still present?)", CSARM_lastWin );\n            }\n        }\n    }\n    return egl_eglSwapBuffers(dpy, surface);@' src/egl/egl.c
grep -q "csARM round 100: probe + manual present" src/egl/egl.c || { echo "::error::egl.c r100 swap patch failed"; exit 1; }
grep -c "SwapProbe #" src/egl/egl.c | grep -q "^1$" || { echo "::error::egl.c r100 swap patch double-applied"; exit 1; }
# csARM round 100a: the EGL wrapper ships with SONAME "libEGL.so" (file
# libEGL.so, copied to libEGLgl4es.so).  CMake derives SONAME from the
# output file name, so SUFFIX ".so" (was ".so.1") bakes soname=libEGL.so:
# the engine's own dlopen("libEGL.so") then soname-matches the ALREADY
# RESIDENT wrapper (csarm_main round 100 preload) instead of resolving
# the system goldfish EGL.
sed -i 's@set_target_properties(EGL PROPERTIES SUFFIX ".so.1")@set_target_properties(EGL PROPERTIES SUFFIX ".so")@' src/CMakeLists.txt
grep -q 'EGL PROPERTIES SUFFIX ".so")' src/CMakeLists.txt || { echo "::error::CMakeLists r100 soname patch failed"; exit 1; }
# loader.c (compiled into libGL.so): same macro + open_lib/load_libs
sed -i 's@#include "loader.h"@#include "loader.h"\n\n#if defined(ANDROID) || defined(__ANDROID__)\n#include <android/log.h>\n/* csARM round 75: EGL-chain instrumentation (see ci.yml) */\n#define CSARM_EGLW_LOG(...) __android_log_print(ANDROID_LOG_INFO, "CSARM_EGLW", __VA_ARGS__)\n#else\n#define CSARM_EGLW_LOG(...) do {} while (0)\n#endif@' src/gl/loader.c
grep -q "CSARM_EGLW_LOG" src/gl/loader.c || { echo "::error::loader.c log macro patch failed"; exit 1; }
sed -i 's@            strncpy(path_name, override, PATH_MAX);@            strncpy(path_name, override, PATH_MAX);\n            CSARM_EGLW_LOG("open_lib override OK: %s lib=%p", path_name, lib);@' src/gl/loader.c
grep -q "open_lib override OK" src/gl/loader.c || { echo "::error::loader.c override patch failed"; exit 1; }
sed -i 's@                if ((lib = dlopen(path_name, flags))) {@                if ((lib = dlopen(path_name, flags))) {\n                    CSARM_EGLW_LOG("open_lib search OK: %s lib=%p", path_name, lib);@' src/gl/loader.c
grep -q "open_lib search OK" src/gl/loader.c || { echo "::error::loader.c search patch failed"; exit 1; }
sed -i 's@^    return lib;@    CSARM_EGLW_LOG("open_lib done lib=%p", lib);\n    return lib;@' src/gl/loader.c
grep -q "open_lib done lib=" src/gl/loader.c || { echo "::error::loader.c tail patch failed"; exit 1; }
sed -i 's@    gles = open_lib((globals4es.es==1)?gles_lib:gles2_lib, gles_override);@    CSARM_EGLW_LOG("load_libs gles override=%s", gles_override ? gles_override : "(unset)");\n    gles = open_lib((globals4es.es==1)?gles_lib:gles2_lib, gles_override);@' src/gl/loader.c
grep -q "load_libs gles override" src/gl/loader.c || { echo "::error::loader.c gles pin patch failed"; exit 1; }
sed -i 's@    egl = open_lib(egl_lib, egl_override);@    CSARM_EGLW_LOG("load_libs egl override=%s", egl_override ? egl_override : "(unset)");\n    egl = open_lib(egl_lib, egl_override);@' src/gl/loader.c
grep -q "load_libs egl override" src/gl/loader.c || { echo "::error::loader.c egl pin patch failed"; exit 1; }
# ninja resolution: prefer a real ELF binary — a script named "ninja" earlier
# on PATH (dev stubs) prints a version but cannot build anything.
pick_ninja() {
  local c
  for c in ${NINJA:-} /usr/bin/ninja /usr/local/bin/ninja /usr/bin/ninja-build \
           "$(command -v ninja-build 2>/dev/null || true)" "$(command -v ninja 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    [ "$(head -c 2 "$c")" = "#!" ] && continue      # script, not ninja
    "$c" --version 2>/dev/null | grep -qE '^[0-9]+\.[0-9]+' && { echo "$c"; return 0; }
  done
  return 1
}
NINJA=$(pick_ninja) || { echo "::error::no working ninja binary (set NINJA=/path/to/ninja)"; exit 1; }
echo "ninja: $NINJA ($("$NINJA" --version))"
[ "${FORCE:-0}" = "1" ] && rm -rf out
# round 75 fixup: -llog must be on EVERY target link line — the
# CSARM_EGLW_LOG instrumentation calls __android_log_print from
# BOTH the GL target (loader.c) and the EGL wrapper (egl.c), but
# USE_ANDROID_LOG is OFF in gl4es's default config so its own
# ${log-lib} link (src/CMakeLists.txt) never fires (run #222:
# ld.lld undefined __android_log_print from open_lib, both ABIs).
cmake -S . -B out -G Ninja \
  -DCMAKE_MAKE_PROGRAM="$NINJA" \
  -DCMAKE_TOOLCHAIN_FILE="$NDKROOT/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=${ABI} -DANDROID_PLATFORM=android-24 \
# gl4es declares cmake_minimum_required(VERSION 2.8.12...3.10) —
# CMake 4.x (runner image since 2026-11) needs POLICY_VERSION_MINIMUM
# to configure at all; matters on every cache miss of gl4es-libs.
# NOTE: keep this comment ABOVE the cmake invocation — a '#' inside
# a backslash continuation truncates the command (round 75 fixup).
cmake -S . -B out -G Ninja \
  -DCMAKE_MAKE_PROGRAM="$NINJA" \
  -DCMAKE_TOOLCHAIN_FILE="$NDKROOT/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=${ABI} -DANDROID_PLATFORM=android-24 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_C_STANDARD_LIBRARIES="-lm -llog" \
  -DEGL_WRAPPER=ON -DGLX_STUBS=ON
cmake --build out --parallel $(nproc)
# NB: stay inside gl4es/ is fine — B is absolute (run #196: the cp
# landed in gl4es/bundle/ and the artifact uploaded empty)
found=$(find out lib -name "libGL.so*" 2>/dev/null | head -1)
[ -n "$found" ] || { echo "::error::gl4es libGL.so not produced"; find . -name "*.so*" | head; exit 1; }
mkdir -p "$B"
cp "$found" "$B/libGL.so"
# round 65: the EGL wrapper (cmake target "EGL" -> libEGL.so) ships
# as libEGLgl4es.so - SDL pins it via SDL_VIDEO_EGL_DRIVER (absolute
# path) so SDL creates the desktop-GL context THROUGH gl4es; a live
# gl4es context is what togl/GLM device creation requires (run #207:
# contextless gl4es returned 0 from glCheckFramebufferStatusEXT and
# the FBO gate int3'd).  Renamed to avoid clashing with the bundled
# SwiftShader libEGL.so in lib/<abi>/.
foundegl=$(find out lib -name "libEGL.so*" 2>/dev/null | head -1)
[ -n "$foundegl" ] || { echo "::error::gl4es EGL wrapper not produced (EGL_WRAPPER=ON)"; find . -name "*.so*" | head; exit 1; }
cp "$foundegl" "$B/libEGLgl4es.so"
ls -la "$B"
$NDKROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf -W --dyn-syms "$B/libGL.so" | grep -c "glGenFramebuffersEXT\|glShaderSource" || true
  )
done
ls -la "$R"/thirdparty/gl4es-*/lib*.so
