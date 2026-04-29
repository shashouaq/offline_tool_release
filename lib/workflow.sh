#!/bin/bash

EXISTING_PACKAGE_PATH=""
declare -a EXISTING_PACKAGE_TOOLS=()
declare -A EXISTING_TOOL_SET=()

_wf_msg(){ local zh="$1" en="$2"; lang_pick "$zh" "$en"; }

append_local_unsupported_rule(){
    local target_os="$1" target_arch="$2" tool_id="$3" reason="$4" detail="$5"
    local rule_file="$CONF_DIR/tool_os_rules.local.conf" existed
    existed=$(get_tool_os_rule "$target_os" "$target_arch" "$tool_id" 2>/dev/null || true)
    [[ -n "$existed" ]] && return 0
    mkdir -p "$CONF_DIR"
    [[ -f "$rule_file" ]] || { echo "# Local auto-learned rules" > "$rule_file"; echo "# os_pattern|arch_pattern|tool_id|status|rpm_override|deb_override|suggestion" >> "$rule_file"; }
    echo "${target_os}|${target_arch}|${tool_id}|UNSUPPORTED|-|-|auto-learned: ${reason} (${detail})" >> "$rule_file"
    log_event "WARN" "rules" "auto_append" "added unsupported rule" "os=$target_os" "arch=$target_arch" "tool=$tool_id" "reason=$reason"
}

