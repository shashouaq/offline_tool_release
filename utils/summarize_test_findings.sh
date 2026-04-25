#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
LOG_DIR="${ROOT_DIR}/logs"
OUT_FILE="${ROOT_DIR}/docs/test-findings.md"
ROUND_ID="${1:-auto-$(date +%Y%m%d_%H%M%S)}"
MAX_FILES="${MAX_FILES:-8}"

if [[ ! -d "$LOG_DIR" ]]; then
  echo "[summary] log dir not found: $LOG_DIR"
  exit 1
fi

mapfile -t FILES < <(find "$LOG_DIR" -maxdepth 1 -type f -name "*.log" -printf "%T@|%p\n" \
  | sort -t'|' -k1,1nr \
  | head -n "$MAX_FILES" \
  | cut -d'|' -f2-)

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "[summary] no log files found"
  exit 1
fi

tmp="$(mktemp)"
{
  echo ""
  echo "### Round: ${ROUND_ID}"
  echo "- Environment:"
  echo "  - OS: mixed"
  echo "  - Arch: mixed"
  echo "  - Online/Offline: mixed"
  echo "- Build/Script version: offline_tools_v14.sh"
  echo "- Test scope: auto summary from logs"
  echo "- Result summary:"
} >"$tmp"

passed=0
failed=0

for f in "${FILES[@]}"; do
  name="$(basename "$f")"
  menu_hits="$(grep -Eci 'dep_check/menu_render|Environment self-check|环境自检|Select \[1/2/0\]|请选择 \[1/2/0\]' "$f" || true)"
  err_hits="$(grep -Eci '(^|\]) *\[ERR\]| FAIL|failed|invalid_input|ERROR' "$f" || true)"
  select_ok_hits="$(grep -Eci 'select/target_system.*result=ok' "$f" || true)"
  if [[ "$err_hits" -eq 0 ]]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
  fi
  {
    echo "  - ${name}: menu_hits=${menu_hits}, select_ok=${select_ok_hits}, err_hits=${err_hits}"
  } >>"$tmp"
done

{
  echo "  - Passed: ${passed}"
  echo "  - Failed: ${failed}"
  echo "- Failures:"
  echo "  1. Symptom: see per-log err_hits > 0"
  echo "  2. Repro steps: run with same script and menu inputs"
  echo "  3. Expected: menu visible and flow continues"
  echo "  4. Actual: determined by log metrics above"
  echo "  5. Root cause: pending manual confirmation for each failed log"
  echo "  6. Fix: align menu rendering + input handling + logging"
  echo "  7. Re-test result: pending"
  echo "- Logs:"
  for f in "${FILES[@]}"; do
    echo "  - Path: ${f#${ROOT_DIR}/}"
    echo "  - Key lines:"
    grep -Ei 'dep_check/menu_render|Environment self-check|环境自检|select/target_system|result=ok|FAIL|failed|invalid_input|ERROR' "$f" | tail -n 6 | sed 's/^/    - /' || true
  done
} >>"$tmp"

cat "$tmp" >> "$OUT_FILE"
rm -f "$tmp"
echo "[summary] appended round ${ROUND_ID} -> ${OUT_FILE}"

