#!/bin/bash

TOOL_SELECTION_MODE="${TOOL_SELECTION_MODE:-all}"
VERIFY_LAST_REASON=""

declare -a VERIFIED_TOOLS=()
declare -a FAILED_TOOLS=()
declare -A FAILED_TOOL_REASON=()
declare -A FAILED_TOOL_DETAIL=()

_ts_msg(){
    local zh="$1" en="$2"
    lang_pick "$zh" "$en"
}

tool_mode_label(){
    case "${1:-$TOOL_SELECTION_MODE}" in
        all) echo "$(_ts_msg '全部工具' 'All tools')" ;;
        group) echo "$(_ts_msg '包组模式' 'Group mode')" ;;
        package) echo "$(_ts_msg '单包模式' 'Package mode')" ;;
        *) echo "${1:-$TOOL_SELECTION_MODE}" ;;
    esac
}

choose_tool_selection_mode(){
    while true; do
        print_section "$(_ts_msg '下载模式选择' 'Download mode selection')"
        echo "  1) $(_ts_msg '包组模式（推荐）' 'Group mode (Recommended)')"
        echo "  2) $(_ts_msg '单包模式' 'Package mode')"
        echo "  3) $(_ts_msg '全部工具' 'All tools')"
        echo "  0) $(lang_pick '返回上级' 'Back')"
        echo ""
        read -r -p "$(_ts_msg '请选择 [1/2/3/0]: ' 'Select [1/2/3/0]: ')" mode_choice || return 1
        case "${mode_choice:-1}" in
            1) TOOL_SELECTION_MODE="group"; return 0 ;;
            2) TOOL_SELECTION_MODE="package"; return 0 ;;
            3) TOOL_SELECTION_MODE="all"; return 0 ;;
            0) return 1 ;;
            *) print_error "$(t TOOL_INVALID_INPUT): ${mode_choice}" ;;
        esac
    done
}

print_current_selection_panel(){
    local total="${#SELECTED_TOOLS[@]}"
    echo ""
    print_section "$(_ts_msg '当前已选工具' 'Current selection')"
    echo "  $(_ts_msg '模式' 'Mode'): $(tool_mode_label)"
    echo "  $(_ts_msg '数量' 'Count'): $total"
    if [[ $total -gt 0 ]]; then
        printf '  %s\n' "${SELECTED_TOOLS[@]}" | sed 's/^/  - /'
    else
        echo "  $(lang_pick '暂无' 'None')"
    fi
}

