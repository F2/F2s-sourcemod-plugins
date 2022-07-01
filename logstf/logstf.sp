/*
Release notes:

---- 1.0.0 (01/11/2013) ----
- Automatically uploads logs
- Can upload a separate log with real damage
- cvar 'logstf_apikey'
- cvar 'logstf_title'
- cvar 'logstf_autoupload'


---- 1.0.1 (02/11/2013) ----
- Fixed the log URL being blank (thanks to george for reporting it)


---- 1.0.2 (07/11/2013) ----
- Fixed .ss not working


---- 1.1.0 (14/12/2013) ----
- Made it possible for other plugins to get notified when a log has been uploaded
- Fixed a problem with "class play-time" being too low on logs.tf


---- 2.0.0 (23/12/2013) ----
- Can upload logs after each round (the log will be updated on logs.tf after each round) - to enable, set: logstf_midgameupload 1
- You can use .ss after each round if logstf_midgameupload is enabled
- No longer uploads a separate Real Damage file
- If Sizzling Stats is installed, LogsTF will not react on .ss


---- 2.0.1 (23/12/2013) ----
- Fixed upload bug


---- 2.1.0 (28/12/2013) ----
- Uploads logs after each round by default (set logstf_midgameupload 0 to disable it)
- Players are noticed after the first round that they can see midgame stats (set logstf_midgamenotice 0 to disable it)
- Fixed "uploading too fast" when the match ended due to winlimit/windiff
- logstf_autoupload now defaults to 2 (upload logs from all matches)
- Minor bug fixes


---- 2.1.1 (01/01/2014) ----
- Increased memory buffer (to accomodate for Accuracy Stats in supstats2)


---- 2.1.2 (03/01/2014) ----
- Fixed "Updating too fast" on payload maps


---- 2.2.0 (28/01/2014) ----
- Added warning about cl_disablehtmlmotd
- Fixed log upload not working on ctf_ballin_sky and ctf_bball_comptf
- Fixed SteamIDs sometimes being wrong in the logs


---- 2.2.1 (15/05/2014) ----
- Fixed log upload sometimes failing on ctf maps


---- 2.2.2 (26/05/2014) ----
- Fixed log upload sometimes failing on ctf maps (again)


---- 2.2.3 (25/08/2014) ----
- Fixed problem with snapshot version of SourceMod (regarding new SteamID format)


---- 2.3.0 (14/07/2015) ----
- Added support for SteamTools as an alternative for cURL
- Better error handling
- Support for new ready-up behaviour


---- 2.3.2 (30/06/2022) ----
- Added support for SteamWorks extension
- Fixed log upload not working on bball_tf_v2





TODO:
- Check if midgameupload works for mini-rounds
- Make a logstf.txt, logstf-upload1.txt, logstf-upload2.txt, such that a new match can start while it is still uploading the old log
*/

#pragma semicolon 1

#include <sourcemod>
#include <tf2_stocks>
#include <smlib>
#include <morecolors>
#include <anyhttp>
#include <regex>
#include <f2stocks>
#include <match>
#undef REQUIRE_PLUGIN
#include <updater>


#define PLUGIN_VERSION "2.3.2"
#define UPDATE_URL		"http://sourcemod.krus.dk/logstf/update.txt"

#define LOG_PATH  "logstf.log"
#define PLOG_PATH "logstf-partial.log"
#define LOG_BUFFERSIZE 768 // I have seen log lines longer than 512
#define LOG_BUFFERCNT 100


public Plugin:myinfo = {
	name = "Logs.TF Uploader",
	author = "F2",
	description = "Logs.TF log uploader",
	version = PLUGIN_VERSION,
	url = "http://sourcemod.krus.dk/"
};

new String:g_sPluginVersion[32];
new String:g_sDefaultTrigger[8] = ".ss";
new String:g_sClassNamesLower[][16] = { "undefined", "scout", "sniper", "soldier", "demoman", "medic", "heavyweapons", "pyro", "spy", "engineer" };

