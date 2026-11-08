//= csARM — Android native launcher (libmain.so) =============================
// Replaces SDL2's SDL_android_main.c inside our libSDL2 build (that file was
// excluded from the SDL source list; its JNI entry lives HERE instead).
//
// Boot flow (mirrors Valve's launcher_main/main.cpp POSIX branch):
//   SDLActivity(Java) -> nativeInit() [this lib]
//     -> SDL_Android_Init + logcat pipe for stdout/stderr
//     -> SDL_main(argc, argv) [this lib]
//        -> build argv (files/csarm.args or defaults)
//        -> <files>/bin/*.so symlinks (Valve Sys_LoadModule compatibility)
//        -> dlopen liblauncher.so -> dlsym "LauncherMain" -> call
//
// Every stage logs "CSARM_*" lines so CI can assert real engine boot.
//============================================================================

#include <jni.h>
#include <android/log.h>
#include <dlfcn.h>
#include <unistd.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <pthread.h>
#include <dirent.h>
#include <errno.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <time.h>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  "CSARM", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "CSARM", __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN,  "CSARM", __VA_ARGS__)

// ---------------------------------------------------------------------------
// Boot timing: process start -> SDL_main entry (CI asserts this is small).
// ---------------------------------------------------------------------------
static long long nowMs()
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000LL + ts.tv_nsec / 1000000LL;
}
static long long g_llLibLoadMs = -1;

__attribute__((constructor(101))) static void csarm_ctor()
{
    g_llLibLoadMs = nowMs();
}

// ---------------------------------------------------------------------------
// stdout/stderr -> logcat pipe (engine Msg/Warning/Error become visible).
// ---------------------------------------------------------------------------
static void *logcat_pipe_thread(void *arg)
{
    int fd = (int)(intptr_t)arg;
    char buf[1024];
    ssize_t n;
    std::string pending;
    while ((n = read(fd, buf, sizeof(buf) - 1)) > 0)
    {
        buf[n] = '\0';
        pending.append(buf);
        size_t pos;
        while ((pos = pending.find('\n')) != std::string::npos)
        {
            std::string line = pending.substr(0, pos);
            pending.erase(0, pos + 1);
            if (!line.empty())
                __android_log_print(ANDROID_LOG_INFO, "CSARM_ENG", "%s", line.c_str());
        }
    }
    if (!pending.empty())
        __android_log_print(ANDROID_LOG_INFO, "CSARM_ENG", "%s", pending.c_str());
    return nullptr;
}

static void redirectStdioToLogcat()
{
    int fds[2];
    if (pipe(fds) != 0) return;
    // keep original fds alive (engine may reopen); just replace 1 and 2
    dup2(fds[1], STDOUT_FILENO);
    dup2(fds[1], STDERR_FILENO);
    if (fds[1] > STDERR_FILENO) close(fds[1]);
    pthread_t th;
    pthread_create(&th, nullptr, logcat_pipe_thread, (void*)(intptr_t)fds[0]);
    pthread_detach(th);
    setvbuf(stdout, nullptr, _IONBF, 0);
    setvbuf(stderr, nullptr, _IONBF, 0);
}

// ---------------------------------------------------------------------------
// SDL glue (same contract as SDL2-2.0.2 src/main/android/SDL_android_main.c)
// ---------------------------------------------------------------------------
extern "C" void SDL_Android_Init(JNIEnv* env, jclass cls);   // libSDL2.so
extern "C" void SDL_SetMainReady(void);                      // libSDL2.so
extern "C" int  SDL_main(int argc, char *argv[]);            // defined below

// defined below (keep C linkage: libSDL2's flow expects the plain symbol)
extern "C" JNIEXPORT void JNICALL
Java_org_libsdl_app_SDLActivity_nativeInit(JNIEnv* env, jclass cls, jobject obj)
{
    (void)obj;
    SDL_Android_Init(env, cls);
    SDL_SetMainReady();
    redirectStdioToLogcat();
    LOGI("CSARM_NATIVE_INIT ok (lib load -> init: %lld ms)", g_llLibLoadMs >= 0 ? nowMs() - g_llLibLoadMs : -1);

    // SDL_main on this thread, dummy args like stock SDL (real argv built inside)
    char *argv[2];
    argv[0] = strdup("csARM");
    argv[1] = NULL;
    SDL_main(1, argv);
    // NOTE: no exit() here — the app process must survive SDL_main return
}

