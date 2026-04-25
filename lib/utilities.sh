#!/bin/bash
# =====================================================
# 实用工具模块
# 功能：日志查看、清理、帮助等辅助功能
# =====================================================

# =============================================
# 查看日志
# =============================================
show_log(){
    local log_file="${1:-$LOG_FILE}"

    if [[ ! -f "$log_file" ]]; then
        echo "$(t LOG_EMPTY)"
        show_navigation_menu "main_menu"
        return
    fi

    echo ""
    print_section "$(t LOG_TITLE)"

    # 显示最后60行
    tail -60 "$log_file"

    echo ""
    echo "--- 更多操作 ---"
    echo "  1) 查看全部日志"
    echo "  2) 搜索日志内容"
    echo "  3) 导出日志到文件"
    echo "  0) 返回主菜单"
    echo ""
    read -p "请选择 [0]: " choice
    choice=${choice:-0}

    case "$choice" in
        1)
            less "$log_file" 2>/dev/null || cat "$log_file"
            ;;
        2)
            read -p "输入搜索关键词: " keyword
            if [[ -n "$keyword" ]]; then
                grep -n --color=auto "$keyword" "$log_file" | tail -50
            fi
            ;;
        3)
            local export_file="${log_file%.log}_export_$(date '+%Y%m%d_%H%M%S').log"
            cp "$log_file" "$export_file"
            echo "日志已导出到: $export_file"
            ;;
    esac

    show_navigation_menu "main_menu"
}

# =============================================
# 清理工作区
# =============================================
cleanup(){
    local work_dir="${1:-$WORK_DIR}"
    local pkg_dir="$work_dir/packages"

    echo ""
    print_info "$(t CLEANUP_PROCESSING)..."

    # 清理下载缓存
    clear_download_cache

    # 清理工作目录（保留 output 和 logs）
    if [[ -d "$work_dir" ]] && [[ "$work_dir" != "/" ]]; then
        rm -rf "$work_dir"
        mkdir -p "$pkg_dir"
    fi

    # 清理临时文件
    rm -rf /tmp/manifest_tmp_*.txt
    rm -rf /tmp/merge_*
    rm -rf /tmp/offline_install_*

    print_success "$(t CLEANUP_DONE)"
    echo ""

    show_navigation_menu "main_menu"
}

# =============================================
# 显示帮助信息
# =============================================
show_help(){
    print_header "$(t HELP_TITLE)"

    cat <<HELP
$(t HELP_FEATURES):
  ✓ $(t HELP_FEATURES) - 16 OS (RPM/DEB)
  ✓ x86_64/aarch64/loongarch64
  ✓ GPG + SHA256
  ✓ Parallel Download
  ✓ Metadata Tracking
  ✓ Safe Install

$(t HELP_WORKFLOW):
  1. $(t MENU_DOWNLOAD) on online machine
  2. Select OS & Arch
  3. Select tools
  4. Wait for download
  5. Copy to offline machine
  6. $(t MENU_INSTALL)
  7. Auto-detect & install

$(t HELP_CONFIG):
  conf/os_sources.conf  - OS repo config
  conf/tools.conf       - Available tools

$(t HELP_OUTPUT):
  output/offline_OS_ARCH_merged.tar.xz      - Offline package
  output/offline_OS_ARCH_merged.tar.xz.sha256 - Checksum
  output/.metadata/OS_ARCH.meta              - Metadata

$(t HELP_MODULES):
  lib/ui.sh              - UI 界面组件
  lib/i18n.sh            - 国际化支持
  lib/logger.sh          - 日志系统
  lib/security.sh        - 安全验证
  lib/package_manager.sh - 包管理器
  lib/config.sh          - 配置加载
  lib/downloader.sh      - 下载引擎
  lib/metadata.sh        - 元数据管理
  lib/display.sh         - 显示组件
  lib/dependency_check.sh- 依赖检查
  lib/navigation.sh      - 导航系统
  lib/manifest.sh        - MANIFEST 管理
  lib/archive.sh         - 归档处理
  lib/system_select.sh   - 系统选择
  lib/tool_selector.sh   - 工具选择
  lib/workflow.sh        - 工作流引擎
  lib/installer.sh       - 安装器
  lib/utilities.sh       - 实用工具

HELP

    echo ""
    show_navigation_menu "main_menu"
}

