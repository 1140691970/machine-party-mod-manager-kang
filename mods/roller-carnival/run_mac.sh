#!/usr/bin/env bash
set -euo pipefail

MOD_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$MOD_DIR/../.." && pwd)"
GODOT="$REPO_ROOT/.agent/mod-dev/tools/Godot.app/Contents/MacOS/Godot"

if [ ! -x "$GODOT" ]; then
  echo "ERROR: macOS Godot 4.5.2 binary not found at $GODOT" >&2
  exit 1
fi

MODE="${1:-play}"
case "$MODE" in
  --self-test)
    exec "$GODOT" --headless --path "$MOD_DIR" -- --self-test
    ;;
  --screenshot)
    OUT="${2:-$REPO_ROOT/.agent/mod-dev/dist/roller_carnival_preview.png}"
    exec "$GODOT" --path "$MOD_DIR" --windowed --resolution 1280x720 -- "--capture-screenshot=$OUT"
    ;;
  play|"")
    exec "$GODOT" --path "$MOD_DIR"
    ;;
  *)
    echo "Usage: $0 [play | --self-test | --screenshot <output.png>]" >&2
    exit 2
    ;;
esac
