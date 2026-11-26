/*
Release notes:

---- 2.0.0 (23/12/2013) ----
- Logs damage and real damage per weapon
- Logs damage taken
- Logs airshots
- Logs self-healing (eg. by blackbox)
- Logs headshots (not just headshot kills)
- Logs medkit pickups including amount of healing
- Logs which medigun is used when ubering
- Logs crits and mini crits
- Logs non-buffed heals (as in v1)
- Logs ammo pickups (as in v1)
- Logs players spawning (as in v1)
- Logs game pauses (as in v1)


---- 2.1.0 (01/01/2014) ----
- NEW: Accuracy Stats
- Rocket jumping and building uber does not affect accuracy
- Clearing stickies does not affect accuracy
- Post-mortem damage now correctly logged (it sometimes wrote "Player" as weapon)
- Fixed spy backstabs sometimes counting as taunt kills
- Minimum airshot distance-to-ground changed from 80 to 170 units
- Minor bug fixes


---- 2.1.1 (28/01/2014) ----
- Fixed SteamIDs sometimes being wrong in the logs


---- 2.1.2 (01/02/2014) ----
- Fixed minicrits being logged as normal crits


---- 2.2.0 (26/07/2014) ----
- Added accuracy for Crusaders Crossbow. Hitting a teammate also counts as a hit.
- Added accuracy for Stickybombs. Stickyjumping and building uber doesn't affect accuracy.
- Fixed a minor bug with "pause" logs


---- 2.2.1 (31/07/2014) ----
- Fixed crash on startup caused by the latest TF2 update


---- 2.2.2 (25/08/2014) ----
- Fixed problem with snapshot version of SourceMod (regarding new SteamID format)


---- 2.2.3 (03/07/2015) ----
- Fixed bugs introduced by Gun Mettle update


---- 2.3.0 (21/10/2015) ----
- Fixed skinned mediguns being logged as 'unknown'
- Fixed skinned weapons being logged as 'unknown'
- Added accuracy for revolver


---- 2.3.1 (21/08/2016) ----
- Do not crash if the healer/patient is reported as 0
- Do not log self-heal


---- 2.4.0 (02/10/2022) ----
- Added pause length to logs
- Fixed 'pause' logs being wrong
- Fixed SM error logs when picking up medpacks


---- 2.5.0 (15/10/2022) ----
- Added logs for crossbow airshots - by Bv


---- 2.5.1 (21/03/2023) ----
- Added height prop to airshot logs - by Bv
- Switched to using HullRayTracing to eliminate edge-cases - by Bv


---- 2.5.2 (23/04/2023) ----
- Removed 'spawned as unknown' log
- Internal updates - by Leigh MacDonald


---- 2.5.3 (13/08/2024) ----
- Prevent script execution timeout on startup


---- 2.5.4 (14/07/2025) ----
- Updated code to be compatible with SourceMod 1.12


---- 2.6.0 (19/07/2025) ----
- Log meta data at the start of the match (matchid, map, title)


---- 2.6.1 (27/07/2025) ----
- Fixed unnecessary tournament restart when server is almost empty


---- 2.6.2 (08/09/2025) ----
- Added accuracy logs for alternative scout weapons - by s-maurice


---- 3.0.0 (20/11/2026) ----
- Correctly logs deflected projectiles now
- Correctly logs taunt damage now
- Now logs when a medic picks up a medigun
- Now logs plugin version meta data
- Fixed crossbow heals logging the potential heal amount instead of the actual heal amount
- Fixed cannonball accuracy logs
- Fixed telefrags being logged as taunts
- Fixed bleed damage logs
- Fixed Black Box healing being estimated imprecisely
- Fixed bug where medic airshot could wrongly be logged on a heal event
- Fixed bug where lit huntsman headshots counted as multiple headshots on the following burn ticks
- Fixed rare bug where an airshot was incorrectly detected after touching a grenade roller
- Fixed rare bug where a sentry rocket from a destroyed sentry was logged incorrectly
- Fixed rare bug where a rocket jump could be counted as a missed shot
- Fixed pauses not being logged when using setpause/unpause, or when the player left right after pausing
- Fixed detection of giger counter
- Improved detection of shooting/clearing stickies


---- 3.0.1 (23/11/2026) ----
- Added support for the civilian class in TF2 Classified - by Xinayder


---- 3.1.0 (26/11/2026) ----
- Log attacker and victim positions on damage events


TODO:
- Use GetGameTime() instead of GetEngineTime()?
- Write comments in code :D
- Make a separate file that deals with special weapon log-names
- It might be possible to detect the owner of a rocket using m_hOwnerEntity
*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <tf2_stocks>
#include <f2stocks>
#include <sdkhooks>
#include <smlib>
#include <kvizzle>
#include <logtitle>
#include <match>
#undef REQUIRE_PLUGIN
#include <updater>

#define PLUGIN_VERSION "3.1.0"
#define UPDATE_URL		"https://sourcemod.krus.dk/supstats2/update.txt"

#define ITEMS_TXT_PATH "scripts/items/items_game.txt"
#define MAXENTITIES 2048 // Max number of networked entities (edicts)
#define MAXWEPNAMELEN 72
#define MAXITEMCLASSLEN 64

public Plugin myinfo = {
	name = "Supplemental Stats v2",
	author = "F2 (v1 by Jean-Denis Caron)",
	description = "Logs additional information about the game.",
	version = PLUGIN_VERSION,
	url = "https://github.com/F2/F2s-sourcemod-plugins"
};


bool g_bWeaponDataInitialized = false;

bool g_bIsPaused;
bool g_bBlockLog = false;
char g_sBlockLog[64];

char lastWeaponDamage[MAXPLAYERS+1][MAXWEPNAMELEN];
char lastPostHumousWeaponDamage[MAXPLAYERS+1][MAXWEPNAMELEN]; 
float lastPostHumousWeaponDamageTime[MAXPLAYERS+1]; 
int lastHealth[MAXPLAYERS+1];
int lastHealingOnHit[MAXPLAYERS+1];
bool lastHeadshot[MAXPLAYERS+1];
bool lastAirshot[MAXPLAYERS+1]; 
int lastAirshotHeight[MAXPLAYERS+1];
int lastHealArrowPatient[MAXPLAYERS+1]; // [medic] The teammate the medic's healing arrow is touching in this frame (0 if none)
int lastHealArrowPatientHealth[MAXPLAYERS+1]; // [medic] The patient's health before the healing arrow healed them
int g_iPlayerTakenDirectHitRef[MAXPLAYERS+1]; // Entity reference of the projectile that last touched the player (0 if none)
int medpackHealAmount[MAXPLAYERS+1];
int g_iMedigunBeforePickup[MAXPLAYERS+1] = {INVALID_ENT_REFERENCE, ...}; // [medic] The medic's medigun when they pressed the key to pick up a weapon (INVALID_ENT_REFERENCE if it is not a medic trying to pick up a weapon)
float g_fUberBeforePickup[MAXPLAYERS+1]; // [medic] The medic's uber level when they pressed the key to pick up a weapon
char g_sMedigunBeforePickup[MAXPLAYERS+1][64]; // [medic] The name of the medic's medigun when they pressed the key to pick up a weapon
float g_fPauseStartTime;

// Healing from rocket launcher explosions (e.g. Black Box)
enum struct RadiusHealingInfo {
	int LastMaxHealing; // The max healing of the explosion that dealt the last damage (0 if not a healing explosion)
	int Inflictor;      // The explosion currently being accumulated, identified by the inflictor and game tick
	int Tick;
	int Damage;         // The total damage dealt to enemies by the explosion so far
	int Logged;         // The total healing logged for the explosion so far
}
RadiusHealingInfo radiusHealing[MAXPLAYERS+1];

Handle g_hTimerMatchStarted = null;
ConVar g_hCvarLogsTitle = null;
ConVar g_hCvarHostname = null,
	g_hCvarRedTeamName = null,
	g_hCvarBlueTeamName = null;


// ---- ACCURACY ----
ConVar g_hCvarEnableAccuracy = null;
bool g_bEnableAccuracy;

bool g_bIgnoreDamageEnt[MAXENTITIES]; // [entity] The projectile has already been counted as a hit

const float MAXROCKETJUMPTIME = 0.15;
float g_fRocketFiredTime[MAXPLAYERS+1];
bool g_bRocketHurtMe[MAXPLAYERS+1];
bool g_bRocketHurtEnemy[MAXPLAYERS+1];
char g_sRocketFiredLogLine[MAXPLAYERS+1][1024];

// Hitscan shots are tracked from when the weapon fires until the end of the player's PostThink. Everything below happens inside PostThink, in this order:
//   1. TF2_CalcIsAttackCritical: The weapon fires. Starts tracking the shot.
//   2. The bullets deal their damage:
//      - OnTakeDamage: An enemy player is hit. Sets g_bHitscanHurtEnemy.
//      - Event_PlayerDestroyedPipebomb: An enemy sticky is destroyed. Sets g_bHitscanDestroyedSticky.
//   3. LogHitscanShot (PostThinkPost): Logs the shot, unless it only destroyed stickies, and logs the hit.
int g_iHitscanWeapon[MAXPLAYERS+1]; // Weapon entity of the hitscan shot being fired right now, or 0 if none. Reset in PostThinkPost when the shot is logged.
bool g_bHitscanHurtEnemy[MAXPLAYERS+1];
bool g_bHitscanDestroyedSticky[MAXPLAYERS+1]; // The current hitscan shot destroyed an enemy sticky
char g_sHitscanWeapon[MAXPLAYERS+1][MAXWEPNAMELEN]; // Log name of the weapon that fired the current hitscan shot
const MAXSTICKIES = 14;
bool g_bStickyHurtMe[MAXPLAYERS+1][MAXSTICKIES];
bool g_bStickyHurtEnemy[MAXPLAYERS+1][MAXSTICKIES];
int g_iStickyId[MAXPLAYERS+1][MAXSTICKIES];

const SHOT_PROJECTILE_MIN = 0; // inclusive
const SHOT_ROCKET = 0;
const SHOT_NEEDLE = 1;
const SHOT_HEALINGBOLT = 2;
const SHOT_PIPE = 3;
const SHOT_STICKY = 4;
const SHOT_PROJECTILE_MAX = 8; // exclusive
const SHOT_HITSCAN = 16;
StringMap g_tShotTypes = null; // Using a Trie seems to be over twice as fast as StrEqual()
// ---- ACCURACY ----


public void OnPluginStart() {
	if (LibraryExists("updater"))
		Updater_AddPlugin(UPDATE_URL);
	
	Match_OnPluginStart();
	
	g_tShotTypes = CreateTrie();
	g_tShotTypes.SetValue("tf_weapon_rocketlauncher", SHOT_ROCKET);
	g_tShotTypes.SetValue("tf_weapon_particle_cannon", SHOT_ROCKET);
	g_tShotTypes.SetValue("tf_weapon_rocketlauncher_directhit", SHOT_ROCKET);
	g_tShotTypes.SetValue("tf_projectile_rocket", SHOT_ROCKET);
	g_tShotTypes.SetValue("tf_projectile_energy_ball", SHOT_ROCKET);
	
	g_tShotTypes.SetValue("tf_weapon_grenadelauncher", SHOT_PIPE);
	g_tShotTypes.SetValue("tf_weapon_cannon", SHOT_PIPE);
	g_tShotTypes.SetValue("tf_projectile_pipe", SHOT_PIPE);
	//g_tShotTypes.SetValue("tf_weapon_pipebomblauncher", SHOT_STICKY); // Should NOT be added.. causes a bug in OnEntityDestroyed
	g_tShotTypes.SetValue("tf_projectile_pipe_remote", SHOT_STICKY);
	
	g_tShotTypes.SetValue("tf_weapon_syringegun_medic", SHOT_NEEDLE);
	g_tShotTypes.SetValue("tf_weapon_crossbow", SHOT_HEALINGBOLT);
	g_tShotTypes.SetValue("tf_projectile_healing_bolt", SHOT_HEALINGBOLT);
	
	g_tShotTypes.SetValue("tf_weapon_scattergun", SHOT_HITSCAN);
	g_tShotTypes.SetValue("tf_weapon_pep_brawler_blaster", SHOT_HITSCAN);
    g_tShotTypes.SetValue("tf_weapon_handgun_scout_primary", SHOT_HITSCAN);
    g_tShotTypes.SetValue("tf_weapon_soda_popper", SHOT_HITSCAN);
	g_tShotTypes.SetValue("tf_weapon_shotgun_soldier", SHOT_HITSCAN);
	g_tShotTypes.SetValue("tf_weapon_shotgun_primary", SHOT_HITSCAN);
	g_tShotTypes.SetValue("tf_weapon_shotgun_hwg", SHOT_HITSCAN);
	g_tShotTypes.SetValue("tf_weapon_shotgun_pyro", SHOT_HITSCAN);
	g_tShotTypes.SetValue("tf_weapon_pistol_scout", SHOT_HITSCAN);
	g_tShotTypes.SetValue("tf_weapon_handgun_scout_secondary", SHOT_HITSCAN);
	g_tShotTypes.SetValue("tf_weapon_pistol", SHOT_HITSCAN);
	g_tShotTypes.SetValue("tf_weapon_smg", SHOT_HITSCAN);
	g_tShotTypes.SetValue("tf_weapon_sniperrifle", SHOT_HITSCAN);
	g_tShotTypes.SetValue("tf_weapon_revolver", SHOT_HITSCAN);
	
	g_hCvarEnableAccuracy = CreateConVar("supstats_accuracy", "1", "Enable accuracy logs");
	HookConVarChange(g_hCvarEnableAccuracy, CvarChange_EnableAccuracy);
	char cvarEnableAccuracy[16];
	g_hCvarEnableAccuracy.GetString(cvarEnableAccuracy, sizeof(cvarEnableAccuracy));
	CvarChange_EnableAccuracy(g_hCvarEnableAccuracy, cvarEnableAccuracy, cvarEnableAccuracy);

	// The "logstf_" prefix is used because we are reusing the cvar from the logstf plugin.
	// This is done to avoid having all servers defining the title format twice.
	g_hCvarLogsTitle = CreateConVar("logstf_title", "{server}: {blu} vs {red}", "Title for the log", FCVAR_NONE);
	g_hCvarHostname = FindConVar("hostname");
	g_hCvarRedTeamName = FindConVar("mp_tournament_redteamname");
	g_hCvarBlueTeamName = FindConVar("mp_tournament_blueteamname");
	
	char map[128];
	F2_GetCurrentMapDisplayName(map, sizeof(map));
	LogToGame("Loading map \"%s\"", map);

	g_fPauseStartTime = GetEngineTime(); // Just in case it is already paused

	ImportWeaponDefinitions();
}

void FinalizePluginInitialization() {
	AddGameLogHook(GameLog);

	HookEvent("item_pickup", Event_ItemPickup);
	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("player_healed", Event_PlayerHealed);
	HookEvent("player_spawn", Event_PlayerSpawned);
	HookEvent("player_destroyed_pipebomb", Event_PlayerDestroyedPipebomb);
	//HookEvent("player_healonhit", Event_PlayerHealOnHit);
	
	HookEvent("player_chargedeployed", EventPre_player_chargedeployed, EventHookMode_Pre);
	HookEvent("player_chargedeployed", Event_player_chargedeployed);

	AddCommandListener(Listener_Pause, "pause");
	AddCommandListener(Listener_Pause, "setpause");
	AddCommandListener(Listener_Pause, "unpause");

	
	for (int client = 1; client <= MaxClients; client++) {
		if (IsClientInGame(client) && !IsClientSourceTV(client)) {
			SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
			SDKHook(client, SDKHook_PostThinkPost, LogHitscanShot);
		}
	}

	g_bWeaponDataInitialized = true;

	PrintToServer("supstats2 fully initialized");
}

public void OnLibraryAdded(const char[] name) {
	// Set up auto updater
	if (StrEqual(name, "updater"))
		Updater_AddPlugin(UPDATE_URL);
}

public void OnMapStart() {
	Match_OnMapStart();

	for (int i = 0; i < sizeof(g_bIgnoreDamageEnt); i++)
		g_bIgnoreDamageEnt[i] = false;
	
	for (int client = 1; client <= MaxClients; client++) {
		g_iHitscanWeapon[client] = 0;
		for (int i = 0; i < MAXSTICKIES; i++)
			g_iStickyId[client][i] = 0;
	}
	g_bIsPaused = false; // The game is automatically unpaused during a map change
}

public void OnMapEnd() {
	Match_OnMapEnd();
}

public void OnClientPutInServer(int client) {
	if (!g_bWeaponDataInitialized)
		return;
	
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_PostThinkPost, LogHitscanShot);
	g_iHitscanWeapon[client] = 0;
	lastPostHumousWeaponDamage[client][0] = '\0';
}

public void OnPluginEnd() {
	for (int client = 1; client <= MaxClients; client++) {
		if (IsClientInGame(client) && !IsClientSourceTV(client)) {
			SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
			SDKUnhook(client, SDKHook_PostThinkPost, LogHitscanShot);
		}
	}

	RemoveGameLogHook(GameLog);
}

public void CvarChange_EnableAccuracy(Handle cvar, const char[] oldVal, const char[] newVal) {
	g_bEnableAccuracy = StringToInt(newVal) != 0;
}


public Action BlockLogLine(const char[] logline) {
	if (g_bBlockLog && (g_sBlockLog[0] == '\0' || StrContains(logline, g_sBlockLog, false) != -1))
		// If we don't use g_sBlockLog, then chargeready is sometimes blocked
		return Plugin_Handled;
	
	return Plugin_Continue;
}

public Action GameLog(const char[] message) {
	return BlockLogLine(message);
}


public Action Listener_Pause(int client, const char[] command, int argc) {
	if (client == 0)
		return Plugin_Continue; // Using "rcon pause" won't do anything
	
	CreateTimer(0.1, CheckPause, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}


public Action CheckPause(Handle timer, int userId) {
	bool isPaused = !IsServerProcessing();
	int client = GetClientOfUserId(userId);
	char userStr[256];

	if (isPaused && !g_bIsPaused) {
		g_fPauseStartTime = GetEngineTime();

		LogToGame("World triggered \"Game_Paused\"");

		if (client != 0) {
			GetPlayerLogStr(client, userStr, sizeof(userStr));
			LogToGame("\"%s\" triggered \"matchpause\"", userStr);
		}
	}
	if (!isPaused && g_bIsPaused) {
		float pauseDuration = GetEngineTime() - g_fPauseStartTime;

		LogToGame("World triggered \"Game_Unpaused\"");

		if (client != 0) {
			GetPlayerLogStr(client, userStr, sizeof(userStr));
			LogToGame("\"%s\" triggered \"matchunpause\"", userStr);
		}
		LogToGame("World triggered \"Pause_Length\" (seconds \"%.2f\")", pauseDuration);
	}

	g_bIsPaused = isPaused;
	return Plugin_Continue;
}

void StartMatch() {
}

public void StartFirstRound() {
	if (g_hTimerMatchStarted != null) {
		delete g_hTimerMatchStarted;
		g_hTimerMatchStarted = null;
	}

	// First log all the players spawning etc., and then we log the meta data.
	g_hTimerMatchStarted = CreateTimer(0.5, LogMetaData);
}

void ResetMatch() {
	if (g_hTimerMatchStarted != null) {
		delete g_hTimerMatchStarted;
		g_hTimerMatchStarted = null;
	}
}

void EndMatch(bool endedMidgame) {
	if (g_hTimerMatchStarted != null) {
		delete g_hTimerMatchStarted;
		g_hTimerMatchStarted = null;
	}
}

void LogMetaData(Handle timer) {
	g_hTimerMatchStarted = null;

    LogMatchId();
	LogMapName();
	LogTitle();
	LogPluginVersions();
}

void LogMatchId() {
	char matchId[33];
    FormatTime(matchId, sizeof(matchId), "%y%m%d%H%M%S");

    for (int i = 12; i < 32; i++) {
        int randVal = GetRandomInt(0, 61);
        if (randVal < 10) {
            matchId[i] = '0' + randVal;
        } else if (randVal < 36) {
            matchId[i] = 'a' + (randVal - 10);
        } else {
            matchId[i] = 'A' + (randVal - 36);
        }
    }
    matchId[32] = '\0';

	LogToGame("World triggered \"meta_data\" (matchid \"%s\")", matchId);
}

void LogMapName() {
	char currentMap[128];
    F2_GetCurrentMapDisplayName(currentMap, sizeof(currentMap));
    LogToGame("World triggered \"meta_data\" (map \"%s\")", currentMap);
}

void LogTitle() {
	char hostname[64];
	char bluTeamName[32];
	char redTeamName[32];

	g_hCvarHostname.GetString(hostname, sizeof(hostname));
	g_hCvarBlueTeamName.GetString(bluTeamName, sizeof(bluTeamName));
	g_hCvarRedTeamName.GetString(redTeamName, sizeof(redTeamName));
	String_Trim(hostname, hostname, sizeof(hostname));
	String_Trim(bluTeamName, bluTeamName, sizeof(bluTeamName));
	String_Trim(redTeamName, redTeamName, sizeof(redTeamName));

	ShortenHostnameForLogTitle(hostname, sizeof(hostname));

	// Replace placeholders
	char title[128];
	g_hCvarLogsTitle.GetString(title, sizeof(title));
	ReplaceLogTitlePlaceholders(title, sizeof(title), hostname, bluTeamName, redTeamName);

	ReplaceString(title, sizeof(title), "\\", "", false);

	LogToGame("World triggered \"meta_data\" (title \"%s\")", title);
}

void LogPluginVersions() {
	char properties[512] = "";
	AppendPluginVersion(properties, sizeof(properties), "supstats2", PLUGIN_VERSION);
	AppendOtherPluginVersion(properties, sizeof(properties), "medicstats", "medicstats.smx");

	LogToGame("World triggered \"meta_data\"%s", properties);
}

void AppendOtherPluginVersion(char[] properties, int maxlength, const char[] pluginName, const char[] fileName) {
	Handle plugin = FindRunningPluginByBaseFilename(fileName);
	if (plugin == null)
		return;

	char version[32];
	if (!GetPluginInfo(plugin, PlInfo_Version, version, sizeof(version)))
		return;

	AppendPluginVersion(properties, maxlength, pluginName, version);
}

// Like FindPluginByFile, but also finds the plugin if it is placed in a subfolder of the plugins folder.
Handle FindRunningPluginByBaseFilename(const char[] fileName) {
	Handle result = null;
	Handle iter = GetPluginIterator();
	while (MorePlugins(iter)) {
		Handle plugin = ReadPlugin(iter);
		if (GetPluginStatus(plugin) != Plugin_Running)
			continue;

		char path[PLATFORM_MAX_PATH];
		GetPluginFilename(plugin, path, sizeof(path));
		int slashPos = FindCharInString(path, '/', true);
		int backslashPos = FindCharInString(path, '\\', true);
		int startPos = (slashPos > backslashPos ? slashPos : backslashPos) + 1;

		if (StrEqual(path[startPos], fileName, false)) {
			result = plugin;
			break;
		}
	}
	delete iter;
	return result;
}

void AppendPluginVersion(char[] properties, int maxlength, const char[] pluginName, const char[] version) {
	Format(properties, maxlength, "%s (plugin_version_%s \"%s\")", properties, pluginName, version);
}

public Action Event_PlayerHealed(Event event, const char[] name, bool dontBroadcast) {
	char patientStr[256];
	char healerStr[256];
	char strAirshot[64] = "";

	int patientId = event.GetInt("patient");
	int healerId = event.GetInt("healer");
	int patient = GetClientOfUserId(patientId);
	int healer = GetClientOfUserId(healerId);
	int amount = event.GetInt("amount");
	
	if (lastAirshot[healer]) {
		Format(strAirshot, sizeof(strAirshot), " (airshot \"1\") (height \"%i\")", lastAirshotHeight[healer]);
		lastAirshot[healer] = false;
	}

	if (healer == 0 && patient != 0) {
		// Healed by a medpack
		medpackHealAmount[patient] = amount;
		return Plugin_Continue;
	}

	if (patient == 0 || healer == 0) {
		// This has been observed to happen by http://www.teamfortress.tv/post/631052/medicstats-sourcemod-plugin
		LogMessage("Wrong player-healed event detected: patient=%i/%i, healer=%i/%i, amount=%i", patientId, patient, healerId, healer, amount);
		return Plugin_Continue;
	}

	if (patient == healer) {
		// Do not log self-heal
		return Plugin_Continue;
	}

	if (lastHealArrowPatient[healer] == patient) {
		// The game reports the healing arrow's full heal amount, even if the patient was missing less health.
		// Healing arrows do not overheal, so limit the amount to the health the patient was missing.
		lastHealArrowPatient[healer] = 0;
		int maxHealth = GetMaxHealth(patient);
		if (maxHealth != -1) {
			amount = min(amount, maxHealth - lastHealArrowPatientHealth[healer]);
			if (amount <= 0)
				return Plugin_Continue;
		}
	}

	GetPlayerLogStr(healer, healerStr, sizeof(healerStr));
	GetPlayerLogStr(patient, patientStr, sizeof(patientStr));

	LogToGame("\"%s\" triggered \"healed\" against \"%s\" (healing \"%d\")%s",
		healerStr,
		patientStr,
		amount,
		strAirshot);
	
	return Plugin_Continue;
}




//public void Event_PlayerHealOnHit(Event event, const string name[], bool dontBroadcast) {
//	PrintToChatAll("heal on hit - amount(%i) client(%i)", event.GetInt("amount"), event.GetInt("entindex"));
//}

public void Event_PlayerSpawned(Event event, const char[] name, bool dontBroadcast) {
	char playerStr[256];

	int client = GetClientOfUserId(event.GetInt("userid"));
	int clss = event.GetInt("class");

	if (!IsRealPlayer(client))
		return; // eg. SourceTV
	
	if (clss <= 0 || clss >= sizeof(g_sClassNamesLower))
		return; // It has been observed that clss can be 0 and triggered BEFORE "user entered game"
	
	for (int i = 0; i < MAXSTICKIES; i++)
		g_iStickyId[client][i] = 0;
	
	GetPlayerLogStr(client, playerStr, sizeof(playerStr));
	LogToGame("\"%s\" spawned as \"%s\"", playerStr, g_sClassNamesLower[clss]);
}


// "%s<%i><%s><%s>" triggered "chargedeployed" (medigun "%s")
public void EventPre_player_chargedeployed(Event event, const char[] name, bool dontBroadcast) {
	g_bBlockLog = true;
	strcopy(g_sBlockLog, sizeof(g_sBlockLog), "chargedeployed");
}

public void Event_player_chargedeployed(Event event, const char[] name, bool dontBroadcast) {
	g_bBlockLog = false;
	g_sBlockLog = "";
	
	char playerStr[256];
	char medigun[64];

	int client = GetClientOfUserId(event.GetInt("userid"));
	GetPlayerLogStr(client, playerStr, sizeof(playerStr));
	GetMedigunName(client, medigun, sizeof(medigun));


	LogToGame("\"%s\" triggered \"chargedeployed\" (medigun \"%s\")", playerStr, medigun);
}

void GetMedigunName(int client, char[] medigun, int medigunLen) {
	int weaponid = GetPlayerWeaponSlot(client, 1);
	if (weaponid >= 0) {
		int healing;
		bool postHumousDamage;
		int defid;
		if (GetWeaponLogName(medigun, medigunLen, client, weaponid, healing, defid, postHumousDamage, client)) {
			// We found the weapon
		} else {
			strcopy(medigun, medigunLen, "unknown");
		}
	} else {
		strcopy(medigun, medigunLen, "");
	}
}

// The key for using the action item also picks up the weapon the player is looking at (e.g. a medigun dropped by a dead medic).
// The client sends it as a KeyValues command ("+use_action_slot_item_server"), and TF2 does the pickup while handling it.
// We do not read the KeyValues, since that crashes TF2 servers running SourceMod builds from before October 2026 (https://github.com/alliedmodders/sourcemod/issues/2587).
// Instead we check all KeyValues commands, as they are rare and only the pickup changes the medic's medigun.
public Action OnClientCommandKeyValues(int client, KeyValues kv) {
	g_iMedigunBeforePickup[client] = INVALID_ENT_REFERENCE;

	if (!g_bWeaponDataInitialized)
		return Plugin_Continue;

	if (!IsRealPlayer(client) || !IsPlayerAlive(client) || TF2_GetPlayerClass(client) != TFClass_Medic)
		return Plugin_Continue;

	int medigunRef = INVALID_ENT_REFERENCE;
	float uberPct = TF2_GetPlayerUberLevel(client, medigunRef);
	if (medigunRef == INVALID_ENT_REFERENCE)
		return Plugin_Continue;

	g_iMedigunBeforePickup[client] = medigunRef;
	g_fUberBeforePickup[client] = uberPct;
	GetMedigunName(client, g_sMedigunBeforePickup[client], sizeof(g_sMedigunBeforePickup[]));

	return Plugin_Continue;
}

public void OnClientCommandKeyValues_Post(int client, KeyValues kv) {
	int medigunBefore = g_iMedigunBeforePickup[client];
	g_iMedigunBeforePickup[client] = INVALID_ENT_REFERENCE;

	if (medigunBefore == INVALID_ENT_REFERENCE)
		return;

	if (!IsPlayerAlive(client))
		return;

	int medigunRef = INVALID_ENT_REFERENCE;
	float uberPct = TF2_GetPlayerUberLevel(client, medigunRef);
	if (medigunRef == INVALID_ENT_REFERENCE || medigunRef == medigunBefore)
		return; // The medic did not pick up a medigun

	char playerStr[256];
	char medigun[64];
	GetPlayerLogStr(client, playerStr, sizeof(playerStr));
	GetMedigunName(client, medigun, sizeof(medigun));

	LogToGame("\"%s\" triggered \"medigun_pickup\" (medigun \"%s\") (uberpct \"%i\") (previous_medigun \"%s\") (previous_uberpct \"%i\")",
		playerStr,
		medigun,
		RoundToFloor(uberPct * 100.0),
		g_sMedigunBeforePickup[client],
		RoundToFloor(g_fUberBeforePickup[client] * 100.0));
}


// Medkit pickup with healing
public void Event_ItemPickup(Event event, const char[] name, bool dontBroadcast) {
	char item[64];
	event.GetString("item", item, sizeof(item));
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	
	if (strncmp(item, "medkit_", 7, true) == 0 && medpackHealAmount[client] != 0) {
		LogItemPickup(userid, item, medpackHealAmount[client]);
		medpackHealAmount[client] = 0;
		return;
	}
	
	LogItemPickup(userid, item);
}

void LogItemPickup(int userid, char[] item, int healing = 0) {
	char playerStr[256];
	char strHealing[64] = "";

	int client = GetClientOfUserId(userid);
	GetPlayerLogStr(client, playerStr, sizeof(playerStr));

	if (healing != 0)
		FormatEx(strHealing, sizeof(strHealing), " (healing \"%i\")", healing);

	LogToGame("\"%s\" picked up item \"%s\"%s", playerStr, item, strHealing);
}



int FindStickySpot(int client, int inflictor, bool mayCreate = false) {
	int emptyStickyPos = -1, foundStickyPos = -1;
	for (int i = 0; i < MAXSTICKIES; i++) {
		if (g_iStickyId[client][i] == inflictor) {
			foundStickyPos = i;
			break;
		}
		if (emptyStickyPos == -1 && g_iStickyId[client][i] == 0)
			emptyStickyPos = i;
	}
	
	if (foundStickyPos == -1 && mayCreate) {
		if (emptyStickyPos == -1) {
			LogError("Could not find empty sticky pos for player %i", client);
		} else {
			foundStickyPos = emptyStickyPos;
			g_bStickyHurtMe[client][foundStickyPos] = false; // no need - it is set below
			g_bStickyHurtEnemy[client][foundStickyPos] = false;
			g_iStickyId[client][foundStickyPos] = inflictor;
		}
	}
	
	return foundStickyPos;
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom) {
	// Only count it as a direct hit if the projectile that touched the player is the one dealing the damage
	bool wasDirect = g_iPlayerTakenDirectHitRef[victim] != 0 && inflictor > MaxClients && g_iPlayerTakenDirectHitRef[victim] == EntIndexToEntRef(inflictor);
	g_iPlayerTakenDirectHitRef[victim] = 0; // Make sure to reset it before leaving the function
	
	if (victim == attacker) {
		if (g_bEnableAccuracy && IsRealPlayer(attacker) && inflictor > MaxClients) {
			TFClassType cls = TF2_GetPlayerClass(attacker);
			if (cls == TFClass_Soldier) {
				if (g_fRocketFiredTime[attacker] >= GetEngineTime() - MAXROCKETJUMPTIME) {
					char entityName[32];
					GetEntityClassname(inflictor, entityName, sizeof(entityName));
					int shotType;
					if (g_tShotTypes.GetValue(entityName, shotType) && shotType == SHOT_ROCKET)
						g_bRocketHurtMe[attacker] = true;
				}
			} else if (cls == TFClass_DemoMan) {
				if (inflictor > MaxClients) {
					char entityName[32];
					GetEntityClassname(inflictor, entityName, sizeof(entityName));
					int shotType;
					if (g_tShotTypes.GetValue(entityName, shotType) && shotType == SHOT_STICKY) {
						int stickyPos = FindStickySpot(attacker, inflictor, true);
						
						if (stickyPos != -1) {
							g_bStickyHurtMe[attacker][stickyPos] = true;
						}
					}
				}
			}
		}
		return Plugin_Continue;
	}
	if (!(victim > 0 && victim <= MaxClients && attacker > 0 && attacker <= MaxClients))
		return Plugin_Continue;
	if (!IsPlayerAlive(victim))
		return Plugin_Continue; // Sometimes this function is triggered even for dead players.
	
	int attackerTeam = GetClientTeam(attacker);
	int victimTeam = GetClientTeam(victim);
	if (attackerTeam == victimTeam)
		return Plugin_Continue; // The function is triggered for team mates too
	
	TFClassType attackerClass = TF2_GetPlayerClass(attacker);
	lastHealingOnHit[attacker] = 0;
	radiusHealing[attacker].LastMaxHealing = 0;
	lastHealth[attacker] = GetClientHealth(attacker);
	lastHeadshot[attacker] = false;
	lastAirshot[attacker] = false;

	lastWeaponDamage[attacker][0] = '\0';
	
	
	//char strDamagetype[33], strDamagecustom[33];
	//IntToBits(damagetype, strDamagetype);
	//IntToBits(damagecustom, strDamagecustom);
	//PrintToChatAll("vic(%i) att(%i) infl(%i) weap(%i) dmg(%.0f) dmgtype(%s) dmgcus(%s)", victim, attacker, inflictor, weapon, damage, strDamagetype, strDamagecustom);
	
	if (damagecustom == TF_CUSTOM_TELEFRAG) {
		strcopy(lastWeaponDamage[attacker], MAXWEPNAMELEN, "telefrag");
	} else if (GetTauntLogName(lastWeaponDamage[attacker], MAXWEPNAMELEN, damagecustom)) {
		// Taunt kill
	} else {
		int healing; 
		int defid;
		bool postHumousDamage;
		if (!GetWeaponLogName(lastWeaponDamage[attacker], MAXWEPNAMELEN, attacker, weapon, healing, defid, postHumousDamage, inflictor)) {
			if (GetDamageCustomLogName(lastWeaponDamage[attacker], MAXWEPNAMELEN, attacker, damagecustom))
				return Plugin_Continue; // E.g. a Thermal Thruster stomp (it has no weapon), or bleeding after the weapon was removed

			float now = GetEngineTime();
			if (lastPostHumousWeaponDamageTime[attacker] >= now - 15.0) {
				strcopy(lastWeaponDamage[attacker], MAXWEPNAMELEN, lastPostHumousWeaponDamage[attacker]);
				lastPostHumousWeaponDamageTime[attacker] = now;
				return Plugin_Continue;
			} else {
				strcopy(lastWeaponDamage[attacker], MAXWEPNAMELEN, "unknown");
				return Plugin_Continue;
			}
		}
		
		if (healing > 0) {
			if (StrEqual(lastWeaponDamage[attacker], "blackbox")) {
				// The Black Box heals once per explosion, scaled by the total damage the explosion deals to enemies.
				// The actual damage is only known in player_hurt, so the healing is calculated there.
				radiusHealing[attacker].LastMaxHealing = healing;
				int tick = GetGameTickCount();
				if (radiusHealing[attacker].Inflictor != inflictor || radiusHealing[attacker].Tick != tick) {
					radiusHealing[attacker].Inflictor = inflictor;
					radiusHealing[attacker].Tick = tick;
					radiusHealing[attacker].Damage = 0;
					radiusHealing[attacker].Logged = 0;
				}
			} else {
				int maxHealth = GetMaxHealth(attacker);
				if (maxHealth == -1) {
					lastHealingOnHit[attacker] = healing;
				} else if (lastHealth[attacker] < maxHealth) {
					lastHealingOnHit[attacker] = min(maxHealth - lastHealth[attacker], healing);
				}
			}
		}
	
		if (attackerClass == TFClass_Sniper && GetPlayerWeaponSlot(attacker, 0) == weapon) {
			// Huntsman and sniper rifles. The Hitman's Heatmaker uses TF_CUSTOM_HEADSHOT_DECAPITATION.
			lastHeadshot[attacker] = damagecustom == TF_CUSTOM_HEADSHOT || damagecustom == TF_CUSTOM_HEADSHOT_DECAPITATION;
		} else if (defid == 61 || defid == 1006) {
			// Ambassador
			lastHeadshot[attacker] = damagecustom == TF_CUSTOM_HEADSHOT;
		}
		
		if (wasDirect && (attackerClass == TFClass_Soldier || attackerClass == TFClass_DemoMan) && GetPlayerWeaponSlot(attacker, 0) == weapon) {
			SetLastAirshotValues(attacker, victim);
		}
		
		if (attackerClass == TFClass_Medic && GetPlayerWeaponSlot(attacker, 0) == weapon) {
			if (StrEqual(lastWeaponDamage[attacker], "crusaders_crossbow")) {
				SetLastAirshotValues(attacker, victim);
			}
		}

		if (postHumousDamage) {
			// Sometimes these "Post Humous Damage" weapons can do damage AFTER you die or change class (like Boston Basher, Flamethrower, etc.)
			// Remember the weapon, and if we deal damage from an unknown weapon, then credit it to the last Post Humous Damage weapon.
			strcopy(lastPostHumousWeaponDamage[attacker], MAXWEPNAMELEN, lastWeaponDamage[attacker]);
			lastPostHumousWeaponDamageTime[attacker] = GetEngineTime();
		}
		
		
		// ---- ACCURACY ----
		if (g_bEnableAccuracy) {
			if (inflictor > MaxClients && IsValidEntity(inflictor)) {
				// Projectile shot
				
				char classname[128];
				GetEntityClassname(inflictor, classname, sizeof(classname));
				
				int shotType;
				if (g_tShotTypes.GetValue(classname, shotType)) {
					// The class checks are required to avoid pyros getting a shot_hit on a reflect rocket, without any shot_fired.
					bool isRocket = shotType == SHOT_ROCKET && attackerClass == TFClass_Soldier;
					bool isGrenade = shotType == SHOT_PIPE && attackerClass == TFClass_DemoMan;
					bool isSticky = shotType == SHOT_STICKY && attackerClass == TFClass_DemoMan;
					bool isNeedle = shotType == SHOT_NEEDLE && attackerClass == TFClass_Medic;
					if (isRocket || isGrenade || isNeedle) {
						if (isNeedle || !g_bIgnoreDamageEnt[inflictor]) {
							if (!isNeedle)
								g_bIgnoreDamageEnt[inflictor] = true;

							if (isRocket) {
								g_bRocketHurtEnemy[attacker] = true;
								LogHit(attacker, lastWeaponDamage[attacker]);
							} else if (isGrenade)
								LogHit(attacker, lastWeaponDamage[attacker]);
							else if (isNeedle)
								LogHit(attacker, lastWeaponDamage[attacker]);
						}
					} else if (isSticky) {
						int stickyPos = FindStickySpot(attacker, inflictor, true);
						
						if (stickyPos != -1) {
							g_bStickyHurtEnemy[attacker][stickyPos] = true;
						}
					}
				}
			} else if (inflictor > 0 && inflictor <= MaxClients && IsValidEntity(weapon)) {
				if (inflictor == attacker && g_iHitscanWeapon[attacker] == weapon && (damagetype & (DMG_BULLET | DMG_BUCKSHOT)))
					g_bHitscanHurtEnemy[attacker] = true;
			} else {
				char attackerName[64];
				char victimName[64];
				GetClientName(attacker, attackerName, sizeof(attackerName));
				GetClientName(victim, victimName, sizeof(victimName));
				LogError("Accuracy: attacker(%s) victim(%s) inflictor(%i) weapon(%i) defid(%i)", attackerName, victimName, inflictor, weapon, defid);
			}
		}
		// ---- ACCURACY ----

		// Done last, so the code above still sees the weapon's name. E.g. a deflected Black Box rocket heals the pyro, and a Loose Cannon impact can be an airshot.
		// The kind of damage takes priority over deflects, like in TF2 (e.g. a deflected Sandman ball is still "ball").
		if (!GetDamageCustomLogName(lastWeaponDamage[attacker], MAXWEPNAMELEN, attacker, damagecustom))
			GetDeflectedLogName(lastWeaponDamage[attacker], MAXWEPNAMELEN, inflictor, damagecustom);
	}
	
	return Plugin_Continue;
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int damage = event.GetInt("damageamount");

	bool crit = event.GetBool("crit");
	bool minicrit = event.GetBool("minicrit");

	if (victim != attacker && attacker != 0) {
		char attackerStr[256];
		char victimStr[256];
		GetPlayerLogStr(attacker, attackerStr, sizeof(attackerStr));
		GetPlayerLogStr(victim, victimStr, sizeof(victimStr));

		char strHealing[32] = "";
		char strCrit[32] = "";
		char strRealDamage[32] = "";
		char strHeadshot[32] = "";
		char strAirshot[64] = "";

		int healing = lastHealingOnHit[attacker];
		if (radiusHealing[attacker].LastMaxHealing > 0) {
			healing = GetRocketLauncherRadiusHealing(attacker, damage);
			radiusHealing[attacker].LastMaxHealing = 0; // Make sure the damage is only counted once
		}
		if (healing != 0 && IsPlayerAlive(attacker))
			FormatEx(strHealing, sizeof(strHealing), " (healing \"%i\")", healing);
		
		if (minicrit)
			strcopy(strCrit, sizeof(strCrit), " (crit \"mini\")");
		else if (crit)
			strcopy(strCrit, sizeof(strCrit), " (crit \"crit\")");
		
		// When a person with 20 health takes 50 damage, his health will be -30.
		// So the real damage done is 50 + (-30) = 20.
		int clienthealth = GetClientHealth(victim);
		int realdamage = damage;
		if (clienthealth < 0) {
			realdamage += clienthealth;
			FormatEx(strRealDamage, sizeof(strRealDamage), " (realdamage \"%i\")", realdamage);
		}
		
		if (lastHeadshot[attacker])
			strcopy(strHeadshot, sizeof(strHeadshot), " (headshot \"1\")");
		
		if (lastAirshot[attacker]) {
			Format(strAirshot, sizeof(strAirshot), " (airshot \"1\") (height \"%i\")", lastAirshotHeight[attacker]);
			lastAirshot[attacker] = false;
		}

		// Remember: The attacker can be dead!
		float attackerPosition[3], victimPosition[3];
		GetClientAbsOrigin(attacker, attackerPosition);
		GetClientAbsOrigin(victim, victimPosition);

		LogToGame("\"%s\" triggered \"damage\" against \"%s\" (damage \"%d\")%s (weapon \"%s\")%s%s%s%s (attacker_position \"%d %d %d\") (victim_position \"%d %d %d\")",
			attackerStr,
			victimStr,
			damage,
			strRealDamage,
			lastWeaponDamage[attacker],
			strHealing,
			strCrit,
			strAirshot,
			strHeadshot,
			RoundToZero(attackerPosition[0]), RoundToZero(attackerPosition[1]), RoundToZero(attackerPosition[2]),
			RoundToZero(victimPosition[0]), RoundToZero(victimPosition[1]), RoundToZero(victimPosition[2]));
	}
}

// Calculates the healing from a rocket launcher explosion (e.g. Black Box) the same way as CTFGameRules::RadiusDamage does it.
// Only works for weapons with the item class tf_weapon_rocketlauncher, since it uses their base damage.
// The game heals once after the explosion has damaged everyone, so the healing is split over the damage events of the explosion.
// That way the healing logged for the explosion adds up to the actual healing.
int GetRocketLauncherRadiusHealing(int attacker, int damage) {
	radiusHealing[attacker].Damage += damage;

	// The max healing is scaled by the total damage relative to the weapon's base damage
	const float ROCKETLAUNCHER_BASE_DAMAGE = 90.0;
	float scale = float(radiusHealing[attacker].Damage) / ROCKETLAUNCHER_BASE_DAMAGE;
	if (scale > 1.0)
		scale = 1.0;
	int totalHealing = RoundToZero(float(radiusHealing[attacker].LastMaxHealing) * scale);

	// The player cannot be healed above max health. The attacker's health does not change until the explosion has damaged everyone.
	int maxHealth = GetMaxHealth(attacker);
	if (maxHealth != -1)
		totalHealing = min(totalHealing, max(maxHealth - lastHealth[attacker], 0));

	int healing = totalHealing - radiusHealing[attacker].Logged;
	radiusHealing[attacker].Logged = totalHealing;
	return healing;
}

public void OnProjectileTouch(int entity, int other) {
	if (other > 0 && other <= MaxClients) {
		g_iPlayerTakenDirectHitRef[other] = EntIndexToEntRef(entity);
	}
}


// ---- ACCURACY ----
public void OnEntityCreated(int entity, const char[] classname) {
	int shotType;
	if (!g_tShotTypes.GetValue(classname, shotType))
		return;

	if (!F2_String_StartsWith(classname, "tf_projectile_"))
		return; // g_tShotTypes also contains weapons, which we don't want to hook

	if (shotType == SHOT_ROCKET || shotType == SHOT_PIPE) {
		SDKHook(entity, SDKHook_Touch, OnProjectileTouch); // Detecting direct hits
	} else if (shotType == SHOT_HEALINGBOLT) {
		SDKHook(entity, SDKHook_Touch, OnHealArrowTouch); // Detecting when a healing arrow hits
	}
}

public void Event_PlayerDestroyedPipebomb(Event event, const char[] name, bool dontBroadcast) {
	// TF2 fires this event while the bullets deal damage, so if a hitscan shot is being tracked, that shot destroyed the sticky.
	// Melee hits and sentry bullets also fire this event, but never while a hitscan shot is being tracked.
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client != 0 && g_iHitscanWeapon[client] != 0)
		g_bHitscanDestroyedSticky[client] = true;
}

public void OnHealArrowTouch(int entity, int other) {
	if (other > 0 && other <= MaxClients) {
		TFTeam team = TF2_GetClientTeam(other);
		if (team == TFTeam_Red || team == TFTeam_Blue) { // Ignore if we hit a spectator. (This check might not be necessary.)
			int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
			if (IsClientValid(owner) && TF2_GetPlayerClass(owner) == TFClass_Medic) {
				int weapon = GetEntPropEnt(entity, Prop_Send, "m_hLauncher");
				if (IsValidEntity(weapon)) {
					// Enables logging of airshots for healing arrows
					lastAirshot[owner] = false;
					SetLastAirshotValues(owner, other);
					if (lastAirshot[owner]) {
						// The heal/damage event that consumes the airshot is fired while processing this touch.
						// If no such event fires (e.g. the teammate was at full health), clear it so it doesn't leak to the next event.
						RequestFrame(ClearHealArrowAirshot, owner);
					}

					// Used to compute the actual healing amount. The heal event is fired while processing this touch.
					lastHealArrowPatient[owner] = other;
					lastHealArrowPatientHealth[owner] = GetClientHealth(other);
					RequestFrame(ClearHealArrowPatient, owner);

					if (g_bEnableAccuracy) {
						int healing;
						int defid;
						bool postHumousDamage;
						char weap[64];
						weap[0] = '\0';
						if (GetWeaponLogName(weap, sizeof(weap), owner, weapon, healing, defid, postHumousDamage, entity)) {
							LogHit(owner, weap);
						}
					}
				}
			}
		}
	}
}

public void ClearHealArrowAirshot(int client) {
	lastAirshot[client] = false;
}

public void ClearHealArrowPatient(int client) {
	lastHealArrowPatient[client] = 0;
}

public void OnEntityDestroyed(int entity) {
	if (entity <= MaxClients)
		return;
	
	g_bIgnoreDamageEnt[entity] = false;
	
	if (g_bEnableAccuracy) {
		char clsname[32];
		GetEntityClassname(entity, clsname, sizeof(clsname));
		int shotType;
		if (g_tShotTypes.GetValue(clsname, shotType) && shotType == SHOT_STICKY) {
			int owner = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
			if (IsRealPlayer(owner)) { // Check that the owner didn't disconnect
				int stickyPos = FindStickySpot(owner, entity);
				
				bool shot = true;
				bool hit = false;
				if (stickyPos != -1) {
					hit = g_bStickyHurtEnemy[owner][stickyPos];
					if (!hit)
						shot = !g_bStickyHurtMe[owner][stickyPos];
					
					g_iStickyId[owner][stickyPos] = 0;
				}
				
				if (shot || hit) {
					char weap[64];
					weap[0] = '\0';
					int healing;
					int defid;
					bool postHumousDamage;
					int weapon = GetEntPropEnt(entity, Prop_Send, "m_hLauncher"); // The owner may have died or changed class, so don't look at the owner's current weapon
					// If the launcher was removed (e.g. the owner switched sticky launcher at resupply), TF2 destroys the launcher one tick before its stickies.
					// Then weapon is -1 and GetWeaponLogName returns false, so the shots are not logged. This is rare, so we accept it.
					if (GetWeaponLogName(weap, sizeof(weap), owner, weapon, healing, defid, postHumousDamage, entity)) {
						if (shot)
							LogShot(owner, weap);
						if (hit)
							LogHit(owner, weap);
					}
				}
			}
		}
	}
}


public Action LogRocketShot(Handle timer, any client) {
	if (!IsRealPlayer(client))
		return Plugin_Stop;
	
	if (!g_bRocketHurtMe[client] || g_bRocketHurtEnemy[client]) {
		LogToGame("%s", g_sRocketFiredLogLine[client]);
	}
	return Plugin_Stop;
}

public void LogHitscanShot(int client) {
	if (g_iHitscanWeapon[client] == 0)
		return;

	g_iHitscanWeapon[client] = 0;

	// PostThinkPost runs after the weapon has fired and all pellets have dealt damage.
	if (g_bHitscanHurtEnemy[client] || !g_bHitscanDestroyedSticky[client]) {
		LogShot(client, g_sHitscanWeapon[client]);
		if (g_bHitscanHurtEnemy[client])
			LogHit(client, g_sHitscanWeapon[client]);
	}
}

public Action TF2_CalcIsAttackCritical(int attacker, int weapon, char[] weaponname, bool &result) {
	if (!g_bEnableAccuracy || !g_bWeaponDataInitialized)
		return Plugin_Continue;
	
	if (attacker > 0 && attacker <= MaxClients) {
		int healing;
		int defid;
		bool postHumousDamage;
		int shotType;
		if (g_tShotTypes.GetValue(weaponname, shotType)) {
			char weap[64];
			weap[0] = '\0';
			GetWeaponLogName(weap, sizeof(weap), attacker, weapon, healing, defid, postHumousDamage, attacker); // We are setting inflictor = attacker
			
			if (shotType == SHOT_ROCKET) {
				FormatShot(attacker, weap, g_sRocketFiredLogLine[attacker], sizeof(g_sRocketFiredLogLine[]));
				g_fRocketFiredTime[attacker] = GetEngineTime();
				g_bRocketHurtMe[attacker] = false;
				g_bRocketHurtEnemy[attacker] = false;
				CreateTimer(MAXROCKETJUMPTIME, LogRocketShot, attacker, TIMER_FLAG_NO_MAPCHANGE);
			} else if (shotType == SHOT_PIPE || shotType == SHOT_NEEDLE || shotType == SHOT_HEALINGBOLT) {
				LogShot(attacker, weap);
			} else if (shotType == SHOT_HITSCAN) {
				LogHitscanShot(attacker); // Finish any previous shot before recording another one.
				g_iHitscanWeapon[attacker] = weapon;
				g_bHitscanHurtEnemy[attacker] = false;
				g_bHitscanDestroyedSticky[attacker] = false;
				strcopy(g_sHitscanWeapon[attacker], sizeof(g_sHitscanWeapon[]), weap);
			}
		}
	}
	
	return Plugin_Continue;
}





void LogShot(int attacker, const char[] weapon) {
	char logLine[512];
	FormatShot(attacker, weapon, logLine, sizeof(logLine));
	LogToGame("%s", logLine);
}

void FormatShot(int attacker, const char[] weapon, char[] dest, int destlen) {
	char attackerStr[256];
	GetPlayerLogStr(attacker, attackerStr, sizeof(attackerStr));
	FormatEx(dest, destlen, "\"%s\" triggered \"shot_fired\" (weapon \"%s\")", attackerStr, weapon);
}

void LogHit(int attacker, const char[] weapon) {
	char attackerStr[256];
	GetPlayerLogStr(attacker, attackerStr, sizeof(attackerStr));
	LogToGame("\"%s\" triggered \"shot_hit\" (weapon \"%s\")", attackerStr, weapon);
}
// ---- ACCURACY ----


void SetLastAirshotValues(int attacker, int victim) {
	if ((GetEntityFlags(victim) & (FL_ONGROUND | FL_INWATER)) == 0) {
		// The victim is in the air
		float distance = DistanceAboveGroundBox(victim);
		if (distance >= 170.0) {
			lastAirshot[attacker] = true;
			lastAirshotHeight[attacker] = RoundToFloor(distance);
		}
	}
}


float DistanceAboveGroundBox(int victim) {
	float vStart[3];
	float vDirection[3] = { 0.0, 0.0, -16384.0 };
	float vHullMins[3]  = { -24.0, -24.0, 0.0 };
	float vHullMaxs[3]  = { 24.0, 24.0, 0.0 };
	
	GetClientAbsOrigin(victim, vStart);
	float vEnd[3];
	AddVectors(vDirection, vStart, vEnd);

	Handle trace = TR_TraceHullFilterEx(vStart, vEnd, vHullMins, vHullMaxs, MASK_PLAYERSOLID, TraceEntityFilterPlayer);
	
	float distance = -1.0;
	if (TR_DidHit(trace)) {
		TR_GetEndPosition(vEnd, trace);
		distance = GetVectorDistance(vStart, vEnd, false);
	} else {
		LogError("trace error. victim %N(%d)", victim, victim);
	}
	
	delete trace;
	return distance;
}

public bool TraceEntityFilterPlayer(int entity, int contentsMask) {
	return entity > MaxClients || !entity;
}




// F2's WeaponLogName
bool GetWeaponLogName(char[] logname, int lognameLen, int attacker, int weapon, int &healing, int &defid, bool &postHumousDamage, int inflictor = -1) {
	defid = -1;
	if (IsValidEntity(weapon))
		defid = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
	//PrintToChatAll("attacker(%i) weapon(%i) inflictor(%i) defid(%i)", attacker, weapon, inflictor, defid);
	
	if (defid == -1) {
		// Weapon was -1. It is probably a sentry shooting.
		if (inflictor > MaxClients && IsValidEntity(inflictor)) {
			int sentry = inflictor;
			GetEntityClassname(sentry, logname, lognameLen);
			if (StrEqual(logname, "tf_projectile_sentryrocket")) {
				// Only level 3 sentries fire rockets. TF2 names rockets "obj_sentrygun3" even when the sentry is wrangled, since only the bullets count as wrangled.
				strcopy(logname, lognameLen, "obj_sentrygun3");
				return true;
			}

			if (StrEqual(logname, "obj_sentrygun")) {
				// Match the "killed" logs
				// - Level 1: obj_sentrygun
				// - Level 2: obj_sentrygun2
				// - Level 3: obj_sentrygun3
				// - Minisentry: obj_minisentry
				// - Wrangler: wrangler_kill (or giger_counter)

				int shield = GetEntProp(sentry, Prop_Send, "m_nShieldLevel");
				if (shield != 0) {
					// Wrangler is used (valid for sentries of all levels, and mini sentries)
					strcopy(logname, lognameLen, IsGigerCounter(GetPlayerWeaponSlot(attacker, 1)) ? "giger_counter" : "wrangler_kill");
				} else if (GetEntProp(sentry, Prop_Send, "m_bMiniBuilding", 1)) {
					// It is a mini non-wrangled sentry
					strcopy(logname, lognameLen, "obj_minisentry");
				} else {
					// It is a non-wrangled normal sentry
					int sentryLevel = GetEntProp(sentry, Prop_Send, "m_iUpgradeLevel");
					if (sentryLevel != 1) {
						logname[13] = '0' + sentryLevel;
						logname[14] = '\0';
					}
				}
				
				return true;
			}
		}
	} else if (inflictor >= 1 && inflictor <= MaxClients) {
		// Hitscan / melee
		
		bool res = WeaponFromDefid(defid, logname, lognameLen, healing, postHumousDamage);
		 
		TFClassType attackerClass = TF2_GetPlayerClass(attacker);
		
		if (StrEqual(logname, "shotgun") || StrEqual(logname, "shotgun_primary")) {		
			// Upgradable shotgun - it has the same name for all classes in items_game.txt, but not in logs.
			if (attackerClass == TFClass_Soldier) {
				strcopy(logname, lognameLen, "shotgun_soldier");
			} else if (attackerClass == TFClass_Pyro) {
				strcopy(logname, lognameLen, "shotgun_pyro");
			} else if (attackerClass == TFClass_Heavy) {
				strcopy(logname, lognameLen, "shotgun_hwg");
			} else { // Engy
				strcopy(logname, lognameLen, "shotgun_primary");
			}
			res = true;
		} else if (StrEqual(logname, "pistol")) {
			// Upgradable pistol - it has the same name for all classes in items_game.txt, but not in logs.
			if (attackerClass == TFClass_Scout) {
				strcopy(logname, lognameLen, "pistol_scout");
			} else { // Engy
				strcopy(logname, lognameLen, "pistol");
			}
			res = true;
		}
		
		return res;
	} else if ((defid <= 30 /*standard weapons*/ || (defid >= 190 && defid <= 212 /*named standard weapons*/)) && inflictor > MaxClients && IsValidEntity(inflictor)) {
		// Projectiles from standard weapons. These are named after the projectile.
		GetEntityClassname(inflictor, logname, lognameLen);
		
		if (StrContains(logname, "tf_weapon_") == 0)
			strcopy(logname, lognameLen, logname[10]);
		
		return true;
	} else {
		// Projectiles from non-standard weapons. These are named after the weapon.
		bool res = WeaponFromDefid(defid, logname, lognameLen, healing, postHumousDamage);

		if (res && StrEqual(logname, "compound_bow") && inflictor > MaxClients && IsValidEntity(inflictor)) {
			// Huntsmen without an item_logname (the Huntsman, Festive Huntsman and Fortified Compound) are named after the arrow, like standard weapons
			GetEntityClassname(inflictor, logname, lognameLen);
		}

		return res;
	}
	
	return false;
}

