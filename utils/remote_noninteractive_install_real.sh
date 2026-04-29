#!/bin/bash
set -euo pipefail
cd "${1:-/root/offline_tool_release_v1}"
printf '2\n1\n1\n1\n1\n0\n' | OFFLINE_TOOLS_LANG=zh_CN ./offline_tools_v1.sh
