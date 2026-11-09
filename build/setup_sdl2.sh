#!/bin/bash
# csARM — build SDL 2.0.2 static library for aarch64 Android
# c15/thirdparty/SDL2 ships only headers (2.0.2); sources are downloaded and
# built with the file list from SDL's own Android.mk (android backend only).
# Result: thirdparty/SDL2-lib/libSDL2.a
#
# NOTE: SDL is compiled against ITS OWN pristine headers. Valve's bundled
# headers (c15/thirdparty/SDL2) are a modified variant and are NOT ABI-identical
# for SDL-internal structs (SDL_rwops union etc.); overlaying them on the SDL
# tree breaks SDL's own .c files (missing SDL_RWops.androidio, missing 2.0.x
# hints). The engine only consumes SDL's public C ABI, which is stable.
# dynapi is patched OFF (it #error's on -D override; sed the header) so the
# static lib needs no SDL_Render* symbols: the engine renders via ToGL.
# usage: setup_sdl2.sh [workspace_root] [cache_dir]
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
R=${1:-$REPO_DIR}
CACHE=${2:-$R/.cache}
NDKROOT=${NDKROOT:?NDKROOT must be set}
SRCDIR="$CACHE/SDL-2.0.2"
OUTDIR="$R/thirdparty/SDL2-lib"

mkdir -p "$CACHE" "$OUTDIR"

if [ ! -f "$SRCDIR/src/SDL.c" ]; then
  rm -rf "$CACHE/sdl.tgz"
  echo "downloading SDL 2.0.2 (libsdl.org, fallback GitHub)..."
  curl -sfL --retry 3 -o "$CACHE/sdl.tgz" "https://libsdl.org/release/SDL2-2.0.2.tar.gz" \
    || curl -sfL --retry 3 -o "$CACHE/sdl.tgz" "https://github.com/libsdl-org/SDL/releases/download/release-2.0.2/SDL2-2.0.2.tar.gz" \
    || curl -sfL --retry 3 -o "$CACHE/sdl.tgz" "https://github.com/libsdl-org/SDL/archive/refs/tags/release-2.0.2.tar.gz"
  tar xzf "$CACHE/sdl.tgz" -C "$CACHE"
  # tarball names differ (SDL2-2.0.2 vs SDL-release-2.0.2) — normalize
  for d in "$CACHE/SDL2-2.0.2" "$CACHE/SDL-release-2.0.2"; do
    [ -d "$d" ] && [ "$d" != "$SRCDIR" ] && rm -rf "$SRCDIR" && mv "$d" "$SRCDIR"
  done
fi
[ -f "$SRCDIR/src/SDL.c" ] || { echo "SDL source extraction failed"; exit 1; }

# dynapi off (engine links SDL symbols directly; no full-symbol-table needed)
sed -i 's/#define SDL_DYNAMIC_API 1/#define SDL_DYNAMIC_API 0/' "$SRCDIR/src/dynapi/SDL_dynapi.h"
grep -q "#define SDL_DYNAMIC_API 0" "$SRCDIR/src/dynapi/SDL_dynapi.h" || { echo "dynapi patch failed"; exit 1; }

# csARM round 62: SDL 2.0.2 SDL_EGL_LoadLibrary probes the egl library with
# SDL_LoadFunction(dll_handle, "eglChooseConfig") BEFORE consulting
# SDL_VIDEO_EGL_DRIVER, and with dll_handle==NULL SDL_LoadFunction falls
# through to dlsym(NULL) - which resolves against the GLOBAL namespace and
# finds the SYSTEM libEGL.so (goldfish emulation on the emulator; it SEGVs
# in createNativeSync on every eglSwapBuffers, run #202/#203).  The
# SDL_VIDEO_EGL_DRIVER branch is therefore dead code for every app that
# does not pass an explicit egl_path.  Force the env-var probe FIRST so the
# bundled SwiftShader libEGL.so (csarm_main pins it by absolute path) wins.
# Cache key of the link-toolchain cache includes this script, so the SDL
# rebuild happens automatically.
if ! grep -q "csARM round 62" "$SRCDIR/src/video/SDL_egl.c"; then
  sed -i 's#if (SDL_LoadFunction(dll_handle, "eglChooseConfig") == NULL) {#/* csARM round 62: env-var probe before dlsym(NULL) (see setup_sdl2.sh) */\n    if (SDL_getenv("SDL_VIDEO_EGL_DRIVER") != NULL || SDL_LoadFunction(dll_handle, "eglChooseConfig") == NULL) {#' "$SRCDIR/src/video/SDL_egl.c"
  grep -q "csARM round 62" "$SRCDIR/src/video/SDL_egl.c" || { echo "SDL_egl.c env-var probe patch failed"; exit 1; }
