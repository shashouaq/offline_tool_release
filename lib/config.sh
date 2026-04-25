#!/bin/bash
# =====================================================
# 配置管理模块 - config.sh
# 统一管理配置文件加载、验证等功能
# =====================================================

# 全局配置变量
declare -a REPOS=()
PKG_TYPE=""
RELEASE_VER=""
SKIP_SSL=0

# 允许模块在单独测试时运行；主程序中会使用 logger.sh 提供的 log。
if ! declare -F log >/dev/null 2>&1; then
    log(){
        local msg="$1"
        if [[ -n "${LOG_FILE:-}" ]]; then
            echo "[$(date '+%F %T')] $msg" >> "$LOG_FILE" 2>/dev/null || true
        fi
    }
fi

# =============================================
# 加载操作系统仓库配置
# =============================================
load_os_config(){
    local os_type="$1"
    local conf_file="$CONF_DIR/os_sources.conf"

    [[ ! -f "$conf_file" ]] && {
        show_error_detail "配置错误" "配置文件不存在: $conf_file" "请检查配置文件路径"
        return 1
    }

    REPOS=()
    PKG_TYPE=""
    RELEASE_VER=""

    local in_section=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 跳过注释和空行
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # 检测段开始
        if [[ "$line" =~ ^\[([A-Za-z0-9.]+)\] ]]; then
            if [[ "${BASH_REMATCH[1]}" == "$os_type" ]]; then
                in_section=true
            else
                in_section=false
            fi
            continue
        fi

        # 只处理当前段
        $in_section || continue

        # 解析配置项
        if [[ "$line" =~ ^[[:space:]]*PKG_TYPE=(.+) ]]; then
            PKG_TYPE="${BASH_REMATCH[1]// /}"
        elif [[ "$line" =~ ^[[:space:]]*RELEASEVER=(.+) ]]; then
            RELEASE_VER="${BASH_REMATCH[1]// /}"
        elif [[ "$line" =~ \"([^\"]+)\" ]]; then
            REPOS+=("${BASH_REMATCH[1]}")
        fi
    done < "$conf_file"

    # 验证配置
    if [[ ${#REPOS[@]} -eq 0 ]]; then
        show_error_detail "配置错误" "[$os_type] 未找到任何仓库配置" "请检查 os_sources.conf 文件"
        return 1
    fi

    if [[ -z "$PKG_TYPE" ]]; then
        show_error_detail "配置错误" "[$os_type] 未设置 PKG_TYPE" "请检查 os_sources.conf 文件"
        return 1
    fi

    log "[配置] [$os_type] 加载 ${#REPOS[@]} 个仓库, PKG_TYPE=$PKG_TYPE"
    return 0
}

# =============================================
# 检测并选择最佳镜像源
# =============================================
check_repo_availability(){
    local url="$1"
    local timeout="${2:-5}"

    curl -sk --max-time "$timeout" -I "$url" &>/dev/null
    return $?
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

    log "[检测] 测试 ${#REPOS[@]} 个镜像源..."
    
    # 尝试从缓存加载
    if load_mirror_cache "$TARGET_OS" "$TARGET_ARCH"; then
        # 缓存命中，直接使用缓存的镜像源
        return 0
    fi
    
    # 加载镜像源中文名称映射
    declare -A MIRROR_NAMES
    if [[ -f "$CONF_DIR/mirror_names.conf" ]]; then
        while IFS='=' read -r url name; do
            # 跳过注释和空行
            [[ "$url" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${url// }" ]] && continue
            
            # 去除首尾空格
            url=$(echo "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            name=$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            if [[ -n "$url" ]] && [[ -n "$name" ]]; then
                MIRROR_NAMES["$url"]="$name"
            fi
        done < "$CONF_DIR/mirror_names.conf"
    fi
    
    # 只显示简短的进度提示，不显示每个URL的详细进度条
    echo ""
    print_info "正在检测 ${#REPOS[@]} 个镜像源的连通性..."
    
    local idx=0
    for repo in "${REPOS[@]}"; do
        ((idx++))
        local expanded
        expanded=$(echo "$repo" | sed "s/\$ARCH/$TARGET_ARCH/g" | sed "s/\$RELEASEVER/$RELEASE_VER/g")

        # 获取中文名称
        local mirror_name=""
        # 尝试精确匹配
        if [[ -n "${MIRROR_NAMES[$repo]+x}" ]]; then
            mirror_name="${MIRROR_NAMES[$repo]}"
        else
            # 尝试前缀匹配
            for prefix in "${!MIRROR_NAMES[@]}"; do
                if [[ "$repo" == "$prefix"* ]]; then
                    mirror_name="${MIRROR_NAMES[$prefix]}"
                    break
                fi
            done
            
            # 如果还是没有匹配，提取域名
            if [[ -z "$mirror_name" ]]; then
                local domain
                domain=$(echo "$repo" | sed -E 's|https?://([^/]+).*|\1|')
                mirror_name="${MIRROR_NAMES[$domain]:-$domain}"
            fi
        fi

        if check_repo_availability "$expanded"; then
            good_repos+=("$repo")
            # 显示中文名称和序号
            printf "  [${COLOR_GREEN}✓${COLOR_RESET}] %s (%d/%d)\n" "$mirror_name" "$idx" "${#REPOS[@]}"
        else
            printf "  [${COLOR_RED}✗${COLOR_RESET}] %s (%d/%d) (跳过)\n" "$mirror_name" "$idx" "${#REPOS[@]}"
        fi
    done

    echo ""
    if [[ ${#good_repos[@]} -gt 0 ]]; then
        REPOS=("${good_repos[@]}")
        print_success "检测到 ${#REPOS[@]} 个可用镜像源"
        log "[结果] 选用 ${#REPOS[@]} 个可用源"
        
        # 保存检测结果到缓存
        save_mirror_cache "$TARGET_OS" "$TARGET_ARCH" "${REPOS[@]}"
        
        return 0
    else
        print_warning "所有镜像源不可达，仍将尝试下载"
        log "[警告] 所有镜像不可达，仍将尝试下载"
        return 1
    fi
}

# =============================================
# 生成临时 repo 配置文件
# =============================================
generate_repo_config(){
    local repo_file="$WORK_DIR/repo_config/temp.repo"
    mkdir -p "$WORK_DIR/repo_config"

    # SSL 选项
    local ssl_opt=""
    if [[ "$SKIP_SSL" == "1" ]]; then
        ssl_opt=$'sslverify=0\nip_resolve=4'
    fi

    # 构建展开后的 URL 列表
    local -a expanded_urls=()
    for repo_url in "${REPOS[@]}"; do
        local x_url
        x_url=$(echo "$repo_url" | sed "s/\$ARCH/$TARGET_ARCH/g" | sed "s/\$RELEASEVER/$RELEASE_VER/g")
        expanded_urls+=("$x_url")
    done

    # 生成 repo 文件
    cat > "$repo_file" <<'HEADER'
[offline-temp]
name=Offline Temp Repo
HEADER

    for x_url in "${expanded_urls[@]}"; do
        echo "baseurl=$x_url" >> "$repo_file"
    done

    printf '%s\n' 'enabled=1' 'gpgcheck=0' 'skip_if_unavailable=1' >> "$repo_file"

    if [[ -n "$ssl_opt" ]]; then
        echo "$ssl_opt" >> "$repo_file"
    fi

    # 只返回文件路径，不输出日志（避免污染返回值）
    echo "$repo_file"
}

# =============================================
# 加载工具配置（支持多OS包组）
# 全局变量输出：
#   AVAILABLE_TOOLS - 工具ID列表（用于选择）
#   AVAILABLE_TOOL_DESCS - 工具描述列表（用于显示）
#   TOOL_RPM_PACKAGES - RPM系统的包名映射（tool_id -> packages）
#   TOOL_DEB_PACKAGES - DEB系统的包名映射（tool_id -> packages）
# =============================================
load_tools_config(){
    local conf_file="$CONF_DIR/tools.conf"
    local target_os="${1:-$TARGET_OS}"
    local -a tools=()
    local -a descs=()
    
    # 声明关联数组存储包名映射
    declare -gA TOOL_RPM_PACKAGES=()
    declare -gA TOOL_DEB_PACKAGES=()

    [[ ! -f "$conf_file" ]] && {
        show_error_detail "配置错误" "工具配置文件不存在: $conf_file" "请检查配置文件"
        return 1
    }

    while IFS='|' read -r tool_id desc rpm_pkgs deb_pkgs; do
        # 跳过注释和空行
        [[ "$tool_id" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${tool_id// }" ]] && continue

        # 清理空格
        tool_id=$(echo "$tool_id" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        desc=$(echo "$desc" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        rpm_pkgs=$(echo "$rpm_pkgs" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        deb_pkgs=$(echo "$deb_pkgs" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        [[ -z "$tool_id" ]] && continue
        
        # 添加工具到列表
        tools+=("$tool_id")
        descs+=("$desc")
        
        # 存储包名映射
        TOOL_RPM_PACKAGES["$tool_id"]="$rpm_pkgs"
        TOOL_DEB_PACKAGES["$tool_id"]="$deb_pkgs"
        
    done < "$conf_file"

    if [[ ${#tools[@]} -eq 0 ]]; then
        show_error_detail "配置错误" "tools.conf 为空或格式错误" "请检查工具配置文件"
        return 1
    fi

    # 返回工具列表（通过全局变量）
    AVAILABLE_TOOLS=("${tools[@]}")
    AVAILABLE_TOOL_DESCS=("${descs[@]}")
    
    log "[配置] 加载 ${#tools[@]} 个可用工具"
    return 0
}

# =============================================
# 获取工具描述
# =============================================
get_tool_description(){
    local tool="$1"
    
    # 首先尝试从已加载的描述中获取
    if [[ -n "${AVAILABLE_TOOLS+x}" ]] && [[ -n "${AVAILABLE_TOOL_DESCS+x}" ]]; then
        for i in "${!AVAILABLE_TOOLS[@]}"; do
            if [[ "${AVAILABLE_TOOLS[$i]}" == "$tool" ]]; then
                echo "${AVAILABLE_TOOL_DESCS[$i]}"
                return
            fi
        done
    fi
    
    # 否则从配置文件读取
    local conf_file="$CONF_DIR/tools.conf"
    local desc=""
    while IFS='|' read -r tool_id description _rpm _deb; do
        # 跳过注释
        [[ "$tool_id" =~ ^[[:space:]]*# ]] && continue
        tool_id=$(echo "$tool_id" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        if [[ "$tool_id" == "$tool" ]]; then
            desc="$description"
            break
        fi
    done < "$conf_file"

    # 如果没有找到描述，尝试内核依赖描述
    if [[ -z "$desc" ]]; then
        desc=$(get_kernel_dep_description "$tool")
    fi

    echo "${desc:-工具}"
}

# =============================================
# 根据目标OS获取工具的包名列表
# 用法：get_tool_packages_for_os "htop" "openEuler22.03"
# 返回：包名列表（空格分隔）
# =============================================
get_tool_packages_for_os(){
    local tool_id="$1"
    local target_os="${2:-$TARGET_OS}"
    
    # 判断是RPM还是DEB系统
    local pkg_type=""
    case "$target_os" in
        openEuler*|Rocky*|CentOS*|AliOS*|Tlinux*|openAnolis*)
            pkg_type="rpm"
            ;;
        Ubuntu*|Kylin*)
            pkg_type="deb"
            ;;
        *)
            # 默认尝试RPM
            pkg_type="rpm"
            ;;
    esac
    
    # 获取对应的包名
    local packages=""
    if [[ "$pkg_type" == "rpm" ]]; then
        packages="${TOOL_RPM_PACKAGES[$tool_id]:-}"
    else
        packages="${TOOL_DEB_PACKAGES[$tool_id]:-}"
    fi
    
    # 如果没找到，返回工具ID本身作为后备
    if [[ -z "$packages" ]]; then
        echo "$tool_id"
    else
        echo "$packages"
    fi
}

# =============================================
# 获取当前OS下所有选中工具的实际包名列表
# 用法：get_selected_tool_packages "htop,git,vim"
# 返回：包名数组
# =============================================
get_selected_tool_packages(){
    local selected_tools_str="$1"
    local target_os="${2:-$TARGET_OS}"
    local -a all_packages=()
    
    IFS=',' read -ra tools_arr <<< "$selected_tools_str"
    
    for tool in "${tools_arr[@]}"; do
        [[ -z "$tool" ]] && continue
        local packages
        packages=$(get_tool_packages_for_os "$tool" "$target_os")
        
        # 将空格分隔的包名添加到数组
        for pkg in $packages; do
            all_packages+=("$pkg")
        done
    done
    
    # 输出所有包名
    echo "${all_packages[@]}"
}

# =============================================
# 获取内核依赖描述
# =============================================
get_kernel_dep_description(){
    case "$1" in
        make)                    echo "GNU make（编译工具）";;
        dkms)                    echo "Dynamic Kernel Module Support（内核模块编译框架）";;
        gcc)                     echo "GNU C 编译器";;
        kernel-headers)          echo "内核头文件";;
        kernel-devel)            echo "内核开发包";;
        kernel-tlinux4-devel)    echo "Tlinux4 内核开发包";;
        kernel-tlinux4-headers)  echo "Tlinux4 内核头文件";;
        elfutils-libelf-devel)   echo "ELF 工具库开发包";;
        linux-headers)           echo "Linux 内核头文件";;
        linux-libc-dev)          echo "Linux C 库头文件";;
        *)                       echo "内核依赖";;
    esac
}

# =============================================
# 保存用户偏好配置
# =============================================
save_user_preferences(){
    local pref_file="$CONF_DIR/user_prefs.conf"

    cat > "$pref_file" <<PREFS
# 用户偏好配置
LAST_OS=$TARGET_OS
LAST_ARCH=$TARGET_ARCH
LAST_SKIP_SSL=$SKIP_SSL
PREFS

    log "[配置] 已保存用户偏好"
}

# =============================================
# 加载用户偏好配置
# =============================================
load_user_preferences(){
    local pref_file="$CONF_DIR/user_prefs.conf"

    if [[ -f "$pref_file" ]]; then
        while IFS='=' read -r key value; do
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${key// }" ]] && continue
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            case "$key" in
                LAST_OS) TARGET_OS="$value" ;;
                LAST_ARCH) TARGET_ARCH="$value" ;;
                LAST_SKIP_SSL) SKIP_SSL="$value" ;;
            esac
        done < "$pref_file"
        log "[配置] 已加载用户偏好"
        return 0
    fi
    return 1
}

# =============================================
# 导出函数
# =============================================
get_tool_os_rule(){
    local target_os="$1" target_arch="$2" tool_id="$3"
    local -a rule_files=("$CONF_DIR/tool_os_rules.local.conf" "$CONF_DIR/tool_os_rules.conf")
    local rule_file os_pat arch_pat rule_tool status rpm_override deb_override suggestion
    for rule_file in "${rule_files[@]}"; do
        [[ -f "$rule_file" ]] || continue
        while IFS='|' read -r os_pat arch_pat rule_tool status rpm_override deb_override suggestion; do
            [[ -z "${os_pat// }" || "$os_pat" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$arch_pat" ]] && arch_pat="*"
            if [[ "$target_os" == $os_pat && "${target_arch:-*}" == $arch_pat && "$tool_id" == "$rule_tool" ]]; then
                echo "${os_pat}|${arch_pat}|${rule_tool}|${status}|${rpm_override}|${deb_override}|${suggestion}"
                return 0
            fi
        done < "$rule_file"
    done
    return 1
}

get_tool_support_status_for_os(){
    local tool_id="$1" target_os="${2:-$TARGET_OS}" target_arch="${3:-$TARGET_ARCH}"
    local rule_line status
    rule_line=$(get_tool_os_rule "$target_os" "$target_arch" "$tool_id" 2>/dev/null || true)
    if [[ -n "$rule_line" ]]; then
        IFS='|' read -r _a _b _c status _d _e _f <<< "$rule_line"
        [[ "$status" == "UNSUPPORTED" ]] && { echo "UNSUPPORTED"; return 0; }
    fi
    echo "SUPPORTED"
}

get_tool_support_suggestion_for_os(){
    local tool_id="$1" target_os="${2:-$TARGET_OS}" target_arch="${3:-$TARGET_ARCH}"
    local rule_line suggestion
    rule_line=$(get_tool_os_rule "$target_os" "$target_arch" "$tool_id" 2>/dev/null || true)
    if [[ -n "$rule_line" ]]; then
        IFS='|' read -r _a _b _c _d _e _f suggestion <<< "$rule_line"
        echo "${suggestion:-}"
        return 0
    fi
    echo ""
}

get_tool_packages_for_os(){
    local tool_id="$1"
    local target_os="${2:-$TARGET_OS}"
    local target_arch="${3:-$TARGET_ARCH}"
    local pkg_type="rpm"
    local packages="" rule_line status rpm_override deb_override _suggestion
    case "$target_os" in
        openEuler*|Rocky*|CentOS*|AliOS*|Tlinux*|openAnolis*) pkg_type="rpm" ;;
        Ubuntu*|Kylin*) pkg_type="deb" ;;
        *) pkg_type="rpm" ;;
    esac
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

# Override loader with explicit mode filtering (group/package/all).
load_tools_config(){
    local conf_dir="${1:-$CONF_DIR}"
    local target_os="${2:-$TARGET_OS}"
    local target_arch="${3:-$TARGET_ARCH}"
    local mode="${4:-${TOOL_SELECTION_MODE:-all}}"
    local conf_file="$conf_dir/tools.conf"
    local -a tools=()
    local -a descs=()
    local -a filtered_tools=()
    local -a filtered_descs=()
    local tool_id desc rpm_pkgs deb_pkgs idx group_like

    declare -gA TOOL_RPM_PACKAGES=()
    declare -gA TOOL_DEB_PACKAGES=()

    [[ ! -f "$conf_file" ]] && {
        show_error_detail "配置错误" "工具配置文件不存在: $conf_file" "请检查配置文件路径"
        return 1
    }

    while IFS='|' read -r tool_id desc rpm_pkgs deb_pkgs; do
        [[ "$tool_id" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${tool_id// }" ]] && continue
        tool_id=$(echo "$tool_id" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        desc=$(echo "$desc" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        rpm_pkgs=$(echo "$rpm_pkgs" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        deb_pkgs=$(echo "$deb_pkgs" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$tool_id" ]] && continue
        tools+=("$tool_id")
        descs+=("$desc")
        TOOL_RPM_PACKAGES["$tool_id"]="$rpm_pkgs"
        TOOL_DEB_PACKAGES["$tool_id"]="$deb_pkgs"
    done < "$conf_file"

    if [[ ${#tools[@]} -eq 0 ]]; then
        show_error_detail "配置错误" "tools.conf 为空或格式错误" "请检查工具配置文件"
        return 1
    fi

    if [[ "$mode" == "group" || "$mode" == "package" ]]; then
        for idx in "${!tools[@]}"; do
            if is_group_style_tool_for_os "${tools[$idx]}" "$target_os" "$target_arch"; then
                group_like=true
            else
                group_like=false
            fi
            if [[ "$mode" == "group" && "$group_like" == true ]]; then
                filtered_tools+=("${tools[$idx]}")
                filtered_descs+=("${descs[$idx]}")
            elif [[ "$mode" == "package" && "$group_like" == false ]]; then
                filtered_tools+=("${tools[$idx]}")
                filtered_descs+=("${descs[$idx]}")
            fi
        done
    else
        filtered_tools=("${tools[@]}")
        filtered_descs=("${descs[@]}")
    fi

    AVAILABLE_TOOLS=("${filtered_tools[@]}")
    AVAILABLE_TOOL_DESCS=("${filtered_descs[@]}")
    log "[config] loaded ${#AVAILABLE_TOOLS[@]} tools (mode=$mode, os=$target_os, arch=$target_arch)"
    return 0
}

is_group_style_tool_for_os(){
    local tool_id="$1" target_os="${2:-$TARGET_OS}" target_arch="${3:-$TARGET_ARCH}"
    local packages pkg count=0
    packages=$(get_tool_packages_for_os "$tool_id" "$target_os" "$target_arch")
    [[ -z "$packages" ]] && return 1
    for pkg in $packages; do
        ((count++))
        if [[ "$pkg" == @* || "$pkg" == *"*"* || "$pkg" == *"?"* ]]; then
            return 0
        fi
    done
    [[ $count -gt 1 ]]
}

export -f load_os_config
export -f check_repo_availability
export -f filter_reachable_repos
export -f pick_best_repos
export -f generate_repo_config
export -f load_tools_config
export -f get_tool_description
export -f get_tool_packages_for_os
export -f is_group_style_tool_for_os
export -f get_tool_os_rule
export -f get_tool_support_status_for_os
export -f get_tool_support_suggestion_for_os
export -f get_selected_tool_packages
export -f get_kernel_dep_description
export -f save_user_preferences
export -f load_user_preferences
