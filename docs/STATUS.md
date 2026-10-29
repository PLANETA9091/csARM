# CS:GO (cstrike15_src) → Android/aarch64 port — STATUS

Workspace: CI (GitHub Actions, matrix) + local validation via host g++
Clone: `./c15` (sparse checkout of cstrike15_src at pinned SHA f82112a; created by setup_source.sh)
Toolchain: NDK r27d `aarch64-linux-android24-clang` (CI), protobuf **2.5.0** (from the mirror tree)

## Build flags (`trybuild.sh`)

```
CC   = aarch64-linux-android24-clang
OPT  = -O1 (CI default; -O0 for local host validation)
std  = -std=gnu++17   (.c files use gnu11)
DEF  = -include protocompat.h -Wno-narrowing -Wno-register
       -DDX_TO_GL_ABSTRACTION -DCSARM_GL_SHIM -DX64BITS
       -DPOSIX=1 -DLINUX=1 -D_LINUX=1 -DGNUC=1 -DPLATFORM_64BITS=1 -DCOMPILER_GCC=1
       -D_POSIX=1 -D__ANDROID__=1 -DANDROID=1 -DENGINE_DLL=1 -DUSE_SDL=1
       -Dpthread_yield=sched_yield -Dstricmp=strcasecmp -Dstrnicmp=strncasecmp
DEFX = per-matrix Valve-style defs (DCLIENT_DLL=1 → -DCLIENT_DLL=1; plain
       FOO=1 → -DFOO=1), normalized in trybuild.sh
INC  = protobuf-2.5.0/src, pb25shim, glshim, c15 (+public/tier0/1/2, common,
       mathlib, engine, gcsdk, game/shared[/cstrike15], game/server/cstrike15,
       game/client, engine/audio...), genproto, freetype, crypto++-5.61
Per-tag: server → -I c15/game/server; client → -I c15/game/client -I c15/engine
```

## Protobuf strategy (v2)

Valve's code targets protobuf **2.5.0**, which is bundled in the mirror at
`thirdparty/protobuf-2.5.0`. genproto is regenerated with protoc 2.5.0
(`build/setup_proto.sh`, host protoc cached in `.cache/protoc25`); no abseil.
protobuf 2.5.0 predates aarch64 → `thirdparty/pb25shim/.../atomicops_internals_std_atomic.h`
implements AtomicOps via C++11 `std::atomic`; `platform_macros.h` teaches
`__aarch64__`. Runtime is built as CI module `pb25` (lists/protobuf25.txt,
32 files) and linked as `libprotobuf.so`.

## Compile status (CI run 40717175869, pre-fix baseline)

| module            | ok  | fail | notes                          |
|-------------------|-----|------|--------------------------------|
| tier0             | 37  | 0    |                                |
| tier1             | 45  | 0    |                                |
| tier2             | 21  | 0    |                                |
| vstdlib           | 10  | 0    |                                |
| mathlib           | 33  | 0    |                                |
| appframework      | 3   | 0    |                                |
| bzip2             | 8   | 0    |                                |
| engine            | 249 | 2    | XUnzip futimes, crypto++ bswap — fixed |
| materialsystem    | 28  | 0    |                                |
| studiorender      | 13  | 0    |                                |
| vguimatsurface    | 7   | 1    | fontconfig — already patched (stale CI cache) |
| vgui_dll          | 20  | 0    |                                |
| vgui_controls     | 79  | 1    | protobuf — fixed by 2.5.0 switch |
| datacache         | 11  | 0    |                                |
| soundemittersystem| 3   | 0    |                                |
| filesystem_stdio  | 10  | 0    |                                |
| client_cstrike15  | 623 | 16   | view.h shadowing + DEFX — fixed |
| server_cstrike15  | 599 | 15   | offsetof + DEFX — fixed        |
| pb25              | 32  | 0    | protobuf 2.5.0 runtime         |

Fixes after that run (commit 07a8008): Valve offsetof restored, DEFX double-D
bug, client include priority (view.h), crypto++ builtins, XUnzip futimens,
msgprotobuf Hdr() fix, bsplib allocator-generic overloads, ai_movesolver round,
spawn_helper_nut stub, zlib sparse, KHR stub.

