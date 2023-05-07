#include <sourcemod>

#define REQUIRE_EXTENSIONS
#include <dhooks>

#define GAMEDATA_FILE		"special_infected_control"

#define TEAM_ZOMBIE			3

#define L4D2_ZOMBIE_TANK	8
#define L4D_ZOMBIE_TANK		5

enum
{
	OBS_MODE_NONE = 0,	// not in spectator mode
	OBS_MODE_DEATHCAM,	// special mode for death cam animation
	OBS_MODE_FREEZECAM,	// zooms to a target, and freeze-frames on them
	OBS_MODE_FIXED,		// view from a fixed camera position
	OBS_MODE_IN_EYE,	// follow a player in first person view
	OBS_MODE_CHASE,		// follow a player in third person view
	OBS_MODE_ROAMING,	// free roaming

	NUM_OBSERVER_MODES,
};

Handle g_hSDKCall_TakeOverBot = null;
Handle g_hSDKCall_TakeOverZombieBot = null;
Handle g_hSDKCall_IsFinaleVehicleReady = null;
Handle g_hSDKCall_OnZombieRemoved = null;

int g_nOffset_m_iTankPassCount = -1;
int g_nOffset_m_tankLotteryEntryTimer = -1;
int g_nOffset_m_tankLotterySelectionTimer = -1;
int g_nOffset_m_humanSpectatorUserID = -1;

DynamicHook g_hDHook_SetClass = null;

Address g_addrTheDirector = Address_Null;

ConVar z_takecontrol_tank_limit = null;

bool IsL4D2()
{
	char szName[32];
	GetGameFolderName( szName, sizeof( szName ) );

	if ( StrEqual( szName, "left4dead2" ) )
	{
		return true;
	}

	return false;
}

bool IsSacrificeFinale()
{
	char szMap[32];
	GetCurrentMap( szMap, sizeof( szMap ) );

	return StrEqual( szMap, "c7m3_port", false ) || StrEqual( szMap, "l4d_river03_port", false );
}

bool IsButtonPressed( int iClient, int fButtons )
{
	return view_as< bool >( GetEntProp( iClient, Prop_Data, "m_afButtonPressed" ) & fButtons );
}

bool IsTryingToOfferTankBot()
{
	return view_as< float >( LoadFromAddress( g_addrTheDirector + view_as< Address >( g_nOffset_m_tankLotteryEntryTimer + 8 ), NumberType_Int32 ) ) != -1.0;
}

bool HasZombieForTankLotteryBeenSelected()
{
	return view_as< float >( LoadFromAddress( g_addrTheDirector + view_as< Address >( g_nOffset_m_tankLotterySelectionTimer + 8 ), NumberType_Int32 ) ) != -1.0;
}

bool TakeOverBot( int iPlayer, bool bDoesNotHaveToBeSpectator )
{
	return SDKCall( g_hSDKCall_TakeOverBot, iPlayer, bDoesNotHaveToBeSpectator );
}

bool IsFinaleVehicleReady()
{
	return SDKCall( g_hSDKCall_IsFinaleVehicleReady, g_addrTheDirector );
}

void TakeOverZombieBot( int iPlayer, int iBot )
{
	SDKCall( g_hSDKCall_TakeOverZombieBot, iPlayer, iBot );
}

void OnZombieRemoved( int iClient )
{
	SDKCall( g_hSDKCall_OnZombieRemoved, g_addrTheDirector, iClient );
}

int ResolveTankZombieClass()
{
	if ( IsL4D2() )
	{
		return L4D2_ZOMBIE_TANK;
	}

	return L4D_ZOMBIE_TANK;
}

int GetZombieClass( int iClient )
{
	return GetEntProp( iClient, Prop_Send, "m_zombieClass" );
}

int GetObserverTarget( int iClient )
{
	return GetEntPropEnt( iClient, Prop_Send, "m_hObserverTarget" );
}

int GetObserverMode( int iClient )
{
	return GetEntProp( iClient, Prop_Send, "m_iObserverMode" );
}

int GetTankPassCount()
{
	return LoadFromAddress( g_addrTheDirector + view_as< Address >( g_nOffset_m_iTankPassCount ), NumberType_Int32 );
}

public MRESReturn CTerrorPlayer_SetClass( int iClient, DHookParam hParams )
{
	hParams.Set( 1, GetZombieClass( GetObserverTarget( iClient ) ) );

	return MRES_ChangedHandled;
}

