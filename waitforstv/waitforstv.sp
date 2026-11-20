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


---- 1.1.3 (27/07/2025) ----
- Fixed unnecessary tournament restart when server is almost empty


---- 2.0.0 (20/11/2026) ----
- Changes map immediately if no one is watching SourceTV
- Uses SourceTV Manager if it is installed, otherwise checks tv_status every minute


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
#include <regex>
#undef REQUIRE_PLUGIN
#include <updater>
#undef REQUIRE_EXTENSIONS
#include <sourcetvmanager>


#define PLUGIN_VERSION "2.0.0"
#define UPDATE_URL     "https://sourcemod.krus.dk/waitforstv/update.txt"

#define TV_STATUS_POLL_INTERVAL 60.0
#define TV_STATUS_MAX_AGE       150.0 // if the last tv_status result is older than this, assume there are viewers


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
ConVar g_cvarTvEnable = null;
ConVar g_cvarTvDelay = null;
Regex g_hTvStatusRegex;
bool g_bTvStatusValid = false; // whether the last tv_status poll could be parsed
int g_iTvStatusSpectators, g_iTvStatusRelays;
float g_fTvStatusTime;


public void OnPluginStart() {
	RegServerCmd("changelevel", Cmd_Changelevel);
	RegServerCmd("stopchangelevel", Cmd_StopChangelevel);
	
	g_cvarDelayMapChange = FindConVar("tv_delaymapchange_protect");
	HookConVarChange(g_cvarDelayMapChange, ConVar_DelayMapChange);
	g_cvarDelayMapChange.IntValue = 0;
	
	g_cvarTvEnable = FindConVar("tv_enable");
	g_cvarTvDelay = FindConVar("tv_delay");
	
	g_hTvStatusRegex = new Regex("Local Slots \\d+, Spectators (\\d+), Proxies (\\d+)");
	CreateTimer(TV_STATUS_POLL_INTERVAL, Timer_PollTvStatus, _, TIMER_REPEAT);
	
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
	// If a forced changelevel failed, g_iStvCountdown is stuck at 1, which would make the next changelevel skip the wait
	if (g_hCountdownTimer == null)
		g_iStvCountdown = 0;
	
	RequestFrame(Frame_PollTvStatus);
}

void ResetMatch() {
}

void EndMatch(bool endedMidgame) {
	g_bMatchPlayed = true;
	g_fMatchEndTime = GetEngineTime(); // Remember the match end-time
	
	RequestFrame(Frame_PollTvStatus);
}



public void ConVar_DelayMapChange(ConVar cvar, const char[] oldVal, const char[] newVal) {
	int v = StringToInt(newVal);
	if (v == 0)
		return;
	
	g_cvarDelayMapChange.IntValue = 0;
}

