#!/usr/bin/env bash
# Builds test variants of the web export and runs the game's own headless
# test scenes in Chromium. Usage: tools/run_ci.sh (from the repo root).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
mkdir -p "$BUILD"
python3 "$ROOT/tools/pck_tools.py" make-test-build "$ROOT" "$BUILD/tests" res://tests/test_runner.tscn
python3 "$ROOT/tools/pck_tools.py" make-test-build "$ROOT" "$BUILD/bot" res://tests/bot_playthrough.tscn
cd "$ROOT/tools"
echo "== unit-style test scene"
node web_harness.mjs "$BUILD/tests" 600000 'RESULT:' "$BUILD/tests.png" | tee "$BUILD/tests.log"
grep -q 'RESULT: \([0-9]*\)/\1 passed' "$BUILD/tests.log" || { echo "test scene did not fully pass"; exit 1; }
echo "== bot playthrough (all levels)"
node web_harness.mjs "$BUILD/bot" 1500000 'RESULT:' "$BUILD/bot.png" | tee "$BUILD/bot.log"
grep -q 'RESULT: WIN' "$BUILD/bot.log" || { echo "bot did not win"; exit 1; }
echo "all checks passed"