public void OnPlayerRunCmdPost( int iClient, int fButtons, int nImpulse, const float flVecVel[3], const float flQAngles[3], int iWeapon, int nSubtype, int nCmdNum, int nTickcount, int nSeed, const int nMouse[2] )
{
	if ( GetClientTeam( iClient ) != TEAM_ZOMBIE )
	{
		return;
	}

	if ( IsPlayerAlive( iClient ) )
	{
		return;
	}

	if ( !IsButtonPressed( iClient, IN_USE ) )
	{
		return;
	}

	int iTarget = GetObserverTarget( iClient );

	if ( iTarget == INVALID_ENT_REFERENCE )
	{
		return;
	}

	if ( GetClientTeam( iTarget ) == TEAM_ZOMBIE && IsFakeClient( iTarget ) && IsPlayerAlive( iTarget ) )
	{
		int nMode = GetObserverMode( iClient );

		if ( nMode != OBS_MODE_IN_EYE && nMode != OBS_MODE_CHASE )
		{
			return;
		}

		float flVecEyeAngles[3];
		GetClientEyeAngles( iTarget, flVecEyeAngles );

		int nZombieClass = ResolveTankZombieClass();

		if ( GetZombieClass( iTarget ) == nZombieClass )
		{
			if ( GetEntProp( iTarget, Prop_Send, "m_isIncapacitated", 1 ) )
			{
				return;
			}

			// Both games want tanks to remain bots
			if ( IsSacrificeFinale() && IsFinaleVehicleReady() )
			{
				return;
			}

			int nTankPassCount = GetTankPassCount();

			if ( nTankPassCount > z_takecontrol_tank_limit.IntValue )
			{
				return;
			}

			// Someone has been selected to become the Tank by the AI Director
			if ( HasZombieForTankLotteryBeenSelected() )
			{
				return;
			}

			// AI Director is going to let the selected player take over The Tank shortly
			if ( IsTryingToOfferTankBot() )
			{
				return;
			}

			TakeOverZombieBot( iClient, iTarget );

			TeleportEntity( iClient, NULL_VECTOR, flVecEyeAngles, NULL_VECTOR );

			// Make the AI Director keep track so that the Tank won't be passed to other players once the limit is reached
			nTankPassCount++;
			StoreToAddress( g_addrTheDirector + view_as< Address >( g_nOffset_m_iTankPassCount ), nTankPassCount, NumberType_Int32 );
		}
		else
		{
			SetEntData( iTarget, g_nOffset_m_humanSpectatorUserID, GetClientUserId( iClient ) );

			// This is necessary so that special bots continue spawning
			OnZombieRemoved( iTarget );

			// Force it because we're taking over another special bot and we don't care about any class restrictions
			int iHookID = g_hDHook_SetClass.HookEntity( Hook_Pre, iClient, CTerrorPlayer_SetClass );

			TakeOverBot( iClient, false );

			DynamicHook.RemoveHook( iHookID );

			// Avoid some confusion when taking over special bots
			TeleportEntity( iClient, NULL_VECTOR, flVecEyeAngles, NULL_VECTOR );
		}
	}
}

public void OnPluginStart()
{
	GameData hGameData = new GameData( GAMEDATA_FILE );

	if ( !hGameData )
	{
		SetFailState( "Unable to load gamedata file \"" ... GAMEDATA_FILE ... "\"" );
	}

#define PREP_SDKCALL_SET_FROM_CONF_WRAPPER(%0)\
	if ( !PrepSDKCall_SetFromConf( hGameData, SDKConf_Signature, %0 ) ) \
	{\
		delete hGameData;\
		\
		SetFailState( "Unable to find gamedata signature entry or signature in binary for \"" ... %0 ... "\"" );\
	}

#define GET_OFFSET_WRAPPER(%0,%1)\
	%1 = hGameData.GetOffset( %0 );\
	\
	if ( %1 == -1 )\
	{\
		delete hGameData;\
		\
		SetFailState( "Unable to find gamedata offset entry for \"" ... %0 ... "\"" );\
	}

	StartPrepSDKCall( SDKCall_Player );
	PREP_SDKCALL_SET_FROM_CONF_WRAPPER( "TakeOverBot" )
	PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
	PrepSDKCall_AddParameter( SDKType_Bool, SDKPass_Plain );
	g_hSDKCall_TakeOverBot = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Player );
	PREP_SDKCALL_SET_FROM_CONF_WRAPPER( "TakeOverZombieBot" )
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	g_hSDKCall_TakeOverZombieBot = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Raw );
	PREP_SDKCALL_SET_FROM_CONF_WRAPPER( "IsFinaleVehicleReady" )
	PrepSDKCall_SetReturnInfo( SDKType_Bool, SDKPass_Plain );
	g_hSDKCall_IsFinaleVehicleReady = EndPrepSDKCall();

	StartPrepSDKCall( SDKCall_Raw );
	PREP_SDKCALL_SET_FROM_CONF_WRAPPER( "OnZombieRemoved" )
	PrepSDKCall_AddParameter( SDKType_CBaseEntity, SDKPass_Pointer );
	g_hSDKCall_OnZombieRemoved = EndPrepSDKCall();

	g_addrTheDirector = hGameData.GetAddress( "Director" );

	if ( g_addrTheDirector == Address_Null )
	{
		delete hGameData;

		SetFailState( "Unable to find address entry or address in binary for \"Director\"" );
	}

	int iVtbl_SetClass;
	GET_OFFSET_WRAPPER( "SetClass", iVtbl_SetClass )

	GET_OFFSET_WRAPPER( "m_iTankPassCount", g_nOffset_m_iTankPassCount )
	GET_OFFSET_WRAPPER( "m_tankLotteryEntryTimer", g_nOffset_m_tankLotteryEntryTimer )
	GET_OFFSET_WRAPPER( "m_tankLotterySelectionTimer", g_nOffset_m_tankLotterySelectionTimer )
	GET_OFFSET_WRAPPER( "m_humanSpectatorUserID", g_nOffset_m_humanSpectatorUserID )

	g_hDHook_SetClass = new DynamicHook( iVtbl_SetClass, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity );
	g_hDHook_SetClass.AddParam( HookParamType_Int );

	delete hGameData;

	z_takecontrol_tank_limit = CreateConVar( "z_takecontrol_tank_limit", "1", "How many times players can take control of tanks" );
}

public Plugin myinfo =
{
	name = "[L4D/2] Special Infected Control",
	author = "Justin \"Sir Jay\" Chellah",
	description = "Allows dead Special Infected players to take control of other Special Infected bots while spectating them",
	version = "1.0.0",
	url = "https://justin-chellah.com"
};