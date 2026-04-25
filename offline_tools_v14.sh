#!/bin/bash
# =====================================================
# 缂傚倷绀侀崐钘夌暦閻㈢鍚归幖绮规閸熷懘鏌曟径鍫濆姎鐎电増姊归〃銉╂倷閹绘帗姣愰悷?v14.0 - 濠电姭鎷冮崨顓濈捕閻庤鎮傛禍鍫曞箖?# 闂備礁鎲″濠氬窗閺囥垹绀傛慨妞诲亾闁轰礁绉撮～婵嬵敇閻曚椒鐢婚梻浣哄帶閻ゅ洤螞閸曨厸鍋撻崹顐劷缂侇喖顭烽弫宥夊礋椤掆偓閳?| 濠电姰鍨奸崺鏍嚌妤ｅ啫鍨傛い蹇撶墕閸欏﹪鏌涢幘妞炬缁?| 闂備胶顭堢换鎰板疮椤栫偛姹查柣鏃傚帶缁犲弶銇勯弮鍥ㄧ《妞ゅ簶鍋撻梻?| 婵°倗濮烽崑鐐哄磿婵傛悶鈧線骞嬮悙纰樻灃闁诲函缍嗛崢鐣岀矈?
# 闂備礁鎼鍫ュ春閺嶎厽鍊垫い鏍仦閺咁剚鎱ㄥ鍡楀闁哄棙宀搁弻娑滅疀鐎ｎ亜顬夐柤鍨涙櫊閺屾稖顦虫い銊ユ噽閳ь剙鐏氶悡锟犲极瀹ュ洣娌柣鎰靛墻濞笺劍绻涚€涙鐭婃繛鏉戝槻鑿愭い鏇楀亾妤犵偛閰ｆ俊鍫曞川椤旂⒈浼呴梻浣告贡椤ｄ粙寮插☉銏″創?
# =====================================================
set -uo pipefail

# =============================================
# 闂備胶顭堢换鍫ュ礉瀹€鍕剳妞ゆ帒瀚惌妤佹叏濡炶浜鹃梺闈╃稻濡炶棄鐣烽鍕殕闁告劦浜為崬鎾倵閸偅绶查悗姘煎墴瀹曞綊宕归锝呭伎闁诲函缍嗘禍婊堫敋?
# =============================================
SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"
BASE_DIR="$SCRIPT_DIR"
CONF_DIR="$BASE_DIR/conf"
LIB_DIR="$BASE_DIR/lib"
WORK_DIR="${OFFLINE_TOOLS_WORK_DIR:-/tmp/offline_tools_v14}"
PKG_DIR="$WORK_DIR/packages"
OUTPUT_DIR="$BASE_DIR/output"
LOG_DIR="$BASE_DIR/logs"
LOG_FILE="$LOG_DIR/logs_$(date '+%Y%m%d').log"

ensure_tmp_capacity(){
    local required_gb="${OFFLINE_TOOLS_TMP_REQUIRED_GB:-20}"
    local tmp_path="${OFFLINE_TOOLS_TMP_PATH:-/tmp}"
    local available_gb
    available_gb=$(df -BG "$tmp_path" 2>/dev/null | awk 'NR==2 {gsub(/G/,"",$4); print $4+0}')
    [[ -z "$available_gb" || "$available_gb" -ge "$required_gb" ]] && return 0

    echo "[INFO] /tmp available space ${available_gb}GB is below ${required_gb}GB"

    if [[ "$(id -u 2>/dev/null || echo 1)" -ne 0 ]]; then
        WORK_DIR="${OFFLINE_TOOLS_TMP_FALLBACK:-/var/tmp/offline_tools_v14}"
        PKG_DIR="$WORK_DIR/packages"
        echo "[INFO] Non-root mode: switch WORK_DIR to $WORK_DIR"
        return 0
    fi

    if [[ "$(findmnt -n -o FSTYPE "$tmp_path" 2>/dev/null)" == "tmpfs" ]]; then
        if mount -o "remount,size=${required_gb}G" "$tmp_path" 2>/dev/null; then
            echo "[INFO] Remounted $tmp_path tmpfs to ${required_gb}G"
            return 0
        fi
    fi

    local mount_dir="${OFFLINE_TOOLS_TMPFS_DIR:-/tmp/offline_tools_v14_tmpfs}"
    mkdir -p "$mount_dir"
    if ! mountpoint -q "$mount_dir"; then
        mount -t tmpfs -o "size=${required_gb}G,mode=1777" tmpfs "$mount_dir" 2>/dev/null || {
            echo "[WARN] Unable to create tmpfs workspace; continue with WORK_DIR=$WORK_DIR"
            return 0
        }
    fi

    WORK_DIR="$mount_dir/work"
    PKG_DIR="$WORK_DIR/packages"
    echo "[INFO] Switched WORK_DIR to tmpfs workspace $WORK_DIR (${required_gb}G)"
}

ensure_tmp_capacity

