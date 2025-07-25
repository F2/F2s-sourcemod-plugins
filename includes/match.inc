/*
Remember to call:
- Match_OnPluginStart();
- Match_OnMapStart();
- Match_OnMapEnd();


Then use these functions:

void StartMatch() {
}

void ResetMatch() {
}

void EndMatch(bool endedMidgame) {
}

Optional:

public void StartFirstRound() {
}

*/

/*
TODO:
- Make a new callback, AboutToEnd (5 secs before MatchEnded)
- g_fMatchEndTime
- g_bCountdownStarted
- g_fLastRoundStart
*/



#if defined _match_included
 #endinput
#endif
#define _match_included

#include <smlib/math>
#include <f2stocks>


ConVar match_hCvarTimelimit, match_hCvarWinlimit, match_hCvarWindiff, match_hCvarMaxRounds, match_hCvarTournament;
bool g_bInMatch = false;
float g_fMatchStartTime = 0.0, g_fLastRoundEnd = 0.0;
bool g_bIsBonusRoundTime = false;
bool g_bFirstRoundStarted = false;
int g_iRoundsPlayed = 0;

stock void Match_dummy() {
	// To avoid warnings regarding these variables not being used
	LogMessage("%i%f", g_bIsBonusRoundTime, g_fLastRoundEnd);
}


void Match_OnPluginStart() {
	// The countdown starts
	// Purpose: Call StartMatch
	HookEvent("teamplay_round_restart_seconds", Match_Event_round_restart_seconds, EventHookMode_PostNoCopy);
	
	// Match ended (maxrounds, timelimit, windifference)
	// Purpose: Call EndMatch when the match ended
	HookEvent("tf_game_over", Match_Event_game_over);//, EventHookMode_PostNoCopy);
	HookEvent("teamplay_game_over", Match_Event_game_over);//, EventHookMode_PostNoCopy);
	
	// Round started/ended
	// Purpose: To determine if it is garbage time
	HookEvent("teamplay_restart_round", Match_Event_restart_round);
	HookEvent("teamplay_round_start", Match_Event_round_start);
	HookEvent("teamplay_round_win", Match_Event_round_end);
	//HookEvent("teamplay_round_stalemate", Match_Event_round_end); // I cannot seem to trigger teamplay_round_stalemate, and since it doesn't have full_round, I leave it out for now. (Notice: Stalemates on 5cp maps are triggering a teamplay_round_win event.)
	
	// The tournament state changed
	// Purpose: Call StartMatch when the match is starting, and ResetMatch if the teams unready again
	HookEvent("tournament_stateupdate", Match_Event_tournament_stateupdate);
	
	// A player changed team
	// Purpose: If a player leaves a team, that team will automatically unready.
	//          Also, if no players are left in the teams, reset the match.
	HookEvent("player_team", Match_Event_player_team, EventHookMode_Post);
	
	// A player disconnected
	// Purpose: When all players have disconnected, call ResetMatch
	HookEvent("player_disconnect", Match_Event_player_disconnect, EventHookMode_PostNoCopy);
	
	// Hook mp_tournament_restart
	// Purpose: Call ResetMatch when the tournament mode was reset
	RegServerCmd("mp_tournament_restart", Match_Cmd_tournament_restart);
	
	
	match_hCvarTimelimit = FindConVar("mp_timelimit");
	match_hCvarWinlimit = FindConVar("mp_winlimit");
	match_hCvarWindiff = FindConVar("mp_windifference");
	match_hCvarMaxRounds = FindConVar("mp_maxrounds");
	match_hCvarTournament = FindConVar("mp_tournament");
	HookConVarChange(match_hCvarTournament, Match_TournamentModeChanged);
}

void Match_OnMapStart() {
	Match_ResetMatch();
	
	g_fLastRoundEnd = 0.0;
	g_iRoundsPlayed = 0;
	g_bFirstRoundStarted = false;
}

void Match_OnMapEnd() {
	Match_ResetMatch();
}

