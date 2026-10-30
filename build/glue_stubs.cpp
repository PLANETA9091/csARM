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
// ---------------------------------------------------------------------------
bool ScaleformUI(void) { return false; }

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
