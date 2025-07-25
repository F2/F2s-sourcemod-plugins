/*
Release notes:

---- 1.0.0 (01/11/2013) ----
- Logs buff heals
- Logs average time after spawning before healing
- Logs average time to build uber
- Logs average time having 100% uber before using it
- Logs how often medics die with 95-99% uber
- Logs average time ubers lasted
- Logs how often the medics die shortly after ubering
- Logs amount of uber advantages lost, and the biggest loss


---- 1.1.0 (11/11/2013) ----
- Logs medics' heals per minute alive
- Logs how much health players get from medpacks
- You can disable logging buffed heals with cvar: medicstats_logbuffs 0
- The additional medic stats in chat are now written by 'MedicStats' instead of 'Console'


---- 1.2.0 (14/12/2013) ----
- Automatically sets "medicstats_logbuffs 0" if TFTrue is running on the server
- Fixed a bug regarding "heals by medpacks" - sometimes the number was too big 


---- 1.3.0 (23/12/2013) ----
- No longer writes stats to chat (they are now shown on logs.tf)


---- 1.3.1 (28/01/2014) ----
- Fixed SteamIDs sometimes being wrong in the logs


---- 1.3.2 (25/08/2014) ----
- Fixed problem with snapshot version of SourceMod (regarding new SteamID format)


---- 1.3.3 (03/07/2015) ----
- Fixed bugs introduced by Gun Mettle update


---- 1.3.4 (08/10/2016) ----
- Do not crash if the healer/patient is reported as 0


---- 1.3.5 (01/08/2020) ----
- Fixed wrong empty_uber logs when there are healing events not related to medics (e.g. engineer's dispenser)


---- 1.4.0 (02/10/2020) ----
- Fixed SM error logs when picking up medpacks
- Implemented stephanie's colored STV Stats messages


---- 1.4.1 (23/04/2023) ----
- Internal updates - by Leigh MacDonald


---- 1.4.2 (14/07/2025) ----
- Updated code to be compatible with SourceMod 1.12



TODO:
- The log lines should include which medigun is wielded
- cvar to enable logging medics' self-heal (should be disabled by default)

Known Bugs:
- When there are more than one medic on a team, the heals are likely to be credited to the wrong medic. [No easy/well-performing fix]
- If a person is buffed by other means than the medic (for example Conniver's Kunai), then the medic will get the credit for the heals. [No easy/well-performing fix]
*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <tf2_stocks>
#include <f2stocks>
#include <smlib/arrays>
#undef REQUIRE_PLUGIN
#include <updater>


#define PLUGIN_VERSION "1.4.2"
#define UPDATE_URL "https://sourcemod.krus.dk/medicstats/update.txt"
#define TIMER_TICK 0.15



public Plugin myinfo = {
	name = "Medic Stats",
	author = "F2",
	description = "Logs various medic-related statistics, including buffed heals.",
	version = PLUGIN_VERSION,
	url = "https://github.com/F2/F2s-sourcemod-plugins"
};


enum struct MedicInfo {
    // Info about medic's current life
    int MedicClient;     // The client id of the medic
    int MedicMedigun;    // The client's medigun entity
    bool MedicHasUber;   // True if the medic has 100% uber
    bool MedicIsUbering; // True if the medic is currently ubering
    float MedicTimeToUber; // How far away from uber the medic is (the last time it was checked by the CollectInfo timer)
    float MedicLastUberPct; // The percentage of uber the medic has (the last time it was checked by the CollectInfo timer)
    float MedicStartedBuildTime; // The GameTime of when the medic had 0% - when the medic has 100%, or is ubering, it is set to -1.0
    float MedicInitialHealSpawnTime; // The GameTime of when the medic spawned (the beginning of a round doesn't count) - when the medic starts to heal, it is set to -1.0
    float MedicFullyChargedTime; // The GameTime of when the uber is fully charged - when the uber is used, it is set to -1.0
    float MedicUberStartTime; // The GameTime of when the medic started using his uber (IsUbering = true) - when the uber is over, it is set to -1.0
    float MedicLastUberTime; // The GameTime of last uber
    float MedicLastDeath;    // The GameTime of last death

    bool MedicHasHadAdvantage; // True if the medic has 100% uber and they got it significantly earlier than the opposing medic
    float MedicCurrentBiggestAdvantage; // If MedicHasHadAdvantage is true, this value indicates how big the uber advantage was (in seconds)
}


int g_iMaxHealth[MAXPLAYERS + 1];
int g_iLastHealth[MAXPLAYERS + 1];
int g_iHealedBy[MAXPLAYERS + 1];
int g_iBuffed[MAXPLAYERS + 1];
float g_fLastCollectBuffs;

MedicInfo medic[TFTeam];

bool CountdownStarted;
bool IsInMatch;
bool IsBonusRoundTime;
float LastRoundStart;
//float LastCollectInfoTime;

ConVar g_hCvarLogBuffs = null;
bool g_bLogBuffs = false;


public void OnPluginStart() {
    // Set up auto updater
    if (LibraryExists("updater"))
        Updater_AddPlugin(UPDATE_URL);

    g_hCvarLogBuffs = CreateConVar("medicstats_logbuffs", "1", "Set to 1 to log buff heals. Otherwise 0.");
    HookConVarChange(g_hCvarLogBuffs, Cvar_LogBuffs);
    ConVar tftrue_logs_includebuffs = FindConVar("tftrue_logs_includebuffs");
    if (tftrue_logs_includebuffs != null) {
        if (tftrue_logs_includebuffs.BoolValue)
            g_hCvarLogBuffs.SetString("0");
    }
    char cvarLogBuffs[16];
    g_hCvarLogBuffs.GetString(cvarLogBuffs, sizeof(cvarLogBuffs));
    Cvar_LogBuffs(g_hCvarLogBuffs, "", cvarLogBuffs);

    HookEvent("player_connect", Event_player_connect, EventHookMode_Post);
    HookEvent("player_spawn", Event_player_spawn, EventHookMode_Post);
    HookEvent("player_death", Event_player_death, EventHookMode_Pre);
    HookEvent("player_chargedeployed", Event_player_chargedeployed, EventHookMode_Pre);
    HookEvent("player_healed", Event_player_healed, EventHookMode_Post);

    HookEvent("teamplay_round_win", Event_round_win, EventHookMode_PostNoCopy);
    HookEvent("teamplay_round_restart_seconds", Event_round_restart_seconds, EventHookMode_PostNoCopy);
    HookEvent("teamplay_round_start", Event_teamplay_round_start, EventHookMode_PostNoCopy);
    HookEvent("tf_game_over", Event_game_over, EventHookMode_Pre);
    HookEvent("teamplay_game_over", Event_game_over, EventHookMode_Pre);

    //LastCollectInfoTime = GetGameTime();
    CreateTimer(TIMER_TICK, Timer_CollectInfo, _, TIMER_REPEAT);

    OnMapStart();
}

public void OnLibraryAdded(const char[] name) {
    // Set up auto updater
    if (StrEqual(name, "updater"))
        Updater_AddPlugin(UPDATE_URL);
}

// ResetMedic(team) resets all information about team's medic, including the client id.
void ResetMedic(TFTeam team) {
    medic[team].MedicClient = -1;
    medic[team].MedicLastDeath = -1.0;

    ResetMedicInfo(team);
}

// ResetMedicInfo(team) only resets the info that is related to the medic's current life (like HasUber, IsUbering). All stats are kept.
void ResetMedicInfo(TFTeam team) {
    medic[team].MedicMedigun = -1;

    medic[team].MedicHasUber = false;
    medic[team].MedicIsUbering = false;
    medic[team].MedicTimeToUber = TF2_GetPlayerUberBuildTime(medic[team].MedicClient);
    medic[team].MedicLastUberPct = 0.0;
    medic[team].MedicStartedBuildTime = -1.0;
    medic[team].MedicInitialHealSpawnTime = -1.0;
    medic[team].MedicFullyChargedTime = -1.0;
    medic[team].MedicUberStartTime = -1.0;
    medic[team].MedicLastUberTime = -1.0;

    medic[team].MedicCurrentBiggestAdvantage = 0.0;
    medic[team].MedicHasHadAdvantage = false;
}

public void OnMapStart() {
    ResetMedic(TFTeam_Red);
    ResetMedic(TFTeam_Blue);

    CountdownStarted = false;
    IsInMatch = false;
    IsBonusRoundTime = false;
    LastRoundStart = 0.0;
    g_fLastCollectBuffs = 0.0;
    //LastCollectInfoTime = GetGameTime();
}

public void Cvar_LogBuffs(Handle cvar, const char[] oldValue, const char[] newValue) {
    g_bLogBuffs = StringToInt(newValue) == 1;

    Array_Fill(g_iLastHealth, sizeof(g_iLastHealth), 0);
    Array_Fill(g_iHealedBy, sizeof(g_iHealedBy), 0);
    Array_Fill(g_iBuffed, sizeof(g_iBuffed), 0);
}

public Action Event_player_connect(Event event, const char[] name, bool dontBroadcast) {
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);

    // ==== Buffs ====
    g_iBuffed[client] = 0;
    g_iHealedBy[client] = 0;
    return Plugin_Continue;
}

public Action Event_player_spawn(Event event, const char[] name, bool dontBroadcast) {
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);

    // ==== Buffs ====
    g_iMaxHealth[client] = GetClientHealth(client);
    g_iLastHealth[client] = g_iMaxHealth[client];
    g_iBuffed[client] = 0;

    // ==== Medic stats ====
    if (!IsInMatch || IsBonusRoundTime)
        return Plugin_Continue;

    if (!IsRealPlayer(client))
        return Plugin_Continue;

    for (TFTeam team = TFTeam_Red; team <= TFTeam_Blue; team++) {
        if (medic[team].MedicClient != client)
            continue;

        if (TF2_GetClientTeam(client) != team || TF2_GetPlayerClass(client) != TFClass_Medic) {
            ResetMedic(team);
            continue;
        }

        float uberPct = TF2_GetPlayerUberLevel(client, medic[team].MedicMedigun);
        if (uberPct > 0.0)
            continue; // The medic spawn switched by changing hat.

        if (LastRoundStart >= 0.0) {
            if (GetGameTime() - LastRoundStart >= 20.0) {
                // Don't count spawning (or respawning to get a better spawn position) at the start of a round.
                medic[team].MedicInitialHealSpawnTime = GetGameTime();
            }
        }
    }

    return Plugin_Continue;
}

public Action Event_player_death(Event event, const char[] name, bool dontBroadcast) {
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);

    // ==== Buffs ====
    g_iLastHealth[client] = 0;

    // ==== Medic stats ====
    if (!IsInMatch || IsBonusRoundTime)
        return Plugin_Continue;

    for (TFTeam team = TFTeam_Red; team <= TFTeam_Blue; team++) {
        if (medic[team].MedicClient != client || !IsRealPlayer(client) || TF2_GetPlayerClass(client) != TFClass_Medic)
            continue;

        float uberPct = TF2_GetPlayerUberLevel(client, medic[team].MedicMedigun);

        if (uberPct == 1) {
            CPrintToSTV("{default}[STV Stats] %s{default}'s medic DROPPED!", 
                        team == TFTeam_Red ? "{red}RED" : "{blue}BLU");
        } else if (uberPct >= 0.95) {
            CPrintToSTV("{default}[STV Stats] %s{default}'s medic died with %s%i%%{default} uber", 
                        team == TFTeam_Red ? "{red}RED" : "{blue}BLU", 
                        team == TFTeam_Red ? "{red}" : "{blue}", 
                        RoundToFloor(uberPct * 100.0));
        }
        medic[team].MedicLastDeath = GetGameTime();

        LogMedicDeath(client, RoundToFloor(uberPct * 100.0));
    }

    return Plugin_Continue;
}

public Action Event_player_chargedeployed(Event event, const char[] name, bool dontBroadcast) {
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);

    // ==== Medic stats ====
    for (TFTeam team = TFTeam_Red; team <= TFTeam_Blue; team++) {
        if (medic[team].MedicClient != client)
            continue;

        if (medic[team].MedicHasUber == false)
            LogUberReady(client);

        medic[team].MedicLastUberPct = 1.0;
        medic[team].MedicHasUber = false;
        medic[team].MedicHasHadAdvantage = false;
        medic[team].MedicIsUbering = true;
        medic[team].MedicUberStartTime = GetGameTime();
        medic[team].MedicLastUberTime = GetGameTime();

        float waitTime;
        if (medic[team].MedicFullyChargedTime < 0.0) {
            waitTime = TIMER_TICK / 2;
        } else {
            waitTime = GetGameTime() - medic[team].MedicFullyChargedTime;
            medic[team].MedicFullyChargedTime = -1.0;
        }

        if (waitTime >= 30.0) {
            CPrintToSTV("{default}[STV Stats] %s{default} had uber for %s%i seconds{default} before using it",
                         team == TFTeam_Red ? "{red}RED" : "{blue}BLU", team == TFTeam_Red ? "{red}" : "{blue}",
                         RoundToNearest(waitTime));
        }
    }
    return Plugin_Continue;
}

public Action Event_player_healed(Event event, const char[] name, bool dontBroadcast) {
    int patientId = event.GetInt("patient");
    int healerId = event.GetInt("healer");
    int patient = GetClientOfUserId(patientId);
    int healer = GetClientOfUserId(healerId);
    //int amount = event.GetInt("amount");
    if (healer == 0) {
        // Caused by medpacks
        return Plugin_Continue;
    } else if (healer == 0 || patient == 0) {
        // This has been observed to happen by http://www.teamfortress.tv/post/631052/medicstats-sourcemod-plugin
        LogMessage("Wrong player-healed event detected: patient=%i/%i, healer=%i/%i", patientId, patient, healerId, healer);
        return Plugin_Continue;
    }

    if (TF2_GetPlayerClass(healer) != TFClass_Medic) {
        // This will ignore other heal events, like an Engineer's dispenser
        return Plugin_Continue;
    }

    TFTeam healerTeam = TF2_GetClientTeam(healer);

    // ==== Buffs ====
    g_iHealedBy[patient] = healer;

    // ==== Medic stats ====
    if (medic[healerTeam].MedicClient != healer) {
        ResetMedicInfo(healerTeam);
        medic[healerTeam].MedicClient = healer;
    }
    return Plugin_Continue;
}

public void Event_round_win(Event event, const char[] name, bool dontBroadcast) {
    IsBonusRoundTime = true;
}

public void Event_round_restart_seconds(Event event, const char[] name, bool dontBroadcast) {
    CountdownStarted = true;
    IsInMatch = false;
}

public void Event_teamplay_round_start(Event event, const char[] name, bool dontBroadcast) {
    if (CountdownStarted) {
        CountdownStarted = false;

        ResetMedic(TFTeam_Red);
        ResetMedic(TFTeam_Blue);

        IsInMatch = true;
    } else if (IsInMatch) {
        ResetMedicInfo(TFTeam_Red);
        ResetMedicInfo(TFTeam_Blue);
    }
    IsBonusRoundTime = false;
    LastRoundStart = GetGameTime();
}

public Action Event_game_over(Event event, const char[] name, bool dontBroadcast) {
    if (!IsInMatch)
        return Plugin_Continue;

    IsInMatch = false;
    IsBonusRoundTime = false;

    return Plugin_Continue;
}

public Action Timer_CollectInfo(Handle timer) {
    float gameTime = GetGameTime();
    //new Float:timeSinceLastTick = max(0.0, gameTime - LastCollectInfoTime);
    //LastCollectInfoTime = gameTime;

    for (TFTeam team = TFTeam_Red; team <= TFTeam_Blue; team++) {
        int client = medic[team].MedicClient;
        if (!IsRealPlayer(client) || TF2_GetClientTeam(client) != team || TF2_GetPlayerClass(client) != TFClass_Medic) {
            medic[team].MedicClient = -1;
        } else {
            int target = TF2_GetHealingTarget(client);
            if (IsRealPlayer(target))
                g_iHealedBy[target] = client;
        }
    }

    // Find the medics, if need be.
    if (medic[TFTeam_Red].MedicClient == -1 || medic[TFTeam_Blue].MedicClient == -1) {
        for (int client = 1; client <= MaxClients; client++) {
            if (!IsRealPlayer(client))
                continue;
            if (TF2_GetPlayerClass(client) != TFClass_Medic)
                continue;
            if (medic[GetClientTeam(client)].MedicClient == -1)
                medic[GetClientTeam(client)].MedicClient = client;
        }
    }

    // Log buffs every second.
    if (g_bLogBuffs && gameTime - g_fLastCollectBuffs >= 1.0) {
        CollectBuffs();
    }

    // Don't calculate medic statas in warmup
    if (!IsInMatch || IsBonusRoundTime)
        return Plugin_Continue;

    // Get info about each medic
    for (TFTeam team = TFTeam_Red; team <= TFTeam_Blue; team++) {
        int client = medic[team].MedicClient;
        if (client == -1)
            continue;

        if (IsPlayerAlive(client)) {
            float uberPct = TF2_GetPlayerUberLevel(client, medic[team].MedicMedigun);
            float uberBuildTime = TF2_GetPlayerUberBuildTime(client);

            medic[team].MedicIsUbering = uberPct < medic[team].MedicLastUberPct && uberPct != 0.0;
            medic[team].MedicHasUber =
                uberPct >= 1.0 &&
                !medic[team].MedicIsUbering; // The "!medic[team].MedicIsUbering" should not be necessary, but just to be sure. We never want (HasUber && IsUbering) to be true.
            medic[team].MedicTimeToUber = uberBuildTime * (1 - uberPct);
            medic[team].MedicLastUberPct = uberPct;

            if (medic[team].MedicStartedBuildTime < 0.0) {
                // Medic has not started building yet.

                if (!(medic[team].MedicHasUber || medic[team].MedicIsUbering)) {
                    // If the medic does not have the uber and is not ubering, they have now started building uber.
                    medic[team].MedicStartedBuildTime = gameTime;
                    LogEmptyUber(client);
                }
            } else {
                // Medic has started building uber.

                if (medic[team].MedicHasUber || medic[team].MedicIsUbering) {
                    // Uber is fully built. Calculate some stats.
                    float buildtime = gameTime - medic[team].MedicStartedBuildTime - TIMER_TICK / 2;
                    buildtime = max(buildtime, uberBuildTime);
                    medic[team].MedicStartedBuildTime = -1.0;

                    // Notice that sometimes the medic manages to get 100% and use the uber between two ticks.
                    // In that case, LogUberReady has already been called from the 'chargedeployed' event.
                    if (medic[team].MedicHasUber)
                        LogUberReady(client);

                    //PrintToSTV("[STV Stats] %s built uber in %.0f seconds", team == TFTeam_Red ? "RED" : "BLU", buildtime);
                }
            }

            if (medic[team].MedicInitialHealSpawnTime >= 0.0 && uberPct > 0.0) {
                // Medic has spawned, and just started healing.

                float timeBeforeHealing = gameTime - medic[team].MedicInitialHealSpawnTime;
                medic[team].MedicInitialHealSpawnTime = -1.0;

                if (timeBeforeHealing >= 5.0) {
                    CPrintToSTV(
                        "{default}[STV Stats] %s{default} spent %s%.1f seconds{default} after spawning before healing",
                        team == TFTeam_Red ? "{red}RED" : "{blue}BLU", 
                        team == TFTeam_Red ? "{red}" : "{blue}",
                        timeBeforeHealing);
                }
                LogFirstHeal(client, timeBeforeHealing);
            }

            // Remember when the medic had 100%
            if (medic[team].MedicHasUber && medic[team].MedicFullyChargedTime < 0.0)
                medic[team].MedicFullyChargedTime = gameTime - TIMER_TICK / 2;

            if (medic[team].MedicUberStartTime >= 0.0 && medic[team].MedicIsUbering == false) {
                // If the medic ubered and the uber faded, remember how long it lasted.

                float uberTime = gameTime - medic[team].MedicUberStartTime - TIMER_TICK / 2;
                //PrintToSTV("[STV Stats] %s's uber lasted %.1f seonds", team == TFTeam_Red ? "RED" : "BLU", uberTime);
                LogUberLength(client, uberTime);
                medic[team].MedicUberStartTime = -1.0;
            }
        } else {
            // If the medic is dead, reset his "current life info".
            ResetMedicInfo(team);
        }
    }

    // Find stats about the medics compared to each other
    if (medic[TFTeam_Red].MedicClient != -1 && medic[TFTeam_Blue].MedicClient != -1) {
        for (TFTeam team = TFTeam_Red; team <= TFTeam_Blue; team++) {
            TFTeam oppteam = team == TFTeam_Red ? TFTeam_Blue : TFTeam_Red;
            int client = medic[team].MedicClient; //, oppclient = medic[oppteam][MedicClient];

            if (medic[team].MedicIsUbering == false &&
                medic[team].MedicTimeToUber <= medic[oppteam].MedicTimeToUber - 10.0) {
                // If the medic currently has 10+ seconds uber advantage, remember it.

                if (medic[team].MedicHasHadAdvantage == false)
                    medic[team].MedicCurrentBiggestAdvantage = 0.0;
                medic[team].MedicHasHadAdvantage = true;
                medic[team].MedicCurrentBiggestAdvantage =
                    max(medic[team].MedicCurrentBiggestAdvantage,
                        medic[oppteam].MedicTimeToUber - medic[team].MedicTimeToUber);
            }

            if (medic[oppteam].MedicHasUber && medic[team].MedicHasHadAdvantage) {
                // If the medic has had an uber advantage, and the opposing medic has gotten uber in the meantime, remember the uber advantage loss.

                medic[team].MedicHasHadAdvantage = false;

                LogLostUberAdvantage(client, medic[team].MedicCurrentBiggestAdvantage);
                CPrintToSTV("{default}[STV Stats] %s{default} lost their uber advantage of %s%.0f seconds{default}",
                             team == TFTeam_Red ? "{red}RED" : "{blue}BLU", 
                             team == TFTeam_Red ? "{red}" : "{blue}",
                             medic[team].MedicCurrentBiggestAdvantage);
            }
        }
    }

    return Plugin_Continue;
}

void CollectBuffs() {
    g_fLastCollectBuffs = GetGameTime();

    // Check who each medic is currently healing.
    for (TFTeam team = TFTeam_Red; team <= TFTeam_Blue; team++) {
        int client = medic[team].MedicClient;
        if (!IsRealPlayer(client))
            continue;
        if (!IsPlayerAlive(client))
            continue;
        int target = TF2_GetHealingTarget(client);
        if (IsRealPlayer(target))
            g_iHealedBy[target] = client;
    }

    // Log the recorded buffs.
    for (int client = 1; client <= MaxClients; client++) {
        if (g_iBuffed[client] <= 0)
            continue;
        if (!IsRealPlayer2(client)) {
            g_iBuffed[client] = 0;
            continue;
        }

        if (!IsRealPlayer(g_iHealedBy[client]) || TF2_GetPlayerClass(g_iHealedBy[client]) != TFClass_Medic) {
            TFTeam clientTeam = TF2_GetClientTeam(client);
            g_iHealedBy[client] = medic[clientTeam].MedicClient;
        }

        if (IsRealPlayer(g_iHealedBy[client])) {
            LogHealed(client, g_iHealedBy[client], g_iBuffed[client]);
        }
        g_iBuffed[client] = 0;
    }
}

public void OnGameFrame() {
    if (!g_bLogBuffs)
        return;

    // Each game frame we compare all players' current health with their health in the last game frame. If someone got buffed (above 100% health), record it.
    for (int client = 1; client <= MaxClients; client++) {
        if (g_iLastHealth[client] <= 0)
            continue;
        if (!IsRealPlayer2(client)) {
            g_iLastHealth[client] = 0;
            continue;
        }

        if (!IsPlayerAlive(client))
            continue;

        int newhealth = GetClientHealth(client);
        int oldhealth = g_iLastHealth[client];
        g_iLastHealth[client] = newhealth;
        if (newhealth <= g_iMaxHealth[client])
            continue;
        if (newhealth <= oldhealth)
            continue;
        if (oldhealth < g_iMaxHealth[client])
            oldhealth = g_iMaxHealth[client];
        g_iBuffed[client] += newhealth - oldhealth;
    }
}

// -----------------------------------
// Log functions
// -----------------------------------
void LogFirstHeal(int healer, float time) {
    char healerName[32];
    char healerSteamId[64];
    char healerTeam[64];

    GetClientAuthStringNew(healer, healerSteamId, sizeof(healerSteamId), false);
    GetClientName(healer, healerName, sizeof(healerName));
    GetPlayerTeamStr(GetClientTeam(healer), healerTeam, sizeof(healerTeam));

    LogToGame("\"%s<%d><%s><%s>\" triggered \"first_heal_after_spawn\" (time \"%.1f\")", 
        healerName,
        GetClientUserId(healer), 
        healerSteamId, 
        healerTeam, 
        time);
}

void LogUberReady(int healer) {
    char healerName[32];
    char healerSteamId[64];
    char healerTeam[64];

    GetClientAuthStringNew(healer, healerSteamId, sizeof(healerSteamId), false);
    GetClientName(healer, healerName, sizeof(healerName));
    GetPlayerTeamStr(GetClientTeam(healer), healerTeam, sizeof(healerTeam));

    LogToGame("\"%s<%d><%s><%s>\" triggered \"chargeready\"", 
        healerName, 
        GetClientUserId(healer), 
        healerSteamId,
        healerTeam);
}

void LogMedicDeath(int healer, int pct) {
    char healerName[32];
    char healerSteamId[64];
    char healerTeam[64];

    GetClientAuthStringNew(healer, healerSteamId, sizeof(healerSteamId), false);
    GetClientName(healer, healerName, sizeof(healerName));
    GetPlayerTeamStr(GetClientTeam(healer), healerTeam, sizeof(healerTeam));

    LogToGame("\"%s<%d><%s><%s>\" triggered \"medic_death_ex\" (uberpct \"%i\")", 
        healerName, 
        GetClientUserId(healer),
        healerSteamId, 
        healerTeam, 
        pct);
}

void LogEmptyUber(int healer) {
    char healerName[32];
    char healerSteamId[64];
    char healerTeam[64];

    GetClientAuthStringNew(healer, healerSteamId, sizeof(healerSteamId), false);
    GetClientName(healer, healerName, sizeof(healerName));
    GetPlayerTeamStr(GetClientTeam(healer), healerTeam, sizeof(healerTeam));

    LogToGame("\"%s<%d><%s><%s>\" triggered \"empty_uber\"", 
        healerName, 
        GetClientUserId(healer), 
        healerSteamId,
        healerTeam);
}

void LogUberLength(int healer, float uberLength) {
    char healerName[32];
    char healerSteamId[64];
    char healerTeam[64];

    GetClientAuthStringNew(healer, healerSteamId, sizeof(healerSteamId), false);
    GetClientName(healer, healerName, sizeof(healerName));
    GetPlayerTeamStr(GetClientTeam(healer), healerTeam, sizeof(healerTeam));

    LogToGame("\"%s<%d><%s><%s>\" triggered \"chargeended\" (duration \"%.1f\")", 
        healerName, 
        GetClientUserId(healer),
        healerSteamId, 
        healerTeam, 
        uberLength);
}

void LogLostUberAdvantage(int healer, float uberAdvSeconds) {
    char healerName[32];
    char healerSteamId[64];
    char healerTeam[64];

    GetClientAuthStringNew(healer, healerSteamId, sizeof(healerSteamId), false);
    GetClientName(healer, healerName, sizeof(healerName));
    GetPlayerTeamStr(GetClientTeam(healer), healerTeam, sizeof(healerTeam));

    LogToGame("\"%s<%d><%s><%s>\" triggered \"lost_uber_advantage\" (time \"%.0f\")", 
        healerName,
        GetClientUserId(healer), 
        healerSteamId, 
        healerTeam, 
        uberAdvSeconds);
}



// Borrowed from supstats.sp
void LogHealed(int patient, int healer, int amount) {
    char patientName[32];
    char healerName[32];
    char patientSteamId[64];
    char healerSteamId[64];
    char patientTeam[64];
    char healerTeam[64];

    GetClientAuthStringNew(patient, patientSteamId, sizeof(patientSteamId), false);
    GetClientName(patient, patientName, sizeof(patientName));
    GetClientAuthStringNew(healer, healerSteamId, sizeof(healerSteamId), false);
    GetClientName(healer, healerName, sizeof(healerName));

    GetPlayerTeamStr(GetClientTeam(patient), patientTeam, sizeof(patientTeam));
    GetPlayerTeamStr(GetClientTeam(healer), healerTeam, sizeof(healerTeam));

    LogToGame("\"%s<%d><%s><%s>\" triggered \"healed\" against \"%s<%d><%s><%s>\" (healing \"%d\")", 
        healerName,
        GetClientUserId(healer), 
        healerSteamId, 
        healerTeam, 
        patientName, 
        GetClientUserId(patient), 
        patientSteamId,
        patientTeam, 
        amount);
}
