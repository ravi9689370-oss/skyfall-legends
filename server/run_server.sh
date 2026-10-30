#!/usr/bin/env bash
# run_server.sh — launch the headless authoritative server.
# Usage: ./server/run_server.sh [config.json]
#   GODOT  env override for the Godot 4.7 binary (default: godot on PATH)
set -euo pipefail

GODOT_BIN="${GODOT:-godot}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG="${1:-$ROOT/server/config/server.json}"

exec "$GODOT_BIN" --headless --path "$ROOT" \
  "$ROOT/game/scenes/dedicated_server.tscn" -- --cfg "$CFG"
