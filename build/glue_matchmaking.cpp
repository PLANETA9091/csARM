// csARM matchmaking stub — round 22.
//
// The 2019 engine's CModAppSystemGroup::Create() unconditionally loads
// matchmaking.so and Sys_Error()s (clean exit(0), run #155: process died
// 3 s after launch, "Could not load library matchmaking") when the module
// is absent.  The matchmaking middleware is not part of the ported stack,
// so this ships a no-op libmatchmaking.so that answers the one interface
// the engine asks for (MATCHFRAMEWORK_001) and makes every call a no-op.
// The engine falls back to its direct-connect/listen-server paths; the
// game menu and map load do not need real matchmaking.
//
// Stub policy:
//   - GetEventsSubscription() -> working no-op object (BroadcastEvent is
//     called from the loading screen / gameui unconditionally)
//   - GetMatchTitle() -> working no-op object (34 getters, safe defaults)
//   - GetMatchExtensions() -> working no-op object
//   - GetMatchSession() -> NULL (no session: the natural "not in a match")
//   - GetMatchSystem() / GetMatchNetworkMsgController() -> NULL (session/
//     network-only; a NULL here surfaces as the next probe finding if the
//     boot path ever dereferences one)
#include <string.h>

#include "tier0/platform.h"
#include "tier1/interface.h"
#include "appframework/iappsystem.h"
#include "tier1/keyvalues.h"
#include "matchmaking/imatchframework.h"
#include "matchmaking/imatchevents.h"
#include "matchmaking/imatchtitle.h"
#include "matchmaking/imatchextensions.h"

// ---------------------------------------------------------------------------
// Sub-interface stubs
// ---------------------------------------------------------------------------
class CMatchEventsSubscriptionStub : public IMatchEventsSubscription
{
public:
	virtual void Subscribe( IMatchEventsSink *pSink ) {}
	virtual void Unsubscribe( IMatchEventsSink *pSink ) {}
	virtual void BroadcastEvent( KeyValues *pEvent ) {}
	virtual void RegisterEventData( KeyValues *pEventData ) {}
	virtual KeyValues * GetEventData( char const *szEventDataKey ) { return NULL; }
};

class CMatchTitleStub : public IMatchTitle
{
public:
	virtual uint64 GetTitleID() { return 0; }
	virtual uint64 GetTitleServiceID() { return 0; }
	virtual uint64 GetTitleSettingsFlags() { return 0; }
	virtual void PrepareNetStartupParams( void *pNetStartupParams ) {}
	virtual int GetTotalNumPlayersSupported() { return 0; }
	virtual char const * GetGuestPlayerName( int iUserIndex ) { return ""; }
	virtual TitleDataFieldsDescription_t const * DescribeTitleDataStorage() { return NULL; }
	virtual TitleAchievementsDescription_t const * DescribeTitleAchievements() { return NULL; }
	virtual TitleAvatarAwardsDescription_t const * DescribeTitleAvatarAwards() { return NULL; }
	virtual KeyValues * DescribeTitleLeaderboard( char const *szLeaderboardView ) { return NULL; }
	virtual void PrepareClientForConnect( KeyValues *pSettings ) {}
	virtual bool StartServerMap( KeyValues *pSettings ) { return false; }
	virtual TitleDlcDescription_t const * DescribeTitleDlcs() { return NULL; }
	virtual void RunFrame() {}
	virtual void ExtendServerDetails( KeyValues *pDetails, KeyValues *pRequest ) {}
	virtual void ExtendLobbyDetailsTemplate( KeyValues *pDetails, char const *szReason, KeyValues *pFullSettings ) {}
	virtual void ExtendGameSettingsForLobbyTransition( KeyValues *pSettings, KeyValues *pSettingsUpdate, bool bEndGame ) {}
	virtual void ExtendDatacenterReport( KeyValues *pReportMsg, char const *szReason ) {}
	virtual KeyValues * RollupGameDetails( KeyValues *pDetails, KeyValues *pRollup, KeyValues *pQuery ) { return NULL; }
	virtual KeyValues * DefineSessionSearchKeys( KeyValues *pSettings ) { return NULL; }
	virtual KeyValues * DefineDedicatedSearchKeys( KeyValues *pSettings, bool bNeedOfficialServer, int nSearchPass ) { return NULL; }
	virtual void InitializeGameSettings( KeyValues *pSettings, char const *szReason ) {}
	virtual void SetBspnameFromMapgroup( KeyValues *pSettings ) {}
	virtual void ExtendGameSettingsUpdateKeys( KeyValues *pSettings, KeyValues *pUpdateDeleteKeys ) {}
	virtual KeyValues * ExtendTeamLobbyToGame( KeyValues *pSettings ) { return NULL; }
	virtual KeyValues * PrepareForSessionCreate( KeyValues *pSettings ) { return NULL; }
	virtual void ExecuteCommand( KeyValues *pCommand, KeyValues *pSessionSystemData, KeyValues *pSettings, KeyValues **ppPlayersUpdated ) {}
	virtual void PrepareLobbyForGame( KeyValues *pSettings, KeyValues **ppPlayersUpdated ) {}
	virtual KeyValues * PrepareTeamLinkForGame( KeyValues *pSettingsLocal, KeyValues *pSettingsRemote ) { return NULL; }
	virtual KeyValues * PrepareClientLobbyForMigration( KeyValues *pSettingsLocal, KeyValues *pMigrationInfo ) { return NULL; }
	virtual KeyValues * PrepareClientLobbyForGameDisconnect( KeyValues *pSettingsLocal, KeyValues *pDisconnectInfo ) { return NULL; }
	virtual bool AllowClientProfileUpdate( KeyValues *kvUpdate ) { return false; }
	virtual char const * GetFormulaAverage( int index ) { return ""; }
	virtual void UpdateTeamProperties( KeyValues *pCurrentSettings, KeyValues *pTeamProperties ) {}
};

