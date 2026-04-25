#!/bin/bash
# 测试包组配置功能

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CONF_DIR="$SCRIPT_DIR/conf"
export LOG_FILE="/tmp/test_package_groups.log"
export WORK_DIR="/tmp/test_work"
export TARGET_OS="openEuler22.03"

# 定义颜色变量
export COLOR_BOLD=$'\033[1m'
export COLOR_RESET=$'\033[0m'
export COLOR_CYAN=$'\033[36m'
export COLOR_YELLOW=$'\033[33m'
export COLOR_GREEN=$'\033[32m'
export COLOR_RED=$'\033[31m'

# 加载必要的函数
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/display.sh"

echo "=========================================="
echo "测试1: 加载工具配置 (openEuler22.03)"
echo "=========================================="
load_tools_config "$CONF_DIR" "$TARGET_OS"

echo ""
echo "加载的工具数量: ${#AVAILABLE_TOOLS[@]}"
echo ""

echo "=========================================="
echo "测试2: 获取不同OS的包名对比"
echo "=========================================="
test_tools=("htop" "git" "vim" "gnome-desktop" "ukui-desktop")

printf "\n  %-15s %-35s %s\n" "工具ID" "RPM (openEuler)" "DEB (Ubuntu)"
printf "  %-15s %-35s %s\n" "---------------" "-----------------------------------" "-----------------------------------"

for tool in "${test_tools[@]}"; do
    rpm_pkgs=$(get_tool_packages_for_os "$tool" "openEuler22.03")
    deb_pkgs=$(get_tool_packages_for_os "$tool" "Ubuntu22.04")
    
    # 截断过长的显示
    [[ ${#rpm_pkgs} -gt 33 ]] && rpm_pkgs="${rpm_pkgs:0:30}..."
    [[ ${#deb_pkgs} -gt 33 ]] && deb_pkgs="${deb_pkgs:0:30}..."
    
    printf "  %-15s %-35s %s\n" "$tool" "$rpm_pkgs" "$deb_pkgs"
done

echo ""
echo "=========================================="
echo "测试3: 显示工具列表（带包组信息）"
echo "=========================================="

# 构建显示条目
display_entries=()
for i in {0..9}; do
    display_entries+=("${AVAILABLE_TOOLS[$i]}|${AVAILABLE_TOOL_DESCS[$i]}")
done

display_tools_with_packages "$TARGET_OS" "${display_entries[@]}"

echo "=========================================="
echo "测试完成！"
echo "=========================================="