// ---------------------------------------------------------------------------
// argv building: files/csarm.args (one token per line or space separated)
// ---------------------------------------------------------------------------
#define APP_DATA_DIR "/data/data/com.csarm.port"

static void readArgsFile(const char *path, std::vector<std::string> &out)
{
    FILE *f = fopen(path, "r");
    if (!f) return;
    char line[2048];
    while (fgets(line, sizeof(line), f))
    {
        size_t len = strlen(line);
        while (len && (line[len-1] == '\n' || line[len-1] == '\r')) line[--len] = 0;
        if (!len || line[0] == '#') continue;
        // split on spaces
        char *save = nullptr;
        for (char *tok = strtok_r(line, " \t", &save); tok; tok = strtok_r(nullptr, " \t", &save))
            out.push_back(tok);
    }
    fclose(f);
}

// ---------------------------------------------------------------------------
// Valve Sys_LoadModule compatibility: it dlopen()s "<cwd>/bin/<name>.so".
// Our libs are named lib<name>.so in the read-only nativeLibraryDir, so we
// materialize <files>/bin/<name>.so symlinks -> real lib for every module.
// bionic dedupes by SONAME, so these resolve to the already-loaded instances.
// ---------------------------------------------------------------------------
static const char *kModules[] = {
    "protobuf", "tier0", "tier1", "tier2", "vstdlib", "mathlib",
    "appframework", "datacache", "studiorender", "soundemittersystem",
    "vguimatsurface", "vgui", "vgui_controls", "materialsystem",
    "inputsystem", "launcher", "filesystem_stdio", "engine", "client", "server",
    "bzip2", "tier3", "dmxloader", "bitmap", "vtf", "shaderlib", "scenefilecache",
    "soundsystem", "soundsystem_lowlevel", "matsys_controls", "videocfg", "vpklib",
    "bonesetup", "choreo", "cryptopp", "quickhull", "localize",
    "particles", "raytrace", "shaderapiempty", "matchmaking",
    // round 25: no-op vphysics stub (launcher AppSystemGroup loads
    // "vphysics.so" via Sys_LoadModule <cwd>/bin — symlink required)
    "vphysics",
    // round 55: the real render stack — compiled + linked, dlopen-smoked in
    // CI; the engine still boots with -noshaderapi until the desktop-GL
    // driver question is settled (SwiftShader bundle is ES/EGL-only)
    // round 56a: stdshader_dx9 gets NO bin/ symlink while the engine runs
    // shaderapiempty: CShaderSystem::LoadShaderDLL("stdshader_dx9") searches
    // this exact path and would register the real BEGIN_VS_SHADER classes;
    // materialsystem then initializes them (particles precache ->
    // Spritecard::OnInitShaderParams) against the stub shader API and SEGVs
    // (run #193 tombstone).  togl/shaderapidx9 carry no shader classes and
    // stay symlinked for the round-56 flip.
    "togl", "shaderapidx9", nullptr
};

static std::string nativeLibDir()
{
    Dl_info info;
    if (dladdr((void*)&nativeLibDir, &info) && info.dli_fname)
    {
        std::string p = info.dli_fname;
        size_t slash = p.rfind('/');
        if (slash != std::string::npos) return p.substr(0, slash);
    }
    return std::string(APP_DATA_DIR) + "/lib";
}

// round 56b: the real render stack (gl4es libGL + shaderapidx9 + togl) is
// only live when the engine is NOT told to run shaderapiempty; in that mode
// stdshader_dx9 becomes reachable via bin/ (CShaderSystem::LoadShaderDLL
// searches <cwd>/bin) — see the run #193 Spritecard tombstone for why it
// must stay absent in -noshaderapi mode.
static bool realRendererMode(const std::vector<std::string> &args)
{
    for (size_t i = 0; i < args.size(); i++)
        if (args[i] == "-noshaderapi") return false;
    return true;
}

