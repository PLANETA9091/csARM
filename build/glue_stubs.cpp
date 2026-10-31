/* csARM — small C++ glue stubs for engine services whose real
 * implementations live in closed-source Valve libraries or platform SDKs
 * that do not exist on Android:
 *
 *   - Steam Datagram Relay transport (SDR ships inside steam_api, which is
 *     stubbed out entirely).  Connection-status printing and the client
 *     init/kill/connect entry points are referenced by cl_net code.
 *   - ScaleformUI() feature probe: the Scaleform middleware is not part of
 *     cstrike15_src; returning false makes the gameui take the standard
 *     (non-Scaleform) UI path, which is what we want on Android.
 *   - FileSystem_UpdateAddonSearchPaths: the engine's implementation lives in
 *     engine/filesystem_engine.cpp; the standalone copies of filesystem_init
 *     (appframework / vgui) reference it too — a no-op is correct because
 *     workshop/addon search paths do not exist on Android.
 *   - ToGL entry points: appframework/sdlmgr resolves the GL function table
 *     at video init; the real provider is togl (not part of the boot
 *     milestone) — NULL sends the engine down its fallback path.
 *
 * Signatures mirror the mangled symbols found in the link gate report so
 * they satisfy the exact references emitted by engine code.
 */
#include <stddef.h>
#include <stdint.h>

// ---------------------------------------------------------------------------
// Scaleform UI probe — force the standard GameUI path
// NOTE: weak.  game/client/cstrike15/gameui/gameui_interface.cpp defines the
// real IScaleformUI* ScaleformUI() under INCLUDE_SCALEFORM — same mangled
// name (_Z11ScaleformUIv; return types are not mangled) — so a strong stub
// made libclient.so fail with "duplicate symbol".  The strong definition
// must win wherever it exists.
// ---------------------------------------------------------------------------
__attribute__((weak)) bool ScaleformUI(void) { return false; }

// ---------------------------------------------------------------------------
// Addon/workshop search paths — the ENGINE's real implementation lives in
// engine/filesystem_engine.cpp (which we compile); the standalone copies of
// filesystem_init inside appframework / vgui reference it too.  Those two
// modules get the no-op below via glue_fs.cpp — do NOT link it into the
// engine (duplicate symbol).
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// ToGL GL entry-point table: appframework/sdlmgr.cpp calls this when the
// render device initializes.  The real provider is the togl module (DX9->GL
// shim) which is not part of the boot milestone; NULL makes the engine take
// its fallback path instead of crashing on a missing module.
// ---------------------------------------------------------------------------
extern "C" void *GetOpenGLEntryPoints(void *callback) { (void)callback; return 0; }

// ---------------------------------------------------------------------------
// Steam Datagram Relay — stubs mirroring steamnetworkingsockets flat API
// ---------------------------------------------------------------------------
class CSteamID
{
public:
    uint64_t m_unSteamID;
};

enum EUniverse { k_EUniverseInvalid = 0 };
enum EResult { k_EResultOK = 1, k_EResultFail = 2 };
enum ESteamDatagramPartner { k_ESteamDatagramPartnerInvalid = 0 };

class ISteamNetworkingUtils;

ISteamNetworkingUtils *SteamNetworkingUtils(void) { return nullptr; }

int SteamDatagramClient_Init(const char *pszErrMsg, ESteamDatagramPartner partner, int nAppID)
{ (void)pszErrMsg; (void)partner; (void)nAppID; return 0; }

void SteamDatagramClient_Kill(void) {}

bool SteamDatagramClient_Connect(CSteamID steamID)
{ (void)steamID; return false; }

void SteamDatagram_GameserverListen(EUniverse eUniverse, unsigned short usPort,
                                    EResult *pResult, char (&pszErrMsg)[1024])
{
    (void)eUniverse; (void)usPort;
    if (pResult) *pResult = k_EResultFail;
    (void)pszErrMsg;
}

class ISteamDatagramTransportClient
{
public:
    class ConnectionStatus
    {
    public:
        void Print(char *pchOut, int cchOut) const;  // defined below (out of line)
    };
};

// explicit out-of-line definition so the symbol is exported from this TU
void ISteamDatagramTransportClient::ConnectionStatus::Print(char *pchOut, int cchOut) const
{
    if (pchOut && cchOut > 0) pchOut[0] = '\0';
}

// ---------------------------------------------------------------------------
// CCSFatDemoRecorder::OnTickPre — the client references this one out-of-line
// member (run 41154407280 UND list), but fatdemo.cpp cannot be compiled on
// this branch: it needs the MatchLogic (ML*) classes, which are absent from
// the cstrike15_src mirror (upstream's client vpc does not list fatdemo.cpp
// either — dead code).  Demo recording is a no-op on Android anyway.
class CCSFatDemoRecorder
{
public:
    void OnTickPre( int tickcount );
};

void CCSFatDemoRecorder::OnTickPre( int tickcount )
{
    (void)tickcount;
}

// fatdemo.cpp cannot be compiled on this branch (its MatchLogic ML* classes
// are absent from the mirror), but the client references the recorder's
// global pointer as well as the OnTickPre member stubbed above.
CCSFatDemoRecorder *g_pFatDemoRecorder = nullptr;

// ---------------------------------------------------------------------------
// libjpeg decompress half — the client decodes JPEG textures; the engine
// side (screenshot compress) is stubbed in glue_engine.cpp.  No libjpeg on
// Android: return failure so the texture system falls back to error mats.
#ifdef __cplusplus
extern "C" {
#endif

void jpeg_CreateDecompress(void *cinfo, int version, size_t structsize)
{ (void)cinfo; (void)version; (void)structsize; }
void jpeg_start_decompress(void *cinfo) { (void)cinfo; }
void jpeg_finish_decompress(void *cinfo) { (void)cinfo; }
void jpeg_destroy_decompress(void *cinfo) { (void)cinfo; }
int  jpeg_read_header(void *cinfo, void *infile) { (void)cinfo; (void)infile; return 0; }
void jpeg_read_scanlines(void *cinfo, unsigned char **scanlines, unsigned int max_lines)
{ (void)cinfo; (void)scanlines; (void)max_lines; }
void jpeg_stdio_src(void *cinfo, void *infile) { (void)cinfo; (void)infile; }

// POSIX shared memory (engine mmap helpers) — report unsupported
#include <sys/types.h>
#include <fcntl.h>
int shm_open(const char *name, int oflag, mode_t mode)
{ (void)name; (void)oflag; (void)mode; return -1; }
int shm_unlink(const char *name) { (void)name; return -1; }

#ifdef __cplusplus
}
#endif

// ---------------------------------------------------------------------------
// UTIL_IsDedicatedServer — the particles lib queries it once at init; the
// real definition lives in the engine (layering violation to depend on it
// from libparticles).  false = game client path.
bool UTIL_IsDedicatedServer()
{
    return false;
}