// TF2 names some kinds of damage after the kind of damage instead of the weapon (see CTFGameRules::GetKillingWeaponName).
// Returns false and leaves logname unchanged for other kinds of damage.
bool GetDamageCustomLogName(char[] logname, int lognameLen, int attacker, int damagecustom) {
	if (damagecustom == TF_CUSTOM_BLEEDING) {
		strcopy(logname, lognameLen, "bleed_kill");
	} else if (damagecustom == TF_CUSTOM_BASEBALL) {
		strcopy(logname, lognameLen, "ball"); // Sandman and Wrap Assassin
	} else if (damagecustom == TF_CUSTOM_STICKBOMB_EXPLOSION) {
		strcopy(logname, lognameLen, "ullapool_caber_explosion");
	} else if (damagecustom == TF_CUSTOM_COMBO_PUNCH) {
		strcopy(logname, lognameLen, "robot_arm_combo_kill");
	} else if (damagecustom == TF_CUSTOM_CANNONBALL_PUSH) {
		strcopy(logname, lognameLen, "loose_cannon_impact");
	} else if (damagecustom == TF_CUSTOM_DRAGONS_FURY_BONUS_BURNING) {
		strcopy(logname, lognameLen, "dragons_fury_bonus");
	} else if (damagecustom == TF_CUSTOM_BOOTS_STOMP) {
		strcopy(logname, lognameLen, TF2_IsPlayerInCondition(attacker, TFCond_RocketPack) ? "rocketpack_stomp" : "mantreads");
	} else {
		return false;
	}

	return true;
}

