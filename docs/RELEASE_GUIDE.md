# Release guide — Skyfall Legends

## Versioning

- Project version: `config/version = "0.8.0"` in `project.godot` (also `config_version=5`).
- Android `version/code = 1`, `version/name = "0.8.0"` (debug) / `"0.8.0"` (release) in
  `export_presets.cfg`. Bump both per release; keep code and name in sync.

## CI workflows

| Workflow | Triggers | Produces |
|----------|----------|----------|
| `.github/workflows/automated-tests.yml` | push/PR to main, manual | test pass/fail + `testrun.log` artifact |
| `.github/workflows/android-build.yml` | push main, tags `v*`, release published, manual | debug APK (always); signed release AAB (when secrets configured) |

## Android signing

Release signing requires three GitHub Secrets (never in source):

- `ANDROID_RELEASE_KEYSTORE_B64` — base64 of the `.jks`/`.keystore` file
- `ANDROID_RELEASE_KEYSTORE_USER` — keystore alias
- `ANDROID_RELEASE_KEYSTORE_PASSWORD` — keystore/alias password

The workflow decodes the keystore to a temp file and lets Godot read it via the
`GODOT_ANDROID_KEYSTORE_RELEASE_*` environment variables (Godot 4.7 supports
`get_or_env` for `keystore/release`, `_user`, `_password`). Without secrets,
only the unsigned debug APK is produced; an unsigned AAB cannot be installed or
published.

## Export templates

CI downloads `Godot_v4.7.2-stable_export_templates.tpz` from the official
godot-builds release and installs `android_debug`/`android_release` into
`~/.local/share/godot/export_templates/4.7.2-stable/`, then runs
`--install-android-build-template` followed by `--export-debug`/`--export-release`.

Presets in `export_presets.cfg` (unvalidated locally — editor crashes in this
host):

- `Linux Server (runs headless)` → `build/skyfall-server`
- `Android Debug (APK)` → `build/skyfall-debug.apk` (arm64-v8a, min SDK 24,
  target SDK 35, package `com.skyfalllegends.sandbox`)
- `Android Release (AAB)` → `build/skyfall-release.aab` (package
  `com.skyfalllegends.game`)

## Artifact policy

- `build/`, `.godot/`, keystores, and logs are gitignored and never committed.
- CI uploads `testrun.log` (7 days) and Android build outputs (30 days) as
  artifacts.
- Release tagging: push/create tag `vX.Y.Z` → `android-build.yml` builds the
  release AAB; create a GitHub Release and attach artifacts manually.

## Rollback

Revert the offending commit/tag; CI reruns rebuild artifacts from source.
There is no server-side rollback mechanism (state is in RAM).

## Local verification (not available in this host)

`godot --import` and `--export` crash under PRoot (see `docs/ENVIRONMENT_AUDIT.md`),
so preset-key validation and export outputs can only be validated in CI. Treat
all export-related claims as unverified until a workflow run succeeds.
