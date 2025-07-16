/*

Release notes:

---- 1.0.0 (31/12/2014) ----
- If a player is AFK in warmup, it shows a warning to all players on their team
- If both teams ready up and there is an AFK player, it shows a warning to the person's team


---- 1.1.0 (14/07/2015) ----
- Fixed blinking text
- AFK time is more fine-grained
- Support for new ready-up behaviour


---- 1.1.1 (23/04/2023) ----
- Internal updates


---- 1.1.2 (09/07/2025) ----
- Updated code to be compatible with SourceMod 1.12


*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <morecolors>
#include <f2stocks>
#include <match>
#undef REQUIRE_PLUGIN
#include <updater>

#define PLUGIN_VERSION "1.1.2"
#define UPDATE_URL		"https://sourcemod.krus.dk/afk/update.txt"


public Plugin myinfo = {
	name = "AFK Detector",
	author = "F2",
	description = "Shows which players are AFK in warmup",
	version = PLUGIN_VERSION,
	url = "https://github.com/F2/F2s-sourcemod-plugins"
};

#define DEFANG0 -1.0
#define DEFANG1 -1.0
#define DEFANG2 -1.0

#define TIMERINTERVAL 0.5

bool g_bEnabled = false;

float g_fLastAngles[MAXPLAYERS + 1][3];
float g_fAfkTime[MAXPLAYERS + 1];
Handle g_hTimerCheck = null;
float g_fLastCheck;
bool g_bIsAfk[MAXPLAYERS + 1];

Handle g_hHud[4];

ConVar g_hCvarMaxAfkTime;
ConVar g_hCvarMinPlayers;
float g_fMaxAfkTime;
int g_iMinPlayers;

GlobalForward g_hOnAfkStateChanged; // public void OnAfkStateChanged(int client, bool afk) {

public void OnPluginStart() {
	// Set up auto updater
	if (LibraryExists("updater"))
		Updater_AddPlugin(UPDATE_URL);

	g_hOnAfkStateChanged = CreateGlobalForward("OnAfkStateChanged", ET_Ignore, Param_Cell, Param_Cell);

	g_hCvarMaxAfkTime = CreateConVar("afk_time", "20", "Number of seconds you can stand still before being marked as AFK.", FCVAR_NONE, true, 5.0);
	g_fMaxAfkTime = g_hCvarMaxAfkTime.FloatValue;
	HookConVarChange(g_hCvarMaxAfkTime, CvarChange_MaxAfkTime);

	g_hCvarMinPlayers = CreateConVar("afk_minplayers", "8", "Minimum number of players on the server before the plugin is active.", FCVAR_NONE);
	g_iMinPlayers = g_hCvarMinPlayers.IntValue;
	HookConVarChange(g_hCvarMinPlayers, CvarChange_MinPlayers);

	g_hHud[TFTeam_Blue] = CreateHudSynchronizer();
	g_hHud[TFTeam_Red] = CreateHudSynchronizer();

	// Match.inc
	Match_OnPluginStart();

	// Simulate a map start
	OnMapStart();

	// Start the plugin
	EnablePlugin();
}

public void OnPluginEnd() {
	DisablePlugin();
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	CreateNative("IsPlayerAFK", Native_IsPlayerAFK);
	RegPluginLibrary("afk");
	return APLRes_Success;
}

public any Native_IsPlayerAFK(Handle plugin, int numParams) {
	if (!g_bEnabled)
		return false;

	int client = GetNativeCell(1);
	return IsPlayerAFK(client);
}

public void OnMapStart() {
	Match_OnMapStart();

	for (int client = 1; client <= MaxClients; client++) {
		g_fAfkTime[client] = 0.0;
		g_bIsAfk[client] = false;
	}

	g_fLastCheck = GetGameTime();
}

public void OnMapEnd() {
	Match_OnMapEnd();
}

public void OnLibraryAdded(const char[] name) {
	// Set up auto updater
	if (StrEqual(name, "updater"))
		Updater_AddPlugin(UPDATE_URL);
}

public void OnClientPutInServer(int client) {
	g_fAfkTime[client] = 0.0;
	g_bIsAfk[client] = false;
}

public void CvarChange_MaxAfkTime(ConVar cvar, const char[] oldVal, const char[] newVal) {
	g_fMaxAfkTime = StringToFloat(newVal);
}

public void CvarChange_MinPlayers(ConVar cvar, const char[] oldVal, const char[] newVal) {
	g_iMinPlayers = StringToInt(newVal);
}

// -----------------------------------
// Match - start / end
// -----------------------------------

void StartMatch() {
	bool foundAFK[TFTeam] = { false, ... };
	for (int client = 1; client <= MaxClients; client++) {
		if (IsPlayerAFK(client)) {
			TFTeam clientTeam = TF2_GetClientTeam(client);

			// Warn the player's team

			if (!foundAFK[clientTeam]) {
				foundAFK[clientTeam] = true;
				for (int other = 1; other <= MaxClients; other++) {
					if (!IsRealPlayer2(other))
						continue;
					if (TF2_GetClientTeam(other) != clientTeam)
						continue;
					MC_PrintToChat(other, "{lightgreen}[AFK] {green}WARNING! These players are AFK:");
				}
			}

			for (int other = 1; other <= MaxClients; other++) {
				if (!IsRealPlayer2(other))
					continue;
				if (TF2_GetClientTeam(other) != clientTeam)
					continue;

				CPrintToChatEx2(other, client, "{lightgreen}[AFK] {default}- {teamcolor}%N", client);
			}
		}
	}

	DisablePlugin();
}

void ResetMatch() {
	EnablePlugin();
}

void EndMatch(bool endedMidgame) {
	EnablePlugin();
}

// -----------------------------------

void EnablePlugin() {
	if (g_bEnabled)
		return;
	g_bEnabled = true;

	for (int client = 1; client <= MaxClients; client++) {
		g_fAfkTime[client] = 0.0;
		g_bIsAfk[client] = false;
	}

	HookEvent("player_spawn", Event_player_spawn, EventHookMode_Post);
	HookEvent("player_team", Event_player_team, EventHookMode_Post);

	g_hTimerCheck = CreateTimer(TIMERINTERVAL, Timer_CheckAFK, _, TIMER_REPEAT);
}

void DisablePlugin() {
	if (!g_bEnabled)
		return;
	g_bEnabled = false;

	for (int client = 1; client <= MaxClients; client++) {
		if (!IsRealPlayer(client) || IsFakeClient(client))
			continue;

		TFTeam team = TF2_GetClientTeam(client);
		if (team != TFTeam_Blue && team != TFTeam_Red)
			continue;

		ClearSyncHud(client, g_hHud[team]);
	}

	UnhookEvent("player_spawn", Event_player_spawn, EventHookMode_Post);
	UnhookEvent("player_team", Event_player_team, EventHookMode_Post);

	if (g_hTimerCheck != null) {
		KillTimer(g_hTimerCheck);
		g_hTimerCheck = null;
	}
}

public void Event_player_spawn(Event event, const char[] name, bool dontBroadcast) {
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);

	g_fLastAngles[client][0] = DEFANG0;
	g_fLastAngles[client][1] = DEFANG1;
	g_fLastAngles[client][2] = DEFANG2;

	// We cannot get the angles here, because TF2DM will move the player and change his angles later in this frame or the next frame.
}

public void Event_player_team(Event event, const char[] name, bool dontBroadcast) {
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);

	g_fAfkTime[client] = 0.0;
	g_bIsAfk[client] = false;

	ClearSyncHud(client, g_hHud[TFTeam_Red]);
	ClearSyncHud(client, g_hHud[TFTeam_Blue]);
}

public Action Timer_CheckAFK(Handle timer) {
	float now = GetGameTime();
	float span = now - g_fLastCheck;
	g_fLastCheck = now;

	bool afkBefore[MAXPLAYERS + 1];
	bool relevantClient[MAXPLAYERS + 1];
	TFTeam clientTeam[MAXPLAYERS + 1];

	int realPlayerCount = GetRealPlayerCount();

	for (int client = 1; client <= MaxClients; client++) {
		afkBefore[client] = g_bIsAfk[client];
		relevantClient[client] = false;

		if (!IsRealPlayer(client) || IsFakeClient(client)) {
			g_bIsAfk[client] = false;
			continue;
		}

		TFTeam team = TF2_GetClientTeam(client);
		clientTeam[client] = team;
		if (team != TFTeam_Red && team != TFTeam_Blue) {
			g_bIsAfk[client] = false;
			continue;
		}

		relevantClient[client] = true;

		if (!IsPlayerAlive(client))
			continue; // Remain the same AFK state

		float angles[3];
		if (!GetClientEyeAngles(client, angles)) {
			LogError("Could not get client eye angles for client %i", GetClientUserId(client));
			continue; // Should never happen, but remain the same AFK state
		}

		float vecDist = GetVectorDistance(angles, g_fLastAngles[client], true);
		bool  justSpawned = g_fLastAngles[client][0] == DEFANG0 && g_fLastAngles[client][1] == DEFANG1 && g_fLastAngles[client][2] == DEFANG2;

		g_fLastAngles[client][0] = angles[0];
		g_fLastAngles[client][1] = angles[1];
		g_fLastAngles[client][2] = angles[2];

		if (justSpawned)
			continue; // If the player has just spawned, then record their angles but don't detect if they have moved.

		if (vecDist <= 1.0) {
			g_fAfkTime[client] += span;
		} else {
			g_fAfkTime[client] = 0.0;
		}

		int buttons = GetClientButtons(client);
		int buttonsCheck = IN_ATTACK | IN_JUMP | IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT;
		if ((buttons & buttonsCheck) != 0)
			g_fAfkTime[client] = 0.0;

		g_bIsAfk[client] = false;
		if (g_fMaxAfkTime >= 1.0) {
			if (g_fAfkTime[client] >= g_fMaxAfkTime && realPlayerCount >= g_iMinPlayers) {
				g_bIsAfk[client] = true;
			}
		}
	}

	for (int client = 1; client <= MaxClients; client++) {
		if (!relevantClient[client])
			continue;
		if (afkBefore[client] == g_bIsAfk[client])
			continue;

		// Call forward
		Call_StartForward(g_hOnAfkStateChanged);

		// Push parameters one at a time
		Call_PushCell(client);
		Call_PushCell(g_bIsAfk[client]);

		// Finish the call, get the result
		if (Call_Finish() != SP_ERROR_NONE)
			LogError("Call to forward g_hOnAfkStateChanged failed");
	}

	char hudText[TFTeam][256];
	hudText[TFTeam_Blue] = "";
	hudText[TFTeam_Red]  = "";

	for (int client = 1; client <= MaxClients; client++) {
		if (!relevantClient[client])
			continue;

		TFTeam team = clientTeam[client];

		if (g_bIsAfk[client]) {
			char nickname[32];
			GetClientName(client, nickname, sizeof(nickname));

			int afkTime = RoundToFloor(g_fAfkTime[client] / 60.0);
			if (afkTime >= 1)
				Format(hudText[team], sizeof(hudText[]), "%s\n- %s (%i min)", hudText[team], nickname, afkTime);
			else {
				afkTime = RoundToFloor(g_fAfkTime[client] / 15.0) * 15;
				if (afkTime == 0) {
					afkTime = 15;
					if (RoundToFloor(g_fMaxAfkTime) < afkTime)
						afkTime = RoundToFloor(g_fMaxAfkTime);
				}
				if (afkTime < RoundToFloor(g_fMaxAfkTime))
					afkTime = RoundToFloor(g_fMaxAfkTime);
				Format(hudText[team], sizeof(hudText[]), "%s\n- %s (%i sec)", hudText[team], nickname, afkTime);
			}
		}
	}

	for (TFTeam team = TFTeam_Red; team <= TFTeam_Blue; team++) {
		if (hudText[team][0] != '\0') {
			Format(hudText[team], sizeof(hudText[]), "You have AFK players:%s", hudText[team]);
		}
	}

	for (int client = 1; client <= MaxClients; client++) {
		if (!relevantClient[client])
			continue;

		TFTeam team = clientTeam[client];

		SetHudTextParams(0.04, -1.0, 3.0, 255, 0, 0, 255, 0, 0.0, 0.0, 0.0);
		ShowSyncHudText(client, g_hHud[team], hudText[team]);
	}

	return Plugin_Continue;
}

bool IsPlayerAFK(int client) {
	if (!g_bEnabled)
		return false;
	if (!IsRealPlayer(client) || IsFakeClient(client))
		return false;

	TFTeam team = TF2_GetClientTeam(client);
	if (team != TFTeam_Red && team != TFTeam_Blue)
		return false;

	return g_bIsAfk[client];
}