// TF2 names taunt kills after the taunt instead of the weapon (see CTFGameRules::GetKillingWeaponName).
// Returns false and leaves logname unchanged if the damage is not from a taunt.
bool GetTauntLogName(char[] logname, int lognameLen, int damagecustom) {
	if (damagecustom == TF_CUSTOM_TAUNT_HADOUKEN) {
		strcopy(logname, lognameLen, "taunt_pyro");
	} else if (damagecustom == TF_CUSTOM_TAUNT_HIGH_NOON) {
		strcopy(logname, lognameLen, "taunt_heavy");
	} else if (damagecustom == TF_CUSTOM_TAUNT_GRAND_SLAM) {
		strcopy(logname, lognameLen, "taunt_scout");
	} else if (damagecustom == TF_CUSTOM_TAUNT_BARBARIAN_SWING) {
		strcopy(logname, lognameLen, "taunt_demoman");
	} else if (damagecustom == TF_CUSTOM_TAUNT_UBERSLICE) {
		strcopy(logname, lognameLen, "taunt_medic");
	} else if (damagecustom == TF_CUSTOM_TAUNT_FENCING) {
		strcopy(logname, lognameLen, "taunt_spy");
	} else if (damagecustom == TF_CUSTOM_TAUNT_ARROW_STAB) {
		strcopy(logname, lognameLen, "taunt_sniper");
	} else if (damagecustom == TF_CUSTOM_TAUNT_GRENADE) {
		strcopy(logname, lognameLen, "taunt_soldier"); // TF2 uses "taunt_soldier_lumbricus" if the soldier wears the Worms Gear. We ignore that.
	} else if (damagecustom == TF_CUSTOM_TAUNT_ENGINEER_SMASH) {
		strcopy(logname, lognameLen, "taunt_guitar_kill"); // Frontier Justice
	} else if (damagecustom == TF_CUSTOM_TAUNT_ENGINEER_ARM) {
		strcopy(logname, lognameLen, "robot_arm_blender_kill"); // Gunslinger
	} else if (damagecustom == TF_CUSTOM_TAUNT_ARMAGEDDON) {
		strcopy(logname, lognameLen, "armageddon"); // Rainblower
	} else if (damagecustom == TF_CUSTOM_TAUNT_ALLCLASS_GUITAR_RIFF) {
		strcopy(logname, lognameLen, "taunt_guitar_riff_kill");
	} else if (damagecustom == TF_CUSTOM_TAUNTATK_GASBLAST) {
		strcopy(logname, lognameLen, "gas_blast");
	} else if (damagecustom == TF_CUSTOM_TAUNTATK_TRICKSHOT) {
		strcopy(logname, lognameLen, "taunt_trickshot");
	} else {
		return false;
	}

	return true;
}

