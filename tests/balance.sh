#!/usr/bin/env bash
# Balanceamento em paralelo: ./tests/balance.sh <partidas> ["--set=chave=valor,..."] ["--ruleset=..."]
# Divide as partidas entre os núcleos da máquina e agrega o relatório.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
TOTAL="${1:-48}"; shift || true
JOBS="${JOBS:-$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || nproc 2>/dev/null || echo 4)}"
PER=$(( (TOTAL + JOBS - 1) / JOBS ))
TMP="$(mktemp -d)"
for ((j=0; j<JOBS; j++)); do
  "$GODOT" --headless --path . --script res://tests/balance.gd -- --json --matches=$PER --seed=$((1000 + j * PER)) "$@" \
    2>/dev/null | grep BALANCE_JSON | sed 's/^BALANCE_JSON //' > "$TMP/$j.json" &
done
wait
"$GODOT" --headless --path . --script res://tests/balance_report.gd -- "$TMP" "$@" 2>/dev/null | grep -v -E "^Godot Engine|^$|^\[FOTEBA\]"
rm -rf "$TMP"