# Clean only controlled offline_tools temporary work directories.
if [[ -d "$WORK_DIR" ]]; then
    case "$WORK_DIR" in
        /tmp/offline_tools_*|/var/tmp/offline_tools_*)
            echo "[INFO] Cleaning previous work directory: $WORK_DIR"
            rm -rf -- "$WORK_DIR"
            ;;
        *)
            echo "[ERROR] Refusing to clean uncontrolled work directory: $WORK_DIR" >&2
            exit 1
            ;;
    esac
fi
mkdir -p "$OUTPUT_DIR" "$LOG_DIR" "$WORK_DIR" "$PKG_DIR"

# 闂備胶鍎甸弲鈺呭窗濡ゅ懏鍋夐柨婵嗩槹閻撯偓閻庡箍鍎卞ú銊╁几?
TARGET_OS=""
TARGET_ARCH=""
PKG_TYPE=""
SKIP_SSL=0
RELEASE_VER=""
FORCEARCH=""
STATIC_TARBALL=""
TEMP_REPO_FILE=""

# 闁诲氦顫夐幃鍫曞磿闁秴鐭楅柛褎顨嗛悞璇差熆鐠轰警鍎忔い?
declare -a AVAILABLE_TOOLS=()
declare -a SELECTED_TOOLS=()
declare -a KERNEL_DEPS=()

# =============================================
# 闂備礁鎼悧鍐磻閹剧粯鍊堕煫鍥ㄦ尵缁犱即鎮楅崹顐ゅ弨鐎殿噮鍣ｆ俊鐑藉Ψ瑜忛宥夋⒑閸涘﹤鐏卞┑顔哄€濆鎶芥偄閸忓吋娅栭梺鍓插亝缁诲啴鐓鍕厱闁哄啫鍊搁瀷濠电偞娼欏鐪攇ger.sh濠电偞鍨堕弻銊╊敄閸涱喗娅犻柣妯挎珪婵挳鎮归幁鎺戝闁哄棗绻橀弻?# =============================================
_simple_log(){
    local msg="[$(date '+%F %T')] $1"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

# =============================================
# Load core modules
# =============================================
source "$LIB_DIR/ui.sh" || { echo "ERROR: failed to load ui.sh"; exit 1; }
source "$LIB_DIR/i18n.sh" || { echo "ERROR: failed to load i18n.sh"; exit 1; }

init_language

if [[ $# -eq 0 && -t 0 ]]; then
    show_language_menu
fi

source "$LIB_DIR/logger.sh" || { echo "ERROR: failed to load logger.sh"; exit 1; }
log_session_start
trap 'rc=$?; log_session_end "$rc"' EXIT
source "$LIB_DIR/security.sh" || { echo "ERROR: failed to load security.sh"; exit 1; }
source "$LIB_DIR/package_manager.sh" || { echo "ERROR: failed to load package_manager.sh"; exit 1; }
source "$LIB_DIR/config.sh" || { echo "ERROR: failed to load config.sh"; exit 1; }
source "$LIB_DIR/downloader.sh" || { echo "ERROR: failed to load downloader.sh"; exit 1; }
source "$LIB_DIR/metadata.sh" || { echo "ERROR: failed to load metadata.sh"; exit 1; }
source "$LIB_DIR/display.sh" || { echo "ERROR: failed to load display.sh"; exit 1; }
source "$LIB_DIR/dependency_check.sh" || { echo "ERROR: failed to load dependency_check.sh"; exit 1; }
source "$LIB_DIR/navigation.sh" || { echo "ERROR: failed to load navigation.sh"; exit 1; }
source "$LIB_DIR/manifest.sh" || { echo "ERROR: failed to load manifest.sh"; exit 1; }
source "$LIB_DIR/archive.sh" || { echo "ERROR: failed to load archive.sh"; exit 1; }
source "$LIB_DIR/system_select.sh" || { echo "ERROR: failed to load system_select.sh"; exit 1; }
source "$LIB_DIR/tool_selector.sh" || { echo "ERROR: failed to load tool_selector.sh"; exit 1; }
source "$LIB_DIR/workflow.sh" || { echo "ERROR: failed to load workflow.sh"; exit 1; }
source "$LIB_DIR/installer.sh" || { echo "ERROR: failed to load installer.sh"; exit 1; }
source "$LIB_DIR/utilities.sh" || { echo "ERROR: failed to load utilities.sh"; exit 1; }
source "$LIB_DIR/mirror_cache.sh" || { echo "ERROR: failed to load mirror_cache.sh"; exit 1; }

# Optional v14 modules
source "$LIB_DIR/signature.sh" 2>/dev/null || _simple_log "[WARN] failed to load signature.sh"
source "$LIB_DIR/incremental.sh" 2>/dev/null || _simple_log "[WARN] failed to load incremental.sh"
source "$LIB_DIR/dependency_tree.sh" 2>/dev/null || _simple_log "[WARN] failed to load dependency_tree.sh"
source "$LIB_DIR/version_check.sh" 2>/dev/null || _simple_log "[WARN] failed to load version_check.sh"

# =============================================
# 闂備礁鎼崯銊╁磿鏉堚晜宕查柡鍐ㄧ墕缁€鍕煠閹帒鍔滄繛鍫濈埣閺屻劌鈽夊Ο鐓庮暫闂佸憡鐟ョ换鎺撶閿曞倸鐒垫い鎺戝閻銇勯弽銊х煁闁哄棗绻橀弻?# =============================================
log(){
    local msg="[$(date '+%F %T')] $1"
    echo "$msg" >> "$LOG_FILE"
    # 闂備礁鎲￠悷顖涚濠婂喛鑰挎い蹇撴噽椤╂煡鏌曢崼婵嗩伀闂傚绉堕埀顒侇問閸犳牜鎹㈤幒妤冨祦闁糕剝蓱濞呯娀鏌涢幇闈涘箻缂傚牆顭烽弻娑㈠箣濠靛洦鍎撻梺绯曟櫅閻偐妲愰幒妤€閱囬柕蹇婃櫃缁?
    if [[ -t 1 ]]; then
        echo "$msg"
    fi
}

die(){
    log "ERROR: $1"
    exit 1
}

# =============================================
# Main menu
# =============================================
main_menu(){
    while true; do
        echo ""
        print_header "$(t MENU_TITLE)"
        echo "  1) $(t MENU_DOWNLOAD)"
        echo "  2) $(t MENU_INSTALL)"
        echo "  3) $(t MENU_LOG)"
        echo "  4) $(t MENU_CLEANUP)"
        echo "  5) $(t MENU_HELP)"
        echo "  0) $(t MENU_EXIT)"
        echo ""
        if ! read -p "$(t MENU_SELECT): " c; then
            log_interaction "menu" "eof_exit"
            exit 0
        fi
        if [[ -z "$c" && ! -t 0 ]]; then
            log_interaction "menu" "eof_exit"
            exit 0
        fi
        log_menu_selection "main_menu" "$c"

        case "$c" in
            1)
                log_interaction "menu" "download"
                run_download
                ;;
            2)
                log_interaction "menu" "install"
                install_mode
                ;;
            3)
                log_interaction "menu" "show_log"
                show_log
                ;;
            4)
                log_interaction "menu" "cleanup"
                cleanup
                ;;
            5)
                log_interaction "menu" "help"
                show_help
                ;;
            0)
                log_interaction "menu" "exit"
                print_color "$COLOR_GREEN" "$(t MENU_EXIT)!"
                exit 0
                ;;
            *)
                log_interaction "invalid_input" "$c"
                print_error "$(t ERROR): $(t MENU_SELECT)"
                sleep 1
                ;;
        esac
    done
}

