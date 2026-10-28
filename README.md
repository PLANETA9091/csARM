# csARM — CS:GO (cstrike15_src) → Android ARM64 port

Портирование CS:GO (cstrike15_src) на Android aarch64. Репозиторий содержит
систему сборки, патчи и CI; исходный код движка скачивается из публичного
зеркала `perilouswithadollarsign/cstrike15_src` и патчится при сборке.

## Архитектура

```
csARM/
├── build/               # система сборки
│   ├── vpcmini.py       # парсер Valve VPC проектов
│   ├── trybuild.sh      # компиляция одного модуля (NDK clang; .vpc или .txt список)
│   ├── setup_source.sh  # скачивание зеркала + применение патчей (идемпотентно)
│   ├── setup_proto.sh   # protoc 2.5.0 (кэш .cache/protoc25) + регенерация genproto
│   ├── link.sh          # линковка .so (libprotobuf → tier* → подсистемы → engine/game)
│   └── protocompat.h    # forced-include: byteswap (glibc/bionic-safe)
├── thirdparty/pb25shim/ # aarch64-атомики для protobuf 2.5.0 (std::atomic)
├── patches/
│   ├── all_patches.diff # все патчи порта против чистого зеркала
│   └── extras/          # новые файлы (unicode_native.h, IVGUI.h, sse2neon)
├── genproto/            # сгенерированные protobuf-классы (protoc 2.5.0)
├── protoroot/           # .proto исходники
└── .github/workflows/   # CI: матричная сборка + линковка + qemu-тесты
```

## Быстрый старт (Linux x86_64 host)

```bash
# 1. NDK r27d
curl -L -o ndk.zip https://dl.google.com/android/repository/android-ndk-r27d-linux.zip
unzip -q ndk.zip && export NDKROOT=$PWD/android-ndk-r27d
export PATH=$NDKROOT/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH

# 2. Исходник + патчи (+ genproto при необходимости)
./build/setup_source.sh "$PWD"
./build/setup_proto.sh "$PWD"

# 3. Сборка модуля
R=$PWD JOBS=$(nproc) bash build/trybuild.sh tier0/tier0.vpc
```

## Ключевые решения порта

- **protobuf 2.5.0** — тот же, что в `thirdparty/protobuf-2.5.0` зеркала: код Valve
  написан под его API, поэтому genproto регенерируется protoc 2.5.0 и abseil
  не требуется вовсе. protobuf 2.5.0 древнее aarch64 — в
  `thirdparty/pb25shim/google/protobuf/stubs/atomicops_internals_std_atomic.h`
  атомики реализованы через C++11 `std::atomic` (clang разворачивает их в
  ldaxr/stlxr на ARMv8), а `platform_macros.h` учит `__aarch64__`.
- `-DDX_TO_GL_ABSTRACTION` — рендер через ToGL (GL-абстракция Valve) вместо D3D9.
  На Android header'ы desktop GL нужны только для компиляции (типы/константы);
  все функции резолвятся в рантайме через `dlsym` (`COpenGLEntryPoints`).
- `-DANDROID -DANDROID=1` — ветки bionic; `unicode_native.h` заменяет `iconv`
  (bionic его не имеет) нативными конвертерами UCS-2 ↔ UTF-8 ↔ UTF-32.
- `-DENGINE_DLL`, `-DUSE_SDL` — оконный путь SDL2, включение engine-членов.
- HTTP-загрузка карт (libcurl) заглушена на Android (патч `downloadthread.cpp`);
  fontconfig исключён (патч `MatSystemSurface.cpp`).

## Статус сборки

См. [docs/STATUS.md](docs/STATUS.md). CI: Actions → csARM CI (матрица модулей).

## Roadmap

1. ✅ Core-модули (tier0/1/2, vstdlib, mathlib, appframework)
2. ✅ Engine 250 файлов
3. ⏳ materialsystem / vgui / studiorender / datacache / soundemittersystem
4. ⏳ client + server (cstrike15)
5. ⏳ Линковка .so + SDL2 Android APK
6. ⏳ Оптимизация: -O2/LTO/NEON, gc-sections
