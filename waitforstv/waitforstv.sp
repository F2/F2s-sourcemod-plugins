/*
Release notes:

---- 1.0.0 (01/11/2013) ----
- Waits for STV when changing level
- Only waits the necessary amount of time
- 'stopchangelevel' supported


---- 1.0.1 (15/05/2014) ----
- Improved support for CTF maps


---- 1.0.2 (26/05/2014) ----
- Improved support for CTF maps further


---- 1.1.0 (27/09/2015) ---
- Automatically sets tv_delaymapchange_protect to 0... If you want to use tv_delaymapchange_protect, then remove this plugin.
- Support for new ready-up behaviour


---- 1.1.1 (23/04/2023) ----
- Internal updates


---- 1.1.2 (14/07/2025) ----
- Updated code to be compatible with SourceMod 1.12


BUG:
- When using sm_map twice during a match, you cannot override the 90secs delay [Not a problem with waitforstv - ForceLevelChange simply doesn't call changelevel more than once per map.]


*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <tf2_stocks>
#include <morecolors>
#include <f2stocks>
#include <match>
#undef REQUIRE_PLUGIN
#include <updater>


#define PLUGIN_VERSION "1.1.2"
#define UPDATE_URL     "https://sourcemod.krus.dk/waitforstv/update.txt"


public Plugin myinfo = {
	name = "Wait For STV",
	author = "F2",
	description = "Waits for STV when changing map",
	version = PLUGIN_VERSION,
	url = "https://github.com/F2/F2s-sourcemod-plugins"
};


float g_fMatchEndTime; // time when match ended
int g_iStvCountdown = 0, g_iStvCountdownStartAmount;
char g_sStvCountdownNextMap[128]; // which map to switch to after the countdown
bool g_bMatchPlayed = false;
Handle g_hCountdownTimer = null;
ConVar g_cvarDelayMapChange = null;


public void OnPluginStart() {
	RegServerCmd("changelevel", Cmd_Changelevel);
	RegServerCmd("stopchangelevel", Cmd_StopChangelevel);
	
	g_cvarDelayMapChange = FindConVar("tv_delaymapchange_protect");
	HookConVarChange(g_cvarDelayMapChange, ConVar_DelayMapChange);
	SetConVarInt(g_cvarDelayMapChange, 0);
	
	Match_OnPluginStart();
	
	// Set up auto updater
	if (LibraryExists("updater"))
		Updater_AddPlugin(UPDATE_URL);
}

public void OnLibraryAdded(const char[] name) {
	// Set up auto updater
	if (StrEqual(name, "updater"))
		Updater_AddPlugin(UPDATE_URL);
}

public void OnMapStart() {
	Match_OnMapStart();
	g_bMatchPlayed = false;
	g_hCountdownTimer = null;
	g_iStvCountdown = 0;
}

public void OnMapEnd() {
	Match_OnMapEnd();
}

void StartMatch() {
	g_bMatchPlayed = false;
}

void ResetMatch() {
	EndMatch(true);
}

void EndMatch(bool endedMidgame) {
	g_bMatchPlayed = true;
	g_fMatchEndTime = GetEngineTime(); // Remember the match end-time
}



public void ConVar_DelayMapChange(ConVar cvar, const char[] oldVal, const char[] newVal) {
	int v = StringToInt(newVal);
	if (v == 0)
		return;
	
	SetConVarInt(g_cvarDelayMapChange, 0);
}

public Action Cmd_Changelevel(int args) {
	// If no arguments are given then show the standard syntax message
	if (args == 0)
		return Plugin_Continue;
	
	// If we are not in a match and we haven't finished a match, just change map immediately
	if (g_bMatchPlayed == false && g_bInMatch == false)
		return Plugin_Continue;
	
	// If tv is disabled then just change the map
	bool tvenabled = FindConVar("tv_enable").BoolValue;
	if (tvenabled == false)
		return Plugin_Continue;
	
	// Check if the map is on the server. If not, show an error message.
	char map[128];
	GetCmdArg(1, map, sizeof(map));
	if (!IsMapValid(map))
		return Plugin_Continue;
	
	// Retrieve the stvdelay
	float stvdelayf = FindConVar("tv_delay").FloatValue;
	int stvdelay = RoundToCeil(stvdelayf);
	if (stvdelay < 0)
		stvdelay = 0;
	
	// If there is no delay, change the map immediately
	if (stvdelay == 0)
		return Plugin_Continue;
	
	// If the changelevel command is issued twice then change the map immediately
	if (g_iStvCountdown > 0) {
		// It's already counting down, so just change it now!
		return Plugin_Continue;
	}
	
	if (g_bInMatch == true) {
		// If the match hasn't ended then wait the full time for stv
		g_iStvCountdown = stvdelay;
	} else {
		// A match is over, find out how much more time we need to wait
		stvdelay += 2; // add some extra delay, just in case
		
		float timeuntilchange = (g_fMatchEndTime + stvdelay) - GetEngineTime();
		if (timeuntilchange < 1.0)
			return Plugin_Continue;
		
		g_iStvCountdown = RoundToCeil(timeuntilchange);
	}
	
	g_iStvCountdownStartAmount = g_iStvCountdown;
	
	// Remember which map we need to change to, and start the countdown trigger
	strcopy(g_sStvCountdownNextMap, sizeof(g_sStvCountdownNextMap), map);
	PrintTimeRemainingUntilMapChange();
	ReplyToCommand(0, "[Wait for STV] To stop the changelevel, type: rcon stopchangelevel");
	g_hCountdownTimer = CreateTimer(1.0, StvCountdownTrigger, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
	
	// Block the mapchange
	return Plugin_Stop;
}

public Action Cmd_StopChangelevel(int args) {
	KillTimer(g_hCountdownTimer);
	g_hCountdownTimer = null;
	g_iStvCountdown = 0;
	CPrintToChatAll2("{lightgreen}[Wait for STV] {default}Map change cancelled!");
	
	return Plugin_Continue;
}

public Action StvCountdownTrigger(Handle timer, any edict) {
	g_iStvCountdown--;
	
	if (g_iStvCountdown <= 0) {
		g_iStvCountdown = 1; // We have to force the mapchange
		ServerCommand("changelevel %s", g_sStvCountdownNextMap);
		
		return Plugin_Stop;
	}
	
	if (g_iStvCountdown <= g_iStvCountdownStartAmount - 15) {
		if (g_iStvCountdown == 5 || g_iStvCountdown == 15 || g_iStvCountdown == 30 || g_iStvCountdown == 60)
			PrintTimeRemainingUntilMapChange();
	}
	
	if (g_iStvCountdown <= 5) {
		PrintHintTextToAll("Changing map in %i second%s...", g_iStvCountdown, g_iStvCountdown == 1 ? "" : "s");
	}
	
	return Plugin_Continue;
}

void PrintTimeRemainingUntilMapChange() {
	CPrintToChatAll2("{lightgreen}[Wait for STV] {default}Changing map to %s in %i second%s...", g_sStvCountdownNextMap, g_iStvCountdown, g_iStvCountdown == 1 ? "" : "s");
}
