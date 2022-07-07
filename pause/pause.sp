/*

Release notes:

---- 1.0.0 (26/07/2014) ----
- Adds a 5 second countdown when unpausing
- Unpause protection (if two people write pause at the same time, it doesn't accidentally unpause)
- Shows pause information in chat


---- 1.1.0 (31/07/2014) ----
- Added "repause" command to quickly unpause and pause again
- Added support for setpause and unpause commands


---- 1.2.0 (02/08/2014) ----
- Allow infinite amount of chat messages during pause
- Every minute it shows how long the pause has been going on


---- 1.3.0 (07/01/2015) ----
- Fixed bug with "repause" command

*/

#pragma semicolon 1

#include <sourcemod>
#include <morecolors>
#include <f2stocks>
#undef REQUIRE_PLUGIN
#include <updater>


#define PLUGIN_VERSION "1.3.0"
#define UPDATE_URL		"http://sourcemod.krus.dk/pause/update.txt"

#define PAUSE_UNPAUSE_TIME 2.0
#define UNPAUSE_WAIT_TIME 5

enum PauseState {
	Unpaused,
	Paused,
	AboutToUnpause,
	Ignore__Unpaused,
	Ignore__UnpausePause1,
	Ignore__UnpausePause2,
};



new Handle:g_cvarPausable = INVALID_HANDLE;
new PauseState:g_iPauseState;
new Float:g_fLastPause;
new g_iCountdown;
new Handle:g_hCountdownTimer = INVALID_HANDLE;
new Handle:g_hPauseTimeTimer = INVALID_HANDLE;
new g_iPauseTimeMinutes;
new Handle:g_cvarPauseChat = INVALID_HANDLE;

public Plugin:myinfo = {
	name = "Improved Pause Command",
	author = "F2",
	description = "Avoids accidental unpausing and shows a countdown when unpausing",
	version = PLUGIN_VERSION,
	url = "http://sourcemod.krus.dk/"
};


public OnPluginStart() {
	
	AddCommandListener(Cmd_Pause, "pause");
	AddCommandListener(Cmd_Pause, "setpause");
	AddCommandListener(Cmd_Pause, "unpause");
	
	AddCommandListener(Cmd_UnpausePause, "repause");
	AddCommandListener(Cmd_UnpausePause, "unpausepause");
	AddCommandListener(Cmd_UnpausePause, "pauseunpause");
	
	g_cvarPausable = FindConVar("sv_pausable");
	
	g_cvarPauseChat = CreateConVar("pause_enablechat", "1", "Enable people to chat as much as they want during a pause.", FCVAR_NONE);
	AddCommandListener(Cmd_Say, "say");
	
	OnMapStart();
	
	// Set up auto updater
	if (LibraryExists("updater"))
		Updater_AddPlugin(UPDATE_URL);

}

public OnLibraryAdded(const String:name[]) {
	// Set up auto updater
	if (StrEqual(name, "updater"))
		Updater_AddPlugin(UPDATE_URL);
}

public OnMapStart() {
	g_fLastPause = -10.0;
	g_iPauseState = Unpaused; // The game is automatically unpaused during a map change
	g_hCountdownTimer = INVALID_HANDLE;
	g_hPauseTimeTimer = INVALID_HANDLE;
}