new String:g_sLogBuffer[LOG_BUFFERCNT][LOG_BUFFERSIZE];
new g_iNextLogBuffer = 0, bool:g_bLogReady = false, bool:g_bIsUploading = false;
new g_iUploadAttempt = 0;
new g_iPlayersInMatch;
new Handle:g_hCvarHostname, Handle:g_hCvarRedTeamName, Handle:g_hCvarBlueTeamName, Handle:g_hCvarLogsDir;
new Handle:g_hCvarApikey, Handle:g_hCvarTitle, Handle:g_hCvarAutoUpload, Handle:g_hCvarMidGameUpload, Handle:g_hCvarMidGameNotice;
new String:g_sLastLogURL[128];
new String:g_sCachedHostname[22], String:g_sCachedRedTeamName[32], String:g_sCachedBluTeamName[32], String:g_sCachedMap[32];
new Handle:g_hLogUploaded; // public LogUploaded(bool:success, const String:logid[], const String:url[])
new Handle:g_hBlockLogLine; // public Action:BlockLogLine(const String:logline[])

new bool:g_bIsPartialUpload = false;
new Handle:g_hTimerUploadPartialLog = INVALID_HANDLE;
new String:g_sCurrentLogID[32] = "";
new bool:g_bReuploadASAP = false;
new bool:g_bPartialUploadNotice[MAXPLAYERS+1]; // true if the player should receive a Partial Upload notice upon death
new bool:g_bFirstPartialUploaded = false;

new bool:g_bDisableSS = false;

public OnPluginStart() {
	// Set up auto updater
	if (LibraryExists("updater"))
		Updater_AddPlugin(UPDATE_URL);
	
	// Check for HTTP extension
	AnyHttp.Require();
	
	// Match.inc
	Match_OnPluginStart();
	
	// Hook GameLog
	AddGameLogHook(GameLog);
	
	// A player says something
	// Purpose: When an admin says !ul then upload logs and suppress the message
	// Purpose: React when someone says .ss
	RegConsoleCmd("say", Command_say);
	
	// Remember handles to some cvars
	g_hCvarHostname = FindConVar("hostname");
	g_hCvarRedTeamName = FindConVar("mp_tournament_redteamname");
	g_hCvarBlueTeamName = FindConVar("mp_tournament_blueteamname");
	g_hCvarLogsDir = FindConVar("sv_logsdir");
	
	// Create LogsTF cvars
	g_hCvarApikey = CreateConVar("logstf_apikey", "", "Your logs.tf API key", FCVAR_PROTECTED);
	g_hCvarTitle = CreateConVar("logstf_title", "{server}: {red} vs {blu}", "Title to use on logs.tf", FCVAR_NONE);
	g_hCvarAutoUpload = CreateConVar("logstf_autoupload", "2", "Set to 2 to upload logs from all matches. (default)\n - Set to 1 to upload logs from matches with at least 4 players.\n - Set to 0 to disable automatic upload. Admins can still upload logs by typing !ul", FCVAR_NONE);
	g_hCvarMidGameUpload = CreateConVar("logstf_midgameupload", "1", "Set to 0 to upload logs after the match has finished.\n - Set to 1 to upload the logs after each round.", FCVAR_NONE);
	g_hCvarMidGameNotice = CreateConVar("logstf_midgamenotice", "1", "Set to 1 to notice players about midgame logs.\n - Set to 0 to disable it.", FCVAR_NONE);
	
	// Events
	HookEvent("teamplay_round_win", Event_RoundEnd);
	HookEvent("teamplay_round_stalemate", Event_RoundEnd);
	HookEvent("player_death", Event_PlayerDeath);
	
	// Make it possible for other plugins to get notified when a log has been uploaded
	g_hLogUploaded = CreateGlobalForward("LogUploaded", ET_Ignore, Param_Cell, Param_String, Param_String);
	
	// Let other plugins block log lines
	g_hBlockLogLine = CreateGlobalForward("BlockLogLine", ET_Event, Param_String);
	
	// Remember the plugin version
	FormatEx(g_sPluginVersion, sizeof(g_sPluginVersion), "LogsTF %s", PLUGIN_VERSION);
	
	// Detect if Sizzling Stats is installed (if so, disable .ss)
	new Handle:sizz_stats_version = FindConVar("sizz_stats_version");
	if (sizz_stats_version != INVALID_HANDLE) {
		g_bDisableSS = true;
		g_sDefaultTrigger = "!log";
	}
	
	// Simulate a map start
	OnMapStart();
}

