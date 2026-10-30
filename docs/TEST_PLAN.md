# Test plan — Skyfall Legends

## Unit tests (`game/tests/test_runner.gd`, `-- units --`)

Pure, deterministic, no networking:

| Test | What it checks |
|------|----------------|
| `damage` | falloff at range; armor soaks half; armor over-depletion clamps HP loss |
| `inventory` | 2-weapon cap, medkit/bandage caps, ammo over-cap detection |
| `zone` | start radius, WAIT state, shrink announcement, radius shrink, state dict |
| `map` | island height above/below water, flight points, altitude, loot point count, purity |
| `protocol` | op/seq/v3/v2/yaw/flags round-trip; lobby state round-trip |
| `loot_atomicity` | first claim wins, double claim impossible, distant claim returns none |
| `names` | sanitization (injection chars → `_`, collapse), fallback, max length |
| `rules` | solo 8 players, duo/squad naming/mapping |
| `weapons` | dmg/rpm/mag/reload/range sanity per category |

## Integration test (`-- integration: dedicated server process + 2 real clients --`)

Runs the dedicated server as a **separate OS process** (`dedicated_server.tscn`)
and **two real ENet clients** over loopback (`test_client.gd`), each with its
own `SceneMultiplayer` + `ENetMultiplayerPeer`. All gameplay goes through the
wire protocol; the harness never touches server state directly.

Flow:

1. Server starts on a random loopback port (29200–29700), `bot_fill: false`,
   `spawn_weapons: true`, staged zone phases (5 dps → 30 dps), zone start
   300 m.
2. Clients A and B connect, receive `HELLO_OK` (pid assigned after ENet
   connection completes — hello is deferred until `connected_to_server`).
3. A creates a private solo lobby; both join by code; lobby state, room code,
   roster (2 players) observed by both.
4. Both set ready → countdown → `MATCH_START` received by both.
5. Deploy gate passed (plane over island); both clients deploy and land on
   terrain.
6. A moves (server-validated input); B appears in snapshots.
7. A aims and fires at B (both on ground); server-validated hit lands on B
   (`HIT_TAKEN`/`HIT_DEALT` events).
8. Zone phases advance; zone damage taxation observed (HP attrition).
9. `MATCH_END` received by both.
10. Separate rate-limit check: 90 pings across 4 windows (limit 70/s, 3
    violations → kick).

Determinism knobs: `bot_fill: false`, `spawn_weapons: true`, fixed phases,
chase + aim combat tickers, deploy gate = plane within 60 m of island center
plus building-footprint clearance.

## Known integration risks (tracked, not resolved claims)

- Building line-of-sight can make aim hits probabilistic; test ticker retries
  across snapshots.
- Deploy timing (~t26s) vs zone phase timeouts; timeouts tuned empirically.

## CI

`.github/workflows/automated-tests.yml`: on push/PR to main — download Godot
4.7.2, generate class cache, run headless suite, upload `testrun.log`, fail
the job unless the summary reports a clean pass.

## Manual test matrix (not automated)

- Two real devices on the same LAN connecting to the dedicated server.
- Android debug APK install + local network join (CI produces the APK;
  device test is manual).
- Private lobby code flow end-to-end.
- Rate-limit kick behavior with a flooding client (manual, careful).

## What is NOT tested

- Audio playback (no audio device headless; SFX unwired).
- Android install/run (no devices in CI).
- Editor GUI flows (editor crashes in this host).
