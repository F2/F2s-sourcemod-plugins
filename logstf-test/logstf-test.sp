#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>


#define PLUGIN_VERSION "1.0.0"


public Plugin myinfo = {
	name = "Test: LogsTF",
	author = "F2",
	description = "Used for testing the logstf plugin",
	version = PLUGIN_VERSION,
	url = "https://github.com/F2/F2s-sourcemod-plugins"
};



public void OnPluginStart() {
	RegConsoleCmd("test_logstf", Command_test_logstf);
}

public Action Command_test_logstf(int client, int args) {
	char logline[1024];
	File file = OpenFile("testlog.log", "rt");
	if (file == null) {
		PrintToServer("Failed to open testlog.log");
		return Plugin_Handled;
	}

	while (!IsEndOfFile(file)) {
		if (!ReadFileLine(file, logline, sizeof(logline))) {
			PrintToServer("Failed to read line from testlog.log");
			delete file;
			return Plugin_Handled;
		}

		strcopy(logline, sizeof(logline), logline[25]); // Remove the timestamp
		LogToGame("%s", logline);
	}

	PrintToServer("Logged contents of testlog.log");
	delete file;

	return Plugin_Handled;
}