const int TF_GL_MODE_CANNONBALL = 3;

// TF2 names deflected projectiles after the projectile instead of the weapon (see CTFGameRules::GetKillingWeaponName).
// Returns false and leaves logname unchanged if the inflictor is not a deflected projectile.
// Deflected stickies are not handled, since they stay owned by the demoman, and are only named "deflect_sticky" for a few seconds.
bool GetDeflectedLogName(char[] logname, int lognameLen, int inflictor, int damagecustom) {
	if (inflictor <= MaxClients || !IsValidEntity(inflictor))
		return false;

	// Only rockets (incl. flares and arrows) and grenades can be deflected
	if (!HasEntProp(inflictor, Prop_Send, "m_iDeflected") || GetEntProp(inflictor, Prop_Send, "m_iDeflected") == 0)
		return false;

	char classname[64];
	GetEntityClassname(inflictor, classname, sizeof(classname));

	if (StrEqual(classname, "tf_projectile_rocket") || StrEqual(classname, "tf_projectile_sentryrocket")) {
		strcopy(logname, lognameLen, "deflect_rocket");
	} else if (StrEqual(classname, "tf_projectile_flare")) {
		strcopy(logname, lognameLen, damagecustom == TF_CUSTOM_FLARE_EXPLOSION ? "deflect_flare_detonator" : "deflect_flare");
	} else if (StrEqual(classname, "tf_projectile_arrow")) {
		strcopy(logname, lognameLen, GetEntProp(inflictor, Prop_Send, "m_bArrowAlight") ? "deflect_huntsman_flyingburn" : "deflect_arrow");
	} else if (StrEqual(classname, "tf_projectile_pipe")) {
		strcopy(logname, lognameLen, GetEntProp(inflictor, Prop_Send, "m_iType") == TF_GL_MODE_CANNONBALL ? "loose_cannon_reflect" : "deflect_promode");
	} else if (StrEqual(classname, "tf_projectile_healing_bolt")) {
		strcopy(logname, lognameLen, "crusaders_crossbow");
	} else if (StrEqual(classname, "tf_projectile_energy_ball")) {
		strcopy(logname, lognameLen, classname);
	} else {
		return false;
	}

	return true;
}

