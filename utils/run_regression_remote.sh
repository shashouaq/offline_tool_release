#!/bin/bash
set -euo pipefail
project="${1:-/root/offline_tool_release_v1}"
chmod +x "$project/utils/regression_download.exp" "$project/utils/regression_install.exp" 2>/dev/null || true
expect "$project/utils/regression_download.exp" "$project"
expect "$project/utils/regression_install.exp" "$project"
