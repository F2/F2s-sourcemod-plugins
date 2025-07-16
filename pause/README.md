# Improved Pause <a href="https://sourcemod.krus.dk/pause.zip"><img src="https://img.shields.io/badge/-download-informational" /></a>

Features:

- Makes it possible to chat during pauses
- Use **repause** command to quickly unpause and pause again, allowing people to join the server
- Unpause protection: If two people write pause at the same time, it doesn't accidentally unpause
- Every minute it shows how long the pause has been going on
- Fixes bug in TF2 where the ubercharge keeps building during a pause
- Fixes bug in TF2 where spy's cloak keeps draining if active during a pause
- Fixes bug in TF2 where player's position is fast forwarded after a pause (as if the pause never happened)
- Shows a countdown of 5 seconds when unpausing

| CVAR                         | Default | Description                                                |
| ---------------------------- | ------- | ---------------------------------------------------------- |
| `pause_enablechat <0\|1>`    | `1`     | Enable people to chat as much as they want during a pause. |
| `pause_restore_health <0\|1>`| `0`     | Restores health on unpause.                                |
| `pause_restore_cloak <0\|1>` | `0`     | Restores cloak on unpause.                                 |
| `pause_restore_pos <0\|1>`   | `0`     | Restores position, angle and velocity on unpause.          |

| Command   | Description                                                            |
| --------- | ---------------------------------------------------------------------- |
| `repause` | Quickly unpauses and pauses again, allowing people to join the server. |
