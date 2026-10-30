# Environment audit — Skyfall Legends

Generated as part of repository setup. This file describes the host the
project was developed on and the consequences for tooling, builds, and tests.

## Host

| Item | Value |
|------|-------|
| Architecture | aarch64 Linux |
| OS | Ubuntu 26.04 (inside PRoot) |
| CPU | 8 cores |
| Memory | ~3.7 GB RAM |
| Network | Available (GitHub and godotengine.org reachable) |
| Java | Java 17 (temurin-compatible) |
| Android SDK | Not installed locally |
| Display / GPU | No reliable graphical display for the Godot editor |

## Godot engine

- **Version:** Godot 4.7.2-stable (MIT)
- **Binary:** `/root/tools/godot-4.7.2` (official Linux x86_64 release)
- **Game mode (`--headless --path .`):** Verified working — dedicated server
  starts, binds UDP, and runs matches; headless test suite runs (SceneTree
  script probe works).
- **Editor mode (`--import`, `--export`, GUI):** **Crashes** on startup with
  `double free or corruption (out)` even on a brand-new minimal project. This
  is an environmental PRoot heap-corruption issue, not a project issue.

## Editor crash — evidence and mitigations attempted

Command tried (and equivalents):

```bash
/root/tools/godot-4.7.2 --editor --import
```

Fails with `double free or corruption (out)` immediately during import, before
any project-specific work. Mitigations attempted, **none successful**:

- `MALLOC_CHECK_=0`
- `MALLOC_ARENA_MAX=1`
- `taskset -c 0` (single core)
- `LD_PRELOAD=libjemalloc.so` (jemalloc)
- `DDRAW_DISABLE=1` / `Dummy` display driver (`--display-driver`)
- Minimal empty project (reproduces the same crash)

## Consequences for this project

1. **`godot --import` cannot be used locally.** The script class cache required
   by `class_name` scripts is generated directly by
   `tools/build/gen_class_cache.py .` (format verified against Godot 4.7.2
   `ProjectSettings::get_global_class_list`: a `list=[{...}]` array of
   dictionaries in the ConfigFile empty section). This substitutes for the
   editor's import step and is part of the local test loop and CI.
2. **No local APK/AAB export.** There is no Android SDK locally and the editor
   cannot run exports. Android builds happen exclusively in CI
   (`.github/workflows/android-build.yml`). Release signing keys are never
   stored in the repository (GitHub Secrets only).
3. **All local verification is headless.** The test suite
   (`res://game/tests/run_tests.gd`) runs the dedicated server as a separate OS
   process plus two real ENet clients over loopback — no editor, no display,
   no GPU.

## `rea` MCP server

The `rea` toolset is reverse-engineering only (binary inspection, debugging,
tracing). It provides no build, export, or Godot-authoring capability and was
not used to produce project code or assets.