public OnMapStart() {
	Match_OnMapStart();
}

public void OnMapEnd() {
	Match_OnMapEnd();
}

public OnLibraryAdded(const String:name[]) {
	// Set up auto updater
	if (StrEqual(name, "updater"))
		Updater_AddPlugin(UPDATE_URL);
}

public OnPluginEnd() {
	// Clean up
	RemoveGameLogHook(GameLog);
	decl String:path[64];
	GetLogPath(LOG_PATH, path, sizeof(path));
	DeleteFile(path);
	CloseHandle(g_hLogUploaded);
}



// -----------------------------------
// Match - start / end
// -----------------------------------

StartMatch() {
	FlushLog();
	g_sLastLogURL = ""; // Avoid people typing .ss towards the end of the match, only to show the old stats
	
	g_iPlayersInMatch = 0;
	for (new client = 1; client <= MaxClients; client++) {
		if (!IsRealPlayer(client))
			continue;
		new TFTeam:team = TFTeam:GetClientTeam(client);
		if (team == TFTeam_Red || team == TFTeam_Blue)
			g_iPlayersInMatch++;
		
		// Write "changed role to" log lines to the log, such that logs.tf can calculate the "class play-time" correctly.
		decl String:playerName[64];
		decl String:playerSteamID[64];
		decl String:playerTeam[64];
		GetClientName(client, playerName, sizeof(playerName));
		GetClientAuthStringNew(client, playerSteamID, sizeof(playerSteamID), false);
		GetPlayerTeamStr(GetClientTeam(client), playerTeam, sizeof(playerTeam));
		LogToGame("\"%s<%i><%s><%s>\" changed role to \"%s\"", playerName, GetClientUserId(client), playerSteamID, playerTeam, g_sClassNamesLower[TF2_GetPlayerClass(client)]);
	}
	
	// Clear the log file and make sure it exists
	decl String:path[64];
	GetLogPath(LOG_PATH, path, sizeof(path));
	new Handle:file = OpenFile(path, "w");
	CloseHandle(file);
	g_bLogReady = false;
	
	// Set up Partial Upload
	// It is too much of a performance hit to upload regularly. Only do it at the end of each round.
	//g_hTimerUploadPartialLog = CreateTimer(120.0, Timer_UploadPartialLog, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
	g_sCurrentLogID = "";
	g_bReuploadASAP = false;
	g_bFirstPartialUploaded = false;
	Array_Fill(g_bPartialUploadNotice, sizeof(g_bPartialUploadNotice), false);
	
	// Cache the current match values, in case the map is about to change
	CacheMatchValues();
}

ResetMatch() {
	if (g_hTimerUploadPartialLog != INVALID_HANDLE) {
		KillTimer(g_hTimerUploadPartialLog);
		g_hTimerUploadPartialLog = INVALID_HANDLE;
	}
	
	FlushLog();
}

EndMatch(bool:endedMidgame) {
	if (g_hTimerUploadPartialLog != INVALID_HANDLE) {
		KillTimer(g_hTimerUploadPartialLog);
		g_hTimerUploadPartialLog = INVALID_HANDLE;
	}
	
	if (endedMidgame) {
		AddLogLine("World triggered \"Round_Stalemate\"\n");
	}
	
	g_bLogReady = true;
	g_iUploadAttempt = 1;
	
	new autoupload = GetConVarInt(g_hCvarAutoUpload);
	if (autoupload == 1) {
		if (g_iPlayersInMatch >= 4 && GetEngineTime() - g_fMatchStartTime >= 90) {
			UploadLog(false);
		} else {
			AnnounceLogReady();
		}
	} else if (autoupload == 2) {
		UploadLog(false);
	} else { // 0
		AnnounceLogReady();
	}
}

