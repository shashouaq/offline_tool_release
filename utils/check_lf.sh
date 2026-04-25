#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
cd "$ROOT_DIR"

hits=0
while IFS= read -r -d '' f; do
  if grep -q $'\r' "$f"; then
    echo "[lf-check] CRLF found: $f"
    hits=$((hits + 1))
  fi
done < <(find . -type f -name "*.sh" -print0 | sort -z)

if [[ $hits -gt 0 ]]; then
  echo "[lf-check] FAIL: $hits file(s) contain CRLF"
  exit 2
fi

echo "[lf-check] PASS"