class CMatchExtensionsStub : public IMatchExtensions
{
public:
	virtual void RegisterExtensionInterface( char const *szInterfaceString, void *pvInterface ) {}
	virtual void UnregisterExtensionInterface( char const *szInterfaceString, void *pvInterface ) {}
	virtual void * GetRegisteredExtensionInterface( char const *szInterfaceString ) { return NULL; }
};

// ---------------------------------------------------------------------------
// MATCHFRAMEWORK_001
// ---------------------------------------------------------------------------
class CMatchFrameworkStub : public CBaseAppSystem< IMatchFramework >
{
public:
	CMatchFrameworkStub() {}

	// IMatchFramework
	virtual void RunFrame() {}
	virtual IMatchExtensions * GetMatchExtensions() { return &m_Extensions; }
	virtual IMatchEventsSubscription * GetEventsSubscription() { return &m_Events; }
	virtual IMatchTitle * GetMatchTitle() { return &m_Title; }
	virtual IMatchSession * GetMatchSession() { return NULL; }
	virtual IMatchNetworkMsgController * GetMatchNetworkMsgController() { return NULL; }
	virtual IMatchSystem * GetMatchSystem() { return NULL; }
	virtual bool ApplySettings( KeyValues *keyValues ) { return false; }
	virtual void CreateSession( KeyValues *pSettings ) {}
	virtual void MatchSession( KeyValues *pSettings ) {}
	virtual void AcceptInvite( int iController ) {}
	virtual void CloseSession() {}
	virtual bool IsOnlineGame( void ) { return false; }
	virtual void UpdateTeamProperties( KeyValues *pTeamProperties ) {}
	virtual void DiagnosticInfoAdd( char const *szReportLine ) {}
	virtual char const * DiagnosticInfoGet() { return ""; }

private:
	CMatchEventsSubscriptionStub m_Events;
	CMatchTitleStub m_Title;
	CMatchExtensionsStub m_Extensions;
};

// Valve factory entry (Sys_GetFactory dlsym's exactly this name; the linker
// keeps it via -Wl,--export-dynamic-symbol=CreateInterface in link.sh).
extern "C" __attribute__((visibility("default")))
void *CreateInterface( const char *pName, int *pReturnCode )
{
	if ( pName && strcmp( pName, IMATCHFRAMEWORK_VERSION_STRING ) == 0 )
	{
		static CMatchFrameworkStub s_MatchFrameworkStub;
		if ( pReturnCode )
			*pReturnCode = IFACE_OK;
		return &s_MatchFrameworkStub;
	}
	if ( pReturnCode )
		*pReturnCode = IFACE_FAILED;
	return NULL;
}
