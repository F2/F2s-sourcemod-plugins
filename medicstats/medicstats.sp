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


---- 2.0.0 (12/11/2026) ----
- Reworked the way buffs are detected
- Medic stats are now always logged, also during warmup
- Don't log buffs to enemy spies
- Fixed uber stats being wrong when uber is drained (e.g. by the Pomson) or gained during an uber (e.g. by the Ubersaw)
- Fixed uber stats being wrong when the game is paused during an uber
- Fixed uber stats being wrong when a team has more than one medic
- Fixed STV Stats messages being shown in warmup after a match was cancelled
- Fixed Pomson generating bad logs



TODO:
- The log lines should include which medigun is wielded
- cvar to enable logging medics' self-heal (should be disabled by default)
- Vaccinator ubers are not detected properly (m_bChargeRelease is never true for it), so they are logged with a duration of 0 followed by an empty_uber
*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <tf2_stocks>
#include <dhooks>
#include <f2stocks>
#include <match>
#undef REQUIRE_PLUGIN
#include <updater>


#define PLUGIN_VERSION "2.0.0"
#define UPDATE_URL "https://sourcemod.krus.dk/medicstats/update.txt"
#define TIMER_TICK 0.15
#define MAX_BEAM_HEAL_PER_CALL 10 // A medigun adds 1-2 HP per heal (about 5 during a Quick-Fix uber). Kunai, Eyelander heads etc. add 15 or more at once.



public Plugin myinfo = {
	name = "Medic Stats",
	author = "F2",
	description = "Logs various medic-related statistics, including buffed heals.",
	version = PLUGIN_VERSION,
	url = "https://github.com/F2/F2s-sourcemod-plugins"
};


enum struct MedicInfo {
    // Info about medic's current life
    TFTeam MedicTeam;    // The team the client is a medic on - TFTeam_Unassigned if the client is not a medic
    int MedicMedigun;    // An entity reference to the client's medigun
    bool MedicHasUber;   // True if the medic has 100% uber
    bool MedicIsUbering; // True if the medic is currently ubering
    float MedicTimeToUber; // How far away from uber the medic is (the last time it was checked by the CollectInfo timer)
    float MedicStartedBuildTime; // The GameTime of when the medic had 0% - when the medic has 100%, or is ubering, it is set to -1.0
    float MedicInitialHealSpawnTime; // The GameTime of when the medic spawned (the beginning of a round doesn't count) - when the medic starts to heal, it is set to -1.0
    float MedicFullyChargedTime; // The GameTime of when the uber is fully charged - when the uber is used, it is set to -1.0
    float MedicUberStartTime; // The GameTime of when the medic started using his uber (IsUbering = true) - when the uber is over, it is set to -1.0
    float MedicLastUberTime; // The GameTime of last uber
    float MedicLastDeath;    // The GameTime of last death
}

enum struct TeamInfo {
    // Each team is represented by its medic closest to having uber
    int TeamAdvantageMedic; // The medic that got the team a significant uber advantage over the opposing team - 0 if the team has no advantage
    float TeamBiggestAdvantage; // If TeamAdvantageMedic is set, this value indicates how big the uber advantage was (in seconds)
}


DynamicHook g_hTakeHealth = null; // CBaseEntity::TakeHealth(float flHealth, int bitsDamageType)
int g_iHealthBeforeHeal[MAXPLAYERS + 1]; // [patient] The patient's health right before the current TakeHealth call
int g_iBeamTarget[MAXPLAYERS + 1]; // [healer] The patient the medic's beam was attached to when the medic last healed
int g_iBuffHighest[MAXPLAYERS + 1]; // [patient] The highest health the patient has had since the beam attached or since they last took damage
int g_iBuffed[MAXPLAYERS + 1]; // [healer] The buff heals not yet logged
int g_iBuffedPatient[MAXPLAYERS + 1]; // [healer] The patient that g_iBuffed was given to
float g_fLastCollectBuffs;