// F2's Weapon Info Importer
KeyValues g_kvPrefabs = null;
KeyValues g_kvItems = null;

ArrayList g_hAllWeaponsName = null; // names of all weapons saved in an Array
ArrayList g_hAllWeaponsHealingOnHit = null;
ArrayList g_hAllWeaponsPostHumousDamage = null;
int g_iAllWeaponsCount = 0;
int g_iGigerCounterDefid = -1; // The weapon that makes TF2 name wrangled sentry kills "giger_counter" instead of "wrangler_kill"

const int MAXDEFID = 65535;
int g_iWeaponIndexFromDefid[MAXDEFID+1]; // translates defid -> index in the g_*AllWeapons* arrays (-1 if not a weapon)

bool WeaponFromDefid(int defid, char[] name, int maxlen, int &healing, bool &postHumousDamage) {
	if (defid < 0 || defid > MAXDEFID)
		return false;

	int i = g_iWeaponIndexFromDefid[defid];
	if (i == -1)
		return false;

	g_hAllWeaponsName.GetString(i, name, maxlen);
	healing = g_hAllWeaponsHealingOnHit.Get(i);
	postHumousDamage = g_hAllWeaponsPostHumousDamage.Get(i);
	return true;
}

// Returns true if the weapon makes TF2 name wrangled sentry kills "giger_counter" instead of "wrangler_kill"
bool IsGigerCounter(int weapon) {
	if (!IsValidEntity(weapon))
		return false;

	return g_iGigerCounterDefid != -1 && GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == g_iGigerCounterDefid;
}