CacheMatchValues() {
	GetConVarString(g_hCvarHostname, g_sCachedHostname, sizeof(g_sCachedHostname));
	GetConVarString(g_hCvarBlueTeamName, g_sCachedBluTeamName, sizeof(g_sCachedBluTeamName));
	GetConVarString(g_hCvarRedTeamName, g_sCachedRedTeamName, sizeof(g_sCachedRedTeamName));
	String_Trim(g_sCachedHostname, g_sCachedHostname, sizeof(g_sCachedHostname));
	String_Trim(g_sCachedBluTeamName, g_sCachedBluTeamName, sizeof(g_sCachedBluTeamName));
	String_Trim(g_sCachedRedTeamName, g_sCachedRedTeamName, sizeof(g_sCachedRedTeamName));
	GetCurrentMap(g_sCachedMap, sizeof(g_sCachedMap));
	
	// Remove last word in hostname
	new spacepos = -1;
	for (new i = strlen(g_sCachedHostname) - 1; i >= 17; i--) {
		if (g_sCachedHostname[i] == ' ') {
			spacepos = i;
			break;
		}
	}
	
	if (spacepos != -1) {
		g_sCachedHostname[spacepos] = '\0';
		String_Trim(g_sCachedHostname, g_sCachedHostname, sizeof(g_sCachedHostname), " -:.!,;");
	}
}

AnnounceLogReady() {
	for (new client = 1; client <= MaxClients; client++) {
		if (!IsRealPlayer2(client))
			continue;
		if (!Client_IsAdmin(client))
			continue;
		decl String:nickname[32];
		GetClientName(client, nickname, sizeof(nickname));
		CPrintToChat(client, "%s%s%s", "{lightgreen}[LogsTF] {blue}", nickname, ": To upload logs, type: {yellow}!ul");
	}
}

// -----------------------------------




// -----------------------------------
// Partial Upload (Midgame Logs)
// -----------------------------------

public Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast) {
	if (GetConVarInt(g_hCvarMidGameUpload) <= 0)
		return;
	
	// Don't upload if the map is about to end
	new timeleft = GetTimeLeft();
	if (timeleft != -1 && timeleft < 15)
		return;
	
	if (!g_bInMatch)
		return;
	
	new autoupload = GetConVarInt(g_hCvarAutoUpload);
	new bool:shouldUpload = (autoupload == 1 && g_iPlayersInMatch >= 4 && GetEngineTime() - g_fMatchStartTime >= 90) || (autoupload == 2);
	if (!shouldUpload)
		return;
	
	// Make a timer to be sure the relevant log lines have been written
	CreateTimer(0.1, Timer_UploadPartialLog, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action:Timer_UploadPartialLog(Handle:timer) {
	// Only upload a partial log if the match is still running.
	if (!g_bInMatch)
		return Plugin_Stop;
	
	// If the match is about to end, then don't do a partial upload now. It will cause an "updating too fast" error from logs.tf.
	if (IsWinConditionMet())
		return Plugin_Stop;
	
	UploadLog(true);
	return Plugin_Continue;
}


public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast) {
	if (GetConVarInt(g_hCvarMidGameUpload) <= 0)
		return;
	if (!GetConVarBool(g_hCvarMidGameNotice)) // Is midgame notices disabled?
		return;
	if (!g_bInMatch) // Partial Upload is only relevant during the match
		return;
	if (g_bIsBonusRoundTime) // Ignore deaths during bonus round time
		return;
	if (!g_bFirstPartialUploaded) // Has there not been a partial upload yet?
		return;
	
	new userid = GetEventInt(event, "userid");
	new client = GetClientOfUserId(userid);
	
	if (!g_bPartialUploadNotice[client]) // Does the user need to be notified? If not ...
		return;
	if ((GetEngineTime() - g_fLastRoundEnd) <= 15.0) // Ignore deaths in beginning of the round
		return;
	
	g_bPartialUploadNotice[client] = false;
	CPrintToChat(client, "%s%s", "{lightgreen}[LogsTF] {blue}To see the stats from the previous rounds, type: {yellow}", g_sDefaultTrigger);
}

// -----------------------------------





// -----------------------------------
// Handle user input
// -----------------------------------
new Float:g_fSSTime[MAXPLAYERS+1];
public Action:Command_say(client, args) {
	if (client == 0)
		return Plugin_Continue;
		
	decl String:text[256];
	GetCmdArgString(text, sizeof(text));
	if (text[0] == '"' && strlen(text) >= 2) {
		strcopy(text, sizeof(text), text[1]);
		text[strlen(text)-1] = '\0';
	}
	String_Trim(text, text, sizeof(text));
	
	if (StrEqual(text, "!ul", false) || StrEqual(text, ".ul", false)) {
		if (Client_IsAdmin(client)) {
			decl String:nickname[32];
			GetClientName(client, nickname, sizeof(nickname));
			if (g_bIsUploading && g_bLogReady == false) {
				CPrintToChat(client, "%s%s%s", "{lightgreen}[LogsTF] {blue}", nickname, ": Log is already being uploaded...");
			} else if (g_bLogReady == false) {
				CPrintToChat(client, "%s%s%s", "{lightgreen}[LogsTF] {red}", nickname, ": There are no logs ready to be uploaded.");
			} else if (g_bLogReady == true) {
				UploadLog(false);
			}
			return Plugin_Stop;
		}
	} else if ((!g_bDisableSS && (StrEqual(text, ".ss", false) || StrEqual(text, "!ss", false))) || StrEqual(text, ".stats", false) || StrEqual(text, "!stats", false) || StrEqual(text, ".log", false) || StrEqual(text, "!log", false) || StrEqual(text, ".logs", false) || StrEqual(text, "!logs", false)) {
		
		if (strlen(g_sLastLogURL) != 0) {
			// If the person has used .ss, don't show the Partial Upload notice
			g_bPartialUploadNotice[client] = false;
			
			// Check if the client has disable html motd.
			g_fSSTime[client] = GetTickedTime();
			QueryClientConVar(client, "cl_disablehtmlmotd", QueryConVar_DisableHtmlMotd);
		}
	}
	
	return Plugin_Continue;
}

public QueryConVar_DisableHtmlMotd(QueryCookie:cookie, client, ConVarQueryResult:result, const String:cvarName[], const String:cvarValue[]) {
	if (!IsClientValid(client))
		return;
	
	if (result == ConVarQuery_Okay) {
		if (StringToInt(cvarValue) != 0) {
			decl String:nickname[32];
			GetClientName(client, nickname, sizeof(nickname));
			
			CPrintToChat(client, "%s%s%s", "{lightgreen}[LogsTF] {default}", nickname, ": To see logs in-game, you need to set: {aqua}cl_disablehtmlmotd 0");
			return;
		}
	}
	
	new Float:waitTime = 0.3;
	waitTime -= GetTickedTime() - g_fSSTime[client];
	if (waitTime <= 0.0)
		waitTime = 0.01;
	
	// Using a timer avoids an error where the stats close immediately due to the user pressing ENTER when typing .ss
	CreateTimer(waitTime, Timer_ShowStats, client, TIMER_FLAG_NO_MAPCHANGE);
}

// Compatibility with ChatColor plugin
public Action:BlockSay(client, const String:text[], bool:teamSay) {
	if (teamSay)
		return Plugin_Continue;
	if (StrEqual(text, "!ul", false) && Client_IsAdmin(client))
		return Plugin_Handled;
	return Plugin_Continue;
}

public Action:Timer_ShowStats(Handle:timer, any:client) {
	if (!IsClientValid(client))
		return;
	
	decl String:num[3];
	new Handle:Kv = CreateKeyValues("data");
	IntToString(MOTDPANEL_TYPE_URL, num, sizeof(num));
	KvSetString(Kv, "title", "Logs");
	KvSetString(Kv, "type", num);
	KvSetString(Kv, "msg", g_sLastLogURL);
	KvSetNum(Kv, "customsvr", 1);
	ShowVGUIPanel(client, "info", Kv);
	CloseHandle(Kv);
}

// -----------------------------------



// -----------------------------------
// Save log lines to file
// -----------------------------------

public Action:GameLog(const String:message[]) {
	if (CallBlockLogLine(message) == Plugin_Continue) // I benchmarked this on my computer. In a normal 30min match there can be up to 6,000 log lines. This function can be called 8,500,000,000 times during that time.
		AddLogLine(message);
	return Plugin_Continue;
}

AddLogLine(const String:message[]) {
	if (strlen(message) >= LOG_BUFFERSIZE) {
		LogError("Log line too long (%i): %s", strlen(message), message);
		return;
	}
	if (g_iNextLogBuffer >= LOG_BUFFERCNT)
		SetFailState("%s", "Wrong log buffer");
	
	decl String:time[32];
	FormatTime(time, sizeof(time), "%m/%d/%Y - %H:%M:%S");
	FormatEx(g_sLogBuffer[g_iNextLogBuffer++], LOG_BUFFERSIZE, "L %s: %s", time, message);
	if (g_iNextLogBuffer == LOG_BUFFERCNT)
		FlushLog();
}

FlushLog() {
	if (g_iNextLogBuffer == 0)
		return;
		
	new firstLine = 0;
	new lastLine = g_iNextLogBuffer;
	
	if (g_bInMatch) {
		decl String:path[64];
		GetLogPath(LOG_PATH, path, sizeof(path));
		new Handle:file = OpenFile(path, "a"); // TODO: If it returns null, then handle it! (might wanna set nextlogbuffer to 0 anyway)
		for (new line = firstLine; line < lastLine; line++)
			WriteFileString(file, g_sLogBuffer[line], false);
		CloseHandle(file);
	}
	
	g_iNextLogBuffer = 0;
}

// -----------------------------------





// -----------------------------------
// Upload log file
// -----------------------------------

UploadLog(bool:partial) {
	if (!partial && !g_bLogReady) {
		return;
	}
	
	if (g_bIsUploading) {
		if (!partial && g_bIsPartialUpload) {
			g_bReuploadASAP = true;
		}
		
		return;
	}
	
	decl String:apiKey[64];
	GetConVarString(g_hCvarApikey, apiKey, sizeof(apiKey));
	TrimString(apiKey);
	if (strlen(apiKey) == 0) {
		if (!partial)
			CPrintToChatAll("%s", "{lightgreen}[LogsTF] {red}To upload logs, please\nset {green}logstf_apikey {red}to your logs.tf API key.\nPut it in server.cfg");
		return;
	}
	
	FlushLog();
	
	if (!partial)
		g_bLogReady = false;
	g_bIsUploading = true;
	g_bIsPartialUpload = partial;
	
	decl String:title[128];
	GetConVarString(g_hCvarTitle, title, sizeof(title));
	ReplaceString(title, sizeof(title), "{server}", g_sCachedHostname, false);
	ReplaceString(title, sizeof(title), "{blu}", g_sCachedBluTeamName, false);
	ReplaceString(title, sizeof(title), "{blue}", g_sCachedBluTeamName, false);
	ReplaceString(title, sizeof(title), "{red}", g_sCachedRedTeamName, false);
	
	decl String:path[64], String:partialpath[64];
	GetLogPath(LOG_PATH, path, sizeof(path));
	GetLogPath(PLOG_PATH, partialpath, sizeof(partialpath));
	
	if (partial) {
		DeleteFile(partialpath);
		if (!CopyFile(path, partialpath)) {
			LogError("Failed to create partial log file");
			g_bIsUploading = false;
			if (g_bReuploadASAP) {
				g_bReuploadASAP = false;
				UploadLog(false);
			}
			return;
		}
		
		// We should NOT add a Round_Stalemate just after a round has ended (logs.tf will not understand it)
		//decl String:buffer[128];
		//decl String:time[32];
		//FormatTime(time, sizeof(time), "%m/%d/%Y - %H:%M:%S");
		//FormatEx(buffer, sizeof(buffer), "\nL %s: %s\n", time, "World triggered \"Round_Stalemate\"");
		
		//new Handle:file = OpenFile(partialpath, "a");
		//WriteFileString(file, buffer, false);
		//CloseHandle(file);
	}
	
	if (!partial)
		CPrintToChatAll("%s", "{lightgreen}[LogsTF] {blue}Uploading logs...");
	
	AnyHttpForm form = AnyHttp.CreatePost("http://logs.tf/upload");
	
	form.PutFile("logfile", partial ? partialpath : path);
	form.PutString("title", title);
	form.PutString("map", g_sCachedMap);
	form.PutString("key", apiKey);
	form.PutString("uploader", g_sPluginVersion);
	
	if (g_sCurrentLogID[0] != '\0')
		form.PutString("updatelog", g_sCurrentLogID);
    
	form.Send(UploadLog_Complete);
}

public void UploadLog_Complete(bool success, const char[] contents, int responseCode, int metadata) {
	g_bIsUploading = false;
	
	if (success) {
		success = ParseLogsResponse(contents);
	} else {
		if (!g_bIsPartialUpload)
			CPrintToChatAll("%s", "{lightgreen}[LogsTF] {red}Error occurred when uploading logs :(");
		LogError("Error uploading %slogs", g_bIsPartialUpload ? "partial " : "");
	}
	
	if (!g_bIsPartialUpload && success) {
		g_sCurrentLogID = "";
	}
	
	if (g_bIsPartialUpload) {
		g_bIsPartialUpload = false;
		
		if (g_bReuploadASAP) {
			g_bReuploadASAP = false;
			UploadLog(false);
		} else {
			if (success && g_bFirstPartialUploaded == false) {
				g_bFirstPartialUploaded = true;
				for (new i = 1; i <= MaxClients; i++) {
					if (!IsRealPlayer(i))
						continue;
					
					g_bPartialUploadNotice[i] = true;
				}
			}
		}
	} else if (!success) {
		if (g_iUploadAttempt < 3) {
			new waittime = (g_iUploadAttempt - 1) * 10 + 5;
			if (!g_bIsPartialUpload)
				CPrintToChatAll("%s%i%s", "{lightgreen}[LogsTF] {red}Retrying upload in ", waittime, " seconds...");
			g_iUploadAttempt++;
			g_bIsUploading = true;
			CreateTimer(float(waittime), RetryUploadLog);
		} else {
			g_sCurrentLogID = "";
			
			// Call the global forward LogUploaded()
			CallLogUploaded(false, "", "");
		}
	}
}

public bool:ParseLogsResponse(const char[] contents) {
	// {"log_id":29897, "url":"/29897", "success":true}
	int size = strlen(contents) + 1;
	char[] resBuff = new char[size];
	strcopy(resBuff, size, contents);
	
	decl String:url[64], String:success[16] = "";
	if (FindJsonValue(resBuff, "success", success, sizeof(success)) && StrEqual(success, "true", false) && FindJsonValue(resBuff, "url", url, sizeof(url))) {
		if (!FindJsonValue(resBuff, "log_id", g_sCurrentLogID, sizeof(g_sCurrentLogID))) {
			CPrintToChatAll("%s", "{lightgreen}[LogsTF] {blue}log_id not found");
			return false;
		}
		
		FormatEx(g_sLastLogURL, sizeof(g_sLastLogURL), "%s%s", "logs.tf", url);
		if (!g_bIsPartialUpload) {
			CPrintToChatAll("%s%s", "{lightgreen}[LogsTF] {blue}Logs were uploaded to: ", g_sLastLogURL);
			CPrintToChatAll("%s%s", "{lightgreen}[LogsTF] {blue}To see the stats, type: {yellow}", g_sDefaultTrigger);
		}
		Format(g_sLastLogURL, sizeof(g_sLastLogURL), "%s%s", "http://", g_sLastLogURL);
		
		
		// Call the global forward LogUploaded()
		if (!g_bIsPartialUpload)
			CallLogUploaded(true, g_sCurrentLogID, g_sLastLogURL);
		
		return true;
	} else {
		decl String:error[128] = "Unknown error.";
		if (!FindJsonValue(resBuff, "error", error, sizeof(error))) {
			String_Trim(resBuff, resBuff, size);
			Format(error, sizeof(error), "Unknown error:\n%s", resBuff);
		}
		
		ReplaceString(error, size, "\n", "");
		ReplaceString(error, size, "\\n", " ");
		ReplaceString(error, size, "\r", "");
		ReplaceString(error, size, "\t", "");
		String_Trim(error, error, size);
		
		if (!g_bIsPartialUpload)
			CPrintToChatAll("%s%s", "{lightgreen}[LogsTF] {red}Unsuccesful upload: ", error);
		LogError("Error uploading %slogs: %s", g_bIsPartialUpload ? "partial " : "", error);
		if (StrContains(error, "Invalid log file", false) != -1 || StrContains(error, "Not enough", false) != -1)
			return true; // Retrying won't help
		
		return false;
	}
}

public Action:RetryUploadLog(Handle:timer, any:client) {
	g_bLogReady = true;
	g_bIsUploading = false;
	UploadLog(false);
}






CallLogUploaded(bool:success, const String:logid[], const String:url[]) {
	Call_StartForward(g_hLogUploaded);

	// Push parameters one at a time
	Call_PushCell(success);
	Call_PushString(logid);
	Call_PushString(url);

	// Finish the call
	Call_Finish();
}

Action:CallBlockLogLine(const String:logline[]) {
	Call_StartForward(g_hBlockLogLine);

	// Push parameters one at a time
	Call_PushString(logline);

	// Finish the call
	new Action:result;
	Call_Finish(result);
	
	return result;
}


GetLogPath(const String:file[], String:destpath[], destpathLen) {
	decl String:logsdir[64];
	GetConVarString(g_hCvarLogsDir, logsdir, sizeof(logsdir));
	if (logsdir[0] == '\0')
		strcopy(destpath, destpathLen, file);
	else
		Format(destpath, destpathLen, "%s/%s", logsdir, file);
}



// this is a very simpLe json "parser", that only works on vEry simple json strinGs (as the Ones sent by logs.tf).
bool:FindJsonValue(const String:input[], const String:key[], String:value[], maxlen) {
	/*
		matches: 3
		match 0: "url":"/29897",
		match 1: "/29897"
		match 2: /29897

		matches: 4
		match 0: "log_id":29897,
		match 1: 29897
		match 2: 
		match 3: 29897
	*/

	decl String:regex_str[128];
	Format(regex_str, sizeof(regex_str), "\"%s\"\\s*:\\s*(\"(.*?)\"|(.+?))\\s*[,}]", key);
	new Handle:regex = CompileRegex(regex_str, PCRE_CASELESS);
	if (regex == INVALID_HANDLE)
		return false;
	new matches = MatchRegex(regex, input);
	if (matches < 3) {
		CloseHandle(regex);
		return false;
	}
	if (!GetRegexSubString(regex, matches == 4 ? 3 : 2, value, maxlen)) {
		CloseHandle(regex);
		return false;
	}
	CloseHandle(regex);
	
	return true;
}

// -----------------------------------


