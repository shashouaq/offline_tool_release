#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
cd "$ROOT_DIR"

echo "[quality] root: $ROOT_DIR"

SH_FILES=()
while IFS= read -r f; do
  SH_FILES+=("$f")
done < <(find . -type f -name "*.sh" | sort)

if [[ ${#SH_FILES[@]} -eq 0 ]]; then
  echo "[quality] no shell files found"
  exit 0
fi

echo "[quality] bash -n syntax check"
bash -n "${SH_FILES[@]}"
echo "[quality] syntax: PASS"

echo "[quality] line ending check (CRLF forbidden for .sh)"
CRLF_HITS=0
for f in "${SH_FILES[@]}"; do
  if grep -q $'\r' "$f"; then
    echo "[quality] CRLF found: $f"
    CRLF_HITS=$((CRLF_HITS + 1))
  fi
done
if [[ $CRLF_HITS -gt 0 ]]; then
  echo "[quality] line ending: FAIL ($CRLF_HITS files)"
  exit 2
fi
echo "[quality] line ending: PASS"

if command -v shellcheck >/dev/null 2>&1; then
  echo "[quality] shellcheck"
  shellcheck "${SH_FILES[@]}"
  echo "[quality] shellcheck: PASS"
else
  echo "[quality] shellcheck: SKIP (not installed)"
fi

if command -v shfmt >/dev/null 2>&1; then
  echo "[quality] shfmt -d"
  shfmt -d "${SH_FILES[@]}"
  echo "[quality] shfmt: PASS"
else
  echo "[quality] shfmt: SKIP (not installed)"
fi

if [[ -x "./offline_tools_v14.sh" ]]; then
  echo "[quality] smoke: ./offline_tools_v14.sh --version"
  ./offline_tools_v14.sh --version >/dev/null
  echo "[quality] smoke: PASS"
else
  echo "[quality] smoke: SKIP (offline_tools_v14.sh not executable)"
fi

echo "[quality] ALL CHECKS DONE"

