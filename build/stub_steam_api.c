/* csARM — Steamworks stub.
 *
 * The engine / client / server / inputsystem / vgui_controls link against
 * steam_api (SteamAPI_Init, SteamAPI_RegisterCallback, ...).  The real
 * steam_api is a closed binary from the Steamworks SDK; on Android there is
 * no Steam client, so we provide a stub that keeps every referenced export
 * alive and behaves like "Steam not available":
 *   - SteamAPI_Init / InitSafe / RestartAppIfNecessary return false
 *     (Valve code takes the graceful no-steam path used by dedicated servers)
 *   - callback / call-result registration is a no-op
 *   - SteamInternal_CreateInterface returns NULL (interface pointers stay
 *     NULL and are checked by the engine before use)
 *
 * The stub objects are linked statically INTO the modules that need them,
 * so no extra .so / DT_NEEDED is required and each process-namespace sees a
 * consistent (empty) Steam world.
 */
#include <stdint.h>

typedef int HSteamPipe;
typedef int HSteamUser;

#ifdef __cplusplus
extern "C" {
#endif

HSteamUser SteamAPI_GetHSteamUser(void) { return 0; }
HSteamPipe SteamAPI_GetHSteamPipe(void) { return 0; }
/* flat accessors used by game code (steam_api.h declares these without the
 * SteamAPI_ prefix in some SDK revisions) */
HSteamUser GetHSteamUser(void) { return 0; }
HSteamPipe GetHSteamPipe(void) { return 0; }
HSteamUser SteamGameServer_GetHSteamUser(void) { return 0; }
HSteamPipe SteamGameServer_GetHSteamPipe(void) { return 0; }

int SteamAPI_Init(void) { return 0; }
int SteamAPI_InitSafe(void) { return 0; }
void SteamAPI_Shutdown(void) {}
void SteamAPI_RunCallbacks(void) {}
void SteamAPI_RegisterCallback(void *pCallback, int iCallback) { (void)pCallback; (void)iCallback; }
void SteamAPI_UnregisterCallback(void *pCallback) { (void)pCallback; }
void SteamAPI_RegisterCallResult(void *pCallback, uint64_t hAPICall) { (void)pCallback; (void)hAPICall; }
void SteamAPI_UnregisterCallResult(void *pCallback, uint64_t hAPICall) { (void)pCallback; (void)hAPICall; }
int SteamAPI_RestartAppIfNecessary(uint32_t unAppID) { (void)unAppID; return 0; }
void SteamAPI_SetTryCatchCallbacks(int bTryCatch) { (void)bTryCatch; }
void SteamAPI_SetMiniDumpComment(const char *pchMsg) { (void)pchMsg; }
void SteamAPI_WriteMiniDump(uint32_t unExceptionCode, void *pExceptionInfo, const char *pchBuildID)
{ (void)unExceptionCode; (void)pExceptionInfo; (void)pchBuildID; }

void *SteamInternal_CreateInterface(const char *ver) { (void)ver; return 0; }

int SteamGameServer_InitSafe(void) { return 0; }
void SteamGameServer_Shutdown(void) {}
void SteamGameServer_RunCallbacks(void) {}
uint32_t SteamGameServer_GetIPCCallCount(void) { return 0; }
int SteamInternal_GameServer_Init(uint32_t unIP, uint16_t usPort, uint16_t usGamePort,
                                 uint16_t usQueryPort, uint32_t unFlags, const char *pszVersion)
{ (void)unIP; (void)usPort; (void)usGamePort; (void)usQueryPort; (void)unFlags; (void)pszVersion; return 0; }

#ifdef __cplusplus
}
#endif

/* --- 2019 engine: SteamNetworkingSockets / SteamDatagram / breakpad ------ *
 * Declarations live in public/steamnetworkingsockets (extern "C") and
 * steam_api_internal.h.  The stub world has no Steam client: the init
 * functions return false and the accessors return NULL.  The engine's
 * steam-off code paths never dereference them (everything is guarded by
 * SteamAPI_Init() == false), the symbols only need to exist for the link. */
void *SteamNetworkingSockets( void ) { return 0; }
void *SteamNetworkingSocketsGameServer( void ) { return 0; }
void SteamNetworkingSockets_SetDebugOutputFunction( int eDetailLevel, void *pfnFunc ) { (void)eDetailLevel; (void)pfnFunc; }
void *SteamNetworkingUtils( void ) { return 0; }
void SteamDatagramClient_Internal_SteamAPIKludge( void *a, void *b, void *c, void *d ) { (void)a; (void)b; (void)c; (void)d; }
int SteamDatagramClient_Init_InternalV6( char *errMsg, void *fnCreateInterface, int hSteamUser, int hSteamPipe ) { (void)errMsg; (void)fnCreateInterface; (void)hSteamUser; (void)hSteamPipe; return 0; }
int SteamDatagramServer_Init_Internal( char *errMsg, void *fnCreateInterface, int hSteamUser, int hSteamPipe ) { (void)errMsg; (void)fnCreateInterface; (void)hSteamUser; (void)hSteamPipe; return 0; }
void SteamDatagramClient_Kill( void ) {}
void SteamDatagramServer_Kill( void ) {}
void SteamAPI_UseBreakpadCrashHandler( const char *a, const char *b, const char *c, int d, void *e, void *f ) { (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; }
