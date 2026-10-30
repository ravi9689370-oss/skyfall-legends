# Implementation roadmap — Skyfall Legends

Milestones are deliberately small: match size starts at 8 solo and increases
only after load testing. Status labels: **done**, **in progress**, **planned**,
**blocked (environment)**.

## M0 — Project foundation (done)

- Godot 4.7.2 project at repo root; 31 `class_name` scripts across core/map/match/net/client/ui.
- Server-authoritative MatchSim: zone, loot, combat, damage, inventory, weapons/items/characters DBs.
- ENet UDP custom binary op-code protocol (client ops 1–13, server ops 101–110).
- Reliability split: reliable for lobby/match lifecycle, unreliable for input/snapshots/ping/fire.
- Dedicated server scene + `server_main.gd` with `--cfg` JSON and CLI overrides.
- Rate limiting (70 msg/s per peer, 3 violations → kick), rooms/queues, bots via same validation path.
- Procedural map (analytic island, building AABBs), procedural SFX (12 WAVs), original icon SVG.
- Repo scaffolding: `.gitignore`, `LICENSE`, `README.md`, server config/run script/systemd unit, CI workflows, this documentation set.

## M1 — Test suite green (in progress)

- Unit tests and the integration suite (dedicated server process + 2 real ENet clients over loopback) all pass locally under headless Godot 4.7.2.
- Local run command: `python3 tools/build/gen_class_cache.py . && godot --headless --path . -s res://game/tests/run_tests.gd`
- Previous local run: 92 passed, 19 failed; fixes applied (see commit-free work tree), re-run in progress.

## M2 — CI pipelines (written, awaiting successful runs)

- `.github/workflows/automated-tests.yml`: downloads Godot 4.7.2, generates class cache, runs suite on push/PR.
- `.github/workflows/android-build.yml`: JDK 17 + Android SDK + Godot export templates; debug APK always; signed release AAB when GitHub Secrets are configured.
- Not yet verified: workflows have not run (no Android SDK locally; Godot binary downloaded at CI time).

## M3 — Android artifacts from CI (planned)

- First successful `android-build.yml` run produces `build/skyfall-debug.apk` and (with secrets) signed `build/skyfall-release.aab`.
- Artifact claims are treated as unverified until a run uploads them.

## M4 — Load testing and match-size decision (planned)

- Measure per-match CPU tick budget at 8 solo / 9 squad on target host.
- Only then consider raising `MatchRules.MODE_PLAYERS`; document measured capacity.

## M5 — Documentation complete (in progress)

- All required docs authored (this repo, `docs/`). `docs/STATUS.md` keeps the verified/unverified matrix current.

## Blocked items

- Local editor export / `--import`: blocked by PRoot heap corruption (see `docs/ENVIRONMENT_AUDIT.md`). Workaround: class-cache generator; exports deferred to CI.
- Local Android build verification: blocked by missing Android SDK. Deferred to CI.
