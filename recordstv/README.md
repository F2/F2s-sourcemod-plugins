# Record SourceTV <a href="https://sourcemod.krus.dk/recordstv.zip"><img src="https://img.shields.io/badge/-download-informational" /></a>

Features:

- Automatically records SourceTV demos when a match starts
- Automatically stops recording when the match ends
- Set up the path and the filenames of the demos with cvars: **recordstv_path** and **recordstv_filename**

| CVAR                            | Default                  | Description                             |
| ------------------------------- | ------------------------ | --------------------------------------- |
| `recordstv_path <path>`         | (empty)                  | The path to put the recorded STV demos. |
| `recordstv_filename <filename>` | `match-#Y#m#d-#H#M-#map` | The name of the demo files.             |

In both of these CVARs, you can use these placeholders:

- `#Y` = Year
- `#m` = Month
- `#d` = Day
- `#H` = Hour
- `#M` = Minute
- `#map` = Map name
- `#red` = Red Team Name
- `#blue` = Blue Team Name
