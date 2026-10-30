# Skyfall Legends

Original, self-hosted online multiplayer battle royale prototype for Android,
built in **Godot 4.7.2** (MIT). Server-authoritative: the dedicated server owns
all match state (damage, inventory, loot, zone, victory); clients send intent,
never outcomes.

## Honest status (this repository)

| Area | Local verification | Notes |
|------|-------------------|-------|
| Unit + integration tests (2 real ENet clients vs headless server) | **Running / iterating** | See `.github/workflows/automated-tests.yml`; last local run: 92 passed, 19 failed; fixes landed, re-run in progress |
| Headless server (game mode) | Verified | `godot --headless` starts and binds UDP; editor `--import` crashes in this proot host (see `docs/ENVIRONMENT_AUDIT.md`) |
| Android APK/AAB export | Not locally verified | No Android SDK locally; CI builds debug APK + release AAB via `android-build.yml` (release signing needs GitHub Secrets) |
| Procedural SFX | Generated | 12 original WAVs in `game/audio/` (see `tools/build/gen_sfx.py`); not yet wired into gameplay |
| Bots | Implemented | Server bots (`AI_###`) for lobby fill/practice only, run through the same validation path as clients |

Treat everything not marked "Verified" as a plan, not a claim. No builds, tests,
or artifacts are fabricated.

## Quick start

**Dedicated server** (headless):

```bash
git clone <this repo> && cd skyfall-legends
GODOT=/path/to/godot-4.7.2 ./server/run_server.sh server/config/server.json
```

Config: `server/config/server.json` (port, bot fill, zone start, weapon loadout).
See `server/README.md` for ops, rate limits, and match sizing.

**Client** (on a machine with a display):

```bash
godot --headless --path .   # main scene: res://game/scenes/boot.tscn
```

Connect clients to the server's UDP port (default 7777); lobbies auto-start
when readiness passes, bots fill empty seats when enabled.

**Run tests locally** (Godot 4.7.2):

```bash
python3 tools/build/gen_class_cache.py .
/path/to/godot-4.7.2 --headless --path . -s res://game/tests/run_tests.gd
```

Regenerating the class cache substitutes for `godot --import`, which crashes in
this proot environment (documented in `docs/ENVIRONMENT_AUDIT.md`).

## Repository layout

```
game/            Godot project: src/ (GDScript), scenes/, images/, audio/
tools/build/     Asset generators: gen_sfx.py (SFX), gen_class_cache.py
server/          Dedicated-server config, run script, systemd unit, ops docs
docs/            Authored documentation (audit, design, architecture, security, …)
.github/workflows/CI: automated-tests.yml, android-build.yml
project.godot    Godot project config
export_presets.cfg Linux server, Android debug APK, Android release AAB presets
```

## Documentation

- `docs/ENVIRONMENT_AUDIT.md` — host audit, PRoot `--import` crash evidence and workaround
- `docs/TOOL_CAPABILITY_MATRIX.md` — what works / what's verified / limits
- `docs/REPOSITORY_INVENTORY.md` — repo contents and preserved unrelated projects
- `docs/IMPLEMENTATION_ROADMAP.md` — milestones, done / in progress / planned
- `docs/PRD.md` — product requirements; 8-player solo first, scale after load tests
- `docs/GAME_DESIGN_DOCUMENT.md` — loop, controls, map, weapons, characters, zone
- `docs/TECHNICAL_ARCHITECTURE.md` — scenes, modules, data flow, procedural map
- `docs/MULTIPLAYER_ARCHITECTURE.md` — authority model, op codes, tick rates, bots
- `docs/SECURITY.md` — threat model, mitigations, signing
- `docs/BRAND_GUIDELINES.md`, `docs/ASSET_REGISTER.md`, `docs/ASSET_LICENSES.md`
- `docs/TEST_PLAN.md` — unit + integration + manual matrices
- `docs/RELEASE_GUIDE.md` — CI workflows, secrets, signing, artifacts

## Licensing

- Code: MIT (see `LICENSE`).
- Assets: all original/procedural (see `docs/ASSET_REGISTER.md`, `docs/ASSET_LICENSES.md`); no third-party or protected content.
- Engine: Godot 4.7.2 (MIT).

## Repository hygiene

Never commit `.godot/`, `build/`, `*.keystore`, `*.jks`, `*.log`, or secrets
(see `.gitignore`). Android signing keystore material enters CI only via
GitHub Secrets (`ANDROID_RELEASE_KEYSTORE_B64`, `_USER`, `_PASS`).
