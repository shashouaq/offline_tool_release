#!/bin/bash
set -euo pipefail
cd "${1:-/root/offline_tool_release_v1}"
printf '1\n1\n1\n1\n1\n1\n' | TOOL_SELECTION_MODE=group OFFLINE_TOOLS_LANG=zh_CN ./offline_tools_v1.sh
