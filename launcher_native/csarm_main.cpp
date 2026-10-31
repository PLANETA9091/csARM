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
    "particles", "raytrace", "shaderapiempty", nullptr
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

static void makeModuleLinks(const std::string &filesDir, const std::string &libDir)
{
    std::string bin = filesDir + "/bin";
    mkdir(bin.c_str(), 0755);
    // Valve's POSIX x64 loader looks in <game>/bin/linux64/ first
    // (Sys_LoadModule builds basedir/bin/linux64/<name>.so paths)
    mkdir((bin + "/linux64").c_str(), 0755);
    int made = 0;
    for (int i = 0; kModules[i]; i++)
    {
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
    LOGI("CSARM_BIN_LINKS made=%d dir=%s", made, bin.c_str());
}

// ---------------------------------------------------------------------------
// SDL_main: the real boot
// ---------------------------------------------------------------------------
extern "C" int SDL_main(int argc, char *argv[])
{
    (void)argc; (void)argv;
    long long t0 = nowMs();
    LOGI("CSARM_MAIN enter");

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

    makeModuleLinks(filesDir, nativeLibDir());

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
