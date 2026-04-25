#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
cd "$ROOT_DIR"

echo "[menu-test] root: $ROOT_DIR"

if ! command -v expect >/dev/null 2>&1; then
  echo "[menu-test] FAIL: expect not installed"
  echo "[menu-test] install hint:"
  echo "  - RPM: sudo dnf install -y expect"
  echo "  - DEB: sudo apt-get install -y expect"
  exit 2
fi

chmod +x ./offline_tools_v14.sh ./utils/test_menu_visibility.expect

./utils/test_menu_visibility.expect "$ROOT_DIR"

