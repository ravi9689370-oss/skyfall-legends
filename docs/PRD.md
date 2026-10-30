# Product requirements document — Skyfall Legends

## 1. Product

**Skyfall Legends** is an original, self-hosted online multiplayer battle
royale prototype for Android, built in Godot 4.7.2. Matches are small by
design: **8 players, solo only, to start**. Larger modes (duo/squad, bigger
lobbies) exist in code (`MatchRules.Mode.DUO/SQUAD`, caps 8/9) but are not
promoted until load-tested.

## 2. Core requirements

| ID | Requirement | Status |
|----|-------------|--------|
| R1 | Real online multiplayer, server-authoritative | Implemented, under test |
| R2 | Clients never trusted for damage, inventory, or victory | Implemented (MatchSim owns all state) |
| R3 | Dedicated headless server from the same Godot binary | Implemented (`dedicated_server.tscn`) |
| R4 | Android build pipeline via CI (debug APK + release AAB) | Pipeline written; not yet run |
| R5 | Bots for practice/testing only, clearly marked (`AI_###`) | Implemented |
| R6 | No secrets in source; signing material via CI secrets only | Policy enforced by `.gitignore` + workflow design |
| R7 | Only implemented-and-tested features are claimed | Honest-status policy (see `README.md`) |
| R8 | Match size starts at 8 solo; increase only after load testing | Design cap in `MatchRules.MODE_PLAYERS` |

## 3. Out of scope (explicitly)

- Account system, login, persistent inventory, cross-match progression.
- Display-name uniqueness or impersonation protection (names are ephemeral strings; see `docs/SECURITY.md`).
- Monetization, IAP, ads, battle passes.
- Match sizes above 8 solo until load-tested.
- Third-party assets of any kind (all visuals code-procedural, all audio procedurally generated).

## 4. Success metrics (to be measured, not claimed)

- Per-match server CPU at 30 Hz ticks with 8 players (load test milestone M4).
- End-to-end integration test determinism: deploy → movement → hit → zone attrition → MATCH_END.
- CI: green test run on push/PR; debug APK artifact per main push; signed release AAB on tag/release.

## 5. Known limits and costs

- One UDP port per server instance; in-RAM state only (a crash ends live matches).
- ~3.7 GB RAM dev host limits local scale; CI runners provide the real build/test environment.
- Android export templates and the Godot binary (~40–60 MB downloads) are fetched by CI per run.
