#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <profiler>

#define PLUGIN_VERSION "2.0.0"

public Plugin myinfo = {
	name = "Test: LogsTF",
	author = "F2",
	description = "Used for testing the logstf plugin",
	version = PLUGIN_VERSION,
	url = "https://github.com/F2/F2s-sourcemod-plugins"
};


#define MAX_LINES 10000
#define MAX_LINE_LENGTH 1024

int ReadFileLines(const char[] filePath, char[][] lines, int maxLines, int maxLineLength) {
	File file = OpenFile(filePath, "rt");
	if (file == null) {
		return -1;
	}

	int count = 0;
	char rawLine[MAX_LINE_LENGTH];

	while (!IsEndOfFile(file)) {
		if (!ReadFileLine(file, rawLine, sizeof(rawLine))) {
			break;
		}

		if (count >= maxLines) {
			SetFailState("Too many lines in %s, increase MAX_LINES", filePath);
			return 0;
		}

		// Remove trailing newline/carriage return
		int len = strlen(rawLine);
		while (len > 0 && (rawLine[len - 1] == '\n' || rawLine[len - 1] == '\r')) {
			rawLine[len - 1] = '\0';
			len--;
		}

		// Remove the 25-character timestamp prefix
		if (len > 25) {
			strcopy(lines[count], maxLineLength, rawLine[25]);
		} else {
			// Invalid line, skip it.
			continue;
		}

		count++;
	}

	delete file;
	return count;
}

public void OnPluginStart() {
	RegConsoleCmd("test_logstf", Command_test_logstf);
	RegConsoleCmd("test_logstf_bench", Command_test_logstf_bench);
}

public Action Command_test_logstf(int client, int args) {
	char lines[MAX_LINES][MAX_LINE_LENGTH];
	int lineCount = ReadFileLines("testlog.log", lines, MAX_LINES, MAX_LINE_LENGTH);
	if (lineCount < 0) {
		PrintToServer("Failed to open testlog.log");
		return Plugin_Handled;
	}

	for (int i = 0; i < lineCount; i++) {
		LogToGame("%s", lines[i]);
	}

	PrintToServer("Logged %d lines from testlog.log", lineCount);

	return Plugin_Handled;
}

public Action Command_test_logstf_bench(int client, int args) {
	char lines[MAX_LINES][MAX_LINE_LENGTH];
	int lineCount = ReadFileLines("testlog.log", lines, MAX_LINES, MAX_LINE_LENGTH);
	if (lineCount < 0) {
		PrintToServer("Failed to open testlog.log");
		return Plugin_Handled;
	}

	Profiler prof = new Profiler();
	prof.Start();

	for (int j = 0; j < 10; j++) {
		for (int i = 0; i < lineCount; i++) {
			LogToGame("%s", lines[i]);
		}
	}

	prof.Stop();

	float elapsed = prof.Time;
    PrintToServer("[Benchmark] Execution took: %.6f seconds", elapsed);


	return Plugin_Handled;
}