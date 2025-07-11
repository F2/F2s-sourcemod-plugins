/*

Release notes:

---- 1.0.0 (26/07/2014) ----
- In ETF2L class limits are not enforced by the server. This plugin warns players in chat if they are breaking the class limit.


---- 1.1.0 (14/07/2015) ----
- Now also works when configs are in /custom/ folder
- Support for new ready-up behaviour


---- 1.1.1 (23/04/2023) ----
- Internal updates


---- 1.1.2 (10/07/2025) ----
- Updated code to be compatible with SourceMod 1.12

*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <morecolors>
#include <f2stocks>
#include <match>
#include <smlib/strings>
#include <smlib/files>
#undef REQUIRE_PLUGIN
#include <updater>

#define PLUGIN_VERSION "1.1.2"
#define UPDATE_URL     "https://sourcemod.krus.dk/classwarning/update.txt"
public Plugin myinfo =
{
	name        = "Class Warning",
	author      = "F2",
	description = "Warns players that are breaking the class limits",
	version     = PLUGIN_VERSION,
	url         = "https://github.com/F2/F2s-sourcemod-plugins"
};

int    g_iClassLimits[10];
ConVar g_hCvarClassLimit[10];
Handle g_hWarningTimer[MAXPLAYERS + 1];
float  g_fLastPosition[MAXPLAYERS + 1][3];
ConVar g_hCvarAutoReset;
bool   g_bEnabled = false;

public void OnPluginStart() {
	// Set up auto updater
	if (LibraryExists("updater"))
		Updater_AddPlugin(UPDATE_URL);

	// Match.inc
	Match_OnPluginStart();

	CreateDefaultConfigs();

	g_hCvarAutoReset = CreateConVar("sm_tournament_classlimit_autoreset", "1", "If 1, sets all class warning limits to -1 upon map start.", FCVAR_NONE);

	for (int class = 1; class <= 9; class ++) {
		char cvarName[64], cvarDesc[128];
		Format(cvarName, sizeof(cvarName), "sm_tournament_classlimit_%s", g_sClassNames[class]);
		String_ToLower(cvarName, cvarName, sizeof(cvarName));
		Format(cvarDesc, sizeof(cvarDesc), "Class warning limit for %s", g_sClassNames[class]);
		g_hCvarClassLimit[class] = CreateConVar(cvarName, "-1", cvarDesc, FCVAR_NONE);
		g_hCvarClassLimit[class].AddChangeHook(CvarChange_ClassLimit);
		char cvarVal[32];
		g_hCvarClassLimit[class].GetString(cvarVal, sizeof(cvarVal));
		g_iClassLimits[class] = StringToInt(cvarVal);
	}

	AddCommandListener(Cmd_Exec, "exec");

	// Simulate a map start
	OnMapStart();
}

public void OnLibraryAdded(const char[] name) {
	// Set up auto updater
	if (StrEqual(name, "updater"))
		Updater_AddPlugin(UPDATE_URL);
}

void CreateDefaultConfigs() {
	char path[128];
	char contents[1024];

	path = "cfg/etf2l_6v6_classwarning.cfg";
	if (!FileExists(path, true)) {
		Format(contents, sizeof(contents), "%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s",
			   "sm_tournament_classlimit_scout 2",
			   "sm_tournament_classlimit_soldier 2",
			   "sm_tournament_classlimit_pyro 1",
			   "sm_tournament_classlimit_demoman 1",
			   "sm_tournament_classlimit_heavy 1",
			   "sm_tournament_classlimit_engineer 1",
			   "sm_tournament_classlimit_medic 1",
			   "sm_tournament_classlimit_sniper 1",
			   "sm_tournament_classlimit_spy 2");

		File_StringToFile(path, contents);
	}

	path = "cfg/etf2l_9v9_classwarning.cfg";
	if (!FileExists(path, true)) {
		Format(contents, sizeof(contents), "%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s",
			   "sm_tournament_classlimit_scout 1",
			   "sm_tournament_classlimit_soldier 1",
			   "sm_tournament_classlimit_pyro 1",
			   "sm_tournament_classlimit_demoman 1",
			   "sm_tournament_classlimit_heavy 1",
			   "sm_tournament_classlimit_engineer 1",
			   "sm_tournament_classlimit_medic 1",
			   "sm_tournament_classlimit_sniper 1",
			   "sm_tournament_classlimit_spy 1");

		File_StringToFile(path, contents);
	}
}

public Action Cmd_Exec(int client, const char[] command, int argc) {
	if (argc < 1)
		return Plugin_Continue;

	char text[128];
	GetCmdArg(1, text, sizeof(text));

	if (!CfgExists(text))
		return Plugin_Continue;

	if (String_EndsWith(text, ".cfg"))
		text[strlen(text) - 4] = '\0';

	if (String_EndsWith(text, "_classwarning"))
		return Plugin_Continue;

	char path[128];
	Format(path, sizeof(path), "%s_classwarning", text);

	if (!CfgExists(path))
		return Plugin_Continue;

	ServerCommand("exec %s", path);
	return Plugin_Continue;
}

stock bool CfgExists(const char[] path) {
	char p[128];
	strcopy(p, sizeof(p), path);
	if (!String_EndsWith(p, ".cfg"))
		StrCat(p, sizeof(p), ".cfg");

	if (!String_StartsWith(p, "cfg/"))
		Format(p, sizeof(p), "cfg/%s", p);

	return FileExists(p, true); // true, such that also looks in /custom/ folders
}

public void OnMapStart() {
	Match_OnMapStart();
}

public void OnMapEnd() {
	Match_OnMapEnd();

	if (g_hCvarAutoReset.BoolValue) {
		for (int class = 1; class <= 9; class ++) {
			g_hCvarClassLimit[class].SetInt(-1);
		}
	}
}

public void OnClientDisconnect(int client) {
	StopWarning(client);
}

// -----------------------------------
// Match - start / end
// -----------------------------------

void StartMatch() {
	EnablePlugin();
}

void ResetMatch() {
	DisablePlugin();
}

void EndMatch(bool endedMidgame) {
	DisablePlugin();
}

// -----------------------------------

void EnablePlugin() {
	if (g_bEnabled)
		return;
	g_bEnabled = true;

	HookEvent("player_spawn", Event_player_spawn, EventHookMode_Post);
}

void DisablePlugin() {
	if (!g_bEnabled)
		return;
	g_bEnabled = false;

	UnhookEvent("player_spawn", Event_player_spawn, EventHookMode_Post);

	for (int client = 1; client <= MaxClients; client++) {
		StopWarning(client);
	}
}

public void CvarChange_ClassLimit(ConVar cvar, const char[] oldVal, const char[] newVal) {
	for (int class = 1; class <= 9; class ++) {
		if (g_hCvarClassLimit[class] == cvar) {
			g_iClassLimits[class] = StringToInt(newVal);

			break;
		}
	}
}

public void Event_player_spawn(Handle event, const char[] name, bool dontBroadcast) {
	if (!g_bEnabled)
		return;

	if (GetEngineTime() - g_fMatchStartTime < 5.0)
		return; // Don't report anything before the game starts

	int userid = GetEventInt(event, "userid");
	int client = GetClientOfUserId(userid);

	StartWarning(client);
}

void StopWarning(int client) {
	if (g_hWarningTimer[client] != null) {
		KillTimer(g_hWarningTimer[client]);
		g_hWarningTimer[client] = null;
	}
}

void StartWarning(int client) {
	StopWarning(client);

	GetClientAbsOrigin(client, g_fLastPosition[client]);
	g_hWarningTimer[client] = CreateTimer(0.1, Timer_Warn, client, TIMER_REPEAT);
}

int CountClass(TFTeam team, TFClassType class) {
	int classCount = 0;
	for (int client = 1; client <= MaxClients; client++) {
		if (!IsClientValid2(client) || TF2_GetClientTeam(client) != team)
			continue;

		if (IsPlayerAlive(client) && TF2_GetPlayerClass(client) == class)
			classCount++;
	}
	return classCount;
}

public Action Timer_Warn(Handle timer, any client) {
	if (!IsRealPlayer2(client) || !IsPlayerAlive(client)) {
		StopWarning(client);
		return Plugin_Stop;
	}

	float pos[3];
	GetClientAbsOrigin(client, pos);
	if (GetVectorDistance(pos, g_fLastPosition[client], true) <= 100 * 100)
		return Plugin_Continue;

	TFClassType class = TF2_GetPlayerClass(client);
	if (g_iClassLimits[view_as<int>(class)] < 0) {
		StopWarning(client);
		return Plugin_Stop;
	}

	TFTeam team              = TF2_GetClientTeam(client);
	int    currentClassCount = CountClass(team, class);

	if (currentClassCount <= g_iClassLimits[view_as<int>(class)]) {
		StopWarning(client);
		return Plugin_Stop;
	}

	MC_PrintToChat(client, "{red}------------------");
	MC_PrintToChat(client, "{red}<<{yellow}WARNING{red}>> {yellow}You are breaking the %s limit of %i", g_sClassNames[view_as<int>(class)], g_iClassLimits[view_as<int>(class)]);
	MC_PrintToChat(client, "{red}------------------");

	StopWarning(client);
	return Plugin_Stop;
}
