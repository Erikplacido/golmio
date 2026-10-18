#!/usr/bin/env bash
# Capturas de todas as telas nas quatro resoluções de referência (celular em retrato e deitado,
# notebook e desktop). Perfil de save próprio: não toca no save do jogador.
#   ./tools/capturar_telas.sh [pasta_de_saida] [rotas separadas por vírgula]
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="${1:-/tmp/foteba_telas}"
ROUTES="${2:-}"
EXTRA=()
[ -n "$ROUTES" ] && EXTRA+=("--routes=$ROUTES")
FIRST=1
for RES in 390x844 844x390 1280x800 1920x1080; do
  ARGS=(--keep-window --profile=capturas --ruleset=dev "--out=$OUT")
  if [ $FIRST -eq 1 ]; then ARGS+=(--fresh --play=3 --official); FIRST=0; fi
  "$GODOT" --path . --resolution "$RES" res://tools/screens_snapshot.tscn -- "${ARGS[@]}" ${EXTRA[@]+"${EXTRA[@]}"} 2>&1 | grep -E "capturas|ERROR|SCRIPT" || true
done
echo "Capturas em $OUT"
