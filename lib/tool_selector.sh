#!/bin/bash
# Tool selection and repository validation.

TOOL_SELECTION_MODE="${TOOL_SELECTION_MODE:-all}"
VERIFY_LAST_REASON=""

tool_mode_label(){
    case "${1:-$TOOL_SELECTION_MODE}" in
        group) echo "$(lang_pick "包组模式" "Group mode")" ;;
        package) echo "$(lang_pick "单包模式" "Package mode")" ;;
        *) echo "$(lang_pick "全部模式" "All mode")" ;;
    esac
}

choose_tool_selection_mode(){
    print_section "$(lang_pick "下载模式选择" "Download mode selection")"
    echo "  1) $(lang_pick "包组模式（推荐，适合离线安装）" "Group mode (Recommended, better for offline install)")"
    echo "  2) $(lang_pick "单包模式（精细选择）" "Package mode (fine-grained)")"
    echo "  3) $(lang_pick "全部模式（显示全部工具）" "All mode (show all tools)")"
    echo "  0) $(t BACK_MENU)"
    echo ""
    local mode_choice
    read -r -p "$(lang_pick "请选择 [1/2/3/0]: " "Select [1/2/3/0]: ")" mode_choice
    mode_choice=${mode_choice:-3}
    case "$mode_choice" in
        1) TOOL_SELECTION_MODE="group" ;;
        2) TOOL_SELECTION_MODE="package" ;;
        3) TOOL_SELECTION_MODE="all" ;;
        0) return 1 ;;
        *) print_error "$(t TOOL_INVALID_INPUT)"; return 1 ;;
    esac
    log_event "INFO" "tool_mode" "selected" "tool selection mode chosen" "mode=$TOOL_SELECTION_MODE"
    print_info "$(lang_pick "当前模式" "Current mode"): $(tool_mode_label "$TOOL_SELECTION_MODE")"
    return 0
}