MedicInfo medic[MAXPLAYERS + 1];
TeamInfo teams[TFTeam];

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

    // Every heal a player gets goes through CBaseEntity::TakeHealth(). Borrow its offset from SourceMod's own gamedata:
    // it is declared two virtual functions after CBaseEntity::OnTakeDamage() (with AdjustDamageDirection() in between).
    GameData gameConf = new GameData("sdkhooks.games");
    if (gameConf == null)
        SetFailState("Cannot find sdkhooks.games gamedata");
    int onTakeDamageOffset = gameConf.GetOffset("OnTakeDamage");
    delete gameConf;
    if (onTakeDamageOffset == -1)
        SetFailState("Cannot find OnTakeDamage offset in sdkhooks.games gamedata");

    g_hTakeHealth = new DynamicHook(onTakeDamageOffset + 2, HookType_Entity, ReturnType_Int, ThisPointer_CBaseEntity);
    g_hTakeHealth.AddParam(HookParamType_Float);
    g_hTakeHealth.AddParam(HookParamType_Int);
    for (int client = 1; client <= MaxClients; client++) {
        if (IsClientInGame(client))
            OnClientPutInServer(client);
    }

    HookEvent("player_spawn", Event_player_spawn, EventHookMode_Post);
    HookEvent("player_death", Event_player_death, EventHookMode_Pre);
    HookEvent("player_hurt", Event_player_hurt, EventHookMode_Post);
    HookEvent("player_chargedeployed", Event_player_chargedeployed, EventHookMode_Pre);

    HookEvent("teamplay_round_start", Event_teamplay_round_start, EventHookMode_PostNoCopy);

    // Match.inc
    Match_OnPluginStart();

    //LastCollectInfoTime = GetGameTime();
    CreateTimer(TIMER_TICK, Timer_CollectInfo, _, TIMER_REPEAT);

    OnMapStart();
}

public void OnLibraryAdded(const char[] name) {
    // Set up auto updater
    if (StrEqual(name, "updater"))
        Updater_AddPlugin(UPDATE_URL);
}

// ResetMedic(client) resets all information about the medic, including which team they are a medic on.
void ResetMedic(int client) {
    medic[client].MedicTeam = TFTeam_Unassigned;
    medic[client].MedicLastDeath = -1.0;

    ResetMedicInfo(client);
}

// ResetMedicInfo(client) only resets the info that is related to the medic's current life (like HasUber, IsUbering). All stats are kept.
void ResetMedicInfo(int client) {
    medic[client].MedicMedigun = INVALID_ENT_REFERENCE;

    medic[client].MedicHasUber = false;
    medic[client].MedicIsUbering = false;
    medic[client].MedicTimeToUber = TF2_GetPlayerUberBuildTime(client);
    medic[client].MedicStartedBuildTime = -1.0;
    medic[client].MedicInitialHealSpawnTime = -1.0;
    medic[client].MedicFullyChargedTime = -1.0;
    medic[client].MedicUberStartTime = -1.0;
    medic[client].MedicLastUberTime = -1.0;

    ResetAdvantage(client);
}

// ResetAdvantage(client) forgets the uber advantage that the medic got their team.
void ResetAdvantage(int client) {
    for (TFTeam team = TFTeam_Red; team <= TFTeam_Blue; team++) {
        if (teams[team].TeamAdvantageMedic == client) {
            teams[team].TeamAdvantageMedic = 0;
            teams[team].TeamBiggestAdvantage = 0.0;
        }
    }
}

// UpdateMedicTeam(client) starts or stops tracking the client as a medic, if they have changed class or team.
void UpdateMedicTeam(int client) {
    TFTeam team = TFTeam_Unassigned;
    if (IsRealPlayer(client) && TF2_GetPlayerClass(client) == TFClass_Medic) {
        team = TF2_GetClientTeam(client);
        if (team != TFTeam_Red && team != TFTeam_Blue)
            team = TFTeam_Unassigned;
    }

    if (medic[client].MedicTeam != team) {
        ResetMedic(client);
        medic[client].MedicTeam = team;
    }
}

