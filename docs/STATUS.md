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
- build: 9 matrix jobs (core, engine, render, vgui, data, client, server, pb25)
- link: libprotobuf → tier0/1/2 → vstdlib/mathlib → subsystems → engine/game
- tests: qemu-aarch64 mathlib unit tests (needs `-I c15/thirdparty` for
  `<sse2neon/sse_shim.h>`)
- source cache key v2; patches applied idempotently on every run.

## Next
1. Verify CI green after 07a8008 (expect ~1780 files, 0 fail).
2. Link all .so (link.sh): resolve undefined symbols iteratively.
3. SDL2 for Android (thirdparty/SDL2 → libSDL2.a) + APK packaging.
4. Optimization: -O2, LTO, gc-sections, NEON paths; measure.
5. Runtime smoke test: engine + minimal map under qemu-user or Android.