void ImportWeaponDefinitions() {
	g_hAllWeaponsName = new ArrayList(MAXWEPNAMELEN);
	g_hAllWeaponsHealingOnHit = new ArrayList();
	g_hAllWeaponsPostHumousDamage = new ArrayList();
	g_iAllWeaponsCount = 0;
	g_iGigerCounterDefid = -1;
	Array_Fill(g_iWeaponIndexFromDefid, sizeof(g_iWeaponIndexFromDefid), -1);
	if (!FileExists(ITEMS_TXT_PATH, true))
		SetFailState("Could not find items_game.txt: %s", ITEMS_TXT_PATH);
	
	// Load items_game.txt for items traversal
	g_kvItems = KvizCreateFromFile("items_game", ITEMS_TXT_PATH);
	if (g_kvItems == null)
		SetFailState("Could not load items_game.txt");

	// Copy the prefabs section into its own KeyValues, so it can be traversed independently without parsing the items_game.txt file twice.
	// Uses the native cursor while it is still at the root, and returns it there afterwards to keep Kvizzle in sync.
	if (!g_kvItems.JumpToKey("prefabs"))
		SetFailState("items_game.txt: '%s' key not found", "prefabs");
	g_kvPrefabs = KvizCreate("prefabs");
	if (g_kvPrefabs == null)
		SetFailState("Could not create prefabs KeyValues");
	g_kvPrefabs.Import(g_kvItems);
	g_kvItems.GoBack();

	// Go to items section
	if (!KvizJumpToKey(g_kvItems, false, "items"))
		SetFailState("items_game.txt: '%s' key not found", "items");
	
	// To avoid script execution timeout, we need to import small chunks at a time
	CreateTimer(0.1, ImportWeaponDefinitionsChunk, 1);
}

