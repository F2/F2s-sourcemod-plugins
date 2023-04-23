/*

Release notes:

---- 1.0.0 (31/12/2014) ----
- If a player is AFK in warmup, it shows a warning to all players on their team
- If both teams ready up and there is an AFK player, it shows a warning to the person's team


---- 1.1.0 (14/07/2015) ----
- Fixed blinking text
- AFK time is more fine-grained
- Support for new ready-up behaviour

*/

#pragma semicolon 1

#include <sourcemod>
#include <morecolors>
#include <f2stocks>
#include <match>
#undef REQUIRE_PLUGIN
#include <updater>


#define PLUGIN_VERSION "1.1.0"
#define UPDATE_URL		"http://sourcemod.krus.dk/afk/update.txt"



public Plugin:myinfo = {
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


new bool:g_bEnabled = false;

new Float:g_fLastAngles[MAXPLAYERS+1][3];
new Float:g_fAfkTime[MAXPLAYERS+1];
new Handle:g_hTimerCheck = INVALID_HANDLE;
new Float:g_fLastCheck;
new bool:g_bIsAfk[MAXPLAYERS+1];

Handle g_hHud[4];

new Handle:g_hCvarMaxAfkTime, Handle:g_hCvarMinPlayers;
new Float:g_fMaxAfkTime;
new g_iMinPlayers;

new Handle:g_hOnAfkStateChanged; // public OnAfkStateChanged(client, bool:afk) {


public OnPluginStart() {
	// Set up auto updater
	if (LibraryExists("updater"))
		Updater_AddPlugin(UPDATE_URL);
	
	g_hOnAfkStateChanged = CreateGlobalForward("OnAfkStateChanged", ET_Ignore, Param_Cell, Param_Cell);
	
	g_hCvarMaxAfkTime = CreateConVar("afk_time", "20", "Number of seconds you can stand still before being marked as AFK.", FCVAR_NONE, true, 5.0);
	g_fMaxAfkTime = GetConVarFloat(g_hCvarMaxAfkTime);
	HookConVarChange(g_hCvarMaxAfkTime, CvarChange_MaxAfkTime);
	
	g_hCvarMinPlayers = CreateConVar("afk_minplayers", "8", "Minimum number of players on the server before the plugin is active.", FCVAR_NONE);
	g_iMinPlayers = GetConVarInt(g_hCvarMinPlayers);
	HookConVarChange(g_hCvarMinPlayers, CvarChange_MinPlayers);
	
	g_hHud[TFTeam_Blue] = _:CreateHudSynchronizer();
	g_hHud[TFTeam_Red] = _:CreateHudSynchronizer();
	
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

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max) {
	CreateNative("IsPlayerAFK", Native_IsPlayerAFK);
	RegPluginLibrary("afk");
	return APLRes_Success;
}

public Native_IsPlayerAFK(Handle:plugin, numParams) {
	if (!g_bEnabled)
		return _:false;
	
	new client = GetNativeCell(1);
	return _:IsPlayerAFK(client);
}

public OnMapStart() {
	Match_OnMapStart();
	
	for (new client = 1; client <= MaxClients; client++) {
		g_fAfkTime[client] = 0.0;
		g_bIsAfk[client] = false;
	}
	
	g_fLastCheck = GetGameTime();
}

public void OnMapEnd() {
	Match_OnMapEnd();
}

public OnLibraryAdded(const String:name[]) {
	// Set up auto updater
	if (StrEqual(name, "updater"))
		Updater_AddPlugin(UPDATE_URL);
}

public OnClientPutInServer(client) {
	g_fAfkTime[client] = 0.0;
	g_bIsAfk[client] = false;
}

public CvarChange_MaxAfkTime(Handle:cvar, const String:oldVal[], const String:newVal[]) {
	g_fMaxAfkTime = StringToFloat(newVal);
}

public CvarChange_MinPlayers(Handle:cvar, const String:oldVal[], const String:newVal[]) {
	g_iMinPlayers = StringToInt(newVal);
}


// -----------------------------------
// Match - start / end
// -----------------------------------

StartMatch() {
	new bool:foundAFK[TFTeam] = {false, ...};
	for (new client = 1; client <= MaxClients; client++) {
		if (IsPlayerAFK(client)) {
			new TFTeam:clientTeam = TFTeam:GetClientTeam(client);
			
			// Warn the player's team
			
			if (!foundAFK[clientTeam]) {
				foundAFK[clientTeam] = true;
				for (new other = 1; other <= MaxClients; other++) {
					if (!IsRealPlayer2(other))
						continue;
					if (TFTeam:GetClientTeam(other) != clientTeam)
						continue;
					MC_PrintToChat(other, "{lightgreen}[AFK] {green}WARNING! These players are AFK:");
				}
			}
			
			for (new other = 1; other <= MaxClients; other++) {
				if (!IsRealPlayer2(other))
					continue;
				if (TFTeam:GetClientTeam(other) != clientTeam)
					continue;
				
				CPrintToChatEx2(other, client, "{lightgreen}[AFK] {default}- {teamcolor}%N", client);
			}
		}
	}
	
	DisablePlugin();
}

ResetMatch() {
	EnablePlugin();
}

EndMatch(bool:endedMidgame) {
	EnablePlugin();
}

// -----------------------------------


EnablePlugin() {
	if (g_bEnabled)
		return;
	g_bEnabled = true;
	
	for (new client = 1; client <= MaxClients; client++) {
		g_fAfkTime[client] = 0.0;
		g_bIsAfk[client] = false;
	}
	
	HookEvent("player_spawn", Event_player_spawn, EventHookMode_Post);
	HookEvent("player_team", Event_player_team, EventHookMode_Post);
	
	g_hTimerCheck = CreateTimer(TIMERINTERVAL, Timer_CheckAFK, _, TIMER_REPEAT);
}

DisablePlugin() {
	if (!g_bEnabled)
		return;
	g_bEnabled = false;
	
	for (new client = 1; client <= MaxClients; client++) {
		if (!IsRealPlayer(client) || IsFakeClient(client))
			continue;
		
		new TFTeam:team = TFTeam:GetClientTeam(client);
		if (team != TFTeam_Blue && team != TFTeam_Red)
			continue;
		
		ClearSyncHud(client, g_hHud[team]);
	}
	
	UnhookEvent("player_spawn", Event_player_spawn, EventHookMode_Post);
	UnhookEvent("player_team", Event_player_team, EventHookMode_Post);
	
	if (g_hTimerCheck != INVALID_HANDLE) {
		KillTimer(g_hTimerCheck);
		g_hTimerCheck = INVALID_HANDLE;
	}
}

public Action:Event_player_spawn(Handle:event, const String:name[], bool:dontBroadcast) {
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);
	
	g_fLastAngles[client][0] = DEFANG0;
	g_fLastAngles[client][1] = DEFANG1;
	g_fLastAngles[client][2] = DEFANG2;
	
	// We cannot get the angles here, because TF2DM will move the player and change his angles later in this frame or the next frame.
}