static void makeModuleLinks(const std::string &filesDir, const std::string &libDir, bool realRender)
{
    std::string bin = filesDir + "/bin";
    mkdir(bin.c_str(), 0755);
    // Valve's POSIX x64 loader looks in <game>/bin/linux64/ first
    // (Sys_LoadModule builds basedir/bin/linux64/<name>.so paths)
    mkdir((bin + "/linux64").c_str(), 0755);
    int made = 0;
    for (int i = 0; kModules[i]; i++)
    {
        // round 56b: in -noshaderapi mode these two carry the real shader
        // device/API factories that must NOT shadow shaderapiempty's
        if (!realRender && strcmp(kModules[i], "shaderapidx9") == 0) continue;
        if (!realRender && strcmp(kModules[i], "togl") == 0) continue;
        std::string real = libDir + "/lib" + kModules[i] + ".so";
        struct stat st;
        if (stat(real.c_str(), &st) != 0) continue;              // module absent: skip
        std::string link = bin + "/" + kModules[i] + ".so";
        unlink(link.c_str());
        if (symlink(real.c_str(), link.c_str()) == 0) made++;
        // bare form too (some call sites omit DLL_EXT_STRING)
        std::string link2 = bin + "/" + kModules[i];
        unlink(link2.c_str());
        symlink(real.c_str(), link2.c_str());
        // bin/linux64/ form (Sys_LoadModule POSIX x64 search path)
        std::string link3 = bin + "/linux64/" + kModules[i] + ".so";
        unlink(link3.c_str());
        symlink(real.c_str(), link3.c_str());
    }
    // round 56b: stdshader_dx9 only exists as a bin/ link in real-renderer
    // mode (it is not in kModules at all, unlike togl/shaderapidx9)
    if (realRender)
    {
        std::string ss = libDir + "/libstdshader_dx9.so";
        struct stat st;
        if (stat(ss.c_str(), &st) == 0)
        {
            for (const char *sub : { "", "linux64/" })
            {
                std::string link = bin + "/" + sub + "stdshader_dx9.so";
                unlink(link.c_str());
                if (symlink(ss.c_str(), link.c_str()) == 0) made++;
            }
        }
    }
    LOGI("CSARM_BIN_LINKS made=%d dir=%s realRender=%d", made, bin.c_str(), realRender ? 1 : 0);
}

// ---------------------------------------------------------------------------
// csARM: deterministically fill every module's private interfaces.cpp
// registry (materials, g_pMaterialSystem, g_pFullFileSystem, g_pCVar, ...).
//
// Valve links interfaces.cpp as a static lib into EVERY module, so each .so
// carries its own copy of the global interface pointers plus its own
// ConnectInterfaces().  In the original model every DLL filled its own copy
// during Connect(); in our shared-.so port only the copy of the module that
// happens to win the bionic relocation binding gets written, and which one
// that is depends on load-order/namespace state (run 41405448535: the
// system-EGL APK left libtier2's `materials` NULL -> SEGV in
// CMaterialReference::Init from CMatSystemSurface::Init, while the identical
// binary with bundled SwiftShader resolved it fine and booted far past it).
//
// Fix: after all port libs are loaded, call ConnectInterfaces() INSIDE each
// module (dlsym per handle) with a composite CreateInterface factory that
// walks every loaded module's exported CreateInterface.  Every private
// registry is then filled with the real singletons before LauncherMain runs,
// no relocation-binding lottery involved.  Later Valve Connect/Reconnect
// calls are compatible: RegisterInterface skips already-filled globals and
// ReconnectInterface overwrites them with the same live pointers.
// ---------------------------------------------------------------------------
typedef void *(*CreateInterfaceFn_t)(const char *pName, int *pReturnCode);
typedef void (*ConnectInterfacesFn_t)(CreateInterfaceFn_t *pFactoryList, int nFactoryCount);

static void **g_csarmFactoryModules = NULL;
static int g_csarmFactoryModuleCount = 0;
static CreateInterfaceFn_t g_csarmCompositeFactory = NULL;

// ConnectInterfaces has C++ linkage in interfaces.cpp (no extern "C"), so
// dlsym must use its Itanium mangling: void ConnectInterfaces(CreateInterfaceFn*, int)
static void *csarm_dlsym_connect_interfaces(void *h)
{
    void *p = dlsym(h, "ConnectInterfaces"); // extern "C" alias, if one exists
    if (p)
        return p;
    return dlsym(h, "_Z17ConnectInterfacesPPFPvPKcPiEi");
}

