/*
Release notes:

---- 1.0.0 (01/11/2013) ----
- Restores a player's score when he reconnects
- Stored scores are trashed on mapchange and when a new match starts


---- 1.1.1 (09/11/2013) ----
- Fixed a bug where the scores would not be restored


---- 1.1.2 (28/01/2014) ----
- Fixed a minor error when the server is closing
- Fixed a bug that sometimes caused RestoreScore not to work for certain players (SteamID fix)


Known errors:
- Not compatible with TFTrue.
*/

#pragma semicolon 1

#include <sourcemod>
#include <tf2_stocks>
#include <sdkhooks>
#include <f2stocks>
#undef REQUIRE_PLUGIN
#include <updater>


#define PLUGIN_VERSION "1.1.2"
#define UPDATE_URL		"http://sourcemod.krus.dk/restorescore/update.txt"


public Plugin:myinfo = {
	name = "Restore Score",
	author = "F2",
	description = "Restores the score of a player when reconnecting",
	version = PLUGIN_VERSION,
	url = "https://github.com/F2/F2s-sourcemod-plugins"
};

new bool:g_bHookActivated = false;

new g_iAddScore[MAXPLAYERS+1]; // The old scores that are currently being added to the clients.
new Handle:g_kvOldScores = INVALID_HANDLE; // Keys are steamids of players disconnected, and values are their old scores.



public OnPluginStart() {
	HookEvent("player_activate", Event_player_activate, EventHookMode_Post);
	HookEvent("player_disconnect", Event_player_disconnect, EventHookMode_Pre);
	HookEvent("teamplay_restart_round", Event_restart_round, EventHookMode_Post);
	
	g_kvOldScores = CreateKeyValues("OldScores");
	
	if (LibraryExists("updater"))
		Updater_AddPlugin(UPDATE_URL);
}

public OnLibraryAdded(const String:name[]) {
	if (StrEqual(name, "updater"))
		Updater_AddPlugin(UPDATE_URL);
}

public OnPluginEnd() {
	StopHook();
	CloseHandle(g_kvOldScores);
}



// Clear the old scores when the match is reset and on mapchange.
ResetOldScores() {
	// Stop the hook (for performance reasons)
	StopHook();
	
	// Clear the old scores
	CloseHandle(g_kvOldScores);
	g_kvOldScores = CreateKeyValues("OldScores");
	
	for (new client = 1; client <= MaxClients; client++)
		g_iAddScore[client] = 0;
}

public Action:Event_restart_round(Handle:event, const String:name[], bool:dontBroadcast) {
	ResetOldScores();
}

public OnMapStart() {
	ResetOldScores();
}




// When a player connects, check if it is a returning player, and adjust his score accordingly.
public Action:Event_player_activate(Handle:event, const String:name[], bool:dontBroadcast) {
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);
	if (!IsRealPlayer(client))
		return;
	
	decl String:steamid[64];
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid), false);
	KvRewind(g_kvOldScores);
	if (KvJumpToKey(g_kvOldScores, steamid) == false)
		return;
	new oldscore = KvGetNum(g_kvOldScores, "score");
	KvGoBack(g_kvOldScores);
	KvDeleteKey(g_kvOldScores, steamid);
	
	g_iAddScore[client] = oldscore;
	//SetEntProp(client, Prop_Send, "m_iFrags", KvGetNum(g_kvOldScores, "kills"));
	//SetEntProp(client, Prop_Send, "m_iDeaths", KvGetNum(g_kvOldScores, "deaths"));
	//SetEntProp(client, Prop_Data, "m_iAssists", KvGetNum(g_kvOldScores, "assists"));
	
	StartHook();
}

// When a player disconnects, remember the score.
public Action:Event_player_disconnect(Handle:event, const String:name[], bool:dontBroadcast) {
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);
	
	g_iAddScore[client] = 0;
	
	// Clear the old scores if the server is empty
	if (GetClientCount() == 1) {
		ResetOldScores();
		return;
	}
	
	if (!IsRealPlayer(client))
		return;
	
	// Save the score if it is above 0
	new score = TF2_GetPlayerScore(client);
	if (score <= 0)
		return;
	decl String:steamid[64];
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid), false);
	
	KvRewind(g_kvOldScores);
	if (KvJumpToKey(g_kvOldScores, steamid, true) == false)
		return;
	
	KvSetNum(g_kvOldScores, "score", score);
	//KvSetNum(g_kvOldScores, "kills", GetEntProp(client, Prop_Send, "m_iFrags"));
	//KvSetNum(g_kvOldScores, "deaths", GetEntProp(client, Prop_Send, "m_iDeaths"));
	//KvSetNum(g_kvOldScores, "assists", GetEntProp(client, Prop_Data, "m_iAssists"));
	KvGoBack(g_kvOldScores);
}



// --- This is where the magic happens! ---
StartHook() {
	if (g_bHookActivated)
		return;
	g_bHookActivated = true;
	new iIndex = FindEntityByClassname(-1, "tf_player_manager");
	if (iIndex == -1)
		SetFailState("Unable to find tf_player_manager entity");
	
	SDKHook(iIndex, SDKHook_ThinkPost, Hook_OnThinkPost);
}

StopHook() {
	if (!g_bHookActivated)
		return;
	g_bHookActivated = false;
	new iIndex = FindEntityByClassname(-1, "tf_player_manager");
	if (iIndex == -1)
		SetFailState("Unable to find tf_player_manager entity");
	
	SDKUnhook(iIndex, SDKHook_ThinkPost, Hook_OnThinkPost);
}

public Hook_OnThinkPost(iEnt) {
    static iTotalScoreOffset = -1;
    if (iTotalScoreOffset == -1)
        iTotalScoreOffset = FindSendPropInfo("CTFPlayerResource", "m_iTotalScore");
    
	// Get all players' current scores
    new iTotalScore[MAXPLAYERS+1];
    GetEntDataArray(iEnt, iTotalScoreOffset, iTotalScore, MaxClients+1);
    
	// Add the old scores
    for (new i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i)) {
			iTotalScore[i] += g_iAddScore[i];
        }
    }
    
	// Set all players' new scores
    SetEntDataArray(iEnt, iTotalScoreOffset, iTotalScore, MaxClients+1);
}
// ----------------------------------------
