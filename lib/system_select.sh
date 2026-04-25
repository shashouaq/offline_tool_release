#!/bin/bash
# Target OS/arch selection workflow.

_ss_msg(){
    local zh="$1" en="$2"
    lang_pick "$zh" "$en"
}

select_os_arch(){
    local conf_dir="${1:-$CONF_DIR}"
    local work_dir="${2:-$WORK_DIR}"

    log_action_begin "select" "target_system"
    print_header "Offline Tools v14.0"

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
    echo ""
    echo "$(t DEB_SYSTEMS_TITLE)"
    echo " 12) $(t OS_UBUNTU20)"
    echo " 13) $(t OS_UBUNTU22)"
    echo " 14) $(t OS_UBUNTU24)"
    echo " 15) $(t OS_UBUNTU25)"
    echo " 16) $(t OS_KYLIN)"
    echo ""

    local detected cur_arch c
    detected=$(detect_current_os 2>/dev/null || true)
    cur_arch=$(detect_current_arch)
    if [[ -n "$detected" ]]; then
        show_status "info" "$(_ss_msg '[CN] Detected OS' 'Detected OS'): $detected ($cur_arch)"
        echo "$(_ss_msg '[CN] Press Enter to use detected OS, or input number to choose another' 'Press Enter to use detected OS, or input number to choose another')"
    fi

    read -r -p "$(t OS_USE_DETECTED): " c
    log_user_input "os_select" "${c:-auto-detect}"

    if [[ -z "$c" && -n "$detected" ]]; then
        TARGET_OS="$detected"
    else
        c=${c:-1}
        case "$c" in
             1) TARGET_OS="openEuler22.03" ;;
             2) TARGET_OS="openEuler24.03" ;;
             3) TARGET_OS="openEuler25.03" ;;
             4) TARGET_OS="Rocky8" ;;
             5) TARGET_OS="Rocky9" ;;
             6) TARGET_OS="CentOS7.6" ;;
             7) TARGET_OS="CentOS8.2" ;;
             8) TARGET_OS="AliOS3" ;;
             9) TARGET_OS="Tlinux31" ;;
            10) TARGET_OS="Tlinux32" ;;
            11) TARGET_OS="openAnolis84" ;;
            12) TARGET_OS="Ubuntu20.04" ;;
            13) TARGET_OS="Ubuntu22.04" ;;
            14) TARGET_OS="Ubuntu24.04" ;;
            15) TARGET_OS="Ubuntu25.10" ;;
            16) TARGET_OS="Kylin" ;;
             *) TARGET_OS="openEuler22.03" ;;
        esac
    fi

    print_section "$(t OS_ARCH_TITLE)"
    echo "  1) $(t ARCH_X86)"
    echo "  2) $(t ARCH_AARCH)"
    echo "  3) $(t ARCH_LOONGARCH)"
    read -r -p "$(_ss_msg '[CN] Select architecture [1]: ' 'Select architecture [1]: ')" c
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
    read -r -p "$(_ss_msg '[CN] Select [1]: ' 'Select [1]: ')" c
    c=${c:-1}
    [[ "$c" == "2" ]] && SKIP_SSL=1 || SKIP_SSL=0

    RELEASE_VER=$(get_releasever "$TARGET_OS")
    FORCEARCH="$TARGET_ARCH"
    log "[config] target=${TARGET_OS}/${TARGET_ARCH} release=${RELEASE_VER} skip_ssl=${SKIP_SSL}"

    load_os_config "$TARGET_OS" || { log_action_end "select" "target_system" "failed" "load_os_config"; return 1; }
    pick_best_repos
    print_section "$(_ss_msg '[CN] Entering environment self-check menu' 'Entering environment self-check menu')"
    check_install_deps || { log_action_end "select" "target_system" "failed" "dependency_check"; return 1; }

    STATIC_TARBALL="$work_dir/output/offline_${TARGET_OS}_${TARGET_ARCH}_merged.tar.xz"
    log_action_end "select" "target_system" "ok" "${TARGET_OS}/${TARGET_ARCH}"
    return 0
}

show_system_summary(){
    local target_os="$1"
    local target_arch="$2"
    print_section "$(_ss_msg '[CN] System Summary' 'System Summary')"
    echo "  $(t CONFIG_TARGET): $target_os"
    echo "  $(t INSTALL_ARCH): $target_arch"
    echo "  $(t PKG_TYPE): $(get_pkg_type_from_os "$target_os")"
    echo "  Release: $(get_releasever "$target_os")"
    echo "  SSL: $([[ "$SKIP_SSL" == "1" ]] && echo yes || echo no)"
}

get_pkg_type_from_os(){
    local os="$1"
    case "$os" in
        Ubuntu*|Kylin) echo "deb" ;;
        *) echo "rpm" ;;
    esac
}