static void *csarm_CompositeCreateInterface(const char *pName, int *pReturnCode)
{
    if (pReturnCode)
        *pReturnCode = 1; // IFACE_FAILED
    if (!pName || !g_csarmFactoryModules)
        return NULL;
    for (int i = 0; i < g_csarmFactoryModuleCount; i++)
    {
        void *h = g_csarmFactoryModules[i];
        if (!h)
            continue;
        CreateInterfaceFn_t fn = (CreateInterfaceFn_t)dlsym(h, "CreateInterface");
        if (!fn)
            continue;
        void *r = fn(pName, NULL);
        if (r)
        {
            if (pReturnCode)
                *pReturnCode = 0; // IFACE_OK
            return r;
        }
    }
    return NULL;
}

static void fillInterfaceRegistries()
{
    void *handles[64] = {0};
    int n = 0;
    for (int i = 0; kModules[i]; i++)
    {
        char soname[64];
        snprintf(soname, sizeof(soname), "lib%s.so", kModules[i]);
        // RTLD_NOLOAD: never load anything here; only already-loaded modules
        void *h = dlopen(soname, RTLD_NOW | RTLD_NOLOAD);
        if (!h)
            continue;
        // only modules that carry the interfaces.cpp registry (export
        // ConnectInterfaces) can be filled - and only those also export
        // CreateInterface, so they are exactly the composite-factory set
        if (!csarm_dlsym_connect_interfaces(h))
            continue;
        handles[n++] = h;
        if (n >= (int)(sizeof(handles) / sizeof(handles[0])))
            break;
    }
    if (n == 0)
    {
        LOGW("CSARM_IFACE_FILL no registry modules found");
        return;
    }
    g_csarmFactoryModules = handles;
    g_csarmFactoryModuleCount = n;
    g_csarmCompositeFactory = &csarm_CompositeCreateInterface;
    int connected = 0;
    for (int i = 0; i < n; i++)
    {
        ConnectInterfacesFn_t ci = (ConnectInterfacesFn_t)csarm_dlsym_connect_interfaces(handles[i]);
        if (!ci)
            continue;
        dlerror();
        ci(&g_csarmCompositeFactory, 1);
        connected++;
    }
    g_csarmFactoryModules = NULL;
    g_csarmFactoryModuleCount = 0;
    g_csarmCompositeFactory = NULL;
    LOGI("CSARM_IFACE_FILL modules=%d connected=%d", n, connected);
}

// ---------------------------------------------------------------------------
// SDL_main: the real boot
// ---------------------------------------------------------------------------
// csARM run 41485882642: libtier0's static initializer set
// g_ThreadMainThreadID in the Java UI thread that System.loadLibrary used,
// while the engine runs on the SDL thread.  The first CreateGameWindow ->
// CVideoMode_MaterialSystem::SetMode -> CMaterialSystem::ForceSingleThreaded
// then hit Error("Can't force single thread from within thread!") and a
// clean exit(0) (CSARM_EXIT_HIT, no tombstone).  The SDL thread owns the
// engine from SDL_main onward: declare it the main thread once up front.
extern "C" void DeclareCurrentThreadIsMainThread(void);

