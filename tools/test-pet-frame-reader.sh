#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/limit-rings-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
# Reuse the production types and replace only the application entry point.
sed '/^#if PET_FRAME_READER_TEST/,$d' "$ROOT/tools/codex-pet-limit-rings.swift" > "$TEST_DIR/main.swift"
cat "$ROOT/tests/pet-frame-reader.swift" >> "$TEST_DIR/main.swift"
swiftc -module-cache-path "$TEST_DIR/module-cache" "$TEST_DIR/main.swift" -o "$TEST_DIR/test" -framework AppKit -lsqlite3
"$TEST_DIR/test"
