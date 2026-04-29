#!/bin/bash

show_log(){
    local log_file="${1:-$LOG_FILE}"
    if [[ ! -f "$log_file" ]]; then
        echo "$(t LOG_EMPTY)"
        show_navigation_menu "main_menu"
        return
    fi

    echo ""
    print_section "$(t LOG_TITLE)"
    tail -60 "$log_file"

    echo ""
    echo "--- $(lang_pick "更多操作" "More Actions") ---"
    echo "  1) $(lang_pick "查看完整日志" "View full log")"
    echo "  2) $(lang_pick "搜索日志" "Search in log")"
    echo "  3) $(lang_pick "导出日志副本" "Export log copy")"
    echo "  0) $(t BACK_MENU)"
    echo ""

    local choice
    read -r -p "$(lang_pick "请选择 [0]: " "Select [0]: ")" choice
    choice=${choice:-0}
    case "$choice" in
        1) less "$log_file" 2>/dev/null || cat "$log_file" ;;
        2)
            local keyword
            read -r -p "$(lang_pick "输入关键字: " "Enter keyword: ")" keyword
            [[ -n "$keyword" ]] && grep -n --color=auto "$keyword" "$log_file" | tail -50
            ;;
        3)
            local export_file="${log_file%.log}_export_$(date '+%Y%m%d_%H%M%S').log"
            cp "$log_file" "$export_file"
            echo "$(lang_pick "日志已导出到: " "Exported log to: ")$export_file"
            ;;
    esac
    show_navigation_menu "show_log"
}

cleanup(){
    local work_dir="${1:-$WORK_DIR}"
    local pkg_dir="$work_dir/packages"
    echo ""
    print_info "$(t CLEANUP_PROCESSING)..."
    clear_download_cache
    if [[ -d "$work_dir" ]] && [[ "$work_dir" != "/" ]]; then
        rm -rf "$work_dir"
        mkdir -p "$pkg_dir"
    fi
    rm -rf /tmp/manifest_tmp_*.txt /tmp/merge_* /tmp/offline_install_*
    print_success "$(t CLEANUP_DONE)"
    echo ""
    show_navigation_menu "main_menu"
}

show_help(){
    print_header "$(t HELP_TITLE)"
    cat <<HELP
$(t HELP_FEATURES):
  - 16 target OS profiles (RPM/DEB)
  - x86_64 / aarch64 / loongarch64
  - SHA256 checksum generation
  - Parallel download
  - Metadata and manifest tracking
  - Offline local-repo install flow

$(t HELP_WORKFLOW):
  1. Run $(t MENU_DOWNLOAD) on an online machine
  2. Select target OS and architecture
  3. Select tool groups or tools
  4. Wait for download and packaging
  5. Copy the offline bundle to the offline machine
  6. Run $(t MENU_INSTALL)
  7. Detect compatibility and install from local repo only

$(t HELP_CONFIG):
  conf/os_sources.conf         - repository definitions
  conf/tools.conf              - default tool catalog
  conf/tools.d/*.conf          - optional split tool catalogs
  conf/tool_os_rules.conf      - target-specific compatibility rules
  conf/timeout.conf            - runtime timeout settings

$(t HELP_OUTPUT):
  output/offline_OS_ARCH_merged.tar.xz
  output/offline_OS_ARCH_merged.tar.xz.sha256
  output/.metadata/OS_ARCH.meta

$(t HELP_MODULES):
  lib/ui.sh                    - terminal UI helpers
  lib/i18n.sh                  - bilingual text loading
  lib/logger.sh                - structured logging
  lib/config.sh                - repo and tool config loading
  lib/downloader.sh            - download engine
  lib/manifest.sh              - manifest.json contract
  lib/archive.sh               - offline package creation
  lib/installer.sh             - offline install workflow
  lib/workflow.sh              - end-to-end orchestration
HELP
    echo ""
    show_navigation_menu "main_menu"
}

show_system_status(){
    local work_dir="${1:-$WORK_DIR}" output_dir="${2:-$OUTPUT_DIR}"
    print_section "System Status"
    echo "Workspace:"
    echo "  Path: $work_dir"
    if [[ -d "$work_dir/packages" ]]; then
        local pkg_count
        pkg_count=$(find "$work_dir/packages" -type f \( -name "*.rpm" -o -name "*.deb" \) 2>/dev/null | wc -l)
        echo "  Packages: $pkg_count"
    else
        echo "  Packages: not initialized"
    fi
    echo ""
    echo "Output:"
    echo "  Path: $output_dir"
    local output_count
    output_count=$(find "$output_dir" -maxdepth 1 -name "offline_*.tar.xz" ! -name "*.sha256" 2>/dev/null | wc -l)
    echo "  Offline bundles: $output_count"
    echo ""
}

run_diagnostics(){
    local work_dir="${1:-$WORK_DIR}" conf_dir="${2:-$CONF_DIR}"
    print_section "System Diagnostics"
    echo "[1/6] Check configuration files"
    [[ -f "$conf_dir/os_sources.conf" ]] && echo "  OK os_sources.conf" || echo "  ERR os_sources.conf missing"
    [[ -f "$conf_dir/tools.conf" ]] && echo "  OK tools.conf" || echo "  ERR tools.conf missing"
    echo ""
    echo "[2/6] Check required commands"
    local required_cmds=("curl" "wget" "tar" "sha256sum") cmd
    for cmd in "${required_cmds[@]}"; do command -v "$cmd" &>/dev/null && echo "  OK $cmd" || echo "  ERR $cmd missing"; done
    echo ""
    echo "[3/6] Check workspace"
    [[ -d "$work_dir" ]] && echo "  OK workspace exists: $work_dir" || echo "  ERR workspace missing"
    echo ""
    echo "[4/6] Check network reachability"
    ping -c 1 -W 2 mirrors.aliyun.com &>/dev/null && echo "  OK network reachable" || echo "  WARN unable to reach mirror probe host"
    echo ""
    echo "[5/6] Check disk space"
    local available_space
    available_space=$(df -h "$work_dir" 2>/dev/null | tail -1 | awk '{print $4}')
    [[ -n "$available_space" ]] && echo "  Available: $available_space" || echo "  Unknown"
    echo ""
    echo "[6/6] Check current system"
    local cur_os cur_arch
    cur_os=$(detect_current_os 2>/dev/null || echo "unknown")
    cur_arch=$(detect_current_arch)
    echo "  Current system: $cur_os / $cur_arch"
    echo ""
    print_success "Diagnostics complete"
}

backup_configuration(){
    local conf_dir="${1:-$CONF_DIR}" backup_dir="${2:-$conf_dir/backup}"
    mkdir -p "$backup_dir"
    local backup_file="$backup_dir/conf_backup_$(date '+%Y%m%d_%H%M%S').tar.gz"
    tar -czf "$backup_file" -C "$conf_dir" . 2>/dev/null || { echo "Backup failed" >&2; return 1; }
    echo "Configuration backup created: $backup_file"
}

export -f show_log
export -f cleanup
export -f show_help
export -f show_system_status
export -f run_diagnostics
export -f backup_configuration