set_existing_tools_context(){
    local output_dir="$1" target_os="$2" target_arch="$3" tools_csv="$4" tool key
    EXISTING_PACKAGE_PATH="$output_dir/offline_${target_os}_${target_arch}_merged.tar.xz"
    EXISTING_PACKAGE_TOOLS=()
    EXISTING_TOOL_SET=()
    IFS=',' read -ra _tools <<< "$tools_csv"
    for tool in "${_tools[@]}"; do
        tool="${tool//$'\r'/}"
        tool="${tool#"${tool%%[![:space:]]*}"}"
        tool="${tool%"${tool##*[![:space:]]}"}"
        [[ -z "$tool" ]] && continue
        key="${tool,,}"
        [[ -n "${EXISTING_TOOL_SET[$key]+x}" ]] && continue
        EXISTING_PACKAGE_TOOLS+=("$tool")
        EXISTING_TOOL_SET[$key]=1
    done
}

filter_new_tools_by_existing(){
    local -a input_tools=("$@")
    local -a out_new=() out_skipped=()
    local t key
    for t in "${input_tools[@]}"; do
        key="${t,,}"
        if [[ -n "${EXISTING_TOOL_SET[$key]+x}" ]]; then
            out_skipped+=("$t")
        else
            out_new+=("$t")
        fi
    done
    SELECTED_TOOLS=("${out_new[@]}")
    if [[ ${#out_skipped[@]} -gt 0 ]]; then
        print_info "$(lang_pick "已存在工具已跳过" "Existing tools skipped"): ${#out_skipped[@]}"
        printf "  - %s\n" "${out_skipped[@]}"
        log_event "INFO" "download" "skip_existing_tools" "skip tools already in existing offline package" "count=${#out_skipped[@]}" "tools=$(IFS=','; echo "${out_skipped[*]}")"
    fi
}

write_tool_mapping_files(){
    local pkg_dir="$1" target_os="$2"
    shift 2
    local -a tools=("$@")
    local map_file="$pkg_dir/.tool_pkg_map" tools_file="$pkg_dir/.selected_tools"
    local tool pkg_csv spec artifact_file pkg_name
    mkdir -p "$pkg_dir"
    : > "$map_file"
    : > "$tools_file"
    for tool in "${tools[@]}"; do
        [[ -z "$tool" ]] && continue
        pkg_csv=""
        for spec in $(get_tool_packages_for_os "$tool" "$target_os" "$TARGET_ARCH"); do
            [[ -z "$spec" ]] && continue
            artifact_file=$(download_state_artifact_file "$spec")
            if [[ -f "$artifact_file" ]]; then
                while IFS= read -r pkg_name || [[ -n "$pkg_name" ]]; do
                    [[ -z "$pkg_name" ]] && continue
                    if [[ -z "$pkg_csv" ]]; then
                        pkg_csv="$pkg_name"
                    elif [[ ",$pkg_csv," != *",$pkg_name,"* ]]; then
                        pkg_csv="${pkg_csv},${pkg_name}"
                    fi
                done < "$artifact_file"
            else
                if [[ -z "$pkg_csv" ]]; then
                    pkg_csv="$spec"
                elif [[ ",$pkg_csv," != *",$spec,"* ]]; then
                    pkg_csv="${pkg_csv},${spec}"
                fi
            fi
        done
        echo "$tool|$pkg_csv" >> "$map_file"
    done
    (IFS=','; echo "${tools[*]}") > "$tools_file"
}

artifact_package_name(){
    local file="$1" name=""
    if [[ "$file" == *.rpm ]]; then
        if command -v rpm &>/dev/null; then
            name=$(rpm -qp --qf '%{NAME}\n' "$file" 2>/dev/null | head -n1)
        fi
        [[ -n "$name" ]] || name=$(basename "$file" .rpm | sed -E 's/-[0-9][^-]*-[^-]*\.[^.]+$//')
    else
        if command -v dpkg-deb &>/dev/null; then
            name=$(dpkg-deb -f "$file" Package 2>/dev/null | head -n1)
        fi
        [[ -n "$name" ]] || name=$(basename "$file" .deb)
        name="${name%%_*}"
    fi
    echo "$name"
}

prune_pkg_dir_to_selected_tools(){
    local pkg_dir="$1" target_os="$2"
    shift 2
    local -a keep_tools=("$@")
    local spec artifact_file pkg_name file current_name
    local -A keep_names=()
    local removed=0

    for tool in "${keep_tools[@]}"; do
        [[ -z "$tool" ]] && continue
        for spec in $(get_tool_packages_for_os "$tool" "$target_os" "$TARGET_ARCH"); do
            [[ -z "$spec" ]] && continue
            artifact_file=$(download_state_artifact_file "$spec")
            if [[ -f "$artifact_file" ]]; then
                while IFS= read -r pkg_name || [[ -n "$pkg_name" ]]; do
                    [[ -n "$pkg_name" ]] && keep_names["$pkg_name"]=1
                done < "$artifact_file"
            else
                keep_names["$spec"]=1
            fi
        done
    done

    while IFS= read -r -d '' file; do
        current_name=$(artifact_package_name "$file")
        [[ -n "$current_name" ]] || continue
        if [[ -z "${keep_names[$current_name]+x}" ]]; then
            rm -f -- "$file"
            removed=$((removed + 1))
        fi
    done < <(find "$pkg_dir" -type f \( -name '*.rpm' -o -name '*.deb' \) -print0 2>/dev/null)

    log_event "INFO" "download" "prune" "pruned package directory to successful tools" "keep_tools=${#keep_tools[@]}" "removed_files=$removed"
}

tool_download_success(){
    local tool_id="$1" pkg_dir="$2" target_os="$3" pkg_type="$4" specs spec status_success=0
    specs=$(get_tool_packages_for_os "$tool_id" "$target_os" "$TARGET_ARCH")
    for spec in $specs; do
        [[ -z "$spec" ]] && continue
        [[ "${DOWNLOAD_STATUS[$spec]:-}" == "failed" ]] && return 1
        [[ "${DOWNLOAD_STATUS[$spec]:-}" == "success" ]] && status_success=1
    done
    [[ $status_success -eq 1 ]]
}

tool_failure_reason_detail(){
    local tool_id="$1" specs spec reason detail
    reason="${DOWNLOAD_FAIL_REASON[$tool_id]:-}"
    detail="${DOWNLOAD_FAIL_DETAIL[$tool_id]:-}"
    [[ -n "$reason" || -n "$detail" ]] && { echo "${reason:-UNKNOWN}|${detail:-unknown}"; return 0; }
    specs=$(get_tool_packages_for_os "$tool_id" "$TARGET_OS" "$TARGET_ARCH")
    for spec in $specs; do
        [[ -z "$spec" ]] && continue
        reason="${DOWNLOAD_FAIL_REASON[$spec]:-}"
        detail="${DOWNLOAD_FAIL_DETAIL[$spec]:-}"
        [[ -n "$reason" || -n "$detail" ]] && { echo "${reason:-UNKNOWN}|${detail:-unknown}"; return 0; }
    done
    echo "NO_PACKAGE_ARTIFACT|no package artifacts produced for tool"
}

run_download(){
    local conf_dir="${1:-$CONF_DIR}" work_dir="${2:-$WORK_DIR}" output_dir="${3:-$OUTPUT_DIR}"
    log_action_begin "download" "run"
    SELECTED_TOOLS=()
    KERNEL_DEPS=()

    select_os_arch "$conf_dir" "$work_dir" || { log_action_end "download" "run" "failed" "select_os_arch"; return; }
    if [[ -t 0 ]]; then
        choose_tool_selection_mode || { log_action_end "download" "run" "cancel" "tool_mode_back"; return; }
    else
        TOOL_SELECTION_MODE="${TOOL_SELECTION_MODE:-group}"
        log_event "INFO" "tool_mode" "defaulted" "non-interactive mode selected" "mode=$TOOL_SELECTION_MODE"
    fi

    STATIC_TARBALL="$output_dir/offline_${TARGET_OS}_${TARGET_ARCH}_merged.tar.xz"
    PKG_DIR="$work_dir/packages_${TARGET_OS}_${TARGET_ARCH}"
    mkdir -p "$PKG_DIR"
    find "$PKG_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true

    local merge_mode="new"
    EXISTING_PACKAGE_PATH=""
    EXISTING_PACKAGE_TOOLS=()
    EXISTING_TOOL_SET=()
    if [[ -f "$STATIC_TARBALL" ]]; then
        merge_mode="merge"
        local existing_tools_csv=""
        existing_tools_csv=$(get_package_tools "$TARGET_OS" "$TARGET_ARCH" 2>/dev/null || true)
        set_existing_tools_context "$output_dir" "$TARGET_OS" "$TARGET_ARCH" "$existing_tools_csv"
        if [[ ${#EXISTING_PACKAGE_TOOLS[@]} -gt 0 ]]; then
            print_info "$(lang_pick "检测到已有离线包，将执行增量下载与增量打包" "Existing offline bundle detected; incremental download/package mode enabled")"
            print_info "$(lang_pick "已有工具数量" "Existing tools count"): ${#EXISTING_PACKAGE_TOOLS[@]}"
            log_event "INFO" "download" "incremental_mode" "existing package found, use merge mode" "tarball=$STATIC_TARBALL" "existing_tools=${#EXISTING_PACKAGE_TOOLS[@]}"
        fi
    fi

    show_status "info" "$(t WORKSPACE): $PKG_DIR"
    if [[ "$PKG_TYPE" == "rpm" ]]; then
        dnf install -y dnf-plugins-core createrepo_c >/dev/null 2>&1 || true
    else
        apt-get install -y dpkg-dev apt-utils >/dev/null 2>&1 || true
    fi

    init_tool_whitelist "$conf_dir/tools.conf"
    init_download_cache
    reset_download_state
    init_metadata_dir
    init_manifest "$work_dir"

    print_info "$(lang_pick "加载工具配置..." "Loading tool configuration...")"
    load_tools_from_conf "$conf_dir" "$TARGET_OS" || { log_action_end "download" "run" "failed" "load_tools_from_conf"; return; }
    print_info "$(lang_pick "校验工具在目标仓库中的可用性（可能需要一些时间）..." "Validating tool availability in target repositories (may take some time)...")"
    verify_tools_in_repo "$conf_dir" "$TARGET_OS" || { log_action_end "download" "run" "failed" "verify_tools_in_repo"; return; }
    print_success "$(lang_pick "工具可用性校验完成" "Tool availability validation completed")"

    filter_new_tools_by_existing "${SELECTED_TOOLS[@]}"
    if [[ ${#SELECTED_TOOLS[@]} -eq 0 ]]; then
        print_success "$(lang_pick "本次所选工具已全部存在于离线包中，无需下载与打包" "All selected tools already exist in offline bundle, skip download/package")"
        show_navigation_menu "main_menu"
        log_action_end "download" "run" "ok" "all_selected_tools_already_exist"
        return 0
    fi

    show_selected_tools "${SELECTED_TOOLS[@]}"
    confirm_dialog "$(t DOWNLOAD_START) ${#SELECTED_TOOLS[@]} $(_wf_msg '个工具' 'tools')" "y" "download" || { log_action_end "download" "run" "cancel" "user_declined"; return; }

    filter_reachable_repos || {
        print_error "$(_wf_msg '镜像源探测后无可用源' 'No reachable mirrors after probe')"
        log_action_end "download" "run" "failed" "no_reachable_repos"
        return 1
    }

    TEMP_REPO_FILE=$(generate_repo_config)
    DOWNLOAD_SOURCE_LABEL=$(grep -m1 '^baseurl=' "$TEMP_REPO_FILE" | cut -d= -f2- | sed -E 's#https?://##; s#/.*##')
    [[ -z "$DOWNLOAD_SOURCE_LABEL" ]] && DOWNLOAD_SOURCE_LABEL="repo"
    log_event "INFO" "download" "repo_selected" "using mirror source" "source=${DOWNLOAD_SOURCE_LABEL}"
    log "[config] repo file: $TEMP_REPO_FILE"

    local -a all_packages=() metadata_tools=()
    local packages pkg tool
    for tool in "${SELECTED_TOOLS[@]}"; do
        packages=$(get_tool_packages_for_os "$tool" "$TARGET_OS" "$TARGET_ARCH")
        [[ -z "$packages" ]] && continue
        metadata_tools+=("$tool")
        for pkg in $packages; do
            all_packages+=("$pkg")
        done
    done
    log "[download] expanded ${#metadata_tools[@]} tools to ${#all_packages[@]} packages"

    export FORCE_DOWNLOAD=1
    local download_rc=0
    smart_download "${all_packages[@]}" || download_rc=$?
    export FORCE_DOWNLOAD=0

    local pkg_count
    pkg_count=$(find "$PKG_DIR" -type f \( -name "*.rpm" -o -name "*.deb" \) 2>/dev/null | wc -l)

    local -a successful_tools=() failed_tools=()
    local success_count failed_count ft rsn det tools_str deps_str
    for tool in "${metadata_tools[@]}"; do
        if tool_download_success "$tool" "$PKG_DIR" "$TARGET_OS" "$PKG_TYPE"; then
            successful_tools+=("$tool")
        else
            failed_tools+=("$tool")
        fi
    done
    success_count=${#successful_tools[@]}
    failed_count=${#failed_tools[@]}

    if [[ $success_count -eq 0 || $pkg_count -eq 0 ]]; then
        print_error "$(_wf_msg '没有可安装的下载结果，请检查仓库、网络或工具配置' 'No installable downloads, check repo/network/tool config')"
        show_back_prompt
        log_action_end "download" "run" "failed" "no_successful_downloads"
        return 1
    fi

    if [[ $failed_count -gt 0 ]]; then
        print_warning "$(_wf_msg '部分工具失败，仅打包成功工具' 'Some tools failed, packaging successful tools only:')"
        for ft in "${failed_tools[@]}"; do
            IFS='|' read -r rsn det <<< "$(tool_failure_reason_detail "$ft")"
            echo "  - $ft | $rsn | $det"
            print_warning "$(_wf_msg '下载失败' 'Download failed'): $ft | $rsn | $det"
            case "$rsn" in
                SOURCE_UNREACHABLE) print_info "$(_wf_msg '建议：检查镜像源连通性或切换可用源' 'Suggestion: check mirror connectivity or switch reachable source')" ;;
                PACKAGE_OR_GROUP_NOT_FOUND|PACKAGE_NOT_FOUND) print_info "$(_wf_msg '建议：该工具在当前 OS/架构仓库中不存在，请检查包组名或更换工具' 'Suggestion: tool not found for current OS/arch, check package/group name or choose another tool')" ;;
                DEPENDENCY_RESOLVE_FAILED) print_info "$(_wf_msg '建议：依赖闭包解析失败，请检查仓库完整性' 'Suggestion: dependency closure failed, check repository completeness')" ;;
            esac
            log_event "WARN" "download" "tool_failed" "tool failed in final result" "tool=$ft" "reason=$rsn" "detail=$det"
            if [[ "${OFFLINE_TOOLS_AUTO_LEARN_UNSUPPORTED:-0}" == "1" ]] && [[ "$rsn" == "PACKAGE_OR_GROUP_NOT_FOUND" || "$rsn" == "PACKAGE_NOT_FOUND" ]]; then
                append_local_unsupported_rule "$TARGET_OS" "$TARGET_ARCH" "$ft" "$rsn" "$det"
            fi
        done
        print_info "$(_wf_msg '原因说明：SOURCE_UNREACHABLE=源问题，PACKAGE_OR_GROUP_NOT_FOUND=包名或组名问题，DEPENDENCY_RESOLVE_FAILED=依赖解析问题' 'Reason key: SOURCE_UNREACHABLE=source issue, PACKAGE_OR_GROUP_NOT_FOUND=name issue, DEPENDENCY_RESOLVE_FAILED=dependency issue')"
        metadata_tools=("${successful_tools[@]}")
        if [[ ${#metadata_tools[@]} -eq 0 ]]; then
            print_error "$(_wf_msg '没有成功工具可供打包' 'No successful tools to package')"
            log_action_end "download" "run" "failed" "all_tools_failed"
            return 1
        fi
    else
        print_success "$(_wf_msg '所选工具下载成功' 'Selected tools downloaded successfully')"
    fi

    prune_pkg_dir_to_selected_tools "$PKG_DIR" "$TARGET_OS" "${metadata_tools[@]}"
    write_tool_mapping_files "$PKG_DIR" "$TARGET_OS" "${metadata_tools[@]}"
    pkg_count=$(find "$PKG_DIR" -type f \( -name "*.rpm" -o -name "*.deb" \) 2>/dev/null | wc -l)
    [[ "$pkg_count" -gt 0 ]] && build_repo_index "$PKG_DIR" "$PKG_TYPE" || log "[download] skip repo index: no packages downloaded"
    tools_str=$(IFS=','; echo "${metadata_tools[*]}")
    deps_str=$(IFS=','; echo "${KERNEL_DEPS[*]}")
    sync_manifest "$tools_str" "$deps_str" "$TARGET_ARCH" "$TARGET_OS"
    merge_into_tarball "$STATIC_TARBALL" "$PKG_DIR" "$work_dir" "$merge_mode" "$TARGET_OS" "$TARGET_ARCH" "$tools_str" "$deps_str" "${all_packages[@]}" || {
        log_action_end "download" "run" "failed" "package_failed"
        return 1
    }

    print_header "$(t DOWNLOAD_COMPLETE)"
    show_status "ok" "$(t MENU_INSTALL): $STATIC_TARBALL"
    show_status "ok" "$(t PACKAGE_SIZE): $(du -sh "$STATIC_TARBALL" 2>/dev/null | cut -f1)"
    show_status "ok" "$(t CONFIG_TARGET): $TARGET_OS"
    show_status "ok" "$(t INSTALL_ARCH): $TARGET_ARCH"
    show_status "ok" "$(t CHECKSUM_GENERATED): ${STATIC_TARBALL}.sha256"
    show_status "ok" "$(t PACK_CONTAINS): $pkg_count $(t PACK_FILES)"
    print_section "$(t TOOLS_PACKAGE_TITLE)"
    printf "  - %s\n" "${metadata_tools[@]}"
    show_status "ok" "$(_wf_msg '可安装工具' 'Installable tools'): ${#metadata_tools[@]}"
    show_navigation_menu "main_menu"
    log_action_end "download" "run" "ok" "packaged_tools=${#metadata_tools[@]}"
}

check_and_prompt_existing_package(){
    local target_os="$1" target_arch="$2" output_dir="${3:-$OUTPUT_DIR}" tarball="$output_dir/offline_${target_os}_${target_arch}_merged.tar.xz"
    EXISTING_PACKAGE_PATH=""
    EXISTING_PACKAGE_TOOLS=()
    EXISTING_TOOL_SET=()
    [[ ! -f "$tarball" ]] && { echo "new"; return 0; }

    local existing_tools_csv=""
    existing_tools_csv=$(get_package_tools "$target_os" "$target_arch" 2>/dev/null || true)
    set_existing_tools_context "$output_dir" "$target_os" "$target_arch" "$existing_tools_csv"

    print_section "$(t EXISTING_PACKAGE)"
    echo "  $(t CONFIG_TARGET): ${target_os}_${target_arch}"
    echo "  $tarball"
    if [[ ${#EXISTING_PACKAGE_TOOLS[@]} -gt 0 ]]; then
        print_info "$(_wf_msg '已存在的工具:' 'Existing tools:')"
        printf "  %s\n" "${EXISTING_PACKAGE_TOOLS[@]}"
    fi
    echo "  1) $(_wf_msg '继续进入工具选择' 'Continue to tool selection')"
    echo "  2) $(_wf_msg '返回上级菜单' 'Back to previous menu')"
    echo "  3) $(_wf_msg '返回主菜单' 'Back to main menu')"

    local pre_choice
    read -r -p "$(_wf_msg '请选择操作 [1]: ' 'Select action [1]: ')" pre_choice
    pre_choice=${pre_choice:-1}
    case "$pre_choice" in
        0|2) echo "back"; return 0 ;;
        3) echo "main"; return 0 ;;
    esac

    echo "  1) $(t EXISTING_MERGE)"
    echo "  2) $(t EXISTING_NEW)"
    echo "  3) $(t EXISTING_CANCEL)"

    local choice
    read -r -p "$(_wf_msg '请选择模式 [1]: ' 'Select mode [1]: ')" choice
    choice=${choice:-1}
    case "$choice" in
        1) echo "merge"; return 0 ;;
        2)
            print_warning "$(_wf_msg '将删除已有离线包:' 'Will remove existing offline package:') $tarball"
            local confirm
            read -r -p "$(_wf_msg '确认删除？ [y/N]: ' 'Confirm delete? [y/N]: ')" confirm
            confirm=${confirm:-N}
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                rm -f "$tarball" "${tarball}.sha256"
                delete_package_metadata "$target_os" "$target_arch"
                EXISTING_PACKAGE_PATH=""
                EXISTING_PACKAGE_TOOLS=()
                EXISTING_TOOL_SET=()
                echo "new"
                return 0
            fi
            return 1
            ;;
        0) echo "back"; return 0 ;;
        *) return 1 ;;
    esac
}