public void Match_Event_tournament_stateupdate(Event event, const char[] name, bool dontBroadcast) {
	//new userid = event.GetInt("userid");
	//new team = GetClientTeam(userid);
	bool nameChange = event.GetBool("namechange");
	bool readyState = event.GetBool("readystate");

	if (nameChange)
		return;
	
	// To support mp_switchteams during warmup, we should only restart the match when a team unreadies.
	// The old behaviour would restart the match if both teams were unready, mp_switchteams is called, and one team ready up (because one team is still unready).
	
	if (readyState == false) {
		Match_ResetMatch();
	}
}

public void Match_Event_round_restart_seconds(Event event, const char[] name, bool dontBroadcast) {
	Match_StartMatch();
}

public void Match_Event_game_over(Event event, const char[] name, bool dontBroadcast) {
	char map[64];
	GetCurrentMap(map, sizeof(map));
	if (strncmp(map, "ctf_", 4, false) == 0) {
		if ((GetEngineTime() - g_fLastRoundEnd) > 7.5)
			return;
	}
	
	// Sometimes other events like "Round_Win" is triggered in the same frame.
	// If we log Game_Over without logging Round_Win (etc.), logs.tf won't accept it: "Log has no valid rounds"
	// Therefore we wait until the next frame.
	RequestFrame(Match_Event_game_over_post);
}

public void Match_Event_game_over_post(any data) {
	Match_EndMatch();
}

public void Match_Event_restart_round(Event event, const char[] name, bool dontBroadcast) { // This is called before Match_Event_round_start.
	if (!g_bInMatch)
		Match_StartMatch();
}

public void Match_Event_round_start(Event event, const char[] name, bool dontBroadcast) {
	if (g_bInMatch) {
		g_bIsBonusRoundTime = false;
		
		if (!g_bFirstRoundStarted) {
			g_bFirstRoundStarted = true;

			Function func = GetFunctionByName(null, "StartFirstRound");
			if (func != null) {
				Call_StartFunction(null, func);
				Call_Finish();
			}
		}
	}
}

public void Match_Event_round_end(Event event, const char[] name, bool dontBroadcast) {
	if (g_bInMatch) {
		bool fullRound = event.GetBool("full_round");
		
		g_bIsBonusRoundTime = true;
		g_fLastRoundEnd = GetEngineTime();
		if (fullRound)
			g_iRoundsPlayed++;
	}
}


public void Match_Event_player_team(Event event, const char[] name, bool dontBroadcast) {
	//int userid = event.GetInt("userid");
	//int client = GetClientOfUserId(userid);
	//TFTeam oldteam = view_as<TFTeam>(event.GetInt("oldteam"));
	//TFTeam newteam = view_as<TFTeam>(event.GetInt("team"));
	
	// Note: At this point in time, the player is still on the oldteam.
	//       We wait until next frame before checking the amount of players on the teams.
	
	RequestFrame(Match_Event_player_team_post);
}

public void Match_Event_player_team_post(any data) {
	int playersInTeams = GetTeamClientCount(view_as<int>(TFTeam_Blue)) + GetTeamClientCount(view_as<int>(TFTeam_Red));
	if (g_bInMatch && playersInTeams == 0) {
		// The server is really weird in this case.
		// For example, if you go to spectator during countdown and then join a team, it will resume the countdown.
		// To avoid handling of all this, let's just restart the tournament once the teams are empty.
		// However, do not restart tournament unless both teams were ready (g_bInMatch==true), because otherwise it is impossible to ready both teams as a single person.
		
		// Note that the server seems to start the match anyway. However, this case will be caught by Match_Event_round_start.
		ServerCommand("mp_tournament_restart");
	}
}


public void Match_Event_player_disconnect(Event event, const char[] name, bool dontBroadcast) {
	int count = GetRealPlayerCount();
	if (count <= 1) {
		// The server is really weird in this case.
		// If one team readies up, the server empties, and then you connect and join the other team and ready up, nothing happens.
		// But if you unready the same team and ready again, it works.
		// To avoid handling of all this, let's just restart the tournament once the server is empty.
		ServerCommand("mp_tournament_restart");
		/*
		if (g_bInMatch) {
			if (g_bFirstRoundStarted) {
				Match_ResetMatch();
			}
		}
		*/
	}
}