## Key port decisions
- **offsetof**: Valve's pointer-arithmetic macro, NOT `__builtin_offsetof`
  (the builtin rejects `SENDINFO_VECTORELEM`'s `m_Value[i]` on NetworkVar
  wrappers; Valve's own comment in platform.h warns about exactly this).
- `-DDX_TO_GL_ABSTRACTION`: ToGL instead of D3D9; desktop GL headers
  compile-time only (glshim), runtime via dlsym.
- `unicode_native.h` replaces iconv (bionic lacks it).
- HTTP map downloads (libcurl) stubbed on Android; fontconfig excluded.
- ScaleForm HUD kept (INCLUDE_SCALEFORM comes from the VPC project); engine
  ScaleForm entry points disabled as before.

## Patches applied (all_patches.diff, 1932 lines)
aarch64 platform fixes, ARM math branches, iconv replacement, Steamworks API
update, protobuf aarch64 atomics, curl/fontconfig stubs, misc compile fixes.
extras: unicode_native.h, IVGUI.h, gameeventlistener.h, spawn_helper_nut.h,
sse2neon (+ sse_shim.h).

## CI
- build: 9 matrix jobs (core, engine, render, vgui, data, client, server, pb25);
  strict summary: any err>0 or zero-object module fails the job
- link: libSDL2 -> libprotobuf -> tier0/1/2 -> vstdlib/mathlib/tier2 ->
  subsystems (datacache, studiorender, soundemittersystem, vguimatsurface,
  vgui, vgui_controls, materialsystem) -> engine (+genproto) -> client/server
- visual-test: APK (no-gradle aapt2/d8/apksigner build) -> API 30 x86_64
  google_apis emulator (ARM64 translation) -> dlopen all 17 libs + GLES2
  animated scene -> screencaps + logcat assertions as artifacts
- tests: qemu-aarch64 mathlib unit tests (needs `-I c15/thirdparty` for
  `<sse2neon/sse_shim.h>`)

## Link status (verified locally, NDK r27d, 2026-10-28)

ALL 18 libraries link clean:

| lib | size (-O1, unstripped) | deps |
|-----|------------------------|------|
| libSDL2.so | 665 KB | system (GLES1/2, EGL, log, android) |
| libprotobuf.so | 1.2 MB | system |
| libtier0.so | 270 KB | system |
| libtier1.so | 664 KB | tier0 |
| libvstdlib.so | 284 KB | tier0 tier1 |
| libmathlib.so | 357 KB | tier0 tier1 |
| libtier2.so | 211 KB | tier0 tier1 |
| libappframework.so | 109 KB | tier0 tier1 |
| libdatacache.so | 746 KB | + vstdlib |
| libstudiorender.so | 905 KB | + mathlib |
| libsoundemittersystem.so | 131 KB | + mathlib |
| libvguimatsurface.so | 262 KB | + tier2 SDL2 |
| libvgui.so | 313 KB | + tier2 SDL2 |
| libvgui_controls.so | 3.1 MB | + vgui |
| libmaterialsystem.so | 2.0 MB | + tier2 |
| libengine.so | 12.6 MB | tier0/1/2 vstdlib mathlib protobuf SDL2 + GLESv2/OpenSLES |
| libclient.so | 23.6 MB | engine deps (+ SDL2) |
| libserver.so | 26.7 MB | engine deps |

Key link decisions:
- **libSDL2.so is shared** (was static): engine, vgui, vguimatsurface all
  reference SDL symbols -> one runtime instance via DT_NEEDED.
- **libc++_shared** for every .so: single STL heap + unified std type_info
  across 17 libs (cross-.so exceptions).
- EXCLUDE_RE in link.sh drops objects with colliding/overridden definitions:
  tier0/mem_helpers.cpp (g_pszModule dup with memoverride; no refs to its
  symbols), client weapon_parse_default + c_mod_lesson_stubs (cstrike15
  overrides), server game/server/player_pickup.cpp (cstrike15 override).
- protobuf 2.5.0 shim: const-volatile ToStd overloads; hand-rolled config.h
  for bionic (HAVE_PTHREAD, no zlib -> gzip_stream.cc excluded).
- SDL 2.0.2 built from official tarball against ITS OWN headers with
  -DANDROID=1 (SDL 2.0.2 predates __ANDROID__ gating in SDL_rwops.h); dynapi
  patched off; render/yuv2rgb dropped (engine renders via ToGL).

## CI status: GREEN (run 40879810114, 2026-10-29, dual-ABI)

- build matrix: **16/16 jobs** (8 tags × arm64-v8a/x86_64), -O2 + ThinLTO, 0 errors
- link: **20/20 .so per ABI** (18 port libs + launcher + inputsystem) + libmain.so
- tests/qemu-aarch64: math suite ALL PASSED + **VISUAL_OK** (480x320 PNG
  rendered by the ported mathlib under qemu-aarch64, artifact
  `test-results/out/frame.png`)
- **boot/emulator-x86**: universal flow check on ubuntu runner — x86_64
  emulator runs TCG-only (no KVM on GH runners) and reached "All files loaded,
  notifying device" ~7 min in; first attempts hit package-manager settling
  (broken-pipe install) — boot wait + install retries added (d026e2b)
- visual/emulator (macos-14, arm64): opportunistic, HVF HV_UNSUPPORTED on
  GH runners; APK artifact `csARM-apk` uploads regardless

## Optimization knobs

`workflow_dispatch` inputs: `opt_level` (**-O2 default** since 0.2 / -O1 / -Oz),
`lto` (**ThinLTO default ON**: trybuild adds -flto=thin
-ffunction/data-sections at compile, link.sh links with -flto=thin), `strip`
(llvm-strip --strip-debug on linked .so). Every linked .so also gets
`-Wl,-z,max-page-size=16384` (16 KB-page device compatibility, Android 15+).
Engine threading (real acceleration on big.LITTLE) is enabled in the launch
profile: `host_thread_mode 2`, `mat_queue_mode 2`, `cl_threaded_bone_setup 1`
(autoexec.cfg + libmain defaults); mathlib runs through sse2neon NEON.

## Runtime: full engine boot path (v0.2)

The APK now actually **launches the engine** (not only dlopen checks):

```
CSARMActivity (Java, SDLActivity subclass)
  └─ loads 19 port libs in dependency order (logcat CSARM_LIB_OK/FAIL)
  └─ writes files/csarm.args + extracts assets/cstrike skeleton (gameinfo.txt)
  └─ SDLActivity static: libSDL2.so + libmain.so
       └─ libmain (launcher_native/csarm_main.cpp):
            SDL_Android_Init -> stdout/stderr piped to logcat (CSARM_ENG tag)
            argv builder (csarm.args or fast-boot defaults)
            <files>/bin/<name>.so symlinks  (Valve Sys_LoadModule("<cwd>/bin/.."))
            dlopen liblauncher.so -> dlsym "LauncherMain" -> call
                 └─ Valve CSourceAppSystemGroup: filesystem_stdio -> materialsystem
                    -> datacache -> studiorender -> soundemittersystem
                    -> inputsystem -> vguimatsurface -> vgui2 -> engine
                    (VEngineAPI007) -> IEngineAPI::Run()
```

New pieces since 0.1:
- **launcher module** (`lists/launcher.txt`): Valve's `launcher/launcher.cpp`
  + `reslistgenerator.cpp` + `public/filesystem_init.cpp` -> `liblauncher.so`.
  `TryToLoadSteamOverlayDLL` is WIN32-only; POSIX launcher needs no steam_api.
- **inputsystem module** (sparse + matrix): engine's appsystem list requires it.
- **libmain.so** (`launcher_native/`): SDL android glue moved OUT of libSDL2
  (no undefined SDL_main in libSDL2), logcat spew pipe, boot timer
  (`CSARM_LAUNCHER_CALL pre_ms=...` asserted < 60 s by CI), bin/ symlinks.
- **engine frame proof**: `patches/extras/csarm_boot.diff` logs
  `CSARM_ENGINE_FIRST_FRAME` / `CSARM_ENGINE_TICK N` from `CEngine::Frame`
  (`__ANDROID__`-only).
- **CI boot gate**: emulator (`-gpu swiftshader_indirect` = pure software
  rendering, no GPU) boots CSARMActivity; assertions: NATIVE_INIT -> ARGS ->
  BIN_LINKS -> LAUNCHER_CALL; ENGINE_TICK confirms the frame loop runs
  **без hardware**; `BOOT_TO_LAUNCHER_MS` recorded as the fast-start metric.
- APK assets: minimal `cstrike/gameinfo.txt` + `cfg/autoexec.cfg` skeleton so
  the filesystem mounts; real game VPKs are user-provided on device.

## Next
1. Fix whatever the first boot run uncovers (module/interface mismatches are
   expected — iterate against logcat artifact `visual-test/logcat_boot.txt`).
2. Game-data strategy: user-provided CS:GO VPKs -> filesDir/cstrike with real
   content; menu + map load on device.
3. Measure -O2+ThinLTO size/perf deltas; consider PGO-style profile hints.
4. Re-enable hard emulator gate when GitHub restores KVM/HVF.