fi

# csARM round 75: instrument the EGL chain inside SDL itself (tag
# CSARM_SDLEGL).  Runs #216-#221 established who calls MakeCurrent and what
# SDL returns, but three links stay invisible at runtime:
#   1. SDL_GL_MakeCurrent's TLS fast-path ("We're already current.") returns 0
#      WITHOUT any EGL call - a real bind is indistinguishable from a TLS hit;
#   2. SDL_EGL_MakeCurrent's null-branch (the unbind the round-74
#      MakeCurrent(NULL,NULL) fix relies on) DISCARDS the raw eglMakeCurrent
#      result and returns 0 unconditionally - a failed unbind looks exactly
#      like a successful one;
#   3. SDL never says WHICH EGL library it actually loaded (the pinned
#      egl_path vs the dlsym(NULL)/DEFAULT_EGL fallback), so the
#      SDL_VIDEO_EGL_DRIVER pin was only ever verified indirectly.
# Every log goes to logcat under CSARM_SDLEGL.  eglGetError is resolved from
# the loaded EGL handle per call (SDL 2.0.2's egl_data has no such member);
# err=0xffffffff means "no eglGetError resolvable".  The link-toolchain cache
# key hashes this script, so the SDL rebuild happens automatically.
if ! grep -q "csARM round 75" "$SRCDIR/src/video/SDL_egl.c"; then
  sed -i 's@#include "SDL_hints.h"@#include "SDL_hints.h"\n\n#if defined(__ANDROID__)\n#include <android/log.h>\n/* csARM round 75: EGL-chain instrumentation (see setup_sdl2.sh) */\n#define CSARM_SDLEGL_LOG(...) __android_log_print(ANDROID_LOG_INFO, "CSARM_SDLEGL", __VA_ARGS__)\n#else\n#define CSARM_SDLEGL_LOG(...) do {} while (0)\n#endif@' "$SRCDIR/src/video/SDL_egl.c"
  grep -q "CSARM_SDLEGL_LOG" "$SRCDIR/src/video/SDL_egl.c" || { echo "SDL_egl.c log macro patch failed"; exit 1; }
  # (a) SDL_EGL_LoadLibrary: which egl_path reached SDL and what display it got
  sed -i 's@    _this->egl_data->egl_display = _this->egl_data->eglGetDisplay(native_display);@    /* csARM round 75 */\n    CSARM_SDLEGL_LOG("EGL_LoadLibrary egl_path=%s dll=%p", egl_path ? egl_path : "(null)", dll_handle);\n    _this->egl_data->egl_display = _this->egl_data->eglGetDisplay(native_display);\n    CSARM_SDLEGL_LOG("EGL_LoadLibrary display=%p", _this->egl_data->egl_display);@' "$SRCDIR/src/video/SDL_egl.c"
  grep -q "EGL_LoadLibrary egl_path=" "$SRCDIR/src/video/SDL_egl.c" || { echo "SDL_egl.c LoadLibrary patch failed"; exit 1; }
  # (b) SDL_EGL_MakeCurrent entry: dpy/surf/ctx identity of every call
  sed -i 's@    if (!egl_context || !egl_surface) {@    /* csARM round 75 */\n    {\n        EGLint (*_csarm_eglGetError)(void) = (EGLint (*)(void)) (_this->egl_data->dll_handle ? SDL_LoadFunction(_this->egl_data->dll_handle, "eglGetError") : NULL);\n        int _csarm_err = _csarm_eglGetError ? (int)_csarm_eglGetError() : -1;\n        CSARM_SDLEGL_LOG("EGL_MakeCurrent enter dpy=%p surf=%p ctx=%p (stale-err=0x%x)", _this->egl_data->egl_display, egl_surface, egl_context, (unsigned)_csarm_err);\n    }\n    if (!egl_context || !egl_surface) {@' "$SRCDIR/src/video/SDL_egl.c"
  grep -q "EGL_MakeCurrent enter dpy=" "$SRCDIR/src/video/SDL_egl.c" || { echo "SDL_egl.c MakeCurrent entry patch failed"; exit 1; }
  # (c) null-branch: capture the DISCARDED unbind result + backend error
  sed -i 's@         _this->egl_data->eglMakeCurrent(_this->egl_data->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);@         /* csARM round 75: the pristine code discarded this result (SDL\n          * returns 0 unconditionally) - capture it for logcat. */\n         {\n             EGLBoolean _csarm_rc = _this->egl_data->eglMakeCurrent(_this->egl_data->egl_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);\n             EGLint (*_csarm_eglGetError)(void) = (EGLint (*)(void)) (_this->egl_data->dll_handle ? SDL_LoadFunction(_this->egl_data->dll_handle, "eglGetError") : NULL);\n             int _csarm_err = _csarm_eglGetError ? (int)_csarm_eglGetError() : -1;\n             CSARM_SDLEGL_LOG("EGL_MakeCurrent NULL-branch dpy=%p ctx=%p surf=%p rc=%d err=0x%x", _this->egl_data->egl_display, egl_context, egl_surface, (int)_csarm_rc, (unsigned)_csarm_err);\n         }@' "$SRCDIR/src/video/SDL_egl.c"
  grep -q "EGL_MakeCurrent NULL-branch" "$SRCDIR/src/video/SDL_egl.c" || { echo "SDL_egl.c null-branch patch failed"; exit 1; }
  # (d) real-branch failure path: log the raw rc before the SetError
  sed -i 's@            return SDL_SetError("Unable to make EGL context current");@            CSARM_SDLEGL_LOG("EGL_MakeCurrent real dpy=%p surf=%p ctx=%p rc=0 FAILED", _this->egl_data->egl_display, egl_surface, egl_context);\n            return SDL_SetError("Unable to make EGL context current");@' "$SRCDIR/src/video/SDL_egl.c"
  grep -q "EGL_MakeCurrent real dpy=" "$SRCDIR/src/video/SDL_egl.c" || { echo "SDL_egl.c real-branch patch failed"; exit 1; }
  # The link-toolchain cache has restore-keys (fallback to the previous
  # prefix), so a pre-round-75 .cache/SDL-2.0.2/build-obj gets restored and
  # build_one skips recompiling objects whose name already exists (path-md5
  # derived).  The two instrumented TUs must be forced to recompile or the
  # shipped libSDL2.so stays pristine (run #223: zero CSARM_SDLEGL lines
  # despite the seds running).
  rm -f "$SRCDIR"/build-obj/*_SDL_egl.c.o
fi
# (e) SDL_video.c: expose the TLS fast-path vs the real driver call
if ! grep -q "csARM round 75" "$SRCDIR/src/video/SDL_video.c"; then
  sed -i 's@/\* The high-level video driver subsystem \*/@/* The high-level video driver subsystem */\n\n#if defined(__ANDROID__)\n#include <android/log.h>\n/* csARM round 75: EGL-chain instrumentation (see setup_sdl2.sh) */\n#define CSARM_SDLEGL_LOG(...) __android_log_print(ANDROID_LOG_INFO, "CSARM_SDLEGL", __VA_ARGS__)\n#else\n#define CSARM_SDLEGL_LOG(...) do {} while (0)\n#endif@' "$SRCDIR/src/video/SDL_video.c"
  grep -q "CSARM_SDLEGL_LOG" "$SRCDIR/src/video/SDL_video.c" || { echo "SDL_video.c log macro patch failed"; exit 1; }
  sed -i 's@        /\* We'"'"'re already current. \*/@        /* We'"'"'re already current. */\n        CSARM_SDLEGL_LOG("GL_MakeCurrent FAST-PATH win=%p ctx=%p (no EGL call)", window, ctx);@' "$SRCDIR/src/video/SDL_video.c"
  grep -q "GL_MakeCurrent FAST-PATH" "$SRCDIR/src/video/SDL_video.c" || { echo "SDL_video.c fast-path patch failed"; exit 1; }
  sed -i 's@    retval = _this->GL_MakeCurrent(_this, window, ctx);@    retval = _this->GL_MakeCurrent(_this, window, ctx);\n    CSARM_SDLEGL_LOG("GL_MakeCurrent driver win=%p ctx=%p -> %d", window, ctx, retval);@' "$SRCDIR/src/video/SDL_video.c"
  grep -q "GL_MakeCurrent driver win=" "$SRCDIR/src/video/SDL_video.c" || { echo "SDL_video.c driver-call patch failed"; exit 1; }
  rm -f "$SRCDIR"/build-obj/*_SDL_video.c.o
fi

export PATH="$NDKROOT/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
CC=${CC:-aarch64-linux-android24-clang}   # x86_64 link jobs pass x86_64-linux-android24-clang

# File list mirroring SDL 2.0.2's Android.mk (android backend set).
# src/render/* and src/video/yuv2rgb excluded: engine renders via ToGL and
# never calls SDL_Render*; this also drops the gles2/psp proc-pointer code
# that clang 18 rejects outright.
SRCS=$(cat <<'EOF'
src/*.c
src/audio/*.c
src/audio/android/*.c
src/audio/dummy/*.c
src/atomic/SDL_atomic.c
src/atomic/SDL_spinlock.c
src/core/android/*.c
src/cpuinfo/*.c
src/dynapi/*.c
src/events/*.c
src/file/*.c
src/haptic/*.c
src/haptic/dummy/*.c
src/joystick/*.c
src/joystick/android/*.c
src/loadso/dlopen/*.c
src/power/*.c
src/power/android/*.c
src/filesystem/dummy/*.c
src/stdlib/*.c
src/thread/*.c
src/thread/pthread/*.c
src/timer/*.c
src/timer/unix/*.c
src/video/*.c
src/video/android/*.c
src/video/dummy/*.c
EOF
)

FILES=""
for pat in $SRCS; do
  for f in "$SRCDIR"/$pat; do
    [ -f "$f" ] && FILES="$FILES $f"
  done
done
# SDL_compat.c is the 1.2->2.0 shim (SDL_SetVideoMode etc.): it is the ONLY
# non-render file that references SDL_CreateRenderer/SDL_RenderCopy/... and the
# engine never calls 1.2 APIs.  Leaving it in leaves those symbols UND in
# libSDL2.so -> guaranteed dlopen failure on device.
FILES=$(echo "$FILES" | tr ' ' '\n' | grep -v "src/SDL_compat.c" | tr '\n' ' ')
echo "SDL sources: $(echo $FILES | wc -w)"
[ "$(echo $FILES | wc -w)" -lt 60 ] && { echo "too few SDL sources — file list broken"; exit 1; }

mkdir -p "$SRCDIR/build-obj" "$SRCDIR/build-err"
rm -f "$SRCDIR/build-err/fails.txt"
build_one() {
  f="$1"
  obj="$SRCDIR/build-obj/$(echo "$f" | md5sum | cut -c1-10)_$(basename "$f").o"
  [ -s "$obj" ] && return 0
  $CC -c -fPIC -O2 -w \
    -DANDROID=1 \
    -Wno-error=incompatible-function-pointer-types \
    -Wno-incompatible-function-pointer-types \
    -Wno-error=implicit-function-declaration \
    -I"$SRCDIR/include" \
    -DGL_GLEXT_PROTOTYPES \
    "$f" -o "$obj" 2> "$SRCDIR/build-err/$(basename "$f").log" || echo "FAIL $f" >> "$SRCDIR/build-err/fails.txt"
}
export -f build_one
export CC SRCDIR

echo "$FILES" | tr ' ' '\n' | grep -v '^$' | xargs -P4 -n1 bash -c 'build_one "$0"'
if [ -f "$SRCDIR/build-err/fails.txt" ]; then
  echo "SDL2 build failures:"; cat "$SRCDIR/build-err/fails.txt"
  for f in $(cat "$SRCDIR/build-err/fails.txt" | sed 's/FAIL //' | xargs -n1 basename 2>/dev/null); do
    [ -f "$SRCDIR/build-err/$f.log" ] && { echo "--- $f"; head -6 "$SRCDIR/build-err/$f.log"; }
  done
  exit 1
fi

rm -f "$OUTDIR/libSDL2.a" "$OUTDIR/libSDL2.so"
# renderer-API stubs (SDL_video.c references SDL_CreateRenderer etc. via its
# window-framebuffer path; src/render/* is excluded from this build)
SDLSTUB="$R/build/stub_sdl_render.c"
[ -f "$SDLSTUB" ] && $CC -c -fPIC -O2 -w -DANDROID=1 -I"$SRCDIR/include" \
  "$SDLSTUB" -o "$SRCDIR/build-obj/csarm_sdl_render_stub.o" || echo "WARN: no sdl render stub"
ar rcs "$OUTDIR/libSDL2.a" "$SRCDIR/build-obj"/*.o
# shared build: single SDL instance shared by engine/vgui/vguimatsurface (DT_NEEDED)
$CC -shared -fPIC -fuse-ld=lld -Wl,-soname,libSDL2.so \
  -o "$OUTDIR/libSDL2.so" "$SRCDIR/build-obj"/*.o \
  -lGLESv1_CM -lGLESv2 -lEGL -llog -landroid -ldl -lm -lc 2>> "$SRCDIR/build-err/link-so.log" \
  || { echo "libSDL2.so link failed:"; cat "$SRCDIR/build-err/link-so.log" | head -20; exit 1; }
echo "libSDL2.a: $(du -h "$OUTDIR/libSDL2.a" | cut -f1)"
echo "libSDL2.so: $(du -h "$OUTDIR/libSDL2.so" | cut -f1)"
