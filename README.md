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

## Локальный тестовый цикл (без GitHub CI)

Всё, что делает CI, теперь можно прогнать на своей машине — сборка GL-стека,
эмулятор, стадия контента и оба «проба»-теста. Это единственный способ отлаживать
краши рендера быстрее, чем за 30–50 минут раунда CI.

```bash
export ANDROID_HOME=$HOME/android-sdk            # sdkmanager, platform-tools, emulator
export NDKROOT=$PWD/android-ndk-r27d             # r27d

# GL-стек: тот же скрипт, что запускает CI (пин + все патчи внутри)
bash build/setup_gl4es.sh "$PWD" x86_64

# APK: .so из out/ (или из CI-артефактов so-libs-x86_64) + SwiftShader + gl4es
CSARM_OUT=$PWD/android/b-x86_64 bash android/build_apk.sh x86_64 swiftshader

# эмулятор (x86_64 AOSP ATD под KVM; сам правит AVD, см. local_emu.sh)
bash test/local_emu.sh up
adb install -r -t android/b-x86_64/csARM.apk

# контент (распакованный depot, внутри cstrike/)
bash test/local_stage.sh /path/to/csgo-content

# проверки
bash test/local_boot.sh 90                 # LauncherMain + отсутствие крашей
bash test/local_probe.sh ar_dizzy          # реальный рендер: +map ar_dizzy
bash test/symbolize.sh android/libs/x86_64 .local/probe/logcat_map.txt
```

`test/local_probe.sh` печатает вердикт (маркеры `Host_NewGame`/`Loading map`,
SIGSEGV-бэктрейс с адресами) и складывает полные логи в `.local/probe/`.
`test/symbolize.sh` разворачивает `lib*.so+offset` в `файл:строка` по
нестрипленным библиотекам из сборки.

Если карты нет в контенте — движок падает в `Sys_Version()` («Unable to load
version from steam.inf»): VPK-сет не смонтирован. `test/local_stage.sh`
дописывает минимальный `cstrike/steam.inf` из пяти ключей, чтобы проба шла
дальше.

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
3. ✅ materialsystem / vgui / studiorender / datacache / soundemittersystem
4. ✅ client + server (cstrike15)
5. ✅ Линковка .so (20 шт: + launcher, inputsystem, main) + SDL2 Android APK
6. ✅ Запуск движка на устройстве: libmain → LauncherMain → CSourceAppSystemGroup
7. ✅ Оптимизация: -O2 + ThinLTO по умолчанию, NEON (sse2neon), gc-sections, 16KB pages, многопоточный движок (host_thread_mode/mat_queue_mode)
8. ⏳ Рендер без HW: software GPU путь (swiftshader_indirect в CI) + бандл SwiftShader в APK
9. ⏳ Загрузка реального контента (VPK) с карты в filesDir/cstrike
