/*
Release notes:
---- 1.0.1 (14/12/2013) ----
- Changes the map on server start


---- 2.0.0 (07/07/2022) ----
- Now automatically changes the level if stv is enabled, not just on server start


---- 2.0.1 (10/07/2025) ----
- Updated code to be compatible with SourceMod 1.12


*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <f2stocks>

#undef REQUIRE_PLUGIN
#include <updater>

#define PLUGIN_VERSION "2.0.1"
#define UPDATE_URL     "https://sourcemod.krus.dk/fixstvslot/update.txt"

public Plugin myinfo = {
	name = "Fix STV Slot",
	author = "F2",
	description = "When STV is enabled, change the level so the bot joins.",
	version = PLUGIN_VERSION,
	url = "https://sourcemod.krus.dk/"
};


public void OnPluginStart() {
	// Set up auto updater
	if (LibraryExists("updater")) {
		Updater_AddPlugin(UPDATE_URL);
	}

	// We don't need to do any special logic for handling server boot.
	// It works even if tv_enable is set to 1 on the command line,
	// and also works if it's set in server.cfg.
	HookConVarChange(FindConVar("tv_enable"), OnSTVChanged);
}

public void OnLibraryAdded(const char[] name) {
	// Set up auto updater
	if (StrEqual(name, "updater")) {
		Updater_AddPlugin(UPDATE_URL);
	}
}

public void OnSTVChanged(ConVar convar, char[] oldValue, char[] newValue) {
	if (
		// stv doesn't exist
		FindSTV() == -1
		// stv was off
		&& StrEqual(oldValue, "0")
		// stv is now on
		&& StrEqual(newValue, "1")
	) {
		LogMessage("[FixSTVSlot] tv_enable changed to 1! Changing level...");
		PrintToChatAll("[FixSTVSlot] tv_enable changed to 1! Changing level...");

		// We use the TIMER_FLAG_NO_MAPCHANGE so that,
		// if someone quickly changes the level before the timer hits 0, it won't change the level twice.
		// Also this maintains compatibility with the rglqol plugin.
		CreateTimer(1.0, ChangeMap, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action ChangeMap(Handle timer) {
	char map[128];
	GetCurrentMap(map, sizeof(map));
	ForceChangeLevel(map, "STV joined! Forcibly changing level so the bot can join.");

	return Plugin_Stop;
}
