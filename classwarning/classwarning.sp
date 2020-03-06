/*

Release notes:

---- 1.0.0 (26/07/2014) ----
- In ETF2L class limits are not enforced by the server. This plugin warns players in chat if they are breaking the class limit.


---- 1.1.0 (14/07/2015) ----
- Now also works when configs are in /custom/ folder
- Support for new ready-up behaviour

*/

#pragma semicolon 1

#include <sourcemod>
#include <morecolors>
#include <f2stocks>
#include <match>
#include <smlib/strings>
#include <smlib/files>
#undef REQUIRE_PLUGIN
#include <updater>


#define PLUGIN_VERSION "1.1.0"
#define UPDATE_URL		"http://sourcemod.krus.dk/classwarning/update.txt"


public Plugin:myinfo = {
	name = "Class Warning",
	author = "F2",
	description = "Warns players that are breaking the class limits",
	version = PLUGIN_VERSION,
	url = "http://sourcemod.krus.dk/"
};

new g_iClassLimits[TFClassType];
new Handle:g_hCvarClassLimit[TFClassType];
new Handle:g_hWarningTimer[MAXPLAYERS+1];
new Float:g_fLastPosition[MAXPLAYERS+1][3];
new Handle:g_hCvarAutoReset;
new bool:g_bEnabled = false;


public OnPluginStart() {
	// Set up auto updater
	if (LibraryExists("updater"))
		Updater_AddPlugin(UPDATE_URL);
	
	// Match.inc
	Match_OnPluginStart();
	
	CreateDefaultConfigs();
	
	g_hCvarAutoReset = CreateConVar("sm_tournament_classlimit_autoreset", "1", "If 1, sets all class warning limits to -1 upon map start.", FCVAR_NONE);
	
	for (new class = 1; class <= 9; class++) {
		decl String:cvarName[64], String:cvarDesc[128];
		Format(cvarName, sizeof(cvarName), "sm_tournament_classlimit_%s", g_sClassNames[class]);
		String_ToLower(cvarName, cvarName, sizeof(cvarName));
		Format(cvarDesc, sizeof(cvarDesc), "Class warning limit for %s", g_sClassNames[class]);
		g_hCvarClassLimit[class] = CreateConVar(cvarName, "-1", cvarDesc, FCVAR_NONE);
		HookConVarChange(g_hCvarClassLimit[class], CvarChange_ClassLimit);
		decl String:cvarVal[32];
		GetConVarString(g_hCvarClassLimit[class], cvarVal, sizeof(cvarVal));
		g_iClassLimits[class] = StringToInt(cvarVal);
	}
	
	AddCommandListener(Cmd_Exec, "exec");
	
	// Simulate a map start
	OnMapStart();
}

public OnLibraryAdded(const String:name[]) {
	// Set up auto updater
	if (StrEqual(name, "updater"))
		Updater_AddPlugin(UPDATE_URL);
}

