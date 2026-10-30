# Security policy — Skyfall Legends

## Threat model

- **Malicious clients** may lie about damage, hits, inventory, position, or
  victory. The server must never accept client verdicts.
- **Rate-abusing peers** may flood the server to degrade matches or cause
  disconnects of others.
- **Network observers** can read UDP traffic (no encryption — see limits).
- **Supply chain**: no third-party game assets are used, reducing supply-chain
  surface; the Godot binary and export templates are fetched from
  github.com/godotengine/godot-builds by CI (checksums not pinned — see limits).

## Mitigations (implemented)

1. **Server authority** — `MatchSim` owns all match state. Clients send intent
   only; all verdicts (damage, inventory, loot claims, zone damage,
   elimination, placement, match end) are computed server-side.
2. **Input sanitization** — display names pass through `Names.sanitize`
   (allowed charset, length cap, collapse of injection characters) before
   being stored or broadcast.
3. **Rate limiting** — 70 messages/second per peer; 3 violations → kick with
   `s_kicked`.
4. **Inventory/server validation** — weapon slot cap (2), ammo caps, atomic
   loot claims, movement speed caps; all re-checked on the server.
5. **No secrets in source** — `.gitignore` excludes keystores/logs; CI signs
   release builds only from GitHub Secrets
   (`ANDROID_RELEASE_KEYSTORE_B64`, `_USER`, `_PASS`); nothing secret is
   committed.
6. **Bot isolation** — bots run through the identical server validation path
   as net clients and cannot grant themselves items or HP.

## Documented limits (not mitigated in v0.8)

- **No encryption** on the wire: ENet UDP is plaintext. Match data (positions,
  names) is observable by network observers.
- **No account/auth system**: display names are ephemeral strings; name
  impersonation is possible. This is a known limitation of the prototype, not
  a bug.
- **In-memory state only**: a server crash ends all live matches; there is no
  persistence or replay.
- **DoS surface**: one UDP port per instance; no connection-rate cap beyond
  the per-peer message limit and `max_clients` (default 64).
- **DoS mitigation via engine limits**: ENet peer packet size limits apply;
  oversized packets are dropped by ENet itself.

## Disclosure

There is no bug bounty or formal disclosure process for this prototype.
Security concerns may be raised as repository issues.
