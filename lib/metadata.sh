#!/bin/bash
# =====================================================
# Package metadata management module - entrypoint
# Loads metadata submodules used by list/install workflows.
# =====================================================

METADATA_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/metadata"; pwd)"

source "$METADATA_MODULE_DIR/metadata_core.sh" || { echo "ERROR: failed to load metadata_core.sh"; return 1; }
source "$METADATA_MODULE_DIR/metadata_list.sh" || { echo "ERROR: failed to load metadata_list.sh"; return 1; }
source "$METADATA_MODULE_DIR/metadata_install.sh" || { echo "ERROR: failed to load metadata_install.sh"; return 1; }

# Advanced select/install orchestration stays in offline_tools_v1.sh because it
# coordinates multiple global runtime variables and menu functions.
