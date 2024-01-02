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


---- 1.5.1 (08/10/2022) ----
- Added notification to use 'repause' command when someone joins during a pause
- Fixed building ubercharge during pause glitch - by Aad | hl.RGL.gg
  Credit to rodrigo286 for providng base code for storing/restoring uber on medic death
  (https://forums.alliedmods.net/showthread.php?p=2022903)
- When unpausing, fixed wrong name being logged
- Fixed bug when all players leave the server during a pause

---- 1.6.0 (02/01/2024) ----
- Added support for restoring player positions, angles, and velocities when unpausing - by Shigbeard
  This resolves an issue on some servers where an unpause will "fast forward" players
  to where they would be if the pause never occurred. For example, players in free fall during pause
  would suddenly find themselves grounded on unpause.
- Also saved and restored player health along side this, incase fall damage still applied

---- 1.6.1 (02/01/2024) ----
- Added support for restoring spy cloak after pause, much like how uber is restored. - by Shigbeard
  This resolves an issue where spies would be uncloaked after unpausing.
  This is achieved by setting any spy's cloak meter to a very large number, effectively making it permanent.
*/

#pragma semicolon 1

#include <sourcemod>
#include <morecolors>
#include <f2stocks>
#include <tf2_stocks>
#include <sdktools_functions> // Required to restore Player positions.
#undef REQUIRE_PLUGIN
#include <updater>

#pragma newdecls required

#define PLUGIN_VERSION "1.6.1"
#define UPDATE_URL		"http://sourcemod.krus.dk/pause/update.txt"

#define PAUSE_UNPAUSE_TIME 2.0
#define UNPAUSE_WAIT_TIME 5

enum PauseState {
	Unpaused,
	Paused,
	AboutToUnpause,
	Ignore__Unpaused,
	Ignore__Repause1,
	Ignore__Repause2,
};

ConVar g_cvarPausable = null;
ConVar g_cvarAllowHibernation = null;
PauseState g_iPauseState;
float g_fLastPause;
int g_iClientUnpausing;
int g_iCountdown;
Handle g_hCountdownTimer = null;
Handle g_hPauseTimeTimer = null;
int g_iPauseTimeMinutes;
ConVar g_cvarPauseChat = null;
ConVar g_cvarRestorePos = null;
ConVar g_cvarRestoreHealth = null;
ConVar g_cvarRestoreCloak = null;
float g_fChargeLevel[MAXPLAYERS+1];
float g_fPlayerPos[MAXPLAYERS+1][3];
float g_fPlayerAng[MAXPLAYERS+1][3];
float g_fPlayerVel[MAXPLAYERS+1][3];
int g_iPlayerHealth[MAXPLAYERS+1];

float g_fCloakLevel[MAXPLAYERS+1];

public Plugin myinfo = {
	name = "Improved Pause Command",
	author = "F2",
	description = "Avoids accidental unpausing and shows a countdown when unpausing",
	version = PLUGIN_VERSION,
	url = "https://github.com/F2/F2s-sourcemod-plugins"
};


public void OnPluginStart() {
	AddCommandListener(Cmd_Pause, "pause");
	AddCommandListener(Cmd_Pause, "setpause");
	AddCommandListener(Cmd_Pause, "unpause");

	AddCommandListener(Cmd_UnpausePause, "repause");
	AddCommandListener(Cmd_UnpausePause, "unpausepause");
	AddCommandListener(Cmd_UnpausePause, "pauseunpause");

	g_cvarPausable = FindConVar("sv_pausable");
	g_cvarAllowHibernation = FindConVar("tf_allow_server_hibernation");

	g_cvarPauseChat = CreateConVar("pause_enablechat", "1", "Enable people to chat as much as they want during a pause.", FCVAR_NONE);

	g_cvarRestorePos = CreateConVar("pause_restore_pos", "0", "Restore player positions, angles, and velocities when unpausing.", FCVAR_NONE);
	g_cvarRestoreHealth = CreateConVar("pause_restore_health", "0", "Restore player health when unpausing.", FCVAR_NONE);
	g_cvarRestoreCloak = CreateConVar("pause_restore_cloak", "0", "Restore player cloak when unpausing.", FCVAR_NONE);
	AddCommandListener(Cmd_Say, "say");

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
	// Be aware that this is also called upon Plugin Start.

	g_fLastPause = -10.0;
	g_hCountdownTimer = INVALID_HANDLE;
	g_hPauseTimeTimer = INVALID_HANDLE;
	for (int client = 1; client <= MaxClients; client++) {
		g_fChargeLevel[client] = -1.0;
		ResetClientPosition(client);
		g_iPlayerHealth[client] = 0;
		g_fCloakLevel[client] = 0.0;
	}

	// The game is automatically unpaused during a map change
	g_iPauseState = Unpaused;

	// Detect if the server is already paused
	// If server is hibernating, I suppose we could risk IsServerProcessing() is false. (Although, my testing shows it is still true.)
	bool isServerEmpty = GetRealPlayerCount() == 0;
	if (IsServerProcessing() == false) {
		if (!g_cvarAllowHibernation.BoolValue || (g_cvarAllowHibernation.BoolValue && !isServerEmpty)) {
			g_iPauseState = Paused;
			g_fLastPause = GetTickedTime();
			StorePlayerCloak(true);
			StoreUbercharges();
			StorePlayerPositions();
			StorePlayerHealth();
			if (g_hPauseTimeTimer != null) {
				KillTimer(g_hPauseTimeTimer);
			}
			g_hPauseTimeTimer = CreateTimer(60.0, Timer_PauseTime, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
			g_iPauseTimeMinutes = 0;
		}
	}
}

void ResetClientPosition(int client) { // Helper Function
	g_fPlayerAng[client][0] = 0.0;
	g_fPlayerAng[client][1] = 0.0;
	g_fPlayerAng[client][2] = 0.0;
	g_fPlayerPos[client][0] = 0.0;
	g_fPlayerPos[client][1] = 0.0;
	g_fPlayerPos[client][2] = 0.0;
	g_fPlayerVel[client][0] = 0.0;
	g_fPlayerVel[client][1] = 0.0;
	g_fPlayerVel[client][2] = 0.0;
}

public void OnClientConnected(int client) {
	g_fChargeLevel[client] = -1.0;
	ResetClientPosition(client);
	g_iPlayerHealth[client] = 0;
	g_fCloakLevel[client] = 0.0;
}


public void OnClientPutInServer(int client) {
	if (g_iPauseState == Paused) {
		CPrintToChatAll2("{lightgreen}[Pause] {default}Type {olive}repause {default}in the console to let in {normal}%N", client);
	}
}

public void OnClientDisconnect_Post(int client) {
	if (GetRealPlayerCount() == 0 && g_cvarAllowHibernation.BoolValue) {
		// If everyone disconnects, the game is unpaused due to hibernation

		if (g_hCountdownTimer != null)
			KillTimer(g_hCountdownTimer);
		if (g_hPauseTimeTimer != null)
			KillTimer(g_hPauseTimeTimer);

		OnMapStart();
	}
}

public Action Cmd_UnpausePause(int client, const char[] command, int args) {
	// Let the game handle the "off" situations
	if (!g_cvarPausable.BoolValue)
		return Plugin_Continue;
	if (client == 0)
		return Plugin_Continue;

	if (g_iPauseState != Paused)
		return Plugin_Handled;

	g_iPauseState = Ignore__Repause1;
	FirePauseCommand(client);
	CPrintToChatAllEx2(client, "{lightgreen}[Pause] {default}Game was repaused by {teamcolor}%N", client);

	CreateTimer(0.1, Timer_Repause, client, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Handled;
}

public Action Timer_Repause(Handle timer, int client) {
	FirePauseCommand(client);
	return Plugin_Continue;
}

public Action Cmd_Pause(int client, const char[] command, int args) {
	// Let the game handle the "off" situations
	if (!g_cvarPausable.BoolValue)
		return Plugin_Continue;
	if (client == 0)
		return Plugin_Continue;

	if (StrEqual(command, "unpause", false)) {
		if (!(g_iPauseState == Unpaused || g_iPauseState == AboutToUnpause))
			FirePauseCommand(client);
		return Plugin_Handled;
	}

	if (StrEqual(command, "setpause", false)) {
		if (g_iPauseState == Unpaused || g_iPauseState == AboutToUnpause)
			FirePauseCommand(client);
		return Plugin_Handled;
	}

	if (g_iPauseState == Ignore__Unpaused) {
		RestoreUbercharges();
		if (g_cvarRestorePos.BoolValue) {
			RestorePlayerPositions();
		}
		if (g_cvarRestoreHealth.BoolValue) {
			RestorePlayerHealth();
		}
		if (g_cvarRestoreCloak.BoolValue) {
			RestorePlayerCloak();
		}
		g_iPauseState = Unpaused;
	} else if (g_iPauseState == Ignore__Repause1) {
		// Let the game become unpaused
		if (g_cvarRestorePos.BoolValue) {
			RestorePlayerPositions();
		}
		if (g_cvarRestoreHealth.BoolValue) {
			RestorePlayerHealth();
		}
		if (g_cvarRestoreCloak.BoolValue) {
			RestorePlayerCloak();
		}
		RestoreUbercharges();
		g_iPauseState = Ignore__Repause2;
	} else if (g_iPauseState == Ignore__Repause2) {
		// Let the game become paused
		StorePlayerCloak(!g_cvarRestoreCloak.BoolValue);
		StorePlayerPositions(); // Store them regardless of setting, incase we later decide we want to restore them
		StorePlayerHealth();
		StoreUbercharges();
		g_iPauseState = Paused;
	} else if (g_iPauseState == Unpaused || g_iPauseState == AboutToUnpause) {
		g_fLastPause = GetTickedTime();
		if (g_hCountdownTimer != null) {
			KillTimer(g_hCountdownTimer);
			g_hCountdownTimer = null;
		}

		PauseState oldState = g_iPauseState;
		g_iPauseState = Paused;

		CPrintToChatAllEx2(client, "{lightgreen}[Pause] {default}Game was paused by {teamcolor}%N", client);
		if (oldState == Unpaused) {
			CPrintToChatAll2("{lightgreen}[Pause] {default}Ubercharges are also paused");
			if (g_cvarRestorePos.BoolValue) {
				CPrintToChatAll2("{lightgreen}[Pause] {default}Player Positions saved");
			}
			if (g_cvarRestoreHealth.BoolValue) {
				CPrintToChatAll2("{lightgreen}[Pause] {default}Player Health saved");
			}
			// Don't annouce cloak, it may effect gameplay by prompting teams to think about spies.
		}
		StorePlayerCloak(!g_cvarRestoreCloak.BoolValue);
		StorePlayerPositions();
		StorePlayerHealth();
		StoreUbercharges();

		if (oldState == AboutToUnpause)
			return Plugin_Handled;
		else {
			g_hPauseTimeTimer = CreateTimer(60.0, Timer_PauseTime, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
			g_iPauseTimeMinutes = 0;
		}
	} else { // Paused
		float timeSinceLastPause = GetTickedTime() - g_fLastPause;
		if (timeSinceLastPause < PAUSE_UNPAUSE_TIME) {
			float waitTime = PAUSE_UNPAUSE_TIME - timeSinceLastPause;
			CPrintToChat2(client, "{lightgreen}[Pause] {default}To prevent accidental unpauses, you have to wait %.1f second%s before unpausing.", waitTime, (waitTime >= 0.95 && waitTime < 1.05) ? "" : "s");
			return Plugin_Handled;
		}

		g_iClientUnpausing = client;

		g_iPauseState = AboutToUnpause;
		CPrintToChatAllEx2(client, "{lightgreen}[Pause] {default}Game is being unpaused in %i seconds by {teamcolor}%N{default}...", UNPAUSE_WAIT_TIME, client);

		g_iCountdown = UNPAUSE_WAIT_TIME;
		g_hCountdownTimer = CreateTimer(1.0, Timer_Countdown, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
		TriggerTimer(g_hCountdownTimer, true);

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Timer_Countdown(Handle timer) {
	if (g_iCountdown == 0) {
		g_hCountdownTimer = null;

		if (g_hPauseTimeTimer != null) {
			KillTimer(g_hPauseTimeTimer);
			g_hPauseTimeTimer = null;
		}

		g_iPauseState = Ignore__Unpaused;

		CPrintToChatAll2("{lightgreen}[Pause] {default}Game is unpaused!");
		FirePauseCommand(g_iClientUnpausing);

		return Plugin_Stop;
	} else {
		if (g_iCountdown < UNPAUSE_WAIT_TIME)
			CPrintToChatAll2("{lightgreen}[Pause] {default}Game is being unpaused in %i second%s...", g_iCountdown, g_iCountdown == 1 ? "" : "s");
		g_iCountdown--;
		return Plugin_Continue;
	}
}

public Action Timer_PauseTime(Handle timer) {
	g_iPauseTimeMinutes++;
	if (g_iPauseState != AboutToUnpause)
		CPrintToChatAll2("{lightgreen}[Pause] {default}Game has been paused for %i minute%s", g_iPauseTimeMinutes, g_iPauseTimeMinutes == 1 ? "" : "s");
	return Plugin_Continue;
}

public Action Cmd_Say(int client, const char[] command, int args) {
	if (client == 0)
		return Plugin_Continue;

	if (g_iPauseState == Paused || g_iPauseState == AboutToUnpause) {
		if (!g_cvarPauseChat.BoolValue)
			return Plugin_Continue;

		char buffer[256];
		GetCmdArgString(buffer, sizeof(buffer));
		if (buffer[0] != '\0') {
			if (buffer[strlen(buffer)-1] == '"')
				buffer[strlen(buffer)-1] = '\0';
			if (buffer[0] == '"')
				strcopy(buffer, sizeof(buffer), buffer[1]);

			char dead[16] = "";
			if (TF2_GetClientTeam(client) == TFTeam_Spectator)
				dead = "*SPEC* ";
			else if ((TF2_GetClientTeam(client) == TFTeam_Red || TF2_GetClientTeam(client) == TFTeam_Blue) && !IsPlayerAlive(client))
				dead = "*DEAD* ";

			CPrintToChatAllEx2(client, "%s{teamcolor}%N{default} :  %s", dead, client, buffer);
		}

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

static void FirePauseCommand(int client) {
	if (!IsClientInGame(client)) {
		for (int other = 1; other <= MaxClients; other++) {
			if (IsClientInGame(other)) {
				client = other;
				break;
			}
		}

		if (!IsClientInGame(client)) {
			LogError("Could not find a client for pausing the game");
			return;
		}
	}

	FakeClientCommandEx(client, "pause");
}

static void StoreUbercharges() {
	for (int client = 1; client <= MaxClients; client++) {
		g_fChargeLevel[client] = -1.0;
		if (IsClientInGame(client)) {
			if (TF2_GetPlayerClass(client) == TFClass_Medic) {
				int ubergun = GetPlayerWeaponSlot(client, 1);
				if (ubergun != -1)
				{
					g_fChargeLevel[client] = GetEntPropFloat(ubergun, Prop_Send, "m_flChargeLevel");
				}
			}
		}
	}
}

static void StorePlayerPositions() {
	for (int client = 1; client <= MaxClients; client++) {
		ResetClientPosition(client);
		if (IsClientInGame(client)) {
			if (IsPlayerAlive(client)) {
				GetClientAbsOrigin(client, g_fPlayerPos[client]);
				GetClientAbsAngles(client, g_fPlayerAng[client]);
				GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", g_fPlayerVel[client]);
			}
		}
	}
}

static void StorePlayerHealth() {
	for (int client = 1; client <= MaxClients; client++) {
		g_iPlayerHealth[client] = 0;
		if (IsClientInGame(client)) {
			if (IsPlayerAlive(client)) {
				g_iPlayerHealth[client] = GetClientHealth(client);
			}
		}
	}
}

static void StorePlayerCloak(bool noInfinite = false) {
	for (int client = 1; client <= MaxClients; client++) {
		g_fCloakLevel[client] = 0.0;
		if (IsClientInGame(client)) {
			if (TF2_GetPlayerClass(client) == TFClass_Spy) {
				int weapon = GetPlayerWeaponSlot(client, 4); // Invisiwatch
				if (weapon != -1) {
					g_fCloakLevel[client] = GetEntPropFloat(client, Prop_Send, "m_flCloakMeter");

					// We need to make the cloak permanent.
					if (!noInfinite) { // Unless this isn't a pause.
						SetEntPropFloat(client, Prop_Send, "m_flCloakMeter", 99999999999.0); // Set to some ungodly large number
					}
				}
			}
		}
	}
}

static void RestoreUbercharges() {
	for (int client = 1; client <= MaxClients; client++) {
		if (IsClientInGame(client)) {
			if (TF2_GetPlayerClass(client) == TFClass_Medic) {
				int ubergun = GetPlayerWeaponSlot(client, 1);
				if (ubergun != -1 && g_fChargeLevel[client] >= 0)
				{
					SetEntPropFloat(ubergun, Prop_Send, "m_flChargeLevel", g_fChargeLevel[client]);
				}
			}
		}

		g_fChargeLevel[client] = -1.0;
	}
}

static void RestorePlayerPositions() {
	for (int client = 1; client <= MaxClients; client++) {
		if (IsClientInGame(client)) {
			if (IsPlayerAlive(client)) {
				TeleportEntity(client, g_fPlayerPos[client], g_fPlayerAng[client], g_fPlayerVel[client]);
			}
		}
		ResetClientPosition(client);
	}
}

static void RestorePlayerHealth() {
	for (int client = 1; client <= MaxClients; client++) {
		if (IsClientInGame(client)) {
			if (IsPlayerAlive(client)) {
				SetEntityHealth(client, g_iPlayerHealth[client]);
			}
		}
		g_iPlayerHealth[client] = 0;
	}
}

static void RestorePlayerCloak() {
	for (int client = 1; client <= MaxClients; client++) {
		if (IsClientInGame(client)) {
			if (TF2_GetPlayerClass(client) == TFClass_Spy) {
				int weapon = GetPlayerWeaponSlot(client, 4);
				if (weapon != -1) {
					// g_fCloakLevel[client] = GetEntPropFloat(client, Prop_Send, "m_flCloakMeter");
					// g_bCloaked[client] = TF2_IsPlayerInCondition(client, TFCond_Cloaked);
					SetEntPropFloat(client, Prop_Send, "m_flCloakMeter", g_fCloakLevel[client]);
				}
			}
		}
		g_fCloakLevel[client] = 0.0;
	}
}