CreateDefaultConfigs() {
	decl String:path[128];
	decl String:contents[1024];
	
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

public Action:Cmd_Exec(client, const String:command[], argc) {
	if (argc < 1)
		return Plugin_Continue;
	
	decl String:text[128];
	GetCmdArg(1, text, sizeof(text));
	
	if (!CfgExists(text))
		return Plugin_Continue;
	
	if (String_EndsWith(text, ".cfg"))
		text[strlen(text)-4] = '\0';
	
	if (String_EndsWith(text, "_classwarning"))
		return Plugin_Continue;
	
	decl String:path[128];
	Format(path, sizeof(path), "%s_classwarning", text);
	
	if (!CfgExists(path))
		return Plugin_Continue;
	
	ServerCommand("exec %s", path);
	return Plugin_Continue;
}

stock bool:CfgExists(const String:path[]) {
	decl String:p[128];
	strcopy(p, sizeof(p), path);
	if (!String_EndsWith(p, ".cfg"))
		StrCat(p, sizeof(p), ".cfg");
	
	if (!String_StartsWith(p, "cfg/"))
		Format(p, sizeof(p), "cfg/%s", p);
	
	return FileExists(p, true); // true, such that also looks in /custom/ folders
}

public OnMapStart() {
	Match_OnMapStart();
}

public OnMapEnd() {
	Match_OnMapEnd();
	
	if (GetConVarBool(g_hCvarAutoReset)) {
		for (new class = 1; class <= 9; class++) {
			SetConVarInt(g_hCvarClassLimit[class], -1);
		}
	}
}

public OnClientDisconnect(client) {
	StopWarning(client);
}

// -----------------------------------
// Match - start / end
// -----------------------------------


StartMatch() {
	EnablePlugin();
}

ResetMatch() {
	DisablePlugin();
}

EndMatch(bool:endedMidgame) {
	DisablePlugin();
}

// -----------------------------------


EnablePlugin() {
	if (g_bEnabled)
		return;
	g_bEnabled = true;
	
	HookEvent("player_spawn", Event_player_spawn, EventHookMode_Post);
}

DisablePlugin() {
	if (!g_bEnabled)
		return;
	g_bEnabled = false;
	
	UnhookEvent("player_spawn", Event_player_spawn, EventHookMode_Post);
	
	for (new client = 1; client <= MaxClients; client++) {
		StopWarning(client);
	}
}

public CvarChange_ClassLimit(Handle:cvar, const String:oldVal[], const String:newVal[]) {
	for (new class = 1; class <= 9; class++) {
		if (g_hCvarClassLimit[class] == cvar) {
			g_iClassLimits[class] = StringToInt(newVal);
			
			break;
		}
	}
}

public Event_player_spawn(Handle:event, const String:name[], bool:dontBroadcast) {
	if (!g_bEnabled)
		return;
	
	if (GetEngineTime() - g_fMatchStartTime < 5.0)
		return; // Don't report anything before the game starts
	
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);
	
	StartWarning(client);
}

StopWarning(client) {
	if (g_hWarningTimer[client] != INVALID_HANDLE) {
		KillTimer(g_hWarningTimer[client]);
		g_hWarningTimer[client] = INVALID_HANDLE;
	}
}

StartWarning(client) {
	StopWarning(client);
	
	GetClientAbsOrigin(client, g_fLastPosition[client]);
	g_hWarningTimer[client] = CreateTimer(0.1, Timer_Warn, client, TIMER_REPEAT);
}

CountClass(TFTeam:team, TFClassType:class) {
	new classCount = 0;
	for (new client = 1; client <= MaxClients; client++) {
		if (!IsClientValid2(client) || GetClientTeam(client) != _:team)
			continue;
		
		if (IsPlayerAlive(client) && TF2_GetPlayerClass(client) == class)
			classCount++;
	}
	return classCount;
}

public Action:Timer_Warn(Handle:timer, any:client) {
	if (!IsRealPlayer2(client) || !IsPlayerAlive(client)) {
		StopWarning(client);
		return Plugin_Stop;
	}
	
	decl Float:pos[3];
	GetClientAbsOrigin(client, pos);
	if (GetVectorDistance(pos, g_fLastPosition[client], true) <= 100 * 100)
		return Plugin_Continue;
	
	new TFClassType:class = TF2_GetPlayerClass(client);
	if (g_iClassLimits[class] < 0) {
		StopWarning(client);
		return Plugin_Stop;
	}
	
	new TFTeam:team = TFTeam:GetClientTeam(client);
	new currentClassCount = CountClass(team, class);
	
	if (currentClassCount <= g_iClassLimits[class]) {
		StopWarning(client);
		return Plugin_Stop;
	}
	
	CPrintToChat(client, "{red}------------------");
	CPrintToChat(client, "{red}<<{yellow}WARNING{red}>> {yellow}You are breaking the %s limit of %i", g_sClassNames[class], g_iClassLimits[class]);
	CPrintToChat(client, "{red}------------------");
	
	StopWarning(client);
	return Plugin_Stop;
}