public Action:Event_player_team(Handle:event, const String:name[], bool:dontBroadcast) {
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);
	
	g_fAfkTime[client] = 0.0;
	g_bIsAfk[client] = false;
	
	ClearSyncHud(client, Handle:g_hHud[TFTeam_Red]);
	ClearSyncHud(client, Handle:g_hHud[TFTeam_Blue]);
}

public Action:Timer_CheckAFK(Handle:timer) {
	new Float:now = GetGameTime();
	new Float:span = now - g_fLastCheck;
	g_fLastCheck = now;
	
	decl bool:afkBefore[MAXPLAYERS+1];
	decl bool:relevantClient[MAXPLAYERS+1];
	decl TFTeam:clientTeam[MAXPLAYERS+1];
	
	new realPlayerCount = GetRealPlayerCount();
	
	for (new client = 1; client <= MaxClients; client++) {
		afkBefore[client] = g_bIsAfk[client];
		relevantClient[client] = false;
		
		if (!IsRealPlayer(client) || IsFakeClient(client)) {
			g_bIsAfk[client] = false;
			continue;
		}
		
		new TFTeam:team = TFTeam:GetClientTeam(client);
		clientTeam[client] = team;
		if (team != TFTeam_Red && team != TFTeam_Blue) {
			g_bIsAfk[client] = false;
			continue;
		}
		
		relevantClient[client] = true;
		
		if (!IsPlayerAlive(client))
			continue; // Remain the same AFK state
		
		new Float:angles[3];
		if (!GetClientEyeAngles(client, angles)) {
			LogError("Could not get client eye angles for client %i", GetClientUserId(client));
			continue; // Should never happen, but remain the same AFK state
		}
		
		new Float:vecDist = GetVectorDistance(angles, g_fLastAngles[client], true);
		new bool:justSpawned = g_fLastAngles[client][0] == DEFANG0 && g_fLastAngles[client][1] == DEFANG1 && g_fLastAngles[client][2] == DEFANG2;
		
		g_fLastAngles[client][0] = angles[0];
		g_fLastAngles[client][1] = angles[1];
		g_fLastAngles[client][2] = angles[2];
		
		if (justSpawned)
			continue; // If the player has just spawned, then record his angles but don't detect if he has moved.
		
		if (vecDist <= 1.0) {
			g_fAfkTime[client] += span;
		} else {
			g_fAfkTime[client] = 0.0;
		}
		
		new buttons = GetClientButtons(client);
		new buttonsCheck = IN_ATTACK | IN_JUMP | IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT;
		if ((buttons & buttonsCheck) != 0)
			g_fAfkTime[client] = 0.0;
		
		g_bIsAfk[client] = false;
		if (g_fMaxAfkTime >= 1.0) {
			if (g_fAfkTime[client] >= g_fMaxAfkTime && realPlayerCount >= g_iMinPlayers) {
				g_bIsAfk[client] = true;
			}
		}
	}
	
	
	for (new client = 1; client <= MaxClients; client++) {
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
	
	
	decl String:hudText[TFTeam][256];
	hudText[TFTeam_Blue] = "";
	hudText[TFTeam_Red] = "";
	
	for (new client = 1; client <= MaxClients; client++) {
		if (!relevantClient[client])
			continue;
		
		new TFTeam:team = clientTeam[client];
		
		if (g_bIsAfk[client]) {
			decl String:nickname[32];
			GetClientName(client, nickname, sizeof(nickname));
			
			new afkTime = RoundToFloor(g_fAfkTime[client] / 60.0);
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
	
	for (new TFTeam:team = TFTeam_Red; team <= TFTeam_Blue; team++) {
		if (hudText[team][0] != '\0') {
			Format(hudText[team], sizeof(hudText[]), "You have AFK players:%s", hudText[team]);
		}
	}
	
	for (new client = 1; client <= MaxClients; client++) {
		if (!relevantClient[client])
			continue;
		
		new TFTeam:team = clientTeam[client];
		
		SetHudTextParams(0.04, -1.0, 3.0, 255, 0, 0, 255, 0, 0.0, 0.0, 0.0);
		ShowSyncHudText(client, g_hHud[team], hudText[team]);
	}
	
	return Plugin_Continue;
}

bool:IsPlayerAFK(client) {
	if (!g_bEnabled)
		return false;
	if (!IsRealPlayer(client) || IsFakeClient(client))
		return false;
	
	new TFTeam:team = TFTeam:GetClientTeam(client);
	if (team != TFTeam_Red && team != TFTeam_Blue)
		return false;
	
	return g_bIsAfk[client];
}





