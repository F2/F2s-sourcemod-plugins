/*
Release notes:
---- 1.0.1 (14/12/2013) ----
- Changes the map on server start

---- 2.0.0 (07/07/2022) ----
- Now automatically changes the level if stv is enabled, not just on server start

*/

#pragma semicolon 1 // Force strict semicolon mode.

#include <sourcemod>
#include <f2stocks>

#undef REQUIRE_PLUGIN
#include <updater>

#pragma newdecls required

#define PLUGIN_VERSION "2.0.0"
#define UPDATE_URL      "http://sourcemod.krus.dk/fixstvslot/update.txt"

public Plugin myinfo = {
	name = "Fix STV Slot",
	author = "F2",
	description = "When STV is enabled, change the level so the bot joins.",
	version = PLUGIN_VERSION,
	url = "http://sourcemod.krus.dk/"
};


public void OnPluginStart()
{
	// Set up auto updater
	if (LibraryExists("updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
	// We don't need to do any special logic for handling server boot.
	// Tested this, and it works even if tv_enable is set to 1 on the command line,
	// and obviously it also works if it's set in server.cfg.
	// -sappho
	HookConVarChange(FindConVar("tv_enable"), OnSTVChanged);
}

public void OnLibraryAdded(const char[] name)
{
	// Set up auto updater
	if (StrEqual(name, "updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
}

public void OnSTVChanged(ConVar convar, char[] oldValue, char[] newValue)
{
	if
	(
		// stv doesn't exist
		FindSTV_nocache() == 0
		// stv was off
		&& StrEqual(oldValue, "0")
		// stv is now on
		&& StrEqual(newValue, "1")
	)
	{
		doMapChangeTimer();
	}
}

void doMapChangeTimer()
{
	LogMessage("[FixSTVSlot] tv_enable changed to 1! Changing level...");
	PrintToChatAll("[FixSTVSlot] tv_enable changed to 1! Changing level...");
	// we have TIMER_FLAG_NO_MAPCHANGE so that,
	// if someone quickly changes the level before the timer hits 0, it won't change the level twice
	// also this maintains compatibility with the rglqol plugin
	CreateTimer(1.0, changeMap, TIMER_FLAG_NO_MAPCHANGE);
}

public Action changeMap(Handle timer)
{
	char map[128];
	GetCurrentMap(map, sizeof(map));
	ForceChangeLevel(map, "STV joined! Forcibly changing level so the bot can join.");

	return Plugin_Continue;
}

// find stv stock that doesn't rely on caches
// what if stv is enabled and disabled?
int FindSTV_nocache()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if ( IsClientConnected(client) && IsClientInGame(client) && IsClientSourceTV(client) )
		{
			return client;
		}
	}
	return 0;
}