load_tools_from_conf(){
    local conf_dir="${1:-$CONF_DIR}"
    local target_os="${2:-$TARGET_OS}"
    local target_arch="${3:-$TARGET_ARCH}"

    SELECTED_TOOLS=()
    KERNEL_DEPS=()

    load_tools_config "$conf_dir" "$target_os" "$target_arch" "$TOOL_SELECTION_MODE" || return 1

    if [[ ! -t 0 ]]; then
        SELECTED_TOOLS=("${AVAILABLE_TOOLS[@]}")
        log_event "INFO" "tool_select" "auto_all" "non-interactive mode auto-selected available tools" "count=${#SELECTED_TOOLS[@]}" "mode=$TOOL_SELECTION_MODE"
        return 0
    fi

    show_all_tools_with_pagination "$target_os" "$target_arch"
    [[ ${#SELECTED_TOOLS[@]} -gt 0 ]]
}

show_tool_page(){
    local page="$1"
    local page_size="${2:-12}"
    local total="${#AVAILABLE_TOOLS[@]}"
    local total_pages=$(( (total + page_size - 1) / page_size ))
    local start=$((page * page_size))
    local end=$((start + page_size))
    local i tool desc mark

    (( end > total )) && end=$total

    print_section "$(_ts_msg '工具选择' 'Tool selection') ${page_size:+($((page + 1))/$total_pages)}"
    print_current_selection_panel
    for ((i=start; i<end; i++)); do
        tool="${AVAILABLE_TOOLS[$i]}"
        desc="${AVAILABLE_TOOL_DESCS[$i]}"
        mark="[ ]"
        [[ " ${SELECTED_TOOLS[*]} " == *" $tool "* ]] && mark="[x]"
        printf "  %2d) %-24s %s %s\n" "$i" "$tool" "$mark" "$desc"
    done
    echo ""
    echo "  a) $(_ts_msg '全选当前模式工具' 'Select all in current mode')"
    echo "  n) $(_ts_msg '下一页' 'Next page')"
    echo "  p) $(_ts_msg '上一页' 'Previous page')"
    echo "  q) $(_ts_msg '完成选择' 'Done')"
    echo "  b) $(lang_pick '返回上级' 'Back')"
    echo ""
    echo "  $(t TOOL_COMMANDS_HINT)"
}

show_all_tools_with_pagination(){
    local target_os="${1:-$TARGET_OS}"
    local target_arch="${2:-$TARGET_ARCH}"
    local page=0
    local page_size=12
    local max_page=$(( (${#AVAILABLE_TOOLS[@]} + page_size - 1) / page_size - 1 ))
    local input item

    while true; do
        show_tool_page "$page" "$page_size"
        read -r -p "$(t TOOL_INPUT_PROMPT): " input || {
            if [[ ${#SELECTED_TOOLS[@]} -eq 0 ]]; then
                log_event "WARN" "tool_select" "eof" "interactive selection reached eof without selection"
                return 1
            fi
            return 0
        }
        input="${input//$'\r'/}"
        input="${input#"${input%%[![:space:]]*}"}"
        input="${input%"${input##*[![:space:]]}"}"
        case "$input" in
            a|A)
                SELECTED_TOOLS=("${AVAILABLE_TOOLS[@]}")
                ;;
            n|N)
                (( page < max_page )) && page=$((page + 1))
                ;;
            p|P)
                (( page > 0 )) && page=$((page - 1))
                ;;
            q|Q)
                if [[ ${#SELECTED_TOOLS[@]} -eq 0 ]]; then
                    if [[ "$TOOL_SELECTION_MODE" == "group" ]]; then
                        SELECTED_TOOLS=("${AVAILABLE_TOOLS[@]}")
                        log_event "INFO" "tool_select" "fallback_all" "q with empty selection, auto-selected all available groups" "count=${#SELECTED_TOOLS[@]}"
                    else
                        print_warning "$(t TOOL_NO_SELECTION)"
                        continue
                    fi
                fi
                return 0
                ;;
            b|B)
                SELECTED_TOOLS=()
                return 1
                ;;
            all|ALL)
                SELECTED_TOOLS=("${AVAILABLE_TOOLS[@]}")
                ;;
            none|NONE)
                SELECTED_TOOLS=()
                ;;
            "")
                ;;
            *)
                for item in $input; do
                    toggle_tool_selection_by_id "$item"
                done
                ;;
        esac
    done
}

add_tool_selection(){
    local tool="$1"
    local key="${tool,,}"
    local current
    for current in "${SELECTED_TOOLS[@]}"; do
        [[ "${current,,}" == "$key" ]] && return 0
    done

    if [[ -n "${EXISTING_TOOL_SET[$key]+x}" ]]; then
        print_warning "$(_ts_msg '该工具已存在于当前离线包，无需重复下载' 'Tool already exists in current offline bundle, no need to download again'): $tool"
        if [[ -n "${EXISTING_PACKAGE_PATH:-}" ]]; then
            print_info "$(_ts_msg '如需重新下载，请手动删除离线包' 'To re-download, remove offline bundle manually'): $EXISTING_PACKAGE_PATH"
        fi
        return 0
    fi

    if [[ "$(get_tool_support_status_for_os "$tool" "$TARGET_OS" "$TARGET_ARCH")" == "UNSUPPORTED" ]]; then
        print_warning "$(_ts_msg '该工具当前目标系统不支持' 'Tool is not supported for current target'): $tool"
        current=$(get_tool_support_suggestion_for_os "$tool" "$TARGET_OS" "$TARGET_ARCH")
        [[ -n "$current" ]] && print_info "$current"
        return 0
    fi

    SELECTED_TOOLS+=("$tool")
}

toggle_tool_selection(){
    local tool="$1"
    local key="${tool,,}"
    local -a next=()
    local item found=0
    for item in "${SELECTED_TOOLS[@]}"; do
        if [[ "${item,,}" == "$key" ]]; then
            found=1
            continue
        fi
        next+=("$item")
    done
    if [[ $found -eq 1 ]]; then
        SELECTED_TOOLS=("${next[@]}")
    else
        add_tool_selection "$tool"
    fi
}

toggle_tool_selection_by_id(){
    local input="$1"
    local index

    if [[ "$input" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        local start="${BASH_REMATCH[1]}"
        local end="${BASH_REMATCH[2]}"
        (( start > end )) && { local tmp="$start"; start="$end"; end="$tmp"; }
        for ((index=start; index<=end; index++)); do
            if (( index >= 0 && index < ${#AVAILABLE_TOOLS[@]} )); then
                toggle_tool_selection "${AVAILABLE_TOOLS[$index]}"
            fi
        done
        return 0
    fi

    if [[ "$input" =~ ^[0-9]+$ ]]; then
        index="$input"
        if (( index >= 0 && index < ${#AVAILABLE_TOOLS[@]} )); then
            toggle_tool_selection "${AVAILABLE_TOOLS[$index]}"
            return 0
        fi
    fi

    print_error "$(t TOOL_INVALID_INPUT): $input"
    return 1
}

select_kernel_deps(){
    return 0
}

show_selection_summary(){
    local tool
    print_section "$(t TOOL_SELECTION_SUMMARY)"
    echo "  $(t TOOL_TOTAL): ${#SELECTED_TOOLS[@]}"
    for tool in "${SELECTED_TOOLS[@]}"; do
        echo "  - $tool"
    done
}

validate_tool_names(){
    local tool
    local -A available=()
    for tool in "${AVAILABLE_TOOLS[@]}"; do
        available["${tool,,}"]=1
    done
    for tool in "${SELECTED_TOOLS[@]}"; do
        [[ -n "${available[${tool,,}]+x}" ]] || {
            VERIFY_LAST_REASON="invalid_tool_name:$tool"
            return 1
        }
    done
    return 0
}

verify_package_in_repo(){
    local spec="$1"
    local repo_file="$2"
    local target_os="${3:-$TARGET_OS}"
    local target_arch="${4:-$TARGET_ARCH}"
    local pkg_type="${PKG_TYPE:-$(_tool_pkg_type_for_os "$target_os")}"
    local release_ver="${RELEASE_VER:-}"
    local current_arch fa_arg out rc

    VERIFY_LAST_REASON=""
    current_arch=$(uname -m)
    fa_arg=""
    if [[ -n "$target_arch" && "$target_arch" != "$current_arch" ]]; then
        fa_arg="--forcearch=$target_arch"
    fi

    if [[ "$pkg_type" == "rpm" ]]; then
        if is_rpm_package_group "$spec"; then
            local group_name
            group_name=$(rpm_group_name "$spec")
            if validate_rpm_group_installable "$group_name" "$repo_file" "$release_ver" "$target_arch" "precheck"; then
                return 0
            fi
            VERIFY_LAST_REASON="PACKAGE_OR_GROUP_NOT_FOUND"
            return 1
        fi

        out=$(dnf repoquery --config="$repo_file" --disablerepo='*' --enablerepo="$(offline_temp_repo_selector)" --releasever="$release_ver" $fa_arg "$spec" 2>&1)
        rc=$?
        if [[ $rc -eq 0 ]] && echo "$out" | grep -Eq '^[A-Za-z0-9_.+-]+\.'; then
            return 0
        fi
        out=$(dnf search --config="$repo_file" --disablerepo='*' --enablerepo="$(offline_temp_repo_selector)" --releasever="$release_ver" $fa_arg "$spec" 2>&1)
        if echo "$out" | grep -Eq "^${spec//\*/.*}\."; then
            return 0
        fi
        if echo "$out" | grep -qiE 'Could not resolve host|Cannot download repomd|All mirrors were tried|Timeout|SSL|curl error|failed to download'; then
            VERIFY_LAST_REASON="SOURCE_UNREACHABLE"
        else
            VERIFY_LAST_REASON="PACKAGE_OR_GROUP_NOT_FOUND"
        fi
        return 1
    fi

    out=$(apt-cache policy "$spec" 2>&1)
    rc=$?
    if [[ $rc -eq 0 ]] && ! echo "$out" | grep -qi 'Candidate: (none)'; then
        return 0
    fi
    if echo "$out" | grep -qiE 'Temporary failure resolving|Connection failed|Could not resolve|404'; then
        VERIFY_LAST_REASON="SOURCE_UNREACHABLE"
    else
        VERIFY_LAST_REASON="PACKAGE_NOT_FOUND"
    fi
    return 1
}

verify_tools_in_repo(){
    local conf_dir="${1:-$CONF_DIR}"
    local target_os="${2:-$TARGET_OS}"
    local target_arch="${3:-$TARGET_ARCH}"
    local repo_file tool specs spec reason detail ok suggestion
    local -a verified=() failed=()

    [[ ${#SELECTED_TOOLS[@]} -gt 0 ]] || {
        VERIFY_LAST_REASON="empty_selection"
        return 1
    }

    repo_file=$(generate_repo_config)
    VERIFIED_TOOLS=()
    FAILED_TOOLS=()
    FAILED_TOOL_REASON=()
    FAILED_TOOL_DETAIL=()

    for tool in "${SELECTED_TOOLS[@]}"; do
        if [[ "$(get_tool_support_status_for_os "$tool" "$target_os" "$target_arch")" == "UNSUPPORTED" ]]; then
            reason="UNSUPPORTED"
            detail="$(get_tool_support_suggestion_for_os "$tool" "$target_os" "$target_arch")"
            failed+=("$tool")
            FAILED_TOOL_REASON["$tool"]="$reason"
            FAILED_TOOL_DETAIL["$tool"]="${detail:-unsupported by rule}"
            continue
        fi

        specs=$(get_tool_packages_for_os "$tool" "$target_os" "$target_arch")
        if [[ -z "$specs" ]]; then
            failed+=("$tool")
            FAILED_TOOL_REASON["$tool"]="PACKAGE_OR_GROUP_NOT_FOUND"
            FAILED_TOOL_DETAIL["$tool"]="empty package mapping"
            continue
        fi

        ok=1
        for spec in $specs; do
            verify_package_in_repo "$spec" "$repo_file" "$target_os" "$target_arch" || {
                ok=0
                reason="${VERIFY_LAST_REASON:-PACKAGE_OR_GROUP_NOT_FOUND}"
                detail="$spec"
                break
            }
        done

        if [[ $ok -eq 1 ]]; then
            verified+=("$tool")
            log_event "INFO" "verify" "tool_ok" "tool verified in repo" "tool=$tool"
        else
            failed+=("$tool")
            FAILED_TOOL_REASON["$tool"]="$reason"
            FAILED_TOOL_DETAIL["$tool"]="$detail"
            log_event "WARN" "verify" "tool_failed" "tool precheck failed" "tool=$tool" "reason=$reason" "detail=$detail"
        fi
    done

    VERIFIED_TOOLS=("${verified[@]}")
    FAILED_TOOLS=("${failed[@]}")

    if [[ ${#FAILED_TOOLS[@]} -eq 0 ]]; then
        SELECTED_TOOLS=("${VERIFIED_TOOLS[@]}")
        return 0
    fi

    print_warning "$(t TOOL_UNAVAILABLE): ${#FAILED_TOOLS[@]}"
    for tool in "${FAILED_TOOLS[@]}"; do
        suggestion="${FAILED_TOOL_DETAIL[$tool]}"
        echo "  - $tool | ${FAILED_TOOL_REASON[$tool]} | $suggestion"
    done

    if [[ ${#VERIFIED_TOOLS[@]} -eq 0 ]]; then
        VERIFY_LAST_REASON="all_failed_precheck"
        return 1
    fi

    if [[ ! -t 0 ]]; then
        SELECTED_TOOLS=("${VERIFIED_TOOLS[@]}")
        print_info "$(_ts_msg '非交互模式：已自动跳过不可用工具，仅继续可用工具' 'Non-interactive mode: unavailable tools skipped automatically')"
        return 0
    fi

    echo ""
    echo "  1) $(t TOOL_CONTINUE_AVAILABLE)"
    echo "  0) $(lang_pick '返回上级' 'Back')"
    local choice
    read -r -p "$(lang_pick '请选择 [1/0]: ' 'Select [1/0]: ')" choice || return 1
    case "${choice:-1}" in
        1)
            SELECTED_TOOLS=("${VERIFIED_TOOLS[@]}")
            return 0
            ;;
        *)
            VERIFY_LAST_REASON="user_back_after_precheck"
            return 1
            ;;
    esac
}

export -f tool_mode_label
export -f choose_tool_selection_mode
export -f print_current_selection_panel
export -f load_tools_from_conf
export -f show_tool_page
export -f show_all_tools_with_pagination
export -f add_tool_selection
export -f toggle_tool_selection
export -f toggle_tool_selection_by_id
export -f select_kernel_deps
export -f show_selection_summary
export -f validate_tool_names
export -f verify_tools_in_repo
export -f verify_package_in_repo