public Action Cmd_Changelevel(int args) {
	// If no arguments are given then show the standard syntax message
	if (args == 0)
		return Plugin_Continue;
	
	// If we are not in a match and we haven't finished a match, just change map immediately
	if (g_bMatchPlayed == false && g_bInMatch == false)
		return Plugin_Continue;
	
	// If tv is disabled then just change the map
	bool tvenabled = g_cvarTvEnable.BoolValue;
	if (tvenabled == false)
		return Plugin_Continue;
	
	// Check if the map is on the server. If not, show an error message.
	char map[128];
	GetCmdArg(1, map, sizeof(map));
	if (!IsMapValid(map))
		return Plugin_Continue;
	
	// Retrieve the stvdelay
	float stvdelayf = g_cvarTvDelay.FloatValue;
	int stvdelay = RoundToCeil(stvdelayf);
	if (stvdelay < 0)
		stvdelay = 0;
	
	// If there is no delay, change the map immediately
	if (stvdelay == 0)
		return Plugin_Continue;
	
	// If no one is watching SourceTV, change the map immediately
	int spectators, relays;
	bool viewersKnown = GetStvViewers(spectators, relays);
	if (viewersKnown && spectators == 0 && relays == 0)
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
	if (viewersKnown)
		PrintStvViewers(spectators, relays);
	PrintTimeRemainingUntilMapChange();
	ReplyToCommand(0, "[Wait for STV] To stop the changelevel, type: rcon stopchangelevel");
	g_hCountdownTimer = CreateTimer(1.0, StvCountdownTrigger, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
	
	// Block the mapchange
	return Plugin_Stop;
}

public Action Cmd_StopChangelevel(int args) {
	if (g_hCountdownTimer == null)
		return Plugin_Continue;

	KillTimer(g_hCountdownTimer);
	g_hCountdownTimer = null;
	g_iStvCountdown = 0;
	CPrintToChatAll2("{lightgreen}[Wait for STV] {default}Map change cancelled!");
	ReplyToCommand(0, "[Wait for STV] Map change cancelled!");

	return Plugin_Continue;
}

public Action StvCountdownTrigger(Handle timer) {
	g_iStvCountdown--;
	
	if (g_iStvCountdown <= 0) {
		g_iStvCountdown = 1; // We have to force the mapchange
		g_hCountdownTimer = null;
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

void PrintStvViewers(int spectators, int relays) {
	// Color tags only work in the format string, not in the arguments
	// Only mention spectators if there are any, since relays may have spectators we cannot see
	if (spectators > 0 && relays > 0) {
		CPrintToChatAll2("{lightgreen}[Wait for STV] {default}Map change delayed due to {olive}%i STV spectator%s {default}and {olive}%i STV relay%s", spectators, spectators == 1 ? "" : "s", relays, relays == 1 ? "" : "s");
		ReplyToCommand(0, "[Wait for STV] Map change delayed due to %i STV spectator%s and %i STV relay%s", spectators, spectators == 1 ? "" : "s", relays, relays == 1 ? "" : "s");
	} else if (relays > 0) {
		CPrintToChatAll2("{lightgreen}[Wait for STV] {default}Map change delayed due to {olive}%i STV relay%s", relays, relays == 1 ? "" : "s");
		ReplyToCommand(0, "[Wait for STV] Map change delayed due to %i STV relay%s", relays, relays == 1 ? "" : "s");
	} else {
		CPrintToChatAll2("{lightgreen}[Wait for STV] {default}Map change delayed due to {olive}%i STV spectator%s", spectators, spectators == 1 ? "" : "s");
		ReplyToCommand(0, "[Wait for STV] Map change delayed due to %i STV spectator%s", spectators, spectators == 1 ? "" : "s");
	}
}

// Gets the number of spectators connected directly to SourceTV, and the number of connected SourceTV relays.
// Relays don't report their viewers to the master, so a connected relay must be treated as a viewer.
// Returns false if the numbers are unknown, in which case we must assume there are viewers.
bool GetStvViewers(int &spectators, int &relays) {
	// SourceTV Manager gives the current numbers. Its spectator count includes the relays.
	int proxies, slots, specs;
	if (LibraryExists("sourcetvmanager") && SourceTV_GetLocalStats(proxies, slots, specs)) {
		spectators = specs - proxies;
		if (spectators < 0)
			spectators = 0;
		relays = proxies;
		return true;
	}
	
	// Otherwise use the last tv_status poll, unless it is missing or too old
	if (!g_bTvStatusValid || GetEngineTime() - g_fTvStatusTime > TV_STATUS_MAX_AGE)
		return false;
	
	spectators = g_iTvStatusSpectators;
	relays = g_iTvStatusRelays;
	return true;
}

public Action Timer_PollTvStatus(Handle timer) {
	PollTvStatus();
	return Plugin_Continue;
}

public void Frame_PollTvStatus() {
	PollTvStatus();
}

// ServerCommandEx captures nothing when called from inside a server command, so this must not be called from Cmd_Changelevel.
void PollTvStatus() {
	// Only poll when GetStvViewers() can be used by Cmd_Changelevel
	if (g_bMatchPlayed == false && g_bInMatch == false)
		return;
	if (g_cvarTvEnable.BoolValue == false || g_cvarTvDelay.FloatValue <= 0.0)
		return;
	
	// SourceTV Manager is used instead, so we don't need to spam the console with tv_status
	int proxies, slots, specs;
	if (LibraryExists("sourcetvmanager") && SourceTV_GetLocalStats(proxies, slots, specs))
		return;
	
	char output[2048];
	ServerCommandEx(output, sizeof(output), "tv_status");
	
	if (g_hTvStatusRegex.Match(output) <= 0) {
		g_bTvStatusValid = false;
		return;
	}
	
	// The spectator count in tv_status does not include the relays
	char spectatorsStr[16], proxiesStr[16];
	g_hTvStatusRegex.GetSubString(1, spectatorsStr, sizeof(spectatorsStr));
	g_hTvStatusRegex.GetSubString(2, proxiesStr, sizeof(proxiesStr));
	
	g_bTvStatusValid = true;
	g_iTvStatusSpectators = StringToInt(spectatorsStr);
	g_iTvStatusRelays = StringToInt(proxiesStr);
	g_fTvStatusTime = GetEngineTime();
}
