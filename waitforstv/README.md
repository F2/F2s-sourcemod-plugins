# Wait For SourceTV <a href="https://sourcemod.krus.dk/waitforstv.zip"><img src="https://img.shields.io/badge/-download-informational" /></a>

- Waits up to 90 seconds when changing map
- Doesn't wait more time than necessary
- Doesn't wait if no one is watching SourceTV
  - Viewers on SourceTV relays cannot be seen, so it always waits if a relay is connected
  - For best results, install [SourceTV Manager](https://github.com/peace-maker/sourcetvmanager). Without it, the plugin checks `tv_status` once a minute.

| RCON Command      | Description                    |
| ----------------- | ------------------------------ |
| `stopchangelevel` | Stops the map change countdown |