public Action ImportWeaponDefinitionsChunk(Handle timer, int startId) {
	const int chunkSize = 500;
	int itemId = startId;
	int lastId = startId + (chunkSize - 1);

	for (; itemId <= lastId && KvizJumpToKey(g_kvItems, false, ":nth-child(%i)", itemId); KvizGoBack(g_kvItems), itemId++) {
		// Get the item defid
		int defid;
		if (!KvizGetNumExact(g_kvItems, defid, ":section-name"))
			continue;
		
		//if (KvizExist(g_kvItems, ":nth-child(%i).item_paintkit", itemId)) {
		//	char prefab[64];
		//	if (KvizGetStringExact(g_kvItems, ":nth-child(%i).prefab", itemId)) {
		//		
		//	}
		//}
		
		// Check if it is a stock weapon or a named stock weapon
		bool isStockWeapon = defid <= 30;
		bool isUpgradableStockWeapon = (defid >= 190 && defid <= 212);
		
		// Get the craft class
		char craftclass[32];
		GetItemString(g_kvItems, g_kvPrefabs, "craft_class", craftclass, sizeof(craftclass), "");
		
		// Get the slot for the item
		char itemslot[32];
		GetItemString(g_kvItems, g_kvPrefabs, "item_slot", itemslot, sizeof(itemslot));
		int slot = -1;
		if (StrEqual(itemslot, "primary", false))
			slot = 0;
		else if (StrEqual(itemslot, "secondary", false))
			slot = 1;
		else if (StrEqual(itemslot, "melee", false))
			slot = 2;
		else if (StrEqual(itemslot, "pda", false))
			slot = 3;
		else if (StrEqual(itemslot, "pda2", false))
			slot = 4;
		else if (StrEqual(itemslot, "head", false))
			slot = 5;
		else if (StrEqual(itemslot, "misc", false))
			slot = 6;
		else if (StrEqual(itemslot, "action", false))
			slot = 7;
		
		// Get the item class
		char itemclass[MAXITEMCLASSLEN];
		GetItemString(g_kvItems, g_kvPrefabs, "item_class", itemclass, sizeof(itemclass));
		
		// Check if the item is a weapon
		bool isWeapon = (slot >= 0 && slot <= 4) && (StrEqual(craftclass, "weapon", false) == true || StrEqual(craftclass, "", false) == true);
		
		// Check if the item is a medigun
		bool isMedigun = StrEqual(itemclass, "tf_weapon_medigun");

		// Save the weapon and corresponding defid if it's not a stock weapon
		if (isWeapon) {
			char itemname[MAXWEPNAMELEN] = "";
			
			if (defid == 130) {
				strcopy(itemname, sizeof(itemname), "sticky_resistance"); // Scottish Resistance has the wrong name in items_game.txt
			} else if (defid == 35) {
				strcopy(itemname, sizeof(itemname), "kritzkrieg");
			} else if (defid == 411) {
				strcopy(itemname, sizeof(itemname), "quickfix");
			} else if (defid == 998) {
				strcopy(itemname, sizeof(itemname), "vaccinator");
			} else if (isMedigun) {
				// It is some other medigun. As of this writing, the only other possibility is a normal medigun (or skin of it). /F2, 21-10-2015
				strcopy(itemname, sizeof(itemname), "medigun");
			} else {
				GetItemString(g_kvItems, g_kvPrefabs, "item_logname", itemname, sizeof(itemname));
				if (StrEqual(itemname, "")) {
					if (isStockWeapon || isUpgradableStockWeapon)
						GetItemString(g_kvItems, g_kvPrefabs, "name", itemname, sizeof(itemname));
					
					if (!StrEqual(itemname, "")) {
						if (F2_String_StartsWith(itemname, "Upgradeable ", false))
							strcopy(itemname, sizeof(itemname), itemname[12]);
						if (F2_String_StartsWith(itemname, "tf_weapon_", false))
							strcopy(itemname, sizeof(itemname), itemname[10]);
					} else {
						GetItemString(g_kvItems, g_kvPrefabs, "item_class", itemname, sizeof(itemname));
					}
					
					if (!StrEqual(itemname, "")) {
						if (F2_String_StartsWith(itemname, "tf_weapon_", false))
							strcopy(itemname, sizeof(itemname), itemname[10]);
						if (StrEqual(itemname, "rocketlauncher", false))
							strcopy(itemname, sizeof(itemname), "tf_projectile_rocket");
						else if (StrEqual(itemname, "pipebomblauncher", false))
							strcopy(itemname, sizeof(itemname), "tf_projectile_pipe_remote");
						else if (StrEqual(itemname, "grenadelauncher", false))
							strcopy(itemname, sizeof(itemname), "tf_projectile_pipe");
					}
				}
			}
			
			if (StrEqual(itemname, ""))
				Format(itemname, sizeof(itemname), "unknown(%i)", defid);
			
			String_ToLower(itemname, itemname, sizeof(itemname));

			g_hAllWeaponsName.PushString(itemname);
			int healingOnHit = 0;
			char attr[16];
			if (GetItemAttribute(g_kvItems, g_kvPrefabs, "add_onhit_addhealth", attr, sizeof(attr)) || GetItemAttribute(g_kvItems, g_kvPrefabs, "add_health_on_radius_damage", attr, sizeof(attr))) {
				//PrintToChatAll("health on hit(%i) name(%s)", attr, itemname);
				healingOnHit = StringToInt(attr);
			}
			g_hAllWeaponsHealingOnHit.Push(healingOnHit);
			g_hAllWeaponsPostHumousDamage.Push(GetItemTag(g_kvItems, g_kvPrefabs, "can_deal_posthumous_damage", false));
			GetItemString(g_kvItems, g_kvPrefabs, "static_attrs.is giger counter", attr, sizeof(attr), "0");
			if (StringToInt(attr) > 0) {
				if (g_iGigerCounterDefid == -1)
					g_iGigerCounterDefid = defid;
				else
					LogError("items_game.txt: More than one Giger Counter found (%i and %i). Only %i is detected.", g_iGigerCounterDefid, defid, g_iGigerCounterDefid);
			}
			if (defid < 0 || defid > MAXDEFID)
				LogError("Weapon defid is out of range: %i (%s)", defid, itemname);
			else if (g_iWeaponIndexFromDefid[defid] == -1)
				g_iWeaponIndexFromDefid[defid] = g_iAllWeaponsCount;
			g_iAllWeaponsCount++;
		
		}
	}

	if (itemId > lastId) {
		CreateTimer(0.1, ImportWeaponDefinitionsChunk, itemId);
		return Plugin_Stop;
	}

	// Clean up
	KvizGoBack(g_kvItems);

	KvizClose(g_kvItems);
	KvizClose(g_kvPrefabs);

	g_kvItems = null;
	g_kvPrefabs = null;

	FinalizePluginInitialization();

	return Plugin_Stop;
}

