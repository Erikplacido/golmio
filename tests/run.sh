#!/usr/bin/env bash
# Roda a suíte headless e falha também se o Godot registrar qualquer SCRIPT ERROR.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1
LOG="$(mktemp)"
"$GODOT" --headless --path . --script res://tests/run_tests.gd 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$LOG"; then
  echo "!! Erros de script no log acima."
  STATUS=1
fi
rm -f "$LOG"
exit $STATUS
