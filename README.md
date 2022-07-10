# F2's SourceMod plugins
![CI](https://github.com/F2/F2s-sourcemod-plugins/workflows/CI/badge.svg)

F2's SourceMod plugins for competitive Team Fortress 2.

Download all plugins in a zip file here: <a href="http://sourcemod.krus.dk/f2-sourcemod-plugins.zip"><img src="https://img.shields.io/badge/-download-informational" /></a>

### Medic Stats <a href="http://sourcemod.krus.dk/medicstats.zip"><img src="https://img.shields.io/badge/-download-informational" /></a>
- Logs buff heals (~95% accurate)
- Logs average time to build über
- Logs average time the über lasts
- Logs number of über advantages lost
- Logs how many times the medic dies shortly after übering
- Logs other additional medic stats
- See [example on logs.tf](http://logs.tf/154545)

### Supplemental Stats 2 <a href="http://sourcemod.krus.dk/supstats2.zip"><img src="https://img.shields.io/badge/-download-informational" /></a>
- Logs damage and real damage per weapon
- Logs damage taken
- Logs airshots
- Logs self-healing (eg. by blackbox)
- Logs headshots (not just headshot kills)
- Logs medkit pickups including amount of healing
- Logs which medigun is used when ubering
- Logs crits and mini crits
- Logs non-buffed heals
- Logs ammo pickups
- Logs players spawning
- Logs game pauses
- Logs shots fired and shots hit (for certain weapons)

### LogsTF <a href="http://sourcemod.krus.dk/logstf.zip"><img src="https://img.shields.io/badge/-download-informational" /></a>
- **Note:** Requires the [SteamWorks](http://users.alliedmods.net/~kyles/builds/SteamWorks/) ([mirror](https://github.com/hexa-core-eu/SteamWorks/releases)) extension
- Automatically uploads logs to logs.tf
- Set cvar **logstf_apikey** to your Logs.tf API Key
- You can see the logs in-game by typing `!logs` or `.ss`
- Uploads logs after each round (the log will be updated on logs.tf after each round), so you can use `!logs`/`.ss` after each round
- Fixes several bugs seen in other plugins (including the last round missing, and stats being wrong when you play two matches on the same map)

### Pause <a href="http://sourcemod.krus.dk/pause.zip"><img src="https://img.shields.io/badge/-download-informational" /></a>
- Shows pause information in chat (see [screenshot](http://sourcemod.krus.dk/pause.jpg) and [screenshot](http://sourcemod.krus.dk/pause-time.jpg))
- Use **repause** command to quickly unpause and pause (when someone is trying to rejoin during a pause)
- Adds a 5 second countdown when unpausing
- Allows everyone to chat as much as they want during the pause
- Unpause protection (if two people write pause at the same time, it doesn't accidentally unpause)

### ClassWarning <a href="http://sourcemod.krus.dk/classwarning.zip"><img src="https://img.shields.io/badge/-download-informational" /></a>
- In ETF2L, class limits are not enforced by the server. This plugin warns players in chat if they are breaking the class limit (see [screenshot](http://sourcemod.krus.dk/classwarning.jpg)).

### RecordSTV <a href="http://sourcemod.krus.dk/recordstv.zip"><img src="https://img.shields.io/badge/-download-informational" /></a>
- When a match starts, it starts recording a STV demo
- When the match ends, it stops the recording
- Set up the path and the filenames of the demos with cvars: **recordstv_path** and **recordstv_filename**
- In both cvars you can use several placeholders. See the description of recordstv_filename for the full list of placeholders.

### WaitForSTV <a href="http://sourcemod.krus.dk/waitforstv.zip"><img src="https://img.shields.io/badge/-download-informational" /></a>
- Waits up to 90 seconds when changing map
- Doesn't wait more time than necessary

### AFK <a href="http://sourcemod.krus.dk/afk.zip"><img src="https://img.shields.io/badge/-download-informational" /></a>
- If a player is AFK in warmup, it shows [a warning](http://sourcemod.krus.dk/afk-1.jpg) to all players on their team
- If both teams ready up and there is an AFK player, it shows [a warning](http://sourcemod.krus.dk/afk-2.jpg) to the person's team
- Works together with TF2DM... if a player is AFK, he will be moved back to spawn

### RestoreScore <a href="http://sourcemod.krus.dk/restorescore.zip"><img src="https://img.shields.io/badge/-download-informational" /></a>
- Restores a player's score on the scoreboard when he reconnects

### FixStvSlot <a href="http://sourcemod.krus.dk/fixstvslot.zip"><img src="https://img.shields.io/badge/-download-informational" /></a>
- Changes the map on server start to avoid a crash related to STV slot


## Automatic updates
These plugins can automatically be updated by using <a href="https://forums.alliedmods.net/showthread.php?t=169095">Updater</a> by GoD-Tony.

## Thanks to...
**Lange** for making `soap_tf2dm` and mgemod, from which I borrowed code\
**Jean-Denis Caron** for making `supstats`, from which I borrowed code\
**Duckeh** for making `LogUploader`, from which I borrowed code\
**calm** for sponsoring LEGO, making it possible to test these plugins\
**The LEGO Team** for helping test the plugins and give feedback\
**zoob** for making logs.tf and cooperating in improving TF2 stats