public Action:Cmd_UnpausePause(client, const String:command[], args) {
	// Let the game handle the "off" situations
	if (!GetConVarBool(g_cvarPausable))
		return Plugin_Continue;
	if (client == 0)
		return Plugin_Continue;
	
	if (g_iPauseState != Paused)
		return Plugin_Handled;
	
	g_iPauseState = Ignore__UnpausePause1;
	FakeClientCommand(client, "pause");
	CPrintToChatAllEx2(client, "{lightgreen}[Pause] {default}Game was unpaused by {teamcolor}%N", client);
	
	CreateTimer(0.05, Timer_Repause, client, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Handled;
}

public Action:Timer_Repause(Handle:timer, any:client) {
	FakeClientCommandEx(client, "pause");
	CPrintToChatAllEx2(client, "{lightgreen}[Pause] {default}Game was paused by {teamcolor}%N", client);
}

public Action:Cmd_Pause(client, const String:command[], args) {
	// Let the game handle the "off" situations
	if (!GetConVarBool(g_cvarPausable))
		return Plugin_Continue;
	if (client == 0)
		return Plugin_Continue;
	
	if (StrEqual(command, "unpause", false)) {
		if (!(g_iPauseState == Unpaused || g_iPauseState == AboutToUnpause))
			FakeClientCommandEx(client, "pause");
		return Plugin_Handled;
	}
	
	if (StrEqual(command, "setpause", false)) {
		if (g_iPauseState == Unpaused || g_iPauseState == AboutToUnpause)
			FakeClientCommandEx(client, "pause");
		return Plugin_Handled;
	}
	
	if (g_iPauseState == Ignore__Unpaused) {
		g_iPauseState = Unpaused;
	} else if (g_iPauseState == Ignore__UnpausePause1) {
		g_iPauseState = Ignore__UnpausePause2;
	} else if (g_iPauseState == Ignore__UnpausePause2) {
		g_iPauseState = Paused;
	} else if (g_iPauseState == Unpaused || g_iPauseState == AboutToUnpause) {
		g_fLastPause = GetTickedTime();
		if (g_hCountdownTimer != INVALID_HANDLE) {
			KillTimer(g_hCountdownTimer);
			g_hCountdownTimer = INVALID_HANDLE;
			PrintCenterTextAll(" ");
		}
		
		new PauseState:oldState = g_iPauseState;
		g_iPauseState = Paused;
		CPrintToChatAllEx2(client, "{lightgreen}[Pause] {default}Game was paused by {teamcolor}%N", client);
		
		if (oldState == AboutToUnpause)
			return Plugin_Handled;
		else {
			g_hPauseTimeTimer = CreateTimer(60.0, Timer_PauseTime, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
			g_iPauseTimeMinutes = 0;
		}
	} else { // Paused
		new Float:timeSinceLastPause = GetTickedTime() - g_fLastPause;
		if (timeSinceLastPause < PAUSE_UNPAUSE_TIME) {
			new Float:waitTime = PAUSE_UNPAUSE_TIME - timeSinceLastPause;
			CPrintToChat2(client, "{lightgreen}[Pause] {default}To prevent accidental unpauses, you have to wait %.1f second%s before unpausing.", waitTime, (waitTime >= 0.95 && waitTime < 1.05) ? "" : "s");
			return Plugin_Handled;
		}
		
		g_iPauseState = AboutToUnpause;
		CPrintToChatAllEx2(client, "{lightgreen}[Pause] {default}Game is being unpaused in %i seconds by {teamcolor}%N{default}...", UNPAUSE_WAIT_TIME, client);
		
		g_iCountdown = UNPAUSE_WAIT_TIME;
		g_hCountdownTimer = CreateTimer(1.0, Timer_Countdown, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
		Timer_Countdown(g_hCountdownTimer);
		
		return Plugin_Handled;
	}
	
	// Bla
	return Plugin_Continue;
}

public Action:Timer_Countdown(Handle:timer) {
	if (g_iCountdown == 0) {
		g_hCountdownTimer = INVALID_HANDLE;
		PrintCenterTextAll(" ");
		
		KillTimer(g_hPauseTimeTimer);
		g_hPauseTimeTimer = INVALID_HANDLE;
		
		g_iPauseState = Ignore__Unpaused;
		for (new client = 1; client <= MaxClients; client++) {
			if (IsClientValid(client)) {
				CPrintToChatAll2("{lightgreen}[Pause] {default}Game is unpaused!");
				FakeClientCommandEx(client, "pause");
				break;
			}
		}
		
		return Plugin_Stop;
	} else {
		PrintCenterTextAll("Unpausing in %is...", g_iCountdown);
		if (g_iCountdown < UNPAUSE_WAIT_TIME)
			CPrintToChatAll2("{lightgreen}[Pause] {default}Game is being unpaused in %i second%s...", g_iCountdown, g_iCountdown == 1 ? "" : "s");
		g_iCountdown--;
		return Plugin_Continue;
	}
}

public Action:Timer_PauseTime(Handle:timer) {
	g_iPauseTimeMinutes++;
	if (g_iPauseState != AboutToUnpause)
		CPrintToChatAll2("{lightgreen}[Pause] {default}Game has been paused for %i minute%s", g_iPauseTimeMinutes, g_iPauseTimeMinutes == 1 ? "" : "s");
	return Plugin_Continue;
}

public Action:Cmd_Say(client, const String:command[], args) {
	if (client == 0)
		return Plugin_Continue;
	
	if (g_iPauseState == Paused || g_iPauseState == AboutToUnpause) {
		if (!GetConVarBool(g_cvarPauseChat))
			return Plugin_Continue;
		
		decl String:buffer[256];
		GetCmdArgString(buffer, sizeof(buffer));
		if (buffer[0] != '\0') {
			if (buffer[strlen(buffer)-1] == '"')
				buffer[strlen(buffer)-1] = '\0';
			if (buffer[0] == '"')
				strcopy(buffer, sizeof(buffer), buffer[1]);
			
			decl String:dead[16] = "";
			if (GetClientTeam(client) == _:TFTeam_Spectator)
				dead = "*SPEC* ";
			else if ((GetClientTeam(client) == _:TFTeam_Red || GetClientTeam(client) == _:TFTeam_Blue) && !IsPlayerAlive(client))
				dead = "*DEAD* ";
			
			CPrintToChatAllEx2(client, "%s{teamcolor}%N{default} :  %s", dead, client, buffer);
		}
		
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