extern "C" int SDL_main(int argc, char *argv[])
{
    (void)argc; (void)argv;
    long long t0 = nowMs();
    LOGI("CSARM_MAIN enter");
    DeclareCurrentThreadIsMainThread();
    LOGI("CSARM_MAIN thread declared main");

    const std::string filesDir = APP_DATA_DIR "/files";
    mkdir(filesDir.c_str(), 0755);
    mkdir((filesDir + "/tmp").c_str(), 0755);

    // --- argv ------------------------------------------------------------
    std::vector<std::string> args;
    readArgsFile((filesDir + "/csarm.args").c_str(), args);
    if (args.empty())
    {
        // fast-boot defaults: no intro, windowed, multithreaded engine.
        // -noshaderapi: the launcher then loads shaderapiempty.so (stubs the
        // shader device interfaces) — no NULL shader-API factory crash in
        // CMaterialSystem::Connect until the real ToGL renderer is ported.
        args.push_back("-novid");
        args.push_back("-windowed");
        args.push_back("-w");  args.push_back("1280");
        args.push_back("-h");  args.push_back("720");
        args.push_back("-nobreakpad");
        args.push_back("-nojoy");
        args.push_back("-noshaderapi");
        // round 26: no Scaleform runtime is shipped (scaleformui.so absent),
        // but the client is built with INCLUDE_SCALEFORM - at CEngineVGui::Init
        // -> ActivateGameUI the client's CCStrike15BasePanel::ShowScaleformMainMenu
        // would CCreateMainMenuScreenScaleform::LoadDialog() and SIGSEGV on the
        // NULL g_pScaleformUI (run #161 tombstone, both GL paths).  This engine
        // switch (BasePanel.cpp bNoScaleformFrontEnd) disables the start screen
        // and the Scaleform main menu; the legacy VGUI ShowMainMenu visibility
        // toggle (NULL-guarded, no dialogs) runs instead and the frame loop lives.
        args.push_back("-no_scaleform_menu_on_boot");
        args.push_back("-basedir");
        args.push_back(filesDir);
        args.push_back("-game");
        args.push_back("cstrike");
        args.push_back("+host_thread_mode");   args.push_back("2");
        args.push_back("+mat_queue_mode");     args.push_back("2");
        args.push_back("+cl_threaded_bone_setup"); args.push_back("1");
    }
    std::vector<char*> argvVec;
    argvVec.push_back(strdup("csARM"));
    for (size_t i = 0; i < args.size(); i++) argvVec.push_back(strdup(args[i].c_str()));
    argvVec.push_back(nullptr);
    int argc2 = (int)(argvVec.size() - 1);
    char **argv2 = argvVec.data();

    std::string cmdline;
    for (int i = 0; i < argc2; i++) { cmdline += argv2[i]; cmdline += " "; }
    LOGI("CSARM_ARGS %s", cmdline.c_str());

    // --- environment + cwd -----------------------------------------------
    setenv("HOME", filesDir.c_str(), 1);
    setenv("TMPDIR", (filesDir + "/tmp").c_str(), 1);
    setenv("PWD", filesDir.c_str(), 1);
    setenv("STEAMAPPID", "730", 0);
    // CEngineAPI::SetStartupInfo mounts the USRLOCAL search path from
    // getenv("USRLOCAL" DLLExtTokenPaste2(VPCGAMECAPS)) on Android (the
    // Steam-profile branch is platform-gated away): without it the engine
    // has no writable USRLOCAL dir for configs/saves.  basetypes.h defines
    // DLLExtTokenPaste2(x) as the STRINGIZER (#x), so the engine literally
    // reads "USRLOCALVPCGAMECAPS" - run 41405448535 proved it ("USRLOCAL
    // path not found!" while USRLOCAL/USRLOCALCSGO were both set).
    setenv("USRLOCAL", filesDir.c_str(), 1);
    setenv("USRLOCALCSGO", filesDir.c_str(), 1);
    setenv("USRLOCALVPCGAMECAPS", filesDir.c_str(), 1);

    // csARM round 61: pin SDL's EGL driver to the bundled SwiftShader copy.
    // Run #202: the goldfish emulation stack (/system/lib64/libEGL.so ->
    // /vendor/lib64/egl/libEGL_emulation.so) SEGVs inside createNativeSync
    // during the very first eglSwapBuffers (ATD image, no working native
    // sync fences) - CSDLMgr::CreateHiddenGameWindow died on its priming
    // swap, and the engine frame loop would die the same way at its first
    // present.  SwiftShader's in-process EGL renders software-side and has
    // no goldfish pipe dependency.  The app linker namespace does NOT search
    // nativeLibraryDir ahead of /system (the #202 tombstone resolved the
    // system libEGL despite the bundle), so the absolute path is the only
    // reliable pin.  SDL_VIDEO_GL_DRIVER is deliberately NOT set: on the
    // Android/EGL video backend SDL routes that variable into the EGL
    // driver slot, and libGLESv2.so is not an EGL driver.
    {
        std::string libDir = nativeLibDir();
        struct stat st;
        std::string gl4esEgl = libDir + "/libEGLgl4es.so";
        std::string swEgl    = libDir + "/libEGL.so";
        std::string swGles   = libDir + "/libGLESv2.so";
        if (stat(gl4esEgl.c_str(), &st) == 0)
        {
            // round 65: SDL drives the gl4es EGL WRAPPER - SDL creates the
            // desktop-GL context through gl4es itself, so every gGL call in
            // togl/GLM runs against a LIVE gl4es context (run #207: contextless
            // gl4es returned 0 from glCheckFramebufferStatusEXT and the FBO
            // readiness gate int3'd inside IDirect3DDevice9::Create).  The
            // wrapper's backend is pinned to the bundled SwiftShader libs via
            // gl4es's LIBGL_GLES / LIBGL_EGL loader overrides (src/gl/loader.c)
            // - the whole stack stays in-process software, zero goldfish EGL.
            setenv("SDL_VIDEO_EGL_DRIVER", gl4esEgl.c_str(), 1);
            if (stat(swGles.c_str(), &st) == 0)
                setenv("LIBGL_GLES", swGles.c_str(), 1);
            if (stat(swEgl.c_str(), &st) == 0)
                setenv("LIBGL_EGL", swEgl.c_str(), 1);
            // csARM round 74: pin the ES backend version.  gl4es's
            // eglCreateContext wrapper picks the attrib list from
            // hardext.esversion, and GetHardwareExtensions never updates
            // that field from the driver - it stays at LIBGL_ES (or
            // DEFAULT_ES).  An esversion of 1 makes the wrapper pass an
            // EMPTY attrib list (no EGL_CONTEXT_CLIENT_VERSION), and
            // SwiftShader's es2::getContextLocked() then rejects the
            // context (client version != 2/3 -> es2::getContext() NULL ->
            // every GL entry point silently no-ops on unwritten out
            // params).  LIBGL_ES=2 keeps the whole chain ES2.
            setenv("LIBGL_ES", "2", 1);
            LOGI("CSARM_EGL pin: gl4es wrapper=%s gles=%s egl=%s",
                 getenv("SDL_VIDEO_EGL_DRIVER") ? getenv("SDL_VIDEO_EGL_DRIVER") : "-",
                 getenv("LIBGL_GLES") ? getenv("LIBGL_GLES") : "-",
                 getenv("LIBGL_EGL") ? getenv("LIBGL_EGL") : "-");
        }
        else if (stat(swEgl.c_str(), &st) == 0)
        {
            // round 61 fallback: plain SwiftShader EGL (ES contexts only -
            // togl runs contextless, enough for the fast-boot ladder only)
            setenv("SDL_VIDEO_EGL_DRIVER", swEgl.c_str(), 1);
            LOGI("CSARM_EGL pin: SDL_VIDEO_EGL_DRIVER=%s (SwiftShader, no gl4es wrapper)", swEgl.c_str());
        }
        else
        {
            LOGI("CSARM_EGL pin: no bundled EGL driver in %s - system EGL stays", libDir.c_str());
        }
    }

    makeModuleLinks(filesDir, nativeLibDir(), realRendererMode(args));

    // --- fill every module's private interfaces.cpp registry ---------------
    fillInterfaceRegistries();

    // --- GL driver report: bundled SwiftShader shadows system EGL ----------
    // When the APK ships libEGL.so/libGLESv2.so (SwiftShader), the app
    // nativeLibraryDir is searched before /system/lib64 -> every dlopen
    // of "libEGL.so" (including DT_NEEDED from the engine) resolves to it.
    {
        std::string bundled = nativeLibDir() + "/libEGL.so";
        FILE *f = fopen(bundled.c_str(), "rb");
        LOGI("CSARM_EGL %s", f ? "bundled(swiftshader) - software rendering" : "system");
        if (f) fclose(f);
    }

    if (chdir(filesDir.c_str()) != 0)
        LOGW("chdir(%s) failed: %s", filesDir.c_str(), strerror(errno));

    // --- Valve launcher ----------------------------------------------------
    const std::string launcherPath = nativeLibDir() + "/liblauncher.so";
    LOGI("CSARM_LAUNCHER_LOAD %s", launcherPath.c_str());
    void *hLauncher = dlopen(launcherPath.c_str(), RTLD_NOW | RTLD_GLOBAL);
    if (!hLauncher)
    {
        LOGE("CSARM_MAIN_FAIL dlopen(launcher): %s", dlerror());
        return 1;
    }
    typedef int (*LauncherMain_t)(int argc, char **argv);
    dlerror();
    LauncherMain_t launcherMain = (LauncherMain_t)dlsym(hLauncher, "LauncherMain");
    if (!launcherMain)
    {
        LOGE("CSARM_MAIN_FAIL dlsym(LauncherMain): %s", dlerror());
        return 1;
    }

    long long tPre = nowMs();
    LOGI("CSARM_LAUNCHER_CALL pre_ms=%lld", tPre - t0);
    int rc = launcherMain(argc2, argv2);
    LOGI("CSARM_MAIN_EXIT rc=%d run_ms=%lld", rc, nowMs() - tPre);
    return rc;
}