# =============================================
# Command line arguments
# =============================================
handle_cli_args(){
    [[ $# -eq 0 ]] && return 0
    local command="$1"
    shift || true

    case "$command" in
        --generate-sig|--sig)
            local output_file="${1:-requirements.sig}"
            if [[ $# -gt 0 ]]; then shift; fi
            select_target_system
            load_tools_config "$CONF_DIR" "$TARGET_OS"
            local -a tools_to_use=()
            if [[ $# -gt 0 ]]; then
                tools_to_use=("$@")
            else
                load_tools_from_conf "$CONF_DIR" "$TARGET_OS"
                tools_to_use=("${SELECTED_TOOLS[@]}")
            fi
            [[ ${#tools_to_use[@]} -eq 0 ]] && die "ERROR: no tools selected"
            generate_signature_file "$output_file" "$TARGET_OS" "$TARGET_ARCH" "${tools_to_use[@]}"
            exit 0
            ;;
        --download-from-sig|--from-sig)
            local sig_file="${1:-}"
            [[ -z "$sig_file" ]] && die "ERROR: signature file is required"
            download_from_signature "$sig_file" "$WORK_DIR"
            exit 0
            ;;
        --merge-packages|--merge)
            local existing_pkg="${1:-}"
            local new_packages_dir="${2:-}"
            local output_pkg="${3:-merged_offline_package.tar.gz}"
            [[ -z "$existing_pkg" || -z "$new_packages_dir" ]] && die "Usage: $0 --merge existing.tar.gz packages_dir [output.tar.gz]"
            merge_offline_packages "$existing_pkg" "$new_packages_dir" "$output_pkg"
            exit 0
            ;;
        --dependency-tree|--deps)
            local package="${1:-}"
            [[ -z "$package" ]] && die "ERROR: package name is required"
            select_target_system
            TEMP_REPO_FILE=$(generate_repo_config)
            show_dependency_tree "$package" "$TEMP_REPO_FILE" "$RELEASE_VER"
            exit 0
            ;;
        --version|version)
            echo "offline tools v14"
            exit 0
            ;;
        --help|-h|help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown command: $command" >&2
            echo "Use --help for usage." >&2
            exit 1
            ;;
    esac
}

# =============================================
# Program entry
# =============================================
main(){
    handle_cli_args "$@"
    log "=========================================="
    log "$(t STARTUP_TITLE)"
    log "=========================================="
    main_menu
}

main "$@"
