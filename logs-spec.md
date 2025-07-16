# TF2 Logs Spec 3.0

This is the spritual successor to [Logs.tf Spec 2.0](https://github.com/alevoska/logstf-spec).

## General terminology

When demonstrating a log line, we first write the general format, and then an example:

    Format

    Examples (unless Format has no placeholders)

When we write `<player>`, `<attacker>` or similar, they refer to this format:

    "Nickname<UserID><SteamID><Team>"

    "F2<3><[U:1:1234]><Red>"

## Pauses

When someone pauses the game:

    World triggered "Game_Paused"
    <player> triggered "matchpause"

    World triggered "Game_Paused"
    "F2<3><[U:1:1234]><Red>" triggered "matchpause"

When someone unpauses the game:

    World triggered "Game_Unpaused"
    <player> triggered "matchunpause"
    World triggered "Pause_Length" (seconds "%.2f")

    World triggered "Game_Unpaused"
    "F2<3><[U:1:1234]><Red>" triggered "matchunpause"
    World triggered "Pause_Length" (seconds "14.25")
    
The only reason we are logging the `World triggered` logs are for backwards compatibility, but these can be ignored.

## Heals

When a player heals someone:

    <healer> triggered "healed" against <patient> (healing "%d") (airshot "1") (height "%i")

    "F2<3><[U:1:1234]><Red>" triggered "healed" against "Extremer<4><[U:1:1337]><Red>" (healing "20") (airshot "1") (height "54")

The following properties are optional: `airshot`, `height`  
These are only logged if the healing was caused by an airshot (e.g. crusader's crossbow).

## Spawning

When a player spawns:

    <player> spawned as <class>

    "F2<3><[U:1:1234]><Red>" spawned as "medic"

Possible values for class:
- `"scout"`
- `"sniper"`
- `"soldier"`
- `"demoman"`
- `"medic"`
- `"heavyweapons"`
- `"pyro"`
- `"spy"`
- `"engineer"`

## Ubercharges

When a player pops their ubercharge:

    <player> triggered "chargedeployed" (medigun <medigun-name>)

    "F2<3><[U:1:1234]><Red>" triggered "chargedeployed" (medigun "medigun")

The medigun name can be:
- `"medigun"`
- `"kritzkrieg"`
- `"quickfix"`
- `"vaccinator"`
- `"unknown"` (it could not be detected)