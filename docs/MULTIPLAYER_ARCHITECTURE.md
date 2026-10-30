# Multiplayer architecture — Skyfall Legends

## Authority model

The server is the **sole authority**. The client sends *intent* (movement
vector, aim direction, "use item", fire, ready) and receives *verdicts*
(snapshots, hit events, eliminations, match end). The server never trusts
client damage claims, inventory deltas, or victory announcements:

- Movement is clamped to `MatchRules` speed caps and resolved against building AABBs server-side.
- `Damage.apply` computes HP/armor results server-side; clients only observe.
- `Inventory` validity (2-weapon cap, ammo caps) is enforced server-side; `add_pickup` rejects overflow.
- Loot claims are atomic (`claim(id, pid)`; first claim wins).
- Match end and placement are computed by `MatchSim` and announced via `MATCH_END`.

## Transport and encoding

- ENet UDP; server binds one port (default 7777, config override via `--port` or `server/config/server.json`).
- Custom binary op-code protocol over `StreamPeerBuffer`, little-endian:
  - C2S ops 1–13: HELLO(1), LOBBY_CREATE(2), LOBBY_JOIN(3), LOBBY_BACK(4), SET_READY(5), INPUT(6, unreliable), FIRE(7, unreliable), USE_ITEM(8), PICKUP(9), RELOAD(10), SWITCH_WEAPON(11), SPECTATE(12), PING(13, unreliable).
  - S2C ops 101–110: HELLO_OK(101), LOBBY_STATE(102), LOBBY_MSG(103), MATCH_START(104), SNAPSHOT(105), MATCH_EVENT(106), MATCH_END(107), SERVER_CLOSE(108), KICKED(109), PONG(110).
- `MatchEvents` (0–13) tag events inside snapshots/MATCH_EVENT: HIT_TAKEN, HIT_DEALT, HEALED, LOOT_CLAIMED, DROPPED_LOOT, GRENADE_THROWN, GRENADE_EXPLODED, ABILITY, ELIMINATION, PLAYER_LEFT_MATCH, ZONE_ANNOUNCE, SPECTATE_OFFER, SHOT, MSG.
- Reliability split: lobby/match lifecycle reliable; input, snapshots, ping, fire unreliable.

## Tick rates and timing

- Server physics: 30 Hz (`common/physics_ticks_per_second=30`).
- Match simulation ticks on `_process`; snapshots at 8 Hz per connected viewer.
- Integration-test input/fire tickers run at 10 Hz to stay under the rate cap.
- Match lifecycle timings are config-driven: `zone_start`, zone `phases`
  (wait/shrink/dps/r_mult), lobby auto-start countdown (5 s), queue timeouts.

## Rooms, queues, and matchmaking

- Public queues per mode (SOLO/DUO/SQUAD); private lobbies with 6-character codes
  (`CODE_ALPHABET`, no ambiguous chars).
- Auto-start countdown when readiness passes; matches begin with the players in
  the room.
- `bot_fill` (default true in dev config; false in the integration test) fills
  empty seats with `AI_###` bots; bots run `BotBrain` through the same
  `MatchSim` validation path as network clients and are visibly marked in the
  roster (`[BOT]`).
- Match caps: SOLO 8, DUO 8, SQUAD 9 (`MatchRules.MODE_PLAYERS`). Raise only
  after load testing (see `docs/IMPLEMENTATION_ROADMAP.md`).

## Rate limiting and failure handling

- 70 messages/second per peer; 3 violations → `s_kicked` + disconnect.
- Peer disconnect removes the player from lobby/room; host migration picks the
  next player as host; empty rooms are cleaned up.
- Server crashes lose in-RAM match state (no persistence in this version).

## What is NOT done

- No client-side prediction reconciliation beyond snapshot observation.
- No NAT traversal/relay; players connect directly to the server's UDP port.
- No encryption on the wire (UDP plaintext); TLS/WSS not supported by ENet.
- No account or auth system; display names are ephemeral (impersonation is
  possible — see `docs/SECURITY.md`).
