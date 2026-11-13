/*
Release notes:

---- 1.0.0 (01/11/2013) ----
- Restores a player's score when they reconnect
- Stored scores are trashed on mapchange and when a new match starts


---- 1.1.1 (09/11/2013) ----
- Fixed a bug where the scores would not be restored


---- 1.1.2 (28/01/2014) ----
- Fixed a minor error when the server is closing
- Fixed a bug that sometimes caused RestoreScore not to work for certain players (SteamID fix)


---- 1.1.3 (14/07/2025) ----
- Updated code to be compatible with SourceMod 1.12


---- 1.1.4 (13/11/2026) ----
- Fixed bug where stored scores were not reset on servers with SourceTV
- Fixed rare bug where the plugin could stop working on mapchange


Known issues:
- Not compatible with TFTrue.
*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <tf2_stocks>
#include <sdkhooks>
#include <f2stocks>
#undef REQUIRE_PLUGIN
#include <updater>


#define PLUGIN_VERSION "1.1.4"
#define UPDATE_URL		"https://sourcemod.krus.dk/restorescore/update.txt"


public Plugin myinfo = {
	name = "Restore Score",
	author = "F2",
	description = "Restores the score of a player when reconnecting",
	version = PLUGIN_VERSION,
	url = "https://github.com/F2/F2s-sourcemod-plugins"
};

int g_iAddScore[MAXPLAYERS+1]; // The old scores that are currently being added to the clients.
StringMap g_tOldScores = null; // Keys are steamids of players disconnected, and values are their old scores.



public void OnPluginStart() {
	HookEvent("player_activate", Event_player_activate, EventHookMode_Post);
	HookEvent("player_disconnect", Event_player_disconnect, EventHookMode_Pre);
	HookEvent("teamplay_restart_round", Event_restart_round, EventHookMode_Post);
	
	g_tOldScores = new StringMap();
	
	// Late load
	int iIndex = FindEntityByClassname(-1, "tf_player_manager");
	if (iIndex != -1)
		SDKHook(iIndex, SDKHook_ThinkPost, Hook_OnThinkPost);
	
	if (LibraryExists("updater"))
		Updater_AddPlugin(UPDATE_URL);
}

public void OnLibraryAdded(const char[] name) {
	if (StrEqual(name, "updater"))
		Updater_AddPlugin(UPDATE_URL);
}

public void OnPluginEnd() {
	delete g_tOldScores;
}



// Clear the old scores when the match is reset and on mapchange.
void ResetOldScores() {
	// Clear the old scores
	g_tOldScores.Clear();
	
	for (int client = 1; client <= MaxClients; client++)
		g_iAddScore[client] = 0;
}

public void Event_restart_round(Event event, const char[] name, bool dontBroadcast) {
	ResetOldScores();
}

public void OnMapStart() {
	ResetOldScores();
}




// When a player connects, check if it is a returning player, and adjust his score accordingly.
public void Event_player_activate(Event event, const char[] name, bool dontBroadcast) {
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	if (!IsRealPlayer(client))
		return;
	
	char steamid[64];
	if (!GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid), false))
		return;
	int oldscore;
	if (!g_tOldScores.GetValue(steamid, oldscore))
		return;
	g_tOldScores.Remove(steamid);
	
	g_iAddScore[client] = oldscore;
}

// When a player disconnects, remember the score.
public void Event_player_disconnect(Event event, const char[] name, bool dontBroadcast) {
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	
	g_iAddScore[client] = 0;
	
	// Clear the old scores if the server is empty
	if (GetRealPlayerCount() == (IsRealPlayer(client) ? 1 : 0)) {
		ResetOldScores();
		return;
	}
	
	if (!IsRealPlayer(client))
		return;
	
	// Save the score if it is above 0
	int score = TF2_GetPlayerScore(client);
	if (score <= 0)
		return;
	char steamid[64];
	if (!GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid), false))
		return;
	
	g_tOldScores.SetValue(steamid, score);
}



// --- This is where the magic happens! ---
public void OnEntityCreated(int entity, const char[] classname) {
	if (StrEqual(classname, "tf_player_manager"))
		SDKHook(entity, SDKHook_ThinkPost, Hook_OnThinkPost);
}

public void Hook_OnThinkPost(int iEnt) {
    static int iTotalScoreOffset = -1;
    if (iTotalScoreOffset == -1)
        iTotalScoreOffset = FindSendPropInfo("CTFPlayerResource", "m_iTotalScore");
    
	// Get all players' current scores
    int iTotalScore[MAXPLAYERS+1];
    GetEntDataArray(iEnt, iTotalScoreOffset, iTotalScore, MaxClients+1);
    
	// Add the old scores
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i)) {
			iTotalScore[i] += g_iAddScore[i];
        }
    }
    
	// Set all players' new scores
    SetEntDataArray(iEnt, iTotalScoreOffset, iTotalScore, MaxClients+1);
}
// ----------------------------------------