// GetBestMedic(team) returns the team's medic closest to having uber - or 0 if the team has no medic.
int GetBestMedic(TFTeam team) {
    int best = 0;
    for (int client = 1; client <= MaxClients; client++) {
        if (medic[client].MedicTeam != team)
            continue;
        if (best == 0 || medic[client].MedicTimeToUber < medic[best].MedicTimeToUber)
            best = client;
    }
    return best;
}

// TeamHasUber(team) returns true if any of the team's medics has 100% uber.
bool TeamHasUber(TFTeam team) {
    for (int client = 1; client <= MaxClients; client++) {
        if (medic[client].MedicTeam == team && medic[client].MedicHasUber)
            return true;
    }
    return false;
}

public void OnMapStart() {
    for (int client = 1; client <= MaxClients; client++)
        ResetMedic(client);

    LastRoundStart = 0.0;
    g_fLastCollectBuffs = 0.0;
    //LastCollectInfoTime = GetGameTime();

    Match_OnMapStart();
}

public void OnMapEnd() {
    Match_OnMapEnd();
}

void StartMatch() {
}

void ResetMatch() {
}

void EndMatch(bool endedMidgame) {
}

// ShouldPrintToSTV() returns true if STV Stats messages should be shown - i.e. not in warmup.
bool ShouldPrintToSTV() {
    return g_bInMatch && g_bFirstRoundStarted;
}

public void Cvar_LogBuffs(Handle cvar, const char[] oldValue, const char[] newValue) {
    g_bLogBuffs = StringToInt(newValue) == 1;

    for (int client = 1; client <= MaxClients; client++)
        ResetBuffs(client);
}

void ResetBuffs(int client) {
    g_iBeamTarget[client] = 0;
    g_iBuffHighest[client] = 0;
    g_iBuffed[client] = 0;
    g_iBuffedPatient[client] = 0;

    // Drop unlogged buffs given to this client
    for (int healer = 1; healer <= MaxClients; healer++) {
        if (g_iBuffedPatient[healer] == client)
            g_iBuffed[healer] = 0;
    }
}

public void OnClientConnected(int client) {
    // ==== Buffs ====
    ResetBuffs(client);
}

public void OnClientPutInServer(int client) {
    // ==== Buffs ====
    // The hook is removed automatically when the player entity is deleted.
    g_hTakeHealth.HookEntity(Hook_Pre, client, Hook_TakeHealth_Pre);
    g_hTakeHealth.HookEntity(Hook_Post, client, Hook_TakeHealth_Post);
}

public Action Event_player_spawn(Event event, const char[] name, bool dontBroadcast) {
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);

    // ==== Medic stats ====
    if (g_bIsBonusRoundTime)
        return Plugin_Continue;

    if (!IsRealPlayer(client))
        return Plugin_Continue;

    UpdateMedicTeam(client);
    if (medic[client].MedicTeam == TFTeam_Unassigned)
        return Plugin_Continue;

    float uberPct = TF2_GetPlayerUberLevel(client, medic[client].MedicMedigun);
    if (uberPct > 0.0)
        return Plugin_Continue; // The medic spawn switched by changing hat.

    if (GetGameTime() - LastRoundStart >= 20.0) {
        // Don't count spawning (or respawning to get a better spawn position) at the start of a round.
        medic[client].MedicInitialHealSpawnTime = GetGameTime();
    }

    return Plugin_Continue;
}

