#!/bin/bash
# =====================================================
# 包元数据管理模块 - metadata.sh (模块入口)
# 自动加载所有子模块
# =====================================================

METADATA_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/metadata"; pwd)"

# 加载子模块
source "$METADATA_MODULE_DIR/metadata_core.sh" || { echo "错误: 无法加载元数据核心模块"; return 1; }
source "$METADATA_MODULE_DIR/metadata_list.sh" || { echo "错误: 无法加载元数据列表模块"; return 1; }
source "$METADATA_MODULE_DIR/metadata_install.sh" || { echo "错误: 无法加载元数据安装模块"; return 1; }

# 高级功能（select_and_install_package等）保留在主脚本offline_tools_v14.sh中
# 因为它们依赖于多个全局变量和函数的协同工作
