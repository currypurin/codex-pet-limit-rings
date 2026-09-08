#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -lt 1 || $# -gt 3 ]]; then
  echo "Usage: $0 STATE_PATH [ITERATIONS=1000] [cached|changed]" >&2
  exit 2
fi
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/limit-rings-benchmark.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
sed '/^#if PET_FRAME_READER_TEST/,$d' "$ROOT/tools/codex-pet-limit-rings.swift" > "$TEST_DIR/main.swift"
cat "$ROOT/tests/benchmark-pet-frame-reader.swift" >> "$TEST_DIR/main.swift"
swiftc -O -module-cache-path "$TEST_DIR/module-cache" "$TEST_DIR/main.swift" -o "$TEST_DIR/benchmark" -framework AppKit -lsqlite3
/usr/bin/time -l "$TEST_DIR/benchmark" "$1" "${2:-1000}" "${3:-cached}"