public Action Event_player_death(Event event, const char[] name, bool dontBroadcast) {
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);

    // ==== Medic stats ====
    if (g_bIsBonusRoundTime)
        return Plugin_Continue;

    if (!IsRealPlayer(client))
        return Plugin_Continue;

    TFTeam team = medic[client].MedicTeam;
    if (team == TFTeam_Unassigned || TF2_GetPlayerClass(client) != TFClass_Medic)
        return Plugin_Continue;

    float uberPct = TF2_GetPlayerUberLevel(client, medic[client].MedicMedigun);

    if (ShouldPrintToSTV()) {
        if (uberPct == 1) {
            CPrintToSTV("{default}[STV Stats] %s{default}'s medic DROPPED!",
                        team == TFTeam_Red ? "{red}RED" : "{blue}BLU");
        } else if (uberPct >= 0.95) {
            CPrintToSTV("{default}[STV Stats] %s{default}'s medic died with %s%i%%{default} uber",
                        team == TFTeam_Red ? "{red}RED" : "{blue}BLU",
                        team == TFTeam_Red ? "{red}" : "{blue}",
                        RoundToFloor(uberPct * 100.0));
        }
    }
    medic[client].MedicLastDeath = GetGameTime();

    LogMedicDeath(client, RoundToFloor(uberPct * 100.0));

    return Plugin_Continue;
}

public Action Event_player_hurt(Event event, const char[] name, bool dontBroadcast) {
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);

    // ==== Buffs ====
    // Heals that restore health lost to damage count as buffs again, even if the patient was buffed that high before.
    g_iBuffHighest[client] = event.GetInt("health");
    return Plugin_Continue;
}

public Action Event_player_chargedeployed(Event event, const char[] name, bool dontBroadcast) {
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);

    // ==== Medic stats ====
    TFTeam team = medic[client].MedicTeam;
    if (team == TFTeam_Unassigned)
        return Plugin_Continue;

    if (medic[client].MedicFullyChargedTime < 0.0)
        LogUberReady(client);

    medic[client].MedicHasUber = false;
    ResetAdvantage(client);
    medic[client].MedicIsUbering = true;
    medic[client].MedicUberStartTime = GetGameTime();
    medic[client].MedicLastUberTime = GetGameTime();

    float waitTime;
    if (medic[client].MedicFullyChargedTime < 0.0) {
        waitTime = TIMER_TICK / 2;
    } else {
        waitTime = GetGameTime() - medic[client].MedicFullyChargedTime;
        medic[client].MedicFullyChargedTime = -1.0;
    }

    if (waitTime >= 30.0 && ShouldPrintToSTV()) {
        CPrintToSTV("{default}[STV Stats] %s{default} had uber for %s%i seconds{default} before using it",
                     team == TFTeam_Red ? "{red}RED" : "{blue}BLU", team == TFTeam_Red ? "{red}" : "{blue}",
                     RoundToNearest(waitTime));
    }
    return Plugin_Continue;
}

public void Event_teamplay_round_start(Event event, const char[] name, bool dontBroadcast) {
    for (int client = 1; client <= MaxClients; client++)
        ResetMedicInfo(client);

    LastRoundStart = GetGameTime();
}

