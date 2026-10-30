# Game design document — Skyfall Legends

## Loop

Lobby (ready up) → insertion plane over the island → parachute deploy → land
→ loot buildings → safe zone shrinks with periodic damage → last team alive
wins → results screen. A full match is designed to run in a few minutes; the
zone schedule (8 phases) drives attrition toward a conclusion.

## Map

- Circular analytic island, ~480 m radius default start zone, ocean beyond.
- Height field: shore ramp, terrain amp, ridge noise; pure function
  `MapData.height(x, z)` — deterministic, no heightmap asset.
- Procedural building sites with axis-aligned AABBs; movement resolves circle
  vs boxes (push-out on XZ).
- Flight path starts off-island (~730 m from center); the server's deploy gate
  lets players drop mid-island. Early deploy can land in water by design.
- Loot points spawned deterministically per match seed (`LootField`).

## Weapons (`game/src/core/weapons_db.gd`)

Categories: rifle, SMG, shotgun, sniper, pistol, melee, grenade. Fields:
`dmg`, `range_m`, `rpm`, `mag`, `reload_s`, ammo kind (light/heavy), spread,
recoil. Test loadout (`spawn_weapons`): humans spawn with a fully loaded
`ar_vanguard` and full light ammo; bots never get the boot loadout.

## Characters

`ranger`, `sharp`, `gust` IDs in `CharactersDB`; purely cosmetic for now
(char string carried in player records; abilities stubbed in `MatchSim`).

## Safe zone (`Zone`)

State machine: WAIT → SHRINKING → (next phase) → ENDED. Phases define
`wait_s`, `shrink_s`, `dps`, `r_mult`; next ring drifts within island bounds.
Players outside the current ring take dps per second.

## Loot

`LootField` with atomic claims (`claim(id, pid)` — first claim wins, double
claim impossible), pickup radius 2.4 m, medkits/bandages (heal kinds).

## Combat (server-authoritative)

- Input: movement vector + aim direction + flags (sprint/crouch/jump/deploy/ability) at 10 Hz tickers in tests.
- Fire: ray/angle check on server; hit verdict + damage + armor soak computed by `Damage.apply`; `Combat` owns try_fire/try_reload.
- Health 100, armor plates (see `docs`/damage.gd). Elimination recorded in order; placement shared by teammates.
- Clients never send damage or hit results.

## Controls

- Desktop: WASD move, mouse look, space jump, shift sprint, ctrl crouch, left-click fire, keys for deploy/ability/reload/switch/spectate.
- Android: virtual joystick pad (left), look pad (right), fire/use buttons (UI layer).

## UI screens

Boot → Menu → Lobby (room code, ready, roster, [BOT] markers) → in-game HUD → Results (placement). HUD shows HP, armor, ammo, zone timer.

## Bots

Server-controlled, named `AI_###`, run through `BotBrain` and the identical
server validation path as network clients. Used to fill lobbies when
`bot_fill` is enabled and for practice. Always visibly marked.
