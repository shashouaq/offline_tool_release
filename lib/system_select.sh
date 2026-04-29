#!/bin/bash

_ss_msg(){ local zh="$1" en="$2"; lang_pick "$zh" "$en"; }

select_os_arch(){
    local conf_dir="${1:-$CONF_DIR}" work_dir="${2:-$WORK_DIR}"
    log_action_begin "select" "target_system"
    print_header "Offline Tools v1.0"

    local host_pkg_type="rpm"
    if command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
        host_pkg_type="rpm"
    elif command -v apt-get >/dev/null 2>&1; then
        host_pkg_type="deb"
    fi

    local -a menu_os=()
    if [[ "$host_pkg_type" == "deb" ]]; then
        echo "$(t DEB_SYSTEMS_TITLE)"
        echo "  1) $(t OS_UBUNTU20)"
        echo "  2) $(t OS_UBUNTU22)"
        echo "  3) $(t OS_UBUNTU24)"
        echo "  4) $(t OS_UBUNTU25)"
        echo "  5) $(t OS_KYLIN)"
        menu_os=("Ubuntu20.04" "Ubuntu22.04" "Ubuntu24.04" "Ubuntu25.10" "Kylin")
    else
        echo "$(t RPM_SYSTEMS_TITLE)"
        echo "  1) $(t OS_OPENEULER22)"
        echo "  2) $(t OS_OPENEULER24)"
        echo "  3) $(t OS_OPENEULER25)"
        echo "  4) $(t OS_ROCKY8)"
        echo "  5) $(t OS_ROCKY9)"
        echo "  6) $(t OS_CENTOS7)"
        echo "  7) $(t OS_CENTOS8)"
        echo "  8) $(t OS_ALIOS)"
        echo "  9) $(t OS_TLINUX31)"
        echo " 10) $(t OS_TLINUX32)"
        echo " 11) $(t OS_OPENANOLIS)"
        menu_os=("openEuler22.03" "openEuler24.03" "openEuler25.03" "Rocky8" "Rocky9" "CentOS7.6" "CentOS8.2" "AliOS3" "Tlinux31" "Tlinux32" "openAnolis84")
    fi
    echo ""

    local detected cur_arch c
    detected=$(detect_current_os 2>/dev/null || true)
    cur_arch=$(detect_current_arch)
    if [[ -n "$detected" ]]; then
        show_status "info" "$(_ss_msg '检测到当前系统' 'Detected OS'): $detected ($cur_arch)"
        echo "$(_ss_msg '回车使用当前系统，输入编号切换目标系统' 'Press Enter to use detected OS, or input number to choose another')"
    fi
    echo "  0) $(t BACK_MENU)"
    read -r -p "$(t OS_USE_DETECTED): " c
    [[ "$c" == "0" ]] && { log_action_end "select" "target_system" "cancel" "back_from_os"; return 1; }
    log_user_input "os_select" "${c:-auto-detect}"

    if [[ -z "$c" && -n "$detected" ]]; then
        TARGET_OS="$detected"
    else
        c=${c:-1}
        if [[ "$c" =~ ^[0-9]+$ && "$c" -ge 1 && "$c" -le ${#menu_os[@]} ]]; then
            TARGET_OS="${menu_os[$((c-1))]}"
        else
            TARGET_OS="${menu_os[0]}"
        fi
    fi

    print_section "$(t OS_ARCH_TITLE)"
    echo "  1) $(t ARCH_X86)"
    echo "  2) $(t ARCH_AARCH)"
    echo "  3) $(t ARCH_LOONGARCH)"
    echo "  0) $(t BACK_MENU)"
    read -r -p "$(_ss_msg '请选择架构 [1]: ' 'Select architecture [1]: ')" c
    [[ "$c" == "0" ]] && { log_action_end "select" "target_system" "cancel" "back_from_arch"; return 1; }
    c=${c:-1}
    case "$c" in
        1) TARGET_ARCH="x86_64" ;;
        2) TARGET_ARCH="aarch64" ;;
        3) TARGET_ARCH="loongarch64" ;;
        *) TARGET_ARCH="x86_64" ;;
    esac

    print_section "$(t OS_SSL_TITLE)"
    echo "  1) $(t SSL_NO)"
    echo "  2) $(t SSL_YES)"
    echo "  0) $(t BACK_MENU)"
    read -r -p "$(_ss_msg '请选择 [1]: ' 'Select [1]: ')" c
    [[ "$c" == "0" ]] && { log_action_end "select" "target_system" "cancel" "back_from_ssl"; return 1; }
    c=${c:-1}
    [[ "$c" == "2" ]] && SKIP_SSL=1 || SKIP_SSL=0

    RELEASE_VER=$(get_releasever "$TARGET_OS")
    FORCEARCH="$TARGET_ARCH"
    log "[config] target=${TARGET_OS}/${TARGET_ARCH} release=${RELEASE_VER} skip_ssl=${SKIP_SSL}"

    load_os_config "$TARGET_OS" || { log_action_end "select" "target_system" "failed" "load_os_config"; return 1; }
    pick_best_repos
    print_section "$(_ss_msg '进入环境自检菜单' 'Entering environment self-check menu')"
    check_install_deps || { log_action_end "select" "target_system" "failed" "dependency_check"; return 1; }

    STATIC_TARBALL="$work_dir/output/offline_${TARGET_OS}_${TARGET_ARCH}_merged.tar.xz"
    log_action_end "select" "target_system" "ok" "${TARGET_OS}/${TARGET_ARCH}"
    return 0
}

show_system_summary(){
    local target_os="$1" target_arch="$2"
    print_section "$(_ss_msg '系统摘要' 'System Summary')"
    echo "  $(t CONFIG_TARGET): $target_os"
    echo "  $(t INSTALL_ARCH): $target_arch"
    echo "  $(t PKG_TYPE): $(get_pkg_type_from_os "$target_os")"
    echo "  Release: $(get_releasever "$target_os")"
    echo "  SSL: $([[ "$SKIP_SSL" == "1" ]] && echo yes || echo no)"
}

get_pkg_type_from_os(){
    case "$1" in
        Ubuntu*|Kylin) echo "deb" ;;
        *) echo "rpm" ;;
    esac
}