public Action Timer_CollectInfo(Handle timer) {
    float gameTime = GetGameTime();
    //new Float:timeSinceLastTick = max(0.0, gameTime - LastCollectInfoTime);
    //LastCollectInfoTime = gameTime;

    // Find the medics
    for (int client = 1; client <= MaxClients; client++)
        UpdateMedicTeam(client);

    // Notice when a medic's beam detaches, so it counts as newly attached if it comes back.
    for (int healer = 1; healer <= MaxClients; healer++) {
        if (g_iBeamTarget[healer] != 0 && (!IsRealPlayer(healer) || !IsPlayerAlive(healer) || TF2_GetHealingTarget(healer) != g_iBeamTarget[healer]))
            g_iBeamTarget[healer] = 0;
    }

    // Log buffs every second.
    if (g_bLogBuffs && gameTime - g_fLastCollectBuffs >= 1.0) {
        CollectBuffs();
    }

    // Don't calculate medic stats after a round has been won
    if (g_bIsBonusRoundTime)
        return Plugin_Continue;

    // Don't count time while the game is paused
    if (!IsServerProcessing())
        return Plugin_Continue;

    // Get info about each medic
    for (int client = 1; client <= MaxClients; client++) {
        TFTeam team = medic[client].MedicTeam;
        if (team == TFTeam_Unassigned)
            continue;

        if (IsPlayerAlive(client)) {
            float uberPct = TF2_GetPlayerUberLevel(client, medic[client].MedicMedigun);
            float uberBuildTime = TF2_GetPlayerUberBuildTime(client);

            int medigun = EntRefToEntIndex(medic[client].MedicMedigun);
            medic[client].MedicIsUbering = medigun > 0 && GetEntProp(medigun, Prop_Send, "m_bChargeRelease") != 0;
            medic[client].MedicHasUber =
                uberPct >= 1.0 &&
                !medic[client].MedicIsUbering; // The "!medic[client].MedicIsUbering" should not be necessary, but just to be sure. We never want (HasUber && IsUbering) to be true.
            medic[client].MedicTimeToUber = uberBuildTime * (1 - uberPct);

            // If the full uber was lost without being used (e.g. switching medigun, or the Pomson draining it all), it is no longer the same uber.
            if (uberPct <= 0.0)
                medic[client].MedicFullyChargedTime = -1.0;

            if (medic[client].MedicStartedBuildTime < 0.0) {
                // Medic has not started building yet.

                if (!(medic[client].MedicHasUber || medic[client].MedicIsUbering) && medic[client].MedicFullyChargedTime < 0.0) {
                    // If the medic does not have the uber and is not ubering, they have now started building uber.
                    // Unless they had a full uber that was drained (e.g. by the Pomson) - then it is still the same uber.
                    medic[client].MedicStartedBuildTime = gameTime;
                    LogEmptyUber(client);
                }
            } else {
                // Medic has started building uber.

                if (medic[client].MedicHasUber || medic[client].MedicIsUbering) {
                    // Uber is fully built.
                    medic[client].MedicStartedBuildTime = -1.0;

                    // Notice that sometimes the medic manages to get 100% and use the uber between two ticks.
                    // In that case, LogUberReady has already been called from the 'chargedeployed' event.
                    if (medic[client].MedicHasUber)
                        LogUberReady(client);
                }
            }

            if (medic[client].MedicInitialHealSpawnTime >= 0.0 && uberPct > 0.0) {
                // Medic has spawned, and just started healing.

                float timeBeforeHealing = gameTime - medic[client].MedicInitialHealSpawnTime;
                medic[client].MedicInitialHealSpawnTime = -1.0;

                if (timeBeforeHealing >= 5.0 && ShouldPrintToSTV()) {
                    CPrintToSTV(
                        "{default}[STV Stats] %s{default} spent %s%.1f seconds{default} after spawning before healing",
                        team == TFTeam_Red ? "{red}RED" : "{blue}BLU", 
                        team == TFTeam_Red ? "{red}" : "{blue}",
                        timeBeforeHealing);
                }
                LogFirstHeal(client, timeBeforeHealing);
            }

            // Remember when the medic had 100%
            if (medic[client].MedicHasUber && medic[client].MedicFullyChargedTime < 0.0)
                medic[client].MedicFullyChargedTime = gameTime - TIMER_TICK / 2;

            if (medic[client].MedicUberStartTime >= 0.0 && medic[client].MedicIsUbering == false) {
                // If the medic ubered and the uber faded, remember how long it lasted.

                float uberTime = fmax(0.0, gameTime - medic[client].MedicUberStartTime - TIMER_TICK / 2); // Vaccinator ubers end immediately
                //PrintToSTV("[STV Stats] %s's uber lasted %.1f seonds", team == TFTeam_Red ? "RED" : "BLU", uberTime);
                LogUberLength(client, uberTime);
                medic[client].MedicUberStartTime = -1.0;
            }
        } else {
            // If the medic is dead, reset his "current life info".
            ResetMedicInfo(client);
        }
    }

    // Find stats about the teams compared to each other. Each team is represented by its medic closest to having uber.
    int bestMedic[TFTeam];
    bestMedic[TFTeam_Red] = GetBestMedic(TFTeam_Red);
    bestMedic[TFTeam_Blue] = GetBestMedic(TFTeam_Blue);
    if (bestMedic[TFTeam_Red] != 0 && bestMedic[TFTeam_Blue] != 0) {
        for (TFTeam team = TFTeam_Red; team <= TFTeam_Blue; team++) {
            TFTeam oppteam = team == TFTeam_Red ? TFTeam_Blue : TFTeam_Red;
            int client = bestMedic[team], oppclient = bestMedic[oppteam];

            if (medic[client].MedicIsUbering == false &&
                medic[client].MedicTimeToUber <= medic[oppclient].MedicTimeToUber - 10.0) {
                // If the team currently has 10+ seconds uber advantage, remember it.

                if (teams[team].TeamAdvantageMedic == 0)
                    teams[team].TeamBiggestAdvantage = 0.0;
                teams[team].TeamAdvantageMedic = client;
                teams[team].TeamBiggestAdvantage =
                    fmax(teams[team].TeamBiggestAdvantage,
                        medic[oppclient].MedicTimeToUber - medic[client].MedicTimeToUber);
            }

            if (TeamHasUber(oppteam) && teams[team].TeamAdvantageMedic != 0) {
                // If the team has had an uber advantage, and the opposing team has gotten uber in the meantime, remember the uber advantage loss.

                LogLostUberAdvantage(teams[team].TeamAdvantageMedic, teams[team].TeamBiggestAdvantage);
                if (ShouldPrintToSTV()) {
                    CPrintToSTV("{default}[STV Stats] %s{default} lost their uber advantage of %s%.0f seconds{default}",
                                 team == TFTeam_Red ? "{red}RED" : "{blue}BLU",
                                 team == TFTeam_Red ? "{red}" : "{blue}",
                                 teams[team].TeamBiggestAdvantage);
                }

                ResetAdvantage(teams[team].TeamAdvantageMedic);
            }
        }
    }

    return Plugin_Continue;
}

