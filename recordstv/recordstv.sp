/*
Release notes:

---- 1.0.0 (26/07/2014) ----
- When a match starts, it starts recording an STV demo
- When the match ends, it stops the recording


---- 1.1.0 (02/08/2014) ----
- Added cvar 'recordstv_path'. Use it to specify the folder you want the demos to be stored in.
- Added cvar 'recordstv_filename'. Use it to specify what the names of the demos should be.


---- 1.1.1 (14/07/2015) ----
- Support for new ready-up behaviour


---- 1.1.2 (13/07/2025) ----
- Updated code to be compatible with SourceMod 1.12


TODO:
- Automatic zipping of match*.dem files


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
#define UPDATE_URL		"https://sourcemod.krus.dk/recordstv/update.txt"


char g_sAutoRecordFormat[] = "auto-%Y%m%d-%H%M-%map";
ConVar g_cvarAutoRecord = null;

ConVar g_hCvarRedTeamName = null;
ConVar g_hCvarBlueTeamName = null;

ConVar g_cvarRecordPath = null;
ConVar g_cvarFilename = null;


public Plugin myinfo = {
	name = "Record SourceTV",
	author = "F2",
	description = "Records SourceTV during matches",
	version = PLUGIN_VERSION,
	url = "https://sourcemod.krus.dk/"
};



public void OnPluginStart() {
	// Set up auto updater
	if (LibraryExists("updater"))
		Updater_AddPlugin(UPDATE_URL);
	
	g_cvarAutoRecord = FindConVar("tv_autorecord");
	g_hCvarRedTeamName = FindConVar("mp_tournament_redteamname");
	g_hCvarBlueTeamName = FindConVar("mp_tournament_blueteamname");
	
	g_cvarRecordPath = CreateConVar("recordstv_path", "", "The path to put the recorded STV demos.\n You can use the same placeholders in the path as in recordstv_filename.", FCVAR_NONE);
	
	g_cvarFilename = CreateConVar("recordstv_filename", "match-#Y#m#d-#H#M-#map", "The name of the demo files.\n You can use these placeholders:\n - #Y = Year\n - #m = Month\n - #d = Day\n - #H = Hour\n - #M = Minute\n - #map = Map name\n - #red = Red Team Name\n - #blue = Blue Team Name", FCVAR_NONE);
	HookConVarChange(g_cvarFilename, CvarChange_FileName);
	
	// Match.inc
	Match_OnPluginStart();
}

public void OnLibraryAdded(const char[] name) {
	// Set up auto updater
	if (StrEqual(name, "updater"))
		Updater_AddPlugin(UPDATE_URL);
}

public void OnMapStart() {
	Match_OnMapStart();
}

public void OnMapEnd() {
	Match_OnMapEnd();
}


public void CvarChange_FileName(ConVar cvar, const char[] oldVal, const char[] newVal) {
	if (StrContains(newVal, "/") != -1 || StrContains(newVal, "\\") != -1) {
		ReplyToCommand(0, "recordstv_filename must not contain forward slash or backslash.");
		SetConVarString(g_cvarFilename, oldVal);
	}
}

// -----------------------------------
// Match - start / end
// -----------------------------------

void StartMatch() {
	StartRecording();
}

void ResetMatch() {
	StopRecording();
}

void EndMatch(bool endedMidgame) {
	StopRecording();
}

// -----------------------------------


void StartRecording() {
	ServerCommand("tv_stoprecord");
	
	char path[128];
	g_cvarRecordPath.GetString(path, sizeof(path));
	
	char filename[128];
	g_cvarFilename.GetString(filename, sizeof(filename));
	RecordToFile(path, filename);
}

void StopRecording() {
	ServerCommand("tv_stoprecord");
	if (g_cvarAutoRecord.BoolValue)
		RecordToFile("", g_sAutoRecordFormat);
}

void RecordToFile(const char[] path, const char[] format) {
	char filename[256];
	strcopy(filename, sizeof(filename), format);
	
	// Prepend the path to the filename
	char path2[128];
	strcopy(path2, sizeof(path2), path);
	ReplaceString(path2, sizeof(path2), "\\", "/");
	TrimString(path2);
	if (strlen(path2) != 0) {
		while (path2[0] != '\0' && (path2[strlen(path2) - 1] == '\\' || path2[strlen(path2) - 1] == '/'))
			path2[strlen(path2) - 1] = '\0';
		TrimString(path2);
		if (path2[0] != '\0')
			Format(filename, sizeof(filename), "%s/%s", path2, filename);
	}
	
	ReplaceString(filename, sizeof(filename), "#", "%");
	
	// Replace %map with current map
	char map[128];
	GetCurrentMap(map, sizeof(map));
	ReplaceString(filename, sizeof(filename), "%map", map, false);
	
	// Replace %red and %blue with current team names
	char teamname[128];
	g_hCvarRedTeamName.GetString(teamname, sizeof(teamname));
	CleanFilename(teamname);
	ReplaceString(filename, sizeof(filename), "%red", teamname, false);
	g_hCvarBlueTeamName.GetString(teamname, sizeof(teamname));
	CleanFilename(teamname);
	ReplaceString(filename, sizeof(filename), "%blue", teamname, false);
	ReplaceString(filename, sizeof(filename), "%blu", teamname, false);
	
	// Replace time placeholders
	char filename2[256];
	FormatTime(filename2, sizeof(filename2), filename);
	
	// Remove illegal path characters
	CleanFilename(filename2, true);
	
	// Create the demo directory
	if (filename2[0] != '\0') {
		int slashPos = StrContains(filename2, "/");
		while (slashPos != -1) {
			filename2[slashPos] = '\0';
			CreateDirectory(filename2, FPERM_O_READ | FPERM_O_EXEC | FPERM_G_READ | FPERM_G_EXEC | FPERM_U_READ | FPERM_U_WRITE | FPERM_U_EXEC);
			filename2[slashPos] = '/';
			
			int newSlashPos = StrContains(filename2[slashPos + 1], "/");
			if (newSlashPos == -1)
				slashPos = -1;
			else
				slashPos = newSlashPos + slashPos + 1;
		}
	}
	
	// Start recording
	ServerCommand("tv_record %s", filename2);
}

void CleanFilename(char[] filename, bool allowSlash = false) {
	int srcpos = 0, destpos = 0;
	while (filename[srcpos] != '\0') {
		int c = filename[srcpos];
		if (IsCharAlpha(c) || IsCharNumeric(c) || c == '-' || c == '_' || c == '.' || (allowSlash && c == '/')) {
			filename[destpos] = c;
			destpos++;
		}
		srcpos++;
	}
	filename[destpos] = filename[srcpos]; // Copy over the null byte.
}

