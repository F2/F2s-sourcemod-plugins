# Supplemental Stats v2 <a href="https://sourcemod.krus.dk/supstats2.zip"><img src="https://img.shields.io/badge/-download-informational" /></a>

Features:

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
- Logs unique match id, map name and title at the start of the match

| CVAR                       | Default                    | Description                                                                                                                                                         |
| -------------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `supstats_accuracy <0\|1>` | `1`                        | Enable accuracy logs                                                                                                                                                |
| `logstf_title <title>`     | `{server}: {blu} vs {red}` | Sets the title of the log, which is logged at the start of the match.<br>Use `{server}` to insert the server title.<br>Use `{blu}` or `{red}` to insert team names. |
