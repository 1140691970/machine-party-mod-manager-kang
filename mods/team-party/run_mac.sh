#!/usr/bin/env bash
set -euo pipefail

MOD_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$MOD_DIR/../.." && pwd)"
GODOT="$REPO_ROOT/.agent/mod-dev/tools/Godot.app/Contents/MacOS/Godot"
SANDBOX="$REPO_ROOT/tests/mods/team_party_sandbox.gd"

if [ ! -x "$GODOT" ]; then
  echo "ERROR: macOS Godot 4.5.2 binary not found at $GODOT" >&2
  exit 1
fi

if [ -z "${MP_PCK_PATH:-}" ] && [ -r "$HOME/Downloads/Machine Party.pck" ]; then
  export MP_PCK_PATH="$HOME/Downloads/Machine Party.pck"
fi
if [ ! -r "${MP_PCK_PATH:-}" ]; then
  echo "Sandbox uses fallback visuals when MP_PCK_PATH is unset. Set MP_PCK_PATH to Machine Party.pck for full original assets." >&2
fi

rm -rf "$MOD_DIR/.godot" "$MOD_DIR"/*.uid
trap 'rm -rf "$MOD_DIR/.godot" "$MOD_DIR"/*.uid' EXIT

MODE="${1:-play}"
case "$MODE" in
  --self-test)
    "$GODOT" --headless --path "$MOD_DIR" --script "$SANDBOX" -- --sandbox-test
    ;;
  --screenshot)
    OUT="${2:-$REPO_ROOT/.agent/mod-dev/dist/team_party_sandbox.png}"
    "$GODOT" --path "$MOD_DIR" --windowed --resolution 1280x720 --script "$SANDBOX" -- "--sandbox-screenshot=$OUT"
    ;;
  play|"")
    "$GODOT" --path "$MOD_DIR" --windowed --resolution 1280x720 --script "$SANDBOX"
    ;;
  *)
    echo "Usage: $0 [play | --self-test | --screenshot <output.png>]" >&2
    exit 2
    ;;
esac
