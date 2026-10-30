# Server operations — Skyfall Legends

The dedicated server is the **only** authority in a match. Clients send
intentions (movement vector, aim direction, "use item"), never outcomes.

## Requirements

- Godot 4.7.2 headless-capable binary (MIT). No display, GPU or audio device needed.
- One UDP port reachable by players (default 7777).

## Run

```bash
GODOT=/path/to/godot ./server/run_server.sh server/config/server.json
```

For quick manual runs without the wrapper:

```bash
godot --headless --path . game/scenes/dedicated_server.tscn -- --cfg server/config/server.json
```

## Configuration keys

`server/config/server.json`:

| key | type | meaning |
|---|---|---|
| `port` | int | UDP listen port (default 7777) |
| `max_clients` | int | ENet peer cap (default 64) |
| `bot_fill` | bool | fill empty lobby seats with server bots (marked `AI_xxx`) |
| `zone_start` | float | initial safe-zone radius in metres (default 476) |
| `spawn_weapons` | bool | give human players a loaded Vanguard-7 at insertion (test/practice aid) |
| `phases` | array | zone schedule; each `{wait_s, shrink_s, dps, r_mult}`. Empty = built-in 8-phase schedule |

CLI flags override file values: `--port 7778`, `--bots`, `--no-bots`, `--cfg <file>`.

## Match sizing

`MODE_PLAYERS` in `game/src/core/match_rules.gd` currently caps solo/duo at 8
and squad at 9 by design. Raise only after load-testing the tick budget on the
target host (see `docs/IMPLEMENTATION_ROADMAP.md`).

## Ops notes

- The process exits non-zero when the UDP bind fails (systemd will restart it).
- Session state lives in RAM; a crash ends all live matches. There is no
  persistence or account system in this version — display names are ephemeral.
- Rate limiting: 70 messages/second per peer, 3 violations → disconnect.
- Logs go to stdout; pipe into journald or a log shipper.
- Capacity estimate: one match ≈ 1 % of a modern vCPU at 30 Hz ticks with 8
  players (to be measured in the load-test milestone; treat as a plan, not a claim).
