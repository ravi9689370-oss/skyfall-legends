# Tool capability matrix — Skyfall Legends

What each tool in the pipeline can and cannot do, and what has been verified.

| Capability | Tool / location | Status | Notes |
|------------|-----------------|--------|-------|
| Engine (Godot 4.7.2, MIT) | `/root/tools/godot-4.7.2` | Available | Headless-capable via game mode |
| Dedicated server run | `server/run_server.sh` | Verified locally | Starts, binds UDP port, runs matches |
| Client run (dev machine) | `godot --path .` | Verified in game mode | Editor GUI crashes in PRoot host |
| `godot --import` / class cache | Editor (broken) / `tools/build/gen_class_cache.py` | Cache generator works | Editor crash worked around by direct cache gen |
| Unit tests | `game/tests/test_runner.gd` + `run_tests.gd` | Iterating | Headless; last run: most pass, a handful of fixes landed |
| Integration tests (real ENet clients) | Same suite, 2 clients over loopback | Iterating | Dedicated server as separate OS process |
| Android debug APK | CI `android-build.yml` | Not yet run locally | No Android SDK locally; preset defined |
| Android release AAB | CI `android-build.yml` | Not yet run locally | Signing via GitHub Secrets only |
| SFX generation | `tools/build/gen_sfx.py` | Works | 12 original WAVs in `game/audio/` |
| Asset import (textures/models) | None | N/A | All visuals code-procedural; no third-party assets |
| Version control | git at `/root/skyfall-legends` | Initialized, no commits | User: Skyfall CI Bot / dev@skyfall-legends.local |

## Limits

- Local matches are capped at 8 solo / 9 squad by design (`MatchRules.MODE_PLAYERS`)
  and should only be raised after load testing on the target host.
- Rate limit: 70 messages/second per peer; 3 violations → disconnect.
- One UDP port per server instance; state is in RAM only (no persistence).
- No local build verification for Android; CI artifact claims are unverified
  until the workflow runs successfully.
