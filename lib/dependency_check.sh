#!/bin/bash

declare -a DEP_MISSING=()

_dep_msg(){ local zh="$1" en="$2"; lang_pick "$zh" "$en"; }

dep_display_env_summary(){
    local cur_pm="$1"
    local pretty_os
    pretty_os=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")

    print_section "$(_dep_msg '环境自检' 'Environment self-check')"
    show_status "info" "$(t INSTALL_OS_NAME): ${pretty_os}"
    show_status "info" "$(t INSTALL_ARCH): $(uname -m)"
    show_status "info" "$(t INSTALL_KERNEL): $(uname -r)"
    show_status "info" "$(t WORKSPACE): $(df -h / | awk 'NR==2 {print $4}')"
    show_status "info" "$(t PKG_TYPE): ${cur_pm:-none}"
    show_status "info" "$(t CONFIG_TARGET): ${TARGET_OS:-unknown} (${PKG_TYPE:-unknown})"

    local current_os_name
    current_os_name=$(detect_current_os 2>/dev/null) || current_os_name=""
    if [[ -n "${TARGET_OS:-}" && -n "$current_os_name" ]] && [[ "$current_os_name" != "$TARGET_OS" ]]; then
        show_status "warn" "$(t WARNING): $(t CAUSE_SYSTEM_MISMATCH)"
    else
        show_status "ok" "$(_dep_msg '当前系统信息正常' 'Current system info looks good')"
    fi
}

dep_mark_missing(){ DEP_MISSING+=("$1"); }

dep_collect_missing(){
    local cur_pm="$1"
    DEP_MISSING=()
    case "$cur_pm" in
        dnf|yum)
            if ! command -v dnf &>/dev/null && ! command -v yum &>/dev/null; then
                dep_mark_missing "dnf"
                show_status "error" "dnf/yum $(t CAUSE_NOT_FOUND)"
            else
                show_status "ok" "dnf/yum"
            fi
            if ! command -v createrepo_c &>/dev/null && ! command -v createrepo &>/dev/null; then
                dep_mark_missing "createrepo_c"
                show_status "error" "createrepo_c $(t CAUSE_NOT_FOUND)"
            else
                show_status "ok" "createrepo"
            fi
            ;;
        apt)
            if ! command -v dpkg-scanpackages &>/dev/null; then
                dep_mark_missing "dpkg-dev"
                show_status "error" "dpkg-dev $(t CAUSE_NOT_FOUND)"
            else
                show_status "ok" "dpkg-dev"
            fi
            ;;
        *)
            show_status "warn" "$(_dep_msg '未检测到包管理器(dnf/yum/apt)' 'Package manager not found (dnf/yum/apt)')"
            ;;
    esac
    if ! command -v tar &>/dev/null; then dep_mark_missing "tar"; show_status "error" "tar $(t CAUSE_NOT_FOUND)"; else show_status "ok" "tar"; fi
    if ! command -v curl &>/dev/null; then dep_mark_missing "curl"; show_status "error" "curl $(t CAUSE_NOT_FOUND)"; else show_status "ok" "curl"; fi
}

dep_manual_menu(){
    local -a missing=("$@")
    local choice
    log_event "INFO" "dep_check" "menu_render" "missing dependency menu shown" "count=${#missing[@]}" "items=${missing[*]}"
    while true; do
        print_section "$(_dep_msg '依赖处理' 'Dependency actions')"
        print_warning "$(_dep_msg '缺失依赖' 'Missing dependencies') (${#missing[@]}): ${missing[*]}"
        echo "  1) $(_dep_msg '自动安装缺失依赖' 'Auto install missing dependencies')"
        echo "  2) $(_dep_msg '继续执行（后续可能失败）' 'Continue anyway (may fail later)')"
        echo "  0) $(_dep_msg '返回' 'Back')"
        echo ""
        printf "%s" "$(_dep_msg '请选择 [1/2/0]: ' 'Select [1/2/0]: ')"
        read -r choice
        choice=${choice:-1}
        log_user_input "dep_manual_menu" "$choice"
        case "$choice" in
            1) return 10 ;;
            2) return 20 ;;
            0) return 30 ;;
            *) print_warning "$(_dep_msg '输入无效' 'Invalid input'): $choice" ;;
        esac
    done
}

check_install_deps(){
    local cur_pm
    cur_pm=$(detect_pkg_manager 2>/dev/null || true)
    dep_display_env_summary "$cur_pm"
    dep_collect_missing "$cur_pm"
    if [[ ${#DEP_MISSING[@]} -eq 0 ]]; then
        print_success "$(t INSTALL_VERIFY_SUCCESS)"
        log_event "INFO" "dep_check" "menu_render" "dependency pass menu shown"
        print_section "$(_dep_msg '依赖检查结果' 'Dependency check result')"
        echo "  1) $(_dep_msg '继续' 'Continue')"
        echo "  0) $(_dep_msg '返回' 'Back')"
        echo ""
        local pass_choice
        printf "%s" "$(_dep_msg '请选择 [1/0]: ' 'Select [1/0]: ')"
        read -r pass_choice
        pass_choice=${pass_choice:-1}
        log_user_input "dep_pass_menu" "$pass_choice"
        [[ "$pass_choice" == "0" ]] && return 1
        return 0
    fi
    dep_manual_menu "${DEP_MISSING[@]}"
    case $? in
        10) auto_install_deps "${DEP_MISSING[@]}" || return 1 ;;
        20) print_warning "$(_dep_msg '未自动安装，继续后续流程' 'Continue without auto-install')" ;;
        30) print_info "$(_dep_msg '返回上级菜单' 'Back to previous menu')"; return 1 ;;
        *) return 1 ;;
    esac
    return 0
}

auto_install_deps(){
    local -a to_install=("$@")
    local cur_pm
    cur_pm=$(detect_pkg_manager 2>/dev/null || true)
    [[ ${#to_install[@]} -eq 0 ]] && return 0
    print_info "$(t INSTALLING): ${to_install[*]}"
    case "$cur_pm" in
        dnf|yum)
            local pkg
            for pkg in "${to_install[@]}"; do
                if dnf install -y "$pkg" >/dev/null 2>&1 || yum install -y "$pkg" >/dev/null 2>&1; then
                    show_status "ok" "$pkg $(t INSTALL_SUCCESS)"
                else
                    show_status "error" "$pkg $(t INSTALL_FAILED)"
                    return 1
                fi
            done
            ;;
        apt)
            apt-get update -qq >/dev/null 2>&1 || true
            local pkg
            for pkg in "${to_install[@]}"; do
                if apt-get install -y "$pkg" >/dev/null 2>&1; then
                    show_status "ok" "$pkg $(t INSTALL_SUCCESS)"
                else
                    show_status "error" "$pkg $(t INSTALL_FAILED)"
                    return 1
                fi
            done
            ;;
        *)
            show_error_detail "$(t ERROR_CRITICAL)" "$(_dep_msg '不支持的包管理器' 'Unsupported package manager'): ${cur_pm:-none}" "$(t SOLUTION_CHECK_REPO)"
            return 1
            ;;
    esac
    print_success "$(t INSTALL_COMPLETE)"
    return 0
}

export -f dep_display_env_summary
export -f dep_collect_missing
export -f dep_manual_menu
export -f check_install_deps
export -f auto_install_deps
