#!/bin/bash
# Configuration helpers: repo source loading, tool mapping, and user preferences.

declare -a REPOS=()
PKG_TYPE=""
RELEASE_VER=""
SUPPORTED_ARCHES=""
SKIP_SSL="${SKIP_SSL:-0}"

if ! declare -F log >/dev/null 2>&1; then
    log(){
        local msg="$1"
        if [[ -n "${LOG_FILE:-}" ]]; then
            echo "[$(date '+%F %T')] $msg" >> "$LOG_FILE" 2>/dev/null || true
        fi
    }
fi

_config_trim(){
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    echo "$value"
}

_config_error(){
    local message_zh="$1"
    local message_en="$2"
    local hint_zh="$3"
    local hint_en="$4"
    show_error_detail \
        "$(lang_pick "配置错误" "Configuration error")" \
        "$(lang_pick "$message_zh" "$message_en")" \
        "$(lang_pick "$hint_zh" "$hint_en")"
}

load_os_config(){
    local os_type="$1"
    local conf_file="$CONF_DIR/os_sources.conf"
    local line in_section=0

    if [[ ! -f "$conf_file" ]]; then
        _config_error \
            "系统源配置文件不存在: $conf_file" \
            "OS source config not found: $conf_file" \
            "请检查 conf/os_sources.conf" \
            "Check conf/os_sources.conf"
        return 1
    fi

    REPOS=()
    PKG_TYPE=""
    RELEASE_VER=""
    SUPPORTED_ARCHES=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        line=$(_config_trim "$line")
        [[ -z "$line" || "$line" == \#* ]] && continue

        if [[ "$line" =~ ^\[([A-Za-z0-9._-]+)\]$ ]]; then
            if [[ "${BASH_REMATCH[1]}" == "$os_type" ]]; then
                in_section=1
            else
                in_section=0
            fi
            continue
        fi

        [[ $in_section -eq 1 ]] || continue

        if [[ "$line" =~ ^PKG_TYPE=(.+)$ ]]; then
            PKG_TYPE=$(_config_trim "${BASH_REMATCH[1]}")
        elif [[ "$line" =~ ^RELEASEVER=(.+)$ ]]; then
            RELEASE_VER=$(_config_trim "${BASH_REMATCH[1]}")
        elif [[ "$line" =~ ^SUPPORTED_ARCHES=(.+)$ ]]; then
            SUPPORTED_ARCHES=$(_config_trim "${BASH_REMATCH[1]}")
        elif [[ "$line" =~ \"([^\"]+)\" ]]; then
            REPOS+=("${BASH_REMATCH[1]}")
        fi
    done < "$conf_file"

    if [[ ${#REPOS[@]} -eq 0 ]]; then
        _config_error \
            "[$os_type] 未找到任何仓库配置" \
            "[$os_type] no repositories configured" \
            "请检查 os_sources.conf 中对应的系统段" \
            "Check the matching system section in os_sources.conf"
        return 1
    fi

    if [[ -z "$PKG_TYPE" ]]; then
        _config_error \
            "[$os_type] 未设置 PKG_TYPE" \
            "[$os_type] PKG_TYPE is missing" \
            "请检查 os_sources.conf 中的 PKG_TYPE" \
            "Check PKG_TYPE in os_sources.conf"
        return 1
    fi

    if [[ -n "${SUPPORTED_ARCHES:-}" && " $SUPPORTED_ARCHES " != *" ${TARGET_ARCH:-} "* ]]; then
        _config_error \
            "[$os_type] 不支持架构 ${TARGET_ARCH:-unknown}，支持架构: $SUPPORTED_ARCHES" \
            "[$os_type] unsupported architecture ${TARGET_ARCH:-unknown}; supported: $SUPPORTED_ARCHES" \
            "请重新选择目标系统或架构" \
            "Select a compatible OS and architecture"
        return 1
    fi

    log "[config] loaded os config: os=$os_type repos=${#REPOS[@]} pkg_type=$PKG_TYPE release=$RELEASE_VER arches=${SUPPORTED_ARCHES:-all}"
    return 0
}

check_repo_availability(){
    local url="$1"
    local timeout="${2:-5}"
    local probe="$url"

    if [[ "${PKG_TYPE:-}" == "rpm" ]]; then
        probe="${url%/}/repodata/repomd.xml"
    elif [[ "${PKG_TYPE:-}" == "deb" && -n "${RELEASE_VER:-}" ]]; then
        probe="${url%/}/dists/${RELEASE_VER}/InRelease"
        curl -fsSLk --max-time "$timeout" -o /dev/null "$probe" >/dev/null 2>&1 && return 0
        probe="${url%/}/dists/${RELEASE_VER}/Release"
    fi

    curl -fsSLk --max-time "$timeout" -o /dev/null "$probe" >/dev/null 2>&1
}

filter_reachable_repos(){
    local -a filtered=()
    local repo expanded

    for repo in "${REPOS[@]}"; do
        expanded=$(echo "$repo" | sed "s/\$ARCH/$TARGET_ARCH/g" | sed "s/\$RELEASEVER/$RELEASE_VER/g")
        if check_repo_availability "$expanded" 4; then
            filtered+=("$repo")
        else
            log "[repo] skip unreachable source: $expanded"
        fi
    done

    if [[ ${#filtered[@]} -gt 0 ]]; then
        REPOS=("${filtered[@]}")
        return 0
    fi
    return 1
}

pick_best_repos(){
    local -a good_repos=()
    local -A mirror_names=()
    local repo expanded mirror_name prefix domain
    local idx=0

    log "[repo] probing ${#REPOS[@]} configured sources"

    if load_mirror_cache "$TARGET_OS" "$TARGET_ARCH"; then
        log "[repo] using cached mirror availability"
        return 0
    fi

    if [[ -f "$CONF_DIR/mirror_names.conf" ]]; then
        while IFS='=' read -r repo mirror_name; do
            repo=$(_config_trim "$repo")
            mirror_name=$(_config_trim "$mirror_name")
            [[ -z "$repo" || "$repo" == \#* || -z "$mirror_name" ]] && continue
            mirror_names["$repo"]="$mirror_name"
        done < "$CONF_DIR/mirror_names.conf"
    fi

    echo ""
    print_info "$(lang_pick "正在探测 ${#REPOS[@]} 个镜像源连通性..." "Checking connectivity for ${#REPOS[@]} mirror sources...")"

    for repo in "${REPOS[@]}"; do
        idx=$((idx + 1))
        expanded=$(echo "$repo" | sed "s/\$ARCH/$TARGET_ARCH/g" | sed "s/\$RELEASEVER/$RELEASE_VER/g")

        mirror_name="${mirror_names[$repo]:-}"
        if [[ -z "$mirror_name" ]]; then
            for prefix in "${!mirror_names[@]}"; do
                if [[ "$repo" == "$prefix"* ]]; then
                    mirror_name="${mirror_names[$prefix]}"
                    break
                fi
            done
        fi
        if [[ -z "$mirror_name" ]]; then
            domain=$(echo "$repo" | sed -E 's|https?://([^/]+).*|\1|')
            mirror_name="${mirror_names[$domain]:-$domain}"
        fi

        if check_repo_availability "$expanded"; then
            good_repos+=("$repo")
            printf "  [%bOK%b] %s (%d/%d)\n" "$COLOR_GREEN" "$COLOR_RESET" "$mirror_name" "$idx" "${#REPOS[@]}"
        else
            printf "  [%bSKIP%b] %s (%d/%d)\n" "$COLOR_YELLOW" "$COLOR_RESET" "$mirror_name" "$idx" "${#REPOS[@]}"
        fi
    done

    echo ""
    if [[ ${#good_repos[@]} -gt 0 ]]; then
        REPOS=("${good_repos[@]}")
        print_success "$(lang_pick "已选择 ${#REPOS[@]} 个可用镜像源" "Selected ${#REPOS[@]} reachable mirror sources")"
        save_mirror_cache "$TARGET_OS" "$TARGET_ARCH" "${REPOS[@]}"
        log "[repo] selected ${#REPOS[@]} reachable sources"
        return 0
    fi

    print_warning "$(lang_pick "没有探测到可用镜像源，将继续尝试下载" "No reachable mirror source detected; download will still be attempted")"
    log "[repo] all configured sources unreachable"
    return 1
}

generate_repo_config(){
    local repo_file="$WORK_DIR/repo_config/temp.repo"
    local repo_url expanded
    local ssl_block=""

    mkdir -p "$WORK_DIR/repo_config"

    if [[ "$SKIP_SSL" == "1" ]]; then
        ssl_block=$'sslverify=0\nip_resolve=4'
    fi

    cat > "$repo_file" <<'EOF'
[offline-temp]
name=Offline Temp Repo
EOF

    for repo_url in "${REPOS[@]}"; do
        expanded=$(echo "$repo_url" | sed "s/\$ARCH/$TARGET_ARCH/g" | sed "s/\$RELEASEVER/$RELEASE_VER/g")
        echo "baseurl=$expanded" >> "$repo_file"
    done

    printf '%s\n' 'enabled=1' 'gpgcheck=0' 'skip_if_unavailable=1' >> "$repo_file"
    [[ -n "$ssl_block" ]] && echo "$ssl_block" >> "$repo_file"

    echo "$repo_file"
}

get_tool_os_rule(){
    local target_os="$1"
    local target_arch="$2"
    local tool_id="$3"
    local -a rule_files=("$CONF_DIR/tool_os_rules.local.conf" "$CONF_DIR/tool_os_rules.conf")
    local rule_file os_pat arch_pat rule_tool status rpm_override deb_override suggestion

    for rule_file in "${rule_files[@]}"; do
        [[ -f "$rule_file" ]] || continue
        while IFS='|' read -r os_pat arch_pat rule_tool status rpm_override deb_override suggestion; do
            os_pat=$(_config_trim "$os_pat")
            arch_pat=$(_config_trim "${arch_pat:-*}")
            rule_tool=$(_config_trim "$rule_tool")
            [[ -z "$os_pat" || "$os_pat" == \#* ]] && continue
            if [[ "$target_os" == $os_pat && "${target_arch:-*}" == $arch_pat && "$tool_id" == "$rule_tool" ]]; then
                echo "${os_pat}|${arch_pat}|${rule_tool}|${status}|${rpm_override}|${deb_override}|${suggestion}"
                return 0
            fi
        done < "$rule_file"
    done
    return 1
}

get_tool_support_status_for_os(){
    local tool_id="$1"
    local target_os="${2:-$TARGET_OS}"
    local target_arch="${3:-$TARGET_ARCH}"
    local rule_line status

    rule_line=$(get_tool_os_rule "$target_os" "$target_arch" "$tool_id" 2>/dev/null || true)
    if [[ -n "$rule_line" ]]; then
        IFS='|' read -r _a _b _c status _d _e _f <<< "$rule_line"
        [[ "$status" == "UNSUPPORTED" ]] && { echo "UNSUPPORTED"; return 0; }
    fi
    echo "SUPPORTED"
}

get_tool_support_suggestion_for_os(){
    local tool_id="$1"
    local target_os="${2:-$TARGET_OS}"
    local target_arch="${3:-$TARGET_ARCH}"
    local rule_line suggestion

    rule_line=$(get_tool_os_rule "$target_os" "$target_arch" "$tool_id" 2>/dev/null || true)
    if [[ -n "$rule_line" ]]; then
        IFS='|' read -r _a _b _c _d _e _f suggestion <<< "$rule_line"
        echo "${suggestion:-}"
        return 0
    fi
    echo ""
}

_tool_pkg_type_for_os(){
    case "${1:-$TARGET_OS}" in
        openEuler*|Rocky*|CentOS*|AliOS*|Tlinux*|openAnolis*) echo "rpm" ;;
        Ubuntu*|Kylin*) echo "deb" ;;
        *) echo "rpm" ;;
    esac
}

get_tool_packages_for_os(){
    local tool_id="$1"
    local target_os="${2:-$TARGET_OS}"
    local target_arch="${3:-$TARGET_ARCH}"
    local pkg_type packages="" rule_line status rpm_override deb_override _suggestion

    pkg_type=$(_tool_pkg_type_for_os "$target_os")
    if [[ "$pkg_type" == "rpm" ]]; then
        packages="${TOOL_RPM_PACKAGES[$tool_id]:-}"
    else
        packages="${TOOL_DEB_PACKAGES[$tool_id]:-}"
    fi

    rule_line=$(get_tool_os_rule "$target_os" "$target_arch" "$tool_id" 2>/dev/null || true)
    if [[ -n "$rule_line" ]]; then
        IFS='|' read -r _os_pat _arch_pat _tool status rpm_override deb_override _suggestion <<< "$rule_line"
        if [[ "$status" == "UNSUPPORTED" ]]; then
            echo ""
            return 0
        fi
        if [[ "$pkg_type" == "rpm" && -n "$rpm_override" && "$rpm_override" != "-" ]]; then
            packages="$rpm_override"
        fi
        if [[ "$pkg_type" == "deb" && -n "$deb_override" && "$deb_override" != "-" ]]; then
            packages="$deb_override"
        fi
    fi

    [[ -z "$packages" ]] && echo "$tool_id" || echo "$packages"
}

is_group_style_tool_for_os(){
    local tool_id="$1"
    local target_os="${2:-$TARGET_OS}"
    local target_arch="${3:-$TARGET_ARCH}"
    local packages pkg count=0

    packages=$(get_tool_packages_for_os "$tool_id" "$target_os" "$target_arch")
    [[ -z "$packages" ]] && return 1

    for pkg in $packages; do
        count=$((count + 1))
        if [[ "$pkg" == @* || "$pkg" == *"*"* || "$pkg" == *"?"* ]]; then
            return 0
        fi
    done

    [[ $count -gt 1 ]]
}

load_tools_config(){
    local conf_dir="${1:-$CONF_DIR}"
    local target_os="${2:-$TARGET_OS}"
    local target_arch="${3:-$TARGET_ARCH}"
    local mode="${4:-${TOOL_SELECTION_MODE:-all}}"
    local conf_file="$conf_dir/tools.conf"
    local tool_id desc rpm_pkgs deb_pkgs include_tool group_like
    local -a tools=()
    local -a descs=()

    declare -gA TOOL_RPM_PACKAGES=()
    declare -gA TOOL_DEB_PACKAGES=()

    if [[ ! -f "$conf_file" ]]; then
        _config_error \
            "工具配置文件不存在: $conf_file" \
            "Tool config not found: $conf_file" \
            "请检查 conf/tools.conf" \
            "Check conf/tools.conf"
        return 1
    fi
    while IFS='|' read -r tool_id desc rpm_pkgs deb_pkgs; do
        tool_id=$(_config_trim "$tool_id")
        desc=$(_config_trim "$desc")
        rpm_pkgs=$(_config_trim "$rpm_pkgs")
        deb_pkgs=$(_config_trim "$deb_pkgs")

        [[ -z "$tool_id" || "$tool_id" == \#* ]] && continue

        TOOL_RPM_PACKAGES["$tool_id"]="$rpm_pkgs"
        TOOL_DEB_PACKAGES["$tool_id"]="$deb_pkgs"

        include_tool=1
        if [[ "$mode" == "group" || "$mode" == "package" ]]; then
            if is_group_style_tool_for_os "$tool_id" "$target_os" "$target_arch"; then
                group_like=1
            else
                group_like=0
            fi

            if [[ "$mode" == "group" && $group_like -ne 1 ]]; then
                include_tool=0
            elif [[ "$mode" == "package" && $group_like -eq 1 ]]; then
                include_tool=0
            fi
        fi

        if [[ $include_tool -eq 1 ]]; then
            tools+=("$tool_id")
            descs+=("$desc")
        fi
    done < "$conf_file"

    if [[ ${#tools[@]} -eq 0 ]]; then
        _config_error \
            "閻熸粎澧楅幐鍛婃櫠閻樺弬鐔煎灳瀹曞洨顢呮繛鎴炴尭椤戝棝鎯€閸涙潙瀚夊璺猴工鐠佹煡鏌ｉ～顒€濡煎ù鍏煎姍瀹? \
            "No tools available for current mode" \
            "闁荤姴娲弨閬嵥夐崨鏉戣摕?tools.conf 闂佺懓鐡ㄩ悧鏇㈠垂韫囨稑绠查柕蹇曞С缁憋綁鏌涜箛鏇炲幋闁逞屽墮椤︽壆鈧哎鍔岃灒闁炽儱纾涵鈧? \
            "Check tools.conf or switch tool selection mode"
        return 1
    fi

    AVAILABLE_TOOLS=("${tools[@]}")
    AVAILABLE_TOOL_DESCS=("${descs[@]}")
    log "[config] loaded ${#AVAILABLE_TOOLS[@]} tools (mode=$mode, os=$target_os, arch=$target_arch)"
    return 0
}

get_tool_description(){
    local tool="$1"
    local i conf_file="$CONF_DIR/tools.conf" desc=""

    if [[ -n "${AVAILABLE_TOOLS+x}" && -n "${AVAILABLE_TOOL_DESCS+x}" ]]; then
        for i in "${!AVAILABLE_TOOLS[@]}"; do
            if [[ "${AVAILABLE_TOOLS[$i]}" == "$tool" ]]; then
                echo "${AVAILABLE_TOOL_DESCS[$i]}"
                return 0
            fi
        done
    fi

    if [[ -f "$conf_file" ]]; then
        while IFS='|' read -r tool_id description _rpm _deb; do
            tool_id=$(_config_trim "$tool_id")
            [[ -z "$tool_id" || "$tool_id" == \#* ]] && continue
            if [[ "$tool_id" == "$tool" ]]; then
                desc=$(_config_trim "$description")
                break
            fi
        done < "$conf_file"
    fi

    [[ -z "$desc" ]] && desc=$(get_kernel_dep_description "$tool")
    echo "${desc:-$tool}"
}

get_selected_tool_packages(){
    local selected_tools_str="$1"
    local target_os="${2:-$TARGET_OS}"
    local -a all_packages=()
    local tool packages pkg

    IFS=',' read -ra tools_arr <<< "$selected_tools_str"
    for tool in "${tools_arr[@]}"; do
        tool=$(_config_trim "$tool")
        [[ -z "$tool" ]] && continue
        packages=$(get_tool_packages_for_os "$tool" "$target_os" "$TARGET_ARCH")
        for pkg in $packages; do
            all_packages+=("$pkg")
        done
    done

    echo "${all_packages[*]}"
}

get_kernel_dep_description(){
    case "$1" in
        make) echo "$(lang_pick "GNU make 构建工具" "GNU make build tool")" ;;
        dkms) echo "$(lang_pick "动态内核模块支持" "Dynamic Kernel Module Support")" ;;
        gcc) echo "$(lang_pick "GNU C 编译器" "GNU C compiler")" ;;
        kernel-headers) echo "$(lang_pick "内核头文件" "Kernel headers")" ;;
        kernel-devel) echo "$(lang_pick "内核开发包" "Kernel development package")" ;;
        kernel-tlinux4-devel) echo "$(lang_pick "Tlinux4 内核开发包" "Tlinux4 kernel development package")" ;;
        kernel-tlinux4-headers) echo "$(lang_pick "Tlinux4 内核头文件" "Tlinux4 kernel headers")" ;;
        elfutils-libelf-devel) echo "$(lang_pick "ELF 开发库" "ELF development library")" ;;
        linux-headers) echo "$(lang_pick "Linux 内核头文件" "Linux kernel headers")" ;;
        linux-libc-dev) echo "$(lang_pick "Linux libc 开发头文件" "Linux libc development headers")" ;;
        *) echo "$(lang_pick "内核依赖" "Kernel dependency")" ;;
    esac
}

save_user_preferences(){
    local pref_file="$CONF_DIR/user_prefs.conf"

    cat > "$pref_file" <<EOF
# User preferences
LAST_OS=$TARGET_OS
LAST_ARCH=$TARGET_ARCH
LAST_SKIP_SSL=$SKIP_SSL
EOF

    log "[config] user preferences saved"
}

load_user_preferences(){
    local pref_file="$CONF_DIR/user_prefs.conf"
    local key value

    [[ -f "$pref_file" ]] || return 1

    while IFS='=' read -r key value; do
        key=$(_config_trim "$key")
        value=$(_config_trim "$value")
        [[ -z "$key" || "$key" == \#* ]] && continue
        case "$key" in
            LAST_OS) TARGET_OS="$value" ;;
            LAST_ARCH) TARGET_ARCH="$value" ;;
            LAST_SKIP_SSL) SKIP_SSL="$value" ;;
        esac
    done < "$pref_file"

    log "[config] user preferences loaded"
    return 0
}

export -f load_os_config
export -f check_repo_availability
export -f filter_reachable_repos
export -f pick_best_repos
export -f generate_repo_config
export -f get_tool_os_rule
export -f get_tool_support_status_for_os
export -f get_tool_support_suggestion_for_os
export -f get_tool_packages_for_os
export -f is_group_style_tool_for_os
export -f load_tools_config
export -f get_tool_description
export -f get_selected_tool_packages
export -f get_kernel_dep_description
export -f save_user_preferences
export -f load_user_preferences