# =============================================
# 显示系统状态摘要
# =============================================
show_system_status(){
    local work_dir="${1:-$WORK_DIR}"
    local output_dir="${2:-$OUTPUT_DIR}"

    print_section "系统状态"

    # 工作区状态
    echo "工作区:"
    echo "  路径: $work_dir"
    if [[ -d "$work_dir/packages" ]]; then
        local pkg_count
        pkg_count=$(find "$work_dir/packages" -type f \( -name "*.rpm" -o -name "*.deb" \) 2>/dev/null | wc -l)
        echo "  软件包: $pkg_count 个"
    else
        echo "  软件包: 未初始化"
    fi

    # 输出目录状态
    echo ""
    echo "输出目录:"
    echo "  路径: $output_dir"
    local output_count
    output_count=$(find "$output_dir" -maxdepth 1 -name "offline_*.tar.xz" ! -name "*.sha256" 2>/dev/null | wc -l)
    echo "  离线包: $output_count 个"

    # 磁盘使用情况
    echo ""
    echo "磁盘使用:"
    if command -v df &>/dev/null; then
        local usage
        usage=$(df -h "$work_dir" 2>/dev/null | tail -1)
        echo "  $usage"
    fi

    echo ""
}

# =============================================
# 诊断工具
# =============================================
run_diagnostics(){
    local work_dir="${1:-$WORK_DIR}"
    local conf_dir="${2:-$CONF_DIR}"

    print_section "系统诊断"

    echo "[1/6] 检查配置文件..."
    if [[ -f "$conf_dir/os_sources.conf" ]]; then
        echo "  ✓ os_sources.conf 存在"
    else
        echo "  ✗ os_sources.conf 缺失"
    fi

    if [[ -f "$conf_dir/tools.conf" ]]; then
        echo "  ✓ tools.conf 存在"
    else
        echo "  ✗ tools.conf 缺失"
    fi

    echo ""
    echo "[2/6] 检查必要命令..."
    local required_cmds=("curl" "wget" "tar" "sha256sum")
    for cmd in "${required_cmds[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            echo "  ✓ $cmd"
        else
            echo "  ✗ $cmd (缺失)"
        fi
    done

    echo ""
    echo "[3/6] 检查工作目录..."
    if [[ -d "$work_dir" ]]; then
        echo "  ✓ 工作目录存在: $work_dir"
    else
        echo "  ✗ 工作目录不存在"
    fi

    echo ""
    echo "[4/6] 检查网络连接..."
    if ping -c 1 -W 2 mirrors.aliyun.com &>/dev/null; then
        echo "  ✓ 网络正常"
    else
        echo "  ✗ 无法访问镜像源"
    fi

    echo ""
    echo "[5/6] 检查磁盘空间..."
    local available_space
    available_space=$(df -h "$work_dir" 2>/dev/null | tail -1 | awk '{print $4}')
    if [[ -n "$available_space" ]]; then
        echo "  可用空间: $available_space"
    else
        echo "  无法检测"
    fi

    echo ""
    echo "[6/6] 检查系统兼容性..."
    local cur_os
    cur_os=$(detect_current_os 2>/dev/null) || cur_os="unknown"
    local cur_arch
    cur_arch=$(detect_current_arch)
    echo "  当前系统: $cur_os / $cur_arch"

    echo ""
    print_success "诊断完成"
}

# =============================================
# 备份和恢复功能
# =============================================
backup_configuration(){
    local conf_dir="${1:-$CONF_DIR}"
    local backup_dir="${2:-$conf_dir/backup}"

    mkdir -p "$backup_dir"
    local backup_file="$backup_dir/conf_backup_$(date '+%Y%m%d_%H%M%S').tar.gz"

    tar -czf "$backup_file" -C "$conf_dir" . 2>/dev/null

    if [[ $? -eq 0 ]]; then
        echo "配置已备份到: $backup_file"
    else
        echo "备份失败" >&2
        return 1
    fi
}

restore_configuration(){
    local backup_file="$1"
    local conf_dir="${2:-$CONF_DIR}"

    if [[ ! -f "$backup_file" ]]; then
        echo "备份文件不存在: $backup_file" >&2
        return 1
    fi

    tar -xzf "$backup_file" -C "$conf_dir" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        echo "配置已恢复"
    else
        echo "恢复失败" >&2
        return 1
    fi
}