print_current_selection_panel(){
    if [[ ${#SELECTED_TOOLS[@]} -eq 0 ]]; then
        echo "$(t TOOL_SELECTED): $(t TOOL_SELECTED_NONE)"
    else
        echo "$(t TOOL_SELECTED) (${#SELECTED_TOOLS[@]}): ${SELECTED_TOOLS[*]}"
    fi
}

load_tools_from_conf(){
    local conf_dir="${1:-$CONF_DIR}" target_os="${2:-$TARGET_OS}"
    load_tools_config "$conf_dir" "$target_os" "${TARGET_ARCH:-}" "${TOOL_SELECTION_MODE:-all}" || die "$(t ERROR): $(t TOOL_CONFIG_LOAD_FAILED)"
    if [[ ${#AVAILABLE_TOOLS[@]} -eq 0 ]]; then
        print_error "$(lang_pick "当前模式下没有可选工具，请切换模式后重试" "No tools available for current mode, switch mode and retry")"
        return 1
    fi
    show_all_tools_with_pagination "$target_os"
}

show_tool_page(){
    local title="$1" target_os="$2" page="$3" page_size="$4"
    shift 4
    local -a tools=("$@")
    local total=${#tools[@]}
    local total_pages=$(( (total + page_size - 1) / page_size ))
    [[ $total_pages -lt 1 ]] && total_pages=1
    local start=$(( (page - 1) * page_size ))
    local end=$(( start + page_size ))
    [[ $end -gt $total ]] && end=$total

    print_section "$title ($page/$total_pages) - $(tool_mode_label "$TOOL_SELECTION_MODE")"
    local i tool_id desc mark
    for ((i=start; i<end; i++)); do
        tool_id="${tools[$i]}"
        desc=$(get_tool_description "$tool_id")
        mark="[ ]"
        [[ " ${SELECTED_TOOLS[*]} " == *" $tool_id "* ]] && mark="[x]"
        printf "  %2d) %s %-24s %s\n" "$i" "$mark" "$tool_id" "$desc"
    done

    echo ""
    print_current_selection_panel
    echo "$(t TOOL_COMMANDS_HINT)"
}

show_all_tools_with_pagination(){
    local target_os="$1" page_size=10 current_page=1
    local total=${#AVAILABLE_TOOLS[@]}
    local total_pages=$(( (total + page_size - 1) / page_size ))
    [[ $total_pages -lt 1 ]] && total_pages=1

    while true; do
        show_tool_page "$(t TOOL_SELECTION_ALL)" "$target_os" "$current_page" "$page_size" "${AVAILABLE_TOOLS[@]}"
        read -r -p "$(t TOOL_INPUT_PROMPT) [q]: " input
        input=${input:-q}
        case "$input" in
            n|N) [[ $current_page -lt $total_pages ]] && ((current_page++)) ;;
            p|P) [[ $current_page -gt 1 ]] && ((current_page--)) ;;
            a|A) local t; for t in "${AVAILABLE_TOOLS[@]}"; do add_tool_selection "$t"; done ;;
            q|Q) [[ ${#SELECTED_TOOLS[@]} -gt 0 ]] && return 0 || echo "$(t TOOL_NO_SELECTION)" ;;
            *)
                if [[ "$input" =~ ^[0-9]+$ && $input -ge 0 && $input -lt $total ]]; then
                    toggle_tool_selection "$input"
                else
                    echo "$(t TOOL_INVALID_INPUT)"
                fi
                ;;
        esac
    done
}

add_tool_selection(){
    local tool_id="$1" selected support suggestion existing_key
    support=$(get_tool_support_status_for_os "$tool_id" "$TARGET_OS" "$TARGET_ARCH")
    if [[ "$support" == "UNSUPPORTED" ]]; then
        suggestion=$(get_tool_support_suggestion_for_os "$tool_id" "$TARGET_OS" "$TARGET_ARCH")
        print_warning "$(lang_pick "[CN] Tool not supported on current target: $tool_id" "Tool not supported on current target: $tool_id")"
        [[ -n "$suggestion" ]] && print_info "$suggestion"
        return 0
    fi

    existing_key="${tool_id,,}"
    if [[ -n "${EXISTING_TOOL_SET[$existing_key]+x}" ]]; then
        print_warning "$(lang_pick "[CN] Tool already exists in offline package: $tool_id" "Tool already exists in offline package: $tool_id")"
        if [[ -n "${EXISTING_PACKAGE_PATH:-}" ]]; then
            echo "  $EXISTING_PACKAGE_PATH"
            echo "  rm -f \"$EXISTING_PACKAGE_PATH\" \"$EXISTING_PACKAGE_PATH.sha256\""
        fi
        return 0
    fi

    for selected in "${SELECTED_TOOLS[@]}"; do
        [[ "$selected" == "$tool_id" ]] && return 0
    done
    SELECTED_TOOLS+=("$tool_id")
}

toggle_tool_selection(){
    local index="$1"
    toggle_tool_selection_by_id "${AVAILABLE_TOOLS[$index]}"
}

toggle_tool_selection_by_id(){
    local tool_id="$1" selected found=false support suggestion existing_key
    local -a next=()

    support=$(get_tool_support_status_for_os "$tool_id" "$TARGET_OS" "$TARGET_ARCH")
    if [[ "$support" == "UNSUPPORTED" ]]; then
        suggestion=$(get_tool_support_suggestion_for_os "$tool_id" "$TARGET_OS" "$TARGET_ARCH")
        print_warning "$(lang_pick "[CN] Tool not supported on current target: $tool_id" "Tool not supported on current target: $tool_id")"
        [[ -n "$suggestion" ]] && print_info "$suggestion"
        return 0
    fi

    existing_key="${tool_id,,}"
    if [[ -n "${EXISTING_TOOL_SET[$existing_key]+x}" ]]; then
        print_warning "$(lang_pick "[CN] Tool already exists in offline package: $tool_id" "Tool already exists in offline package: $tool_id")"
        if [[ -n "${EXISTING_PACKAGE_PATH:-}" ]]; then
            echo "  $EXISTING_PACKAGE_PATH"
            echo "  rm -f \"$EXISTING_PACKAGE_PATH\" \"$EXISTING_PACKAGE_PATH.sha256\""
        fi
        return 0
    fi

    for selected in "${SELECTED_TOOLS[@]}"; do
        if [[ "$selected" == "$tool_id" ]]; then
            found=true
        else
            next+=("$selected")
        fi
    done

    if [[ "$found" == true ]]; then
        SELECTED_TOOLS=("${next[@]}")
        echo "$(t TOOL_REMOVED): $tool_id"
    else
        SELECTED_TOOLS+=("$tool_id")
        echo "$(t TOOL_ADDED): $tool_id"
    fi
}

select_kernel_deps(){
    KERNEL_DEPS=()
    return 0
}

show_selection_summary(){
    print_section "$(t TOOL_SELECTION_SUMMARY)"
    print_current_selection_panel
    local total=$(( ${#SELECTED_TOOLS[@]} + ${#KERNEL_DEPS[@]} ))
    echo "$(t TOOL_TOTAL): $total"
}

validate_tool_names(){
    local tools_str="$1" tool
    local -a tools_arr invalid_tools=()
    IFS=',' read -ra tools_arr <<< "$tools_str"
    for tool in "${tools_arr[@]}"; do
        [[ -z "$tool" ]] && continue
        is_valid_tool "$tool" || invalid_tools+=("$tool")
    done
    [[ ${#invalid_tools[@]} -eq 0 ]]
}

verify_tools_in_repo(){
    local conf_dir="${1:-$CONF_DIR}" target_os="${2:-$TARGET_OS}"
    [[ -z "${TEMP_REPO_FILE:-}" || ! -f "$TEMP_REPO_FILE" ]] && TEMP_REPO_FILE=$(generate_repo_config)

    local -a verified_tools=() failed_tools=()
    local tool_id packages pkg ok reason strict_verify
    strict_verify="${OFFLINE_TOOLS_STRICT_VERIFY:-0}"

    print_section "$(t TOOL_VERIFY_TITLE)"
    for tool_id in "${SELECTED_TOOLS[@]}"; do
        if [[ "$(get_tool_support_status_for_os "$tool_id" "$target_os" "$TARGET_ARCH")" == "UNSUPPORTED" ]]; then
            echo "  $(t STATUS_ERROR) $tool_id ($(lang_pick "[CN] unsupported by rule" "unsupported by rule"))"
            local s
            s=$(get_tool_support_suggestion_for_os "$tool_id" "$target_os" "$TARGET_ARCH")
            [[ -n "$s" ]] && echo "      $s"
            failed_tools+=("$tool_id")
            continue
        fi
        packages=$(get_tool_packages_for_os "$tool_id" "$target_os")
        ok=true
        for pkg in $packages; do
            verify_package_in_repo "$pkg" "$TEMP_REPO_FILE" "$target_os"
            if [[ $? -ne 0 ]]; then
                ok=false
                reason="${VERIFY_LAST_REASON:-unknown}"
                break
            fi
        done
        if [[ "$ok" == true ]]; then
            echo "  $(t STATUS_OK) $tool_id"
            verified_tools+=("$tool_id")
        else
            if [[ "$TOOL_SELECTION_MODE" == "group" && "$strict_verify" != "1" ]]; then
                echo "  [WARN] $tool_id ($(lang_pick "仓库预检未通过，继续尝试下载" "repo pre-check failed, continue download"))"
                [[ -n "$reason" ]] && echo "      $reason"
                verified_tools+=("$tool_id")
            else
                echo "  $(t STATUS_ERROR) $tool_id"
                [[ -n "$reason" ]] && echo "      $reason"
                failed_tools+=("$tool_id")
            fi
        fi
    done

    if [[ ${#failed_tools[@]} -gt 0 ]]; then
        echo "$(t TOOL_UNAVAILABLE): ${failed_tools[*]}"
        read -r -p "$(t TOOL_CONTINUE_AVAILABLE) [y]: " continue_choice
        continue_choice=${continue_choice:-y}
        [[ "$continue_choice" == y || "$continue_choice" == Y ]] || return 1
        SELECTED_TOOLS=("${verified_tools[@]}")
    fi
    [[ ${#SELECTED_TOOLS[@]} -gt 0 ]]
}

verify_package_in_repo(){
    local pkg_name="$1" repo_file="$2" target_os="$3"
    local pkg_type="rpm"
    VERIFY_LAST_REASON=""
    case "$target_os" in Ubuntu*|Debian*|Kylin*) pkg_type="deb" ;; esac

    if [[ "$pkg_type" == "rpm" ]]; then
        if [[ "$pkg_name" == *"*"* || "$pkg_name" == *"?"* ]]; then
            dnf search --config="$repo_file" --disablerepo='*' --enablerepo='offline-temp' "$pkg_name" 2>&1 | grep -qE '^[A-Za-z0-9]' || {
                VERIFY_LAST_REASON="$(lang_pick "未在当前仓库检索到通配包: $pkg_name" "wildcard package search empty in current repo: $pkg_name")"
                return 1
            }
        elif is_rpm_package_group "$pkg_name"; then
            local group_name
            group_name=$(rpm_group_name "$pkg_name")
            validate_rpm_group_installable "$group_name" "$repo_file" "${RELEASE_VER:-}" "${FORCEARCH:-}" "precheck" || {
                VERIFY_LAST_REASON="$(lang_pick "当前仓库缺少组ID: $group_name" "group id missing in current repo: $group_name")"
                return 1
            }
        else
            dnf repoquery --config="$repo_file" --disablerepo='*' --enablerepo='offline-temp' "$pkg_name" &>/dev/null || {
                VERIFY_LAST_REASON="$(lang_pick "当前仓库未找到包: $pkg_name" "package not found in current repo: $pkg_name")"
                return 1
            }
        fi
    else
        if [[ "$pkg_name" == *"*"* ]]; then
            apt-cache search "${pkg_name%\*}" 2>/dev/null | grep -qE "^${pkg_name%\*}" || {
                VERIFY_LAST_REASON="$(lang_pick "当前仓库未检索到通配包: $pkg_name" "wildcard package search empty in current apt source: $pkg_name")"
                return 1
            }
        else
            apt-cache show "$pkg_name" &>/dev/null || {
                VERIFY_LAST_REASON="$(lang_pick "当前仓库未找到包: $pkg_name" "package not found in current apt source: $pkg_name")"
                return 1
            }
        fi
    fi
    return 0
}

export -f print_current_selection_panel
export -f tool_mode_label
export -f choose_tool_selection_mode
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