void CollectBuffs() {
    g_fLastCollectBuffs = GetGameTime();

    // Log the recorded buffs.
    for (int healer = 1; healer <= MaxClients; healer++)
        FlushBuffs(healer);
}

void FlushBuffs(int healer) {
    if (g_iBuffed[healer] <= 0)
        return;
    int patient = g_iBuffedPatient[healer];
    if (IsRealPlayer2(healer) && IsRealPlayer(patient))
        LogHealed(patient, healer, g_iBuffed[healer]);
    g_iBuffed[healer] = 0;
}

public MRESReturn Hook_TakeHealth_Pre(int patient, DHookReturn hReturn, DHookParam hParams) {
    g_iHealthBeforeHeal[patient] = GetClientHealth(patient);
    return MRES_Ignored;
}

public MRESReturn Hook_TakeHealth_Post(int patient, DHookReturn hReturn, DHookParam hParams) {
    if (!g_bLogBuffs)
        return MRES_Ignored;

    if (!IsRealPlayer(patient) || !IsPlayerAlive(patient))
        return MRES_Ignored;

    int oldhealth = g_iHealthBeforeHeal[patient];
    int newhealth = GetClientHealth(patient);
    if (newhealth <= oldhealth)
        return MRES_Ignored;

    // Find the medics whose beam is on the patient.
    int healers[MAXPLAYERS];
    int numHealers = 0;
    for (int healer = 1; healer <= MaxClients; healer++) {
        if (!IsRealPlayer(healer) || !IsPlayerAlive(healer) || TF2_GetPlayerClass(healer) != TFClass_Medic)
            continue;
        if (TF2_GetHealingTarget(healer) != patient)
            continue;
        if (GetClientTeam(patient) != GetClientTeam(healer))
            continue; // Enemy spies can be healed, but the game does not log heals to them, so don't log buffs to them either.

        if (g_iBeamTarget[healer] != patient) {
            // The beam just attached.
            g_iBeamTarget[healer] = patient;
            g_iBuffHighest[patient] = oldhealth;
        }
        healers[numHealers++] = healer;
    }
    if (numHealers == 0)
        return MRES_Ignored;

    // If the patient got buffed (above max health) higher than they have been since the beam attached or since they
    // last took damage, record it. Only counting new highs ignores the decay/re-heal loop at the overheal cap.
    int highest = g_iBuffHighest[patient];
    if (newhealth <= highest)
        return MRES_Ignored;
    g_iBuffHighest[patient] = newhealth;
    if (newhealth - oldhealth > MAX_BEAM_HEAL_PER_CALL)
        return MRES_Ignored; // Too much for a medigun in one heal, so it came from something else

    int maxHealth = GetMaxHealth(patient);
    if (maxHealth == -1 || newhealth <= maxHealth)
        return MRES_Ignored;
    int buffStart = oldhealth;
    if (buffStart < highest)
        buffStart = highest;
    if (buffStart < maxHealth)
        buffStart = maxHealth;
    int buff = newhealth - buffStart;

    // When several medics heal the same patient, split the buff between them.
    for (int i = 0; i < numHealers; i++) {
        int healer = healers[i];
        int amount = buff / numHealers + (i < buff % numHealers ? 1 : 0);
        if (amount <= 0)
            continue;
        if (g_iBuffedPatient[healer] != patient) {
            // The medic switched patient. Log the buffs given to the previous patient.
            FlushBuffs(healer);
            g_iBuffedPatient[healer] = patient;
        }
        g_iBuffed[healer] += amount;
    }

    return MRES_Ignored;
}

