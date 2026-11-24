#!/usr/bin/env bash
# Headless smoke test. Usage: tests/run_smoke.sh [path-to-godot-4.7.2]
# Fails if the test fails OR any SCRIPT ERROR / ERROR line is printed.
set -u
GODOT="${1:-${GODOT:-godot}}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import > /dev/null 2>&1 || true
OUT="$(mktemp)"
timeout 600 "$GODOT" --headless --path . -s tests/smoke_test.gd > "$OUT" 2>&1
CODE=$?
cat "$OUT"
if grep -qE "SCRIPT ERROR|^ERROR|Parse Error" "$OUT"; then
	echo "Smoke test: errors were printed"
	CODE=1
fi
rm -f "$OUT"
exit $CODE
