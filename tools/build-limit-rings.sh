#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/tmp/CodexPetLimitRings.app}"
BIN="$APP/Contents/MacOS/CodexPetLimitRings"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/tools/CodexPetLimitRings-Info.plist" "$APP/Contents/Info.plist"
swiftc -O "$ROOT/tools/codex-pet-limit-rings.swift" -o "$BIN" -framework AppKit -lsqlite3

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "$APP"