// -----------------------------------
// Log functions
// -----------------------------------
void LogFirstHeal(int healer, float time) {
    char healerStr[256];
    GetPlayerLogStr(healer, healerStr, sizeof(healerStr));

    LogToGame("\"%s\" triggered \"first_heal_after_spawn\" (time \"%.1f\")", healerStr, time);
}

void LogUberReady(int healer) {
    char healerStr[256];
    GetPlayerLogStr(healer, healerStr, sizeof(healerStr));

    LogToGame("\"%s\" triggered \"chargeready\"", healerStr);
}

void LogMedicDeath(int healer, int pct) {
    char healerStr[256];
    GetPlayerLogStr(healer, healerStr, sizeof(healerStr));

    LogToGame("\"%s\" triggered \"medic_death_ex\" (uberpct \"%i\")", healerStr, pct);
}

void LogEmptyUber(int healer) {
    char healerStr[256];
    GetPlayerLogStr(healer, healerStr, sizeof(healerStr));

    LogToGame("\"%s\" triggered \"empty_uber\"", healerStr);
}

void LogUberLength(int healer, float uberLength) {
    char healerStr[256];
    GetPlayerLogStr(healer, healerStr, sizeof(healerStr));

    LogToGame("\"%s\" triggered \"chargeended\" (duration \"%.1f\")", healerStr, uberLength);
}

void LogLostUberAdvantage(int healer, float uberAdvSeconds) {
    char healerStr[256];
    GetPlayerLogStr(healer, healerStr, sizeof(healerStr));

    LogToGame("\"%s\" triggered \"lost_uber_advantage\" (time \"%.0f\")", healerStr, uberAdvSeconds);
}



// Borrowed from supstats.sp
void LogHealed(int patient, int healer, int amount) {
    char healerStr[256];
    char patientStr[256];
    GetPlayerLogStr(healer, healerStr, sizeof(healerStr));
    GetPlayerLogStr(patient, patientStr, sizeof(patientStr));

    LogToGame("\"%s\" triggered \"healed\" against \"%s\" (healing \"%d\")", healerStr, patientStr, amount);
}