public Action Match_Cmd_tournament_restart(int args) {
	Match_ResetMatch();
	return Plugin_Continue;
}

public void Match_TournamentModeChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	int oldval = StringToInt(oldValue);
	int newval = StringToInt(newValue);
	
	if (oldval != newval) {
		if (newval == 0) {
			Match_ResetMatch();
		}
	}
}


stock bool IsTournamentEnabled() {
	return match_hCvarTournament.BoolValue;
}

stock bool IsWinConditionMet(bool ish = true) {
	int timeleft = GetTimeLeft();
	if (timeleft != -1 && timeleft <= (ish ? 10 : 0))
		return true;
	
	int winlimit = match_hCvarWinlimit.IntValue;
	int blueScore = GetTeamScore(view_as<int>(TFTeam_Blue));
	int redScore = GetTeamScore(view_as<int>(TFTeam_Red));
	if (winlimit > 0 && ((winlimit - blueScore) <= 0 || (winlimit - redScore) <= 0)) // Win limit hit
		return true;
	
	int windiff = match_hCvarWindiff.IntValue;
	if (windiff > 0 && (windiff - Math_Abs(redScore - blueScore)) <= 0) // Win difference limit hit
		return true;
	
	int maxrounds = match_hCvarMaxRounds.IntValue;
	if (maxrounds > 0 && (maxrounds - g_iRoundsPlayed) <= 0) // Max rounds hit
		return true;
	
	return false;
}




void Match_StartMatch() {
	if (g_bInMatch)
		return;
	if (!IsTournamentEnabled())
		return;
	g_bInMatch = true;
	g_bIsBonusRoundTime = false;
	g_fMatchStartTime = GetEngineTime();
	g_fLastRoundEnd = 0.0;
	g_iRoundsPlayed = 0;
	g_bFirstRoundStarted = false;
	
	StartMatch();
}

void Match_ResetMatch() {
	if (!g_bInMatch)
		return;
	
	g_bIsBonusRoundTime = false;
	
	bool wasReset = true;
	int timeleft = GetTimeLeft();
	int winlimit = match_hCvarWinlimit.IntValue;
	int windiff = match_hCvarWindiff.IntValue;
	int maxrounds = match_hCvarMaxRounds.IntValue;
	int blueScore = GetTeamScore(view_as<int>(TFTeam_Blue));
	int redScore = GetTeamScore(view_as<int>(TFTeam_Red));
	
	if (GetEngineTime() - g_fMatchStartTime <= 30)
		wasReset = true;
	else if (timeleft != -1 && timeleft < 9 * 60) // Less than 9 minutes left
		wasReset = false;
	else if (winlimit > 1 && ((winlimit - blueScore) <= 1 || (winlimit - redScore) <= 1))
		wasReset = false;
	else if (windiff > 1 && windiff - Math_Abs(redScore - blueScore) <= 1)
		wasReset = false;
	else if (maxrounds > 1 && (maxrounds - g_iRoundsPlayed) <= 1)
		wasReset = false;
	
	if (!wasReset) {
		EndMatch(true);
		g_bInMatch = false;
		return;
	}
	
	ResetMatch();
	g_bInMatch = false;
}

void Match_EndMatch() {
	if (!g_bInMatch)
		return;
	
	g_bIsBonusRoundTime = false;
	EndMatch(false);
	g_bInMatch = false;
}

/*
GetMapTimeLeft(timeleft) can return 1, and set timeleft to a negative number.
So when timeleft == -1 you can't know whether timelimit is disabled, or timelimit is enabled and the time is up.
GetTimeLeft() will return -1 if timelimit is disabled (or we are not in a match), and otherwise it will return a non-negative number describing the time left in seconds.
*/
stock int GetTimeLeft() {
	if (!g_bInMatch || !g_bFirstRoundStarted)
		return -1;
	
	int timelimit = match_hCvarTimelimit.IntValue;
	if (timelimit <= 0)
		return -1;
	
	int timeleft;
	if (!GetMapTimeLeft(timeleft))
		return -1;
	
	if (timeleft < 0)
		return 0;
	return timeleft;
}
