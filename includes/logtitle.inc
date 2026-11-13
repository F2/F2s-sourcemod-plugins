// Shared log title generation used by logstf and supstats2.

#if defined _logtitle_included
	#endinput
#endif
#define _logtitle_included

#include <smlib>

// Trims the last words in the hostname if it is a long hostname
stock void ShortenHostnameForLogTitle(char[] hostname, int maxlen) {
	int spacepos = -1;
	int hostnameLen = strlen(hostname);
	for (int i = 25; i < hostnameLen; i++) {
		if (hostname[i] == ' ') {
			spacepos = i;
			break;
		}
	}

	if (spacepos != -1) {
		hostname[spacepos] = '\0';
		String_Trim(hostname, hostname, maxlen, " -:.!,;");
	}
}

// Replaces the {server}, {blu}, {blue} and {red} placeholders in a log title
stock void ReplaceLogTitlePlaceholders(char[] title, int maxlen, const char[] hostname, const char[] bluTeamName, const char[] redTeamName) {
	ReplaceString(title, maxlen, "{server}", hostname, false);
	ReplaceString(title, maxlen, "{blu}", bluTeamName, false);
	ReplaceString(title, maxlen, "{blue}", bluTeamName, false);
	ReplaceString(title, maxlen, "{red}", redTeamName, false);
}
