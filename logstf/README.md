# LogsTF

Features:

- **Note:** Requires the [SteamWorks](http://users.alliedmods.net/~kyles/builds/SteamWorks/) ([mirror](https://github.com/hexa-core-eu/SteamWorks/releases)) extension, or the cURL extension.
- Automatically uploads logs to [logs.tf](https://logs.tf)
- You can see the logs in-game by typing `!logs` or `.ss`
- Uploads logs after each round (the log will be updated on logs.tf after each round), so you can use `!logs`/`.ss` after each round
- Fixes several bugs seen in other plugins (including the last round missing, and stats being wrong when you play two matches on the same map)

Available CVARs:
| CVAR | Default | Description |
| --- | --- | --- |
| `logstf_apikey <key>` | (empty) | Sets your Logs.TF API key. Required for the plugin to work. |
| `logstf_title <title>` | `{server}: {red} vs {blu}` | Sets the title of the log.<br>Use `{server}` to insert the server title.<br>Use `{red}` or `{blu}` to insert team names. |
| `logstf_autoupload <0\|1\|2>` | `2` | Set to 2 to upload logs from all matches.<br>Set to 1 to upload logs from matches with at least 4 players.<br>Set to 0 to disable automatic upload. |
| `logstf_midgameupload <0\|1>` | `1` | Set to 0 to upload logs after the match has finished.<br>Set to 1 to upload the logs after each round. |
| `logstf_midgamenotice <0\|1>` | `1` | Set to 1 to notice players about midgame logs. |
| `logstf_suppresschat <0\|1>` | `1` | Set to 1 to hide '!log' chats. |
