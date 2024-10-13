# AFK <a href="https://sourcemod.krus.dk/afk.zip"><img src="https://img.shields.io/badge/-download-informational" /></a>

Features:

- If a player is AFK in warmup, it shows [a warning](https://sourcemod.krus.dk/afk-1.jpg) to all players on their team
- If both teams ready up and there is an AFK player, it shows [a warning](https://sourcemod.krus.dk/afk-2.jpg) to the person's team
- Works together with TF2DM... if a player is AFK, they will be moved back to spawn

| CVAR                       | Default | Description                                                          |
| -------------------------- | ------- | -------------------------------------------------------------------- |
| `afk_time <seconds>`       | `20`    | Number of seconds you can stand still before being marked as AFK.    |
| `afk_minplayers <players>` | `8`     | Minimum number of players on the server before the plugin is active. |
