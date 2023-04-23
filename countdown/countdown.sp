/*
Release notes:

---- 1.0.0 (09/11/2013) ----
- Shows a countdown in the middle of the screen, when an admin writes: !countdown 2m
- !stopcountdown

*/

#pragma semicolon 1

#include <sourcemod>
#include <morecolors>
#include <smlib>
#include <sdktools>
#include <f2stocks>
#undef REQUIRE_PLUGIN
#include <updater>

#define PLUGIN_VERSION 	"1.0.0"
#define UPDATE_URL		"http://sourcemod.krus.dk/countdown/update.txt"
#define REASON_LEN 		256


public Plugin:myinfo = {
	name = "Countdown",
	author = "F2",
	description = "Counts down with a custom text",
	version = PLUGIN_VERSION,
	url = "https://github.com/F2/F2s-sourcemod-plugins"
};


new Handle:g_hTimer = INVALID_HANDLE;
new String:g_sReason[REASON_LEN] = "";
new g_iTimeleft = -1;
new Handle:g_hCvarReason;

public OnPluginStart() {
	RegConsoleCmd("say", Command_say);
	
	g_hCvarReason = CreateConVar("countdown_reason", "Searching for new opponent in %time", "Default reason", FCVAR_NONE);
	HookConVarChange(g_hCvarReason, OnReasonChange);
	
	if (LibraryExists("updater"))
		Updater_AddPlugin(UPDATE_URL);
}

public OnLibraryAdded(const String:name[]) {
	if (StrEqual(name, "updater"))
		Updater_AddPlugin(UPDATE_URL);
}

public OnReasonChange(Handle:cvar, const String:oldVal[], const String:newVal[]) {
	if (StrContains(newVal, "%time", false) == -1 && StrContains(oldVal, "%time", false) != -1) {
		SetConVarString(cvar, oldVal);
	}
}


public Action:Command_say(client, args) {
	if (!IsRealPlayer(client))
		return Plugin_Continue;
	
	if (Client_IsAdmin(client)) {	
		decl String:text[256];
		GetCmdArgString(text, sizeof(text));
		if (text[0] == '"' && strlen(text) >= 2) {
			strcopy(text, sizeof(text), text[1]);
			text[strlen(text)-1] = '\0';
		}
		String_Trim(text, text, sizeof(text));
	
		if (StrEqual(text, "!countdown", false) || StrEqual(text, "!startcountdown", false)) {
			// When user writes !countdown, show the syntax help.
			MC_PrintToChat(client, "{red}%s", "Please specify a duration, for example: !countdown 2m");
			return Plugin_Handled;
		} else if (StrContains(text, "!countdown ", false) == 0 || StrContains(text, "!startcountdown ", false) == 0) {
			// When a user writes !countdown and some more, parse the message.
			decl String:buffers[3][REASON_LEN];
			ReplaceString(text, sizeof(text), "  ", " ");
			new pieces = ExplodeString(text, " ", buffers, 3, REASON_LEN, true);
			new time = -1;
			
			if (pieces >= 2)
				time = ParseDuration(buffers[1]);
			
			if (time == -1) {
				MC_PrintToChat(client, "{red}%s", "Please specify a proper duration, for example: !countdown 2m");
			} else {
				decl String:reason[REASON_LEN];
				GetConVarString(g_hCvarReason, reason, sizeof(reason));
				if (pieces == 3)
					strcopy(reason, sizeof(reason), buffers[2]);
				
				if (StrContains(reason, "%time", false) == -1) {
					MC_PrintToChat(client, "{red}%s%s%s", "Please specify a the reason with a %time: !countdown ", buffers[1], " Exploding in %time");
				} else {
					g_iTimeleft = time;
					strcopy(g_sReason, sizeof(g_sReason), reason);
					if (g_hTimer != INVALID_HANDLE)
						KillTimer(g_hTimer);
					g_hTimer = CreateTimer(1.0, Timer_Countdown, INVALID_HANDLE, TIMER_REPEAT);
					Timer_Countdown(g_hTimer);
					//EmitSoundToAll("UI/hint.wav", SOUND_FROM_PLAYER, SNDCHAN_STATIC);
				}
			}
			return Plugin_Handled;
		} else if (StrEqual(text, "!stopcountdown", false)) {
			KillTimer(g_hTimer);
			g_hTimer = INVALID_HANDLE;
			PrintHintTextToAll("%s", " ");
			PrintHintTextToAll("%s", "");
			return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
}

// When the countdown is active, this is executed every second.
public Action:Timer_Countdown(Handle:timer) {
	decl String:strtime[64];
	DurationFormat(g_iTimeleft, strtime, sizeof(strtime));
	decl String:reason[REASON_LEN];
	strcopy(reason, sizeof(reason), g_sReason);
	ReplaceString(reason, sizeof(reason), "%time", strtime, false);
	PrintHintTextToAll("%s", reason);
	//for (new client = 1; client <= MaxClients; client++)
	//	if (IsRealPlayer(client))
	//		StopSound(client, SNDCHAN_STATIC, "UI/hint.wav");
	
	if (g_iTimeleft <= 0) {
		g_hTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}
	g_iTimeleft--;
	return Plugin_Continue;
}



// Format duration in mins and secs.
stock DurationFormat(seconds, String:buffer[], size) {
	new mins = seconds / 60, secs = seconds % 60;
	strcopy(buffer, size, "");
	if (mins > 0)
		Format(buffer, size, "%s%i%s", buffer, mins, mins == 1 ? " min " : " mins ");
	if (secs > 0 || (secs == 0 && mins == 0))
		Format(buffer, size, "%s%i%s", buffer, secs, secs == 1 ? " sec " : " secs ");
	String_Trim(buffer, buffer, size);
}

// Parse a duration of this format: 7m15s
stock ParseDuration(const String:text[]) {
	new seconds = 0;
	new len = strlen(text);
	if (len == 0)
		return -1;
	
	for (new pos = 0; pos < len; pos++) {
		new num = EatNumbers(text, pos, len+1);
		
		if (num == -1)
			return -1; // Non-numerical character found
		
		if (pos == len)
			return -1; // Number found, but suffix is missing
		
		switch (text[pos]) {
			case 'w': 
				seconds += num  * 60 * 60 * 24 * 7;
			case 'd':
				seconds += num * 60 * 60 * 24;
			case 'h': 
				seconds += num * 60 * 60;
			case 'm':
				seconds += num * 60;
			case 's':
				seconds += num;
			default:
				return -1; // Wrong suffix
		}
	}
	
	return seconds;
}

// Eat as many numbers as possible starting from 'pos' in 'text'.
stock EatNumbers(const String:text[], &pos, len) {
	if (!IsCharNumeric(text[pos]))
		return -1;
	
	new res;
	new consumed = StringToIntEx(text[pos], res);
	if (consumed <= 0)
		return -1;
	
	pos += consumed;
	return res;
}

// Compatibility with the ChatColor plugin.
public Action:BlockSay(client, const String:text[], bool:teamSay) {
	if (teamSay)
		return Plugin_Continue;
	if (Client_IsAdmin(client) && (StrContains(text, "!countdown", false) == 0 || StrContains(text, "!startcountdown", false) == 0 || StrEqual(text, "!stopcountdown", false)))
		return Plugin_Handled;
	return Plugin_Continue;
}