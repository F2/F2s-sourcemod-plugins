# TF2 Logs Spec 3.0

This document builds on [Logs.tf Spec 2.0](https://github.com/alevoska/logstf-spec) and describes all additional log lines beyond the standard ones.

## General terminology

When demonstrating a log line, we first write the general format, and then an example:

    Format

    Examples (unless Format has no placeholders)

When we write `<player>`, `<attacker>` or similar, they refer to this format:

    "Nickname<UserID><SteamID><Team>"

    "F2<3><[U:1:1234]><Red>"

# Supplemental logs (supstats2)

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

The only reason we are logging the `World triggered` logs are for backwards compatibility, so these can be ignored.

## Heals

When a player heals someone:

    <healer> triggered "healed" against <patient> (healing "%d") (airshot "1") (height "%i")

    "F2<3><[U:1:1234]><Red>" triggered "healed" against "Extremer<4><[U:1:1337]><Red>" (healing "20") (airshot "1") (height "54")

The following properties are optional: `airshot`, `height`  
These are only logged if the healing was caused by an airshot (e.g. crusader's crossbow).

Note, a healer is not necessarily medic. For example, an engineer can heal with a dispenser.

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

The \<medigun-name\> can be:

- `"medigun"`
- `"kritzkrieg"`
- `"quickfix"`
- `"vaccinator"`
- `"unknown"` — it could not be detected

## Item Pickup

When a player picks up an item:

    <player> picked up item <item> (healing "%i")

    "F2<3><[U:1:1234]><Red>" picked up item "medkit_medium" (healing "%i")

The following properties are optional: `healing`

The \<item\> can be:

- `"medkit_small"`
- `"medkit_medium"`
- `"medkit_large"`
- `"ammopack_small"`
- `"ammopack_medium"`
- `"ammopack_large"`
- `"tf_ammo_pack"` — these are medium sized ammo packs dropped by players

## Damage

When a player deals damage to another player:

    <attacker> triggered "damage" against <victim> (damage "%i") (realdamage "%i") (weapon "%s") (healing "%i")  (crit "%s") (airshot "1") (height "%i") (headshot "1")

    "F2<3><[U:1:1234]><Red>" triggered "damage" against "dunc<8><[U:1:420]><Blue>" (damage "69") (realdamage "31") (weapon "quake_rl") (healing "20")  (crit "mini") (airshot "1") (height "33") (headshot "1")

It has the following properties:

- `damage`: The amount of damage theoretically dealt (say, _450_ for a fully charged headshot)
- `realdamage`: _(Optional)_ The amount of damage actually dealt (say, _125_ for a fully charged headshot on a scout)  
  If not present: The "real damage" was the same as "damage".
- `weapon`: The weapon used to deal the damage, typically extracted from items_game.txt
- `healing`: _(Optional)_ The amount of self-healing gained from dealing the damage (e.g. using Black Box).  
  If not present: Healing was zero.
- `crit`: _(Optional)_ Can either be `mini` or `crit`.  
  If not present: It was not a crit shot.
- `airshot`: _(Optional)_ If it is `1`, it was an airshot.  
  If not present: It was not an airshot.
- `height`: _(Optional)_ The distance above ground of the victim when the airshot happened.  
  If not present: It was not an airshot.
- `headshot`: _(Optional)_ If it is `1`, it was a headshot.  
  If not present: It was not a headshot.

Note, self damage is not logged.

## Accuracy

When a player shoots a weapon:

    <player> triggered "shot_fired" (weapon "%s")

    "F2<3><[U:1:1234]><Red>" triggered "shot_fired" (weapon "scattergun")

When the shot actually hits someone:

    <player> triggered "shot_hit" (weapon "%s")

    "F2<3><[U:1:1234]><Red>" triggered "shot_hit" (weapon "scattergun")

Note that `shot_hit` will only be logged once per `shot_fired`, even if the shot hits multiple targets. This makes it possible to calculate the accuracy by using this simple formula:

$$\text{Accuracy} = \frac{\text{count(shot\\_hit)}}{\text{count(shot\\_fired)}} \times 100\\%$$

For Crusader's Crossbow, friendly hits will be logged as `shot_hit`.

Destroying a sticky with a hitscan weapon will be logged as `shot_hit` (although it might not always be accurately detected).

# Medic Stats (medicstats)

**A note on vaccinator:** These logs are very bugged for vaccinator. For example, "charge ready" is only logged at 100%, but with vaccinator you can use charge at 25%. And it does not make sense talking about "uber advantage lost" when one team has uber and the other vaccinator. So, if one team uses vaccinator, think carefully about how you use these logs.

## First heal after spawn

When a medic heals for the first time after having spawned:

    <medic> triggered "first_heal_after_spawn" (time "%.1f")

    "F2<3><[U:1:1234]><Red>" triggered "first_heal_after_spawn" (time "1.2")

It is not triggered in the beginning of a round.

It is also not triggered if you switch spawns.

## Ubercharge is ready

When a medic reaches 100% charge:

    <medic> triggered "chargeready"

    "F2<3><[U:1:1234]><Red>" triggered "chargeready"

## Medic deaths

When a medic dies, we log their uber percentage:

    <medic> triggered "medic_death_ex" (uberpct "%i")

    "F2<3><[U:1:1234]><Red>" triggered "medic_death_ex" (uberpct "13")

It is called `medic_death_ex` because there already exists another log line called `medic_death`.

The uber percentage is rounded down, so if they had 99.9% it will be logged as "99".

## Empty uber

When a medic's charge changes to zero, typically upon spawning or after using their charge:

    <medic> triggered "empty_uber"

    "F2<3><[U:1:1234]><Red>" triggered "empty_uber"

## Charge ended

When a medic's charge reached 0% after using a charge:

    <medic> triggered "chargeended" (duration "%.1f")

    "F2<3><[U:1:1234]><Red>" triggered "chargeended" (duration "6.4")

The duration is in seconds.

## Lost uber advantage

When one team gets uber significantly before the other team, but does not use it before the other team got theirs:

    <medic> triggered "lost_uber_advantage" (time "%i")

    "F2<3><[U:1:1234]><Red>" triggered "lost_uber_advantage" (time "14")

Alternatively, this could also be computed by looking at the "chargeready" and "chargedeployed" logs from both teams.
