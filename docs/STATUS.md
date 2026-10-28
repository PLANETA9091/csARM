# CS:GO (cstrike15_src) → Android/aarch64 port — STATUS

Workspace: `/data/data/com.termux/files/home/csgo_port`
Clone: `./c15` (sparse checkout of cstrike15_src; branch `csgo`)
Toolchain: `aarch64-linux-android-clang` (Termux NDK), protobuf 35.1 (system)

## Build flags (`trybuild.sh`)

```
CC=aarch64-linux-android-clang
OPT=-O0 (temp; target -O2+LTO)
std  = -std=gnu++17   (.c files use gnu11)
DEF  = -include protocompat.h -Wno-narrowing -Wno-register
       -DDX_TO_GL_ABSTRACTION -DX64BITS
       -DPOSIX=1 -DLINUX=1 -D_LINUX=1 -DGNUC=1 -DPLATFORM_64BITS=1 -DCOMPILER_GCC=1
       -D_POSIX=1 -D__ANDROID__=1 -DENGINE_DLL=1 -USE_SDL=1
       -Dpthread_yield=sched_yield -Dstricmp=strcasecmp -Dstrnicmp=strncasecmp
INC  = c15, public{,/tier0,/tier1,/tier2,/mathlib,/steam,/vgui_controls},
       common, tier0/1/2, vstdlib, mathlib, engine, engine/audio{,/public,/private},
       thirdparty{,/telemetry/include,/SDL2,/quickhull}, external, external/crypto++-5.61,
       genproto, pbshim, gcsdk, gcsdk/steamextra/tier1,
       game/shared, game/shared/cstrike15, game/client, game/server
```

## Compile status

| module  | ok  | fail |
|---------|-----|------|
| tier0   | 37  | 0    |
| tier1   | 45  | 0    |
| tier2   | 21  | 0    |
| vstdlib | 10  | 0    |
| mathlib | 33  | 0    |
| engine  | 250*| 0*   |  *pre-USE_SDL run; clean rebuild in progress

## Key port decisions
- `-DDX_TO_GL_ABSTRACTION`: use ToGL (Valve's GL abstraction) instead of D3D9 → resolves `D3DFORMAT` etc.
- `-DENGINE_DLL`: enables engine-only members (e.g. `CGameTrace::GetEdict/SetEdict`).
- `-DUSE_SDL`: Linux/Android windowing path in sys_mainwind/sys_dll2/sys_getmodes.
- protobuf 35.1 generated classes are `final` and use `std::string_view`; subclasses
  (`CNetMessagePB`) required stripping `final`/`PROTOBUF_FINAL` from `genproto/*.pb.h`
  and removing Valve's `EXPLICIT` macro (platform.h) that clashed with the pb enum.
- `pbshim/`: patched protobuf headers (`schema`→`pb_schema_`).
- `protocompat.h`: `bswap_16/32/64` + `__bswap_16/32/64` builtins (forced include).

## Patches applied (new clone)
- `public/tier0/platform.h`: offsetof→`__builtin_offsetof`, INT/UINT_MAX literals,
  DebuggerBreak/Plat_Rdtsc aarch64, removed `EXPLICIT` macro.
- `public/tier0/{threadtools.h,microprofiler.h,basetypes.h,hardware_clock_fast.h}` (aarch64).
- `public/tier0/memalloc.h`: offsetof→builtin.
- `public/mathlib/{mathlib.h,ssemath.h,ssemath_x86.h,vector.h,math_pfns.h,vector4d.h}`:
  ARM Round*/FastSinCos branches; x87 `fistpl`→C.
- `public/tier1/{utlblockmemory.h,byteswap.h}`; `public/tier1/tokenset.h` (+strtools.h).
- `public/dt_common.h`, `public/gcsdk/gcclientsdk.h`: offsetof→builtin.
- `thirdparty/telemetry/include/radtypes.h` (+aarch64).
- `common/protobuf_helpers.cpp`: old protobuf log API disabled.
- `common/netmessages.h`: `GetTypeName()` wrapped in `std::string`.
- `tier0/cpu.cpp`, `tier1/processor_detect_linux.cpp`: cpuid no-op on ARM.
- `tier1/pathmatch.cpp`, `tier1/strtools.cpp`, `vstdlib/vstrtools.cpp` (iconv).
- `mathlib/sse.cpp`: ARM VectorNormalize/FastCos.
- `engine/{view.cpp,gl_screen.cpp,vgui_baseui_interface.cpp,sys_mainwind.cpp}`: Scaleform disabled.
- `engine/{cl_steamauth.cpp,sv_steamauth.cpp,sys_dll2.cpp}`: newer Steamworks API
  (`SteamAPI_Init`, no `*_InitSafe`, no `SteamAPI_SetBreakpadAppID/UseBreakpadCrashHandler`).
- `engine/sys_getmodes.cpp`: POSIX no-op branch.
- `crypto++-5.61/pubkey.h`: `std::auto_ptr`→`std::unique_ptr`.

## Excluded from engine build
`openal`, `voice_record_dsound`, `voice_mixer_controls` (no OpenAL / Windows-only).

## Sparse checkout present
public tier0 tier1 tier2 vstdlib mathlib common engine thirdparty/{telemetry,SDL2,sse2neon,quickhull}
gcsdk game/shared external vpc_scripts utils/common utils/bzip2
materialsystem vgui2 vguimatsurface studiorender datacache soundemittersystem scaleformui appframework

## Next
1. Finish clean engine rebuild (0 errors expected).
2. Build supporting modules: materialsystem, vgui2, vguimatsurface, studiorender, datacache,
   soundemittersystem, serverbrowser, game/client (client_cstrike15), game/server.
3. Generate `hostversion.h` (GetHostVersion) for baseclientstate scheme versioning.
4. Link client binary; then optimize (-O2/LTO/gc-sections/strip, NEON).
