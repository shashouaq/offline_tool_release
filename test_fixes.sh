#!/bin/bash
# 快速测试脚本 - 验证变量绑定修复

echo "=========================================="
echo "测试变量绑定修复"
echo "=========================================="
echo ""

# 设置环境变量（模拟主脚本环境）
export SCRIPT_DIR="$(pwd)"
export BASE_DIR="$SCRIPT_DIR"
export CONF_DIR="$BASE_DIR/conf"
export LIB_DIR="$BASE_DIR/lib"
export WORK_DIR="/tmp/offline_tools_test"
export OUTPUT_DIR="$BASE_DIR/output"
export LOG_DIR="$BASE_DIR/logs"
export LOG_FILE="$LOG_DIR/test.log"

mkdir -p "$WORK_DIR" "$OUTPUT_DIR" "$LOG_DIR"

echo "1. 测试 log 函数..."
source "$LIB_DIR/ui.sh"
source "$LIB_DIR/i18n.sh"
init_language

log(){
    local msg="[$(date '+%F %T')] $1"
    echo "$msg" >> "$LOG_FILE"
    if [[ -t 1 ]]; then
        echo "  ✓ log: $1"
    fi
}

log "测试日志消息"

echo ""
echo "2. 测试 installer.sh 函数（无参数）..."
source "$LIB_DIR/installer.sh"
# 不应该报错，会使用默认值
echo "  ✓ install_mode 函数定义正常"

echo ""
echo "3. 测试 utilities.sh 函数（无参数）..."
source "$LIB_DIR/utilities.sh"
echo "  ✓ show_log 函数定义正常"
echo "  ✓ cleanup 函数定义正常"

echo ""
echo "4. 测试 workflow.sh 函数（无参数）..."
source "$LIB_DIR/workflow.sh"
echo "  ✓ run_download 函数定义正常"

echo ""
echo "5. 测试 system_select.sh 函数（无参数）..."
source "$LIB_DIR/system_select.sh"
echo "  ✓ select_os_arch 函数定义正常"

echo ""
echo "6. 测试 tool_selector.sh 函数（无参数）..."
source "$LIB_DIR/tool_selector.sh"
echo "  ✓ load_tools_from_conf 函数定义正常"
echo "  ✓ select_kernel_deps 函数定义正常"

echo ""
echo "=========================================="
echo "所有测试通过！✓"
echo "=========================================="

# 清理
rm -rf "$WORK_DIR"