void GetItemString(KeyValues kv, KeyValues kvPrefabs, const char[] key, char[] value, int valueLen, const char[] def = "") {
	if (KvizGetString(kv, value, valueLen, "", key))
		return;
	
	char prefabs[128], prefab[64];
	KvizGetString(kv, prefabs, sizeof(prefabs), "", "prefab");
	while (PopPrefab(prefabs, prefab, sizeof(prefab))) {
		if (GetItemStringFromPrefab(kvPrefabs, prefab, key, value, valueLen))
			return;
	}
	
	strcopy(value, valueLen, def);
}

bool GetItemStringFromPrefab(KeyValues kvPrefabs, const char[] prefab, const char[] key, char[] value, int valueLen) {
	if (KvizGetStringExact(kvPrefabs, value, valueLen, "%s.%s", prefab, key))
		return true;
	
	char prefabs[128], nextPrefab[64];
	KvizGetString(kvPrefabs, prefabs, sizeof(prefabs), "", "%s.prefab", prefab);
	while (PopPrefab(prefabs, nextPrefab, sizeof(nextPrefab))) {
		if (!StrEqual(nextPrefab, "paintkit_weapon", false)) {
			if (GetItemStringFromPrefab(kvPrefabs, nextPrefab, key, value, valueLen))
				return true;
		}
	}
	
	return false;
}


bool GetItemTag(KeyValues kv, KeyValues kvPrefabs, const char[] key, bool def = false) {
	int ret;
	if (KvizGetNumExact(kv, ret, "tags.%s", key))
		return ret != 0;
	
	char prefabs[128], prefab[64];
	KvizGetString(kv, prefabs, sizeof(prefabs), "", "prefab");
	while (PopPrefab(prefabs, prefab, sizeof(prefab))) {
		if (KvizGetNumExact(kvPrefabs, ret, "%s.tags.%s", prefab, key))
			return ret != 0;
	}
	
	return def;
}

bool GetItemAttribute(KeyValues kv, KeyValues kvPrefabs, const char[] attr, char[] value, int valueLen) {
	if (KvizGetStringExact(kv, value, valueLen, "attributes:any-child.attribute_class:has-value(%s):parent.value", attr))
		return true;
	
	char prefabs[128], prefab[64];
	KvizGetString(kv, prefabs, sizeof(prefabs), "", "prefab");
	while (PopPrefab(prefabs, prefab, sizeof(prefab))) {
		if (KvizGetStringExact(kvPrefabs, value, valueLen, "%s.attributes:any-child.attribute_class:has-value(%s):parent.value", prefab, attr))
			return true;
	}
	
	return false;
}

// Removes the last name from the space-separated prefab list and copies it into prefab. Returns false if the list is empty.
bool PopPrefab(char[] prefabs, char[] prefab, int prefabLen) {
	if (prefabs[0] == '\0')
		return false;
	
	int pos = FindCharInString(prefabs, ' ', true);
	strcopy(prefab, prefabLen, prefabs[pos+1]);
	prefabs[pos == -1 ? 0 : pos] = '\0';
	return true;
}

