/*
Release notes:

---- 1.0.0 (08/08/2025) ----
- Type !more to view more.tf stats after a completed match

*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <f2stocks>
#include <morecolors>
#include <anyhttp>
#include <regex>
#include <adt_trie>
#include <match>
#include "../logstf/logstf.inc"
#undef REQUIRE_PLUGIN
#include <updater>

#define PLUGIN_VERSION	"1.0.0"
#define UPDATE_URL		"https://sourcemod.krus.dk/moretf/update.txt"

public Plugin myinfo = {
	name = "More.TF Uploader",
	author = "F2",
	description = "More.TF log uploader",
	version = PLUGIN_VERSION,
	url = "https://github.com/F2/F2s-sourcemod-plugins"
};


char g_sPluginVersion[32];
ConVar g_hCvarApikey;
char g_sLastLogURL[128] = "";
float g_fChatTime[MAXPLAYERS + 1];


public void OnPluginStart() {
	// Set up auto updater
	if (LibraryExists("updater"))
		Updater_AddPlugin(UPDATE_URL);

	// Check for HTTP extension
	AnyHttp.Require();

	// Match.inc
	Match_OnPluginStart();

	// Create cvars
	g_hCvarApikey = CreateConVar("moretf_apikey", "", "Your more.tf API key", FCVAR_PROTECTED);

	// Remember the plugin version
	FormatEx(g_sPluginVersion, sizeof(g_sPluginVersion), "MoreTF %s", PLUGIN_VERSION);

	// Hook events
	HookEvent("player_say", Event_player_say, EventHookMode_Post);
}

public void OnLibraryAdded(const char[] name) {
	// Set up auto updater
	if (StrEqual(name, "updater"))
		Updater_AddPlugin(UPDATE_URL);
}

public void OnMapStart() {
	// Match.inc
	Match_OnMapStart();
}

public void OnMapEnd() {
	// Match.inc
	Match_OnMapEnd();
}

void StartMatch() {
	g_sLastLogURL = ""; // Avoid people typing !more towards the end of the match, only to show the old stats
}

void ResetMatch() {
}

void EndMatch(bool endedMidgame) {
}

public Action Event_player_say(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (IsRealPlayer(client)) {
		char text[64];
		event.GetString("text", text, sizeof(text));
		if (StrEqual(text, "!more", false) || StrEqual(text, "!moretf", false)) {
			if (strlen(g_sLastLogURL) != 0) {
				g_fChatTime[client] = GetTickedTime();
				QueryClientConVar(client, "cl_disablehtmlmotd", QueryConVar_DisableHtmlMotd);
			}
		}
	}

	return Plugin_Continue;
}

public void QueryConVar_DisableHtmlMotd(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue) {
	if (!IsClientValid(client))
		return;

	if (result == ConVarQuery_Okay) {
		if (StringToInt(cvarValue) != 0) {
			char nickname[32];
			GetClientName(client, nickname, sizeof(nickname));

			MC_PrintToChat(client, "%s%s%s", "{lightgreen}[MoreTF] {default}", nickname, ": To see logs in-game, you need to set: {aqua}cl_disablehtmlmotd 0");
			return;
		}
	}

	float waitTime = 0.3;
	waitTime -= GetTickedTime() - g_fChatTime[client];
	if (waitTime <= 0.0) {
		waitTime = 0.1;
	}

	// Using a timer avoids an error where the stats close immediately due to the user pressing ENTER when typing .ss
	CreateTimer(waitTime, Timer_ShowStats, client, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ShowStats(Handle timer, any client) {
	if (!IsClientValid(client))
		return Plugin_Stop;

	char steamID[32];
	GetClientAuthId(client, AuthId_SteamID64, steamID, sizeof(steamID));

	char lastLogURL[128];
	FormatEx(lastLogURL, sizeof(lastLogURL), "%s#%s", g_sLastLogURL, steamID);

	char num[3];
	Handle Kv = CreateKeyValues("data");
	IntToString(MOTDPANEL_TYPE_URL, num, sizeof(num));
	KvSetString(Kv, "title", "Logs");
	KvSetString(Kv, "type", num);
	KvSetString(Kv, "msg", lastLogURL);
	KvSetNum(Kv, "customsvr", 1);
	ShowVGUIPanel(client, "info", Kv);
	delete Kv;

	return Plugin_Stop;
}

// The logstf plugin calls LogUploaded().
public void LogUploaded(bool logstfSuccess, const char[] logstfLogid, const char[] logstfUrl) {
	if (!logstfSuccess)
		return;
	
	// TODO: Upload to more.tf + retry logic

	StringMap map = ParseSimpleJson("{\"success\": true, \"url\": \"https://more.tf\"}");
	if (map != null) {
		char moretfSuccess[16], moretfUrl[128];
		if (map.GetString("success", moretfSuccess, sizeof(moretfSuccess)) && map.GetString("url", moretfUrl, sizeof(moretfUrl))) {
			g_sLastLogURL = moretfUrl;
			MC_PrintToChatAll("%s%s", "{lightgreen}[MoreTF] {blue}To see the more.tf stats, type: {yellow}", "!more");
		}

		delete map;
	}
}

StringMap ParseSimpleJson(const char[] contents) {
	Regex regex = new Regex("\"([^\"]+)\"\\s*:\\s*(?:\"([^\"]*?)\"|(.+?))\\s*[,}]", PCRE_CASELESS);
	if (regex == null) {
		LogError("Could not create regex for parsing response");
		return null;
	}
	
	int totalMatches = regex.MatchAll(contents);
	if (totalMatches <= 0) {
		LogError("Could not parse response (totalMatches=%i)", totalMatches);
		delete regex;
		return null;
	}

	StringMap map = new StringMap();
	
	for (int matchId = 0; matchId < totalMatches; matchId++) {
		char key[64], value[128];

		if (!regex.GetSubString(1, key, sizeof(key), matchId))
			continue;

		// In the case of "a":"b", the capture count will be 3.
		// In the case of "a":true, the capture count will be 4.
		// Capture 0 = the whole match
		// Capture 1 = the key
		// Capture 2 = the value (if a string, otherwise empty)
		// Capture 3 = the value (if not a string, otherwise the capture does not exist)
		if (!regex.GetSubString(regex.CaptureCount(matchId) - 1, value, sizeof(value), matchId))
			continue;
		
		map.SetString(key, value);
	}

	delete regex;

	return map;
}