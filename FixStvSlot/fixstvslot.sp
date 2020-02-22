/*
Release notes:

---- 1.0.1 (14/12/2013) ----
- Changes the map on server start

*/

#pragma semicolon 1 // Force strict semicolon mode.

#include <sourcemod>
#include <f2stocks>
#undef REQUIRE_PLUGIN
#include <updater>

#define PLUGIN_VERSION "1.0.1"
#define UPDATE_URL		"http://sourcemod.krus.dk/fixstvslot/update.txt"

public Plugin:myinfo = {
	name = "Fix STV Slot",
	author = "F2",
	description = "When a server is started, it changes the map so SourceTV joins.",
	version = PLUGIN_VERSION,
	url = "http://sourcemod.krus.dk/"
};


public OnPluginStart() {
	CreateTimer(10.0, Timer_CheckSTV, _, TIMER_FLAG_NO_MAPCHANGE);
	
	// Set up auto updater
	if (LibraryExists("updater"))
		Updater_AddPlugin(UPDATE_URL);
}

public OnLibraryAdded(const String:name[]) {
	// Set up auto updater
	if (StrEqual(name, "updater"))
		Updater_AddPlugin(UPDATE_URL);
}

public Action:Timer_CheckSTV(Handle:timer, any:client) {
	if (GetEngineTime() > 60.0)
		return;
	
	if (GetConVarBool(FindConVar("tv_enable")) && FindSTV() < 1) {
		// SourceTV is enabled, but it is not on the server. Change map to get it there!
		decl String:map[128];
		GetCurrentMap(map, sizeof(map));
		ForceChangeLevel(map, "Fix STV Slot");
	}
}