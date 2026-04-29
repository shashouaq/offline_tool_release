#!/bin/bash
# =====================================================
# 依赖树解析和可视化模块 - dependency_tree.sh
# 功能：解析、分析和可视化包依赖关系
# 参考：apt-rdepends, dnf repoquery
# =====================================================

# =============================================
# 解析RPM包的依赖树
# 用法：resolve_rpm_dependencies "package_name" "repo_file" "release_ver"
# 输出：依赖包列表（每行一个）
# =============================================
resolve_rpm_dependencies(){
    local package="$1"
    local repo_file="$2"
    local release_ver="$3"
    local depth="${4:-3}"  # 默认递归深度为3层
    
    if ! command -v dnf &>/dev/null; then
        log "[依赖] dnf命令不可用"
        echo "$package"
        return 1
    fi
    
    # 使用dnf repoquery查询依赖
    local deps=""
    
    # 检测是否为包组或通配符
    if [[ "$package" == @* ]] || [[ "$package" == *"*"* ]]; then
        # 包组或通配符，先展开
        log "[依赖] 展开包组/通配符: $package"
        local expanded_packages
        expanded_packages=$(expand_package_group "$package" "$repo_file" "$release_ver")
        
        # 对每个展开的包解析依赖
        local -a all_deps=()
        for pkg in $expanded_packages; do
            local pkg_deps
            pkg_deps=$(resolve_single_rpm_dep "$pkg" "$repo_file" "$release_ver" "$depth")
            for dep in $pkg_deps; do
                all_deps+=("$dep")
            done
        done
        
        # 去重并输出
        printf '%s\n' "${all_deps[@]}" | sort -u
    else
        # 单个包
        resolve_single_rpm_dep "$package" "$repo_file" "$release_ver" "$depth"
    fi
}

# =============================================
# 解析单个RPM包的依赖
# =============================================
resolve_single_rpm_dep(){
    local package="$1"
    local repo_file="$2"
    local release_ver="$3"
    local depth="$4"
    
    # 第一层依赖
    local direct_deps
    direct_deps=$(dnf repoquery \
        --config="$repo_file" \
        --disablerepo='*' \
        --enablerepo="$(offline_temp_repo_selector)" \
        --releasever="$release_ver" \
        --requires \
        --resolve \
        "$package" 2>/dev/null | grep -E '\.(rpm|x86_64|noarch|aarch64)' | sed 's/-[0-9].*//' | sort -u)
    
    if [[ $depth -le 1 ]]; then
        echo "$package"
        echo "$direct_deps"
        return
    fi
    
    # 递归解析子依赖
    local -a all_deps=("$package")
    for dep in $direct_deps; do
        local sub_deps
        sub_deps=$(resolve_single_rpm_dep "$dep" "$repo_file" "$release_ver" $((depth - 1)))
        for sub_dep in $sub_deps; do
            all_deps+=("$sub_dep")
        done
    done
    
    # 去重并输出
    printf '%s\n' "${all_deps[@]}" | sort -u
}

# =============================================
# 解析DEB包的依赖树
# 用法：resolve_deb_dependencies "package_name"
# =============================================
resolve_deb_dependencies(){
    local package="$1"
    local depth="${2:-3}"
    
    if ! command -v apt-cache &>/dev/null; then
        log "[依赖] apt-cache命令不可用"
        echo "$package"
        return 1
    fi
    
    # 使用apt-cache depends查询依赖
    local deps
    deps=$(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "$package" 2>/dev/null | grep "^[a-zA-Z]" | sort -u)
    
    if [[ -z "$deps" ]]; then
        echo "$package"
    else
        echo "$deps"
    fi
}

# =============================================
# 展开展开包组或通配符
# 用法：expand_package_group "pattern" "repo_file" "release_ver"
# =============================================
expand_package_group(){
    local pattern="$1"
    local repo_file="$2"
    local release_ver="$3"
    
    if [[ "$pattern" == @* ]]; then
        # RPM包组
        local group_name="${pattern#@}"
        dnf groupinfo \
            --config="$repo_file" \
            --disablerepo='*' \
                --enablerepo="$(offline_temp_repo_selector)" \
            --releasever="$release_ver" \
            "$group_name" 2>/dev/null | grep -E "^\s+[a-zA-Z]" | awk '{print $1}' | sort -u
    elif [[ "$pattern" == *"*"* ]] || [[ "$pattern" == *"?"* ]]; then
        # 通配符
        dnf search \
            --config="$repo_file" \
            --disablerepo='*' \
                --enablerepo="$(offline_temp_repo_selector)" \
            --releasever="$release_ver" \
            "$pattern" 2>/dev/null | grep -E "^[a-zA-Z0-9._-]+\." | awk -F. '{print $1}' | sort -u
    else
        echo "$pattern"
    fi
}

# =============================================
# 生成依赖树可视化（文本格式）
# 用法：visualize_dependency_tree "package_name" "repo_file" "release_ver" "pkg_type"
# =============================================
visualize_dependency_tree(){
    local package="$1"
    local repo_file="$2"
    local release_ver="$3"
    local pkg_type="$4"
    local max_depth="${5:-2}"
    
    print_section "依赖树: $package"
    echo ""
    
    if [[ "$pkg_type" == "rpm" ]]; then
        _visualize_rpm_tree "$package" "$repo_file" "$release_ver" "" true "$max_depth"
    else
        _visualize_deb_tree "$package" "" true "$max_depth"
    fi
    
    echo ""
}

# =============================================
# 可视化RPM依赖树（递归）
# =============================================
_visualize_rpm_tree(){
    local package="$1"
    local repo_file="$2"
    local release_ver="$3"
    local prefix="$4"
    local is_last="$5"
    local depth="$6"
    
    if [[ $depth -le 0 ]]; then
        echo "${prefix}└── $package (...)"
        return
    fi
    
    # 打印当前节点
    local connector="├──"
    if [[ "$is_last" == true ]]; then
        connector="└──"
    fi
    echo "${prefix}${connector} $package"
    
    # 获取直接依赖
    local deps
    deps=$(dnf repoquery \
        --config="$repo_file" \
        --disablerepo='*' \
        --enablerepo="$(offline_temp_repo_selector)" \
        --releasever="$release_ver" \
        --requires \
        "$package" 2>/dev/null | head -20 | grep -E '\.' | sed 's/-[0-9].*//' | sort -u)
    
    local dep_count=0
    local dep_array=()
    while IFS= read -r dep; do
        [[ -n "$dep" ]] && dep_array+=("$dep")
    done <<< "$deps"
    dep_count=${#dep_array[@]}
    
    # 限制显示的依赖数量
    if [[ $dep_count -gt 10 ]]; then
        echo "${prefix}    └── ... ($dep_count 个依赖，仅显示前10个)"
        return
    fi
    
    # 递归显示子依赖
    local new_prefix="${prefix}    "
    if [[ "$is_last" == true ]]; then
        new_prefix="${prefix}    "
    else
        new_prefix="${prefix}│   "
    fi
    
    for ((i=0; i<dep_count && i<10; i++)); do
        local is_last_child=false
        if [[ $((i + 1)) -eq $dep_count ]]; then
            is_last_child=true
        fi
        _visualize_rpm_tree "${dep_array[$i]}" "$repo_file" "$release_ver" "$new_prefix" "$is_last_child" $((depth - 1))
    done
}

# =============================================
# 可视化DEB依赖树（递归）
# =============================================
_visualize_deb_tree(){
    local package="$1"
    local prefix="$2"
    local is_last="$3"
    local depth="$4"
    
    if [[ $depth -le 0 ]]; then
        echo "${prefix}└── $package (...)"
        return
    fi
    
    # 打印当前节点
    local connector="├──"
    if [[ "$is_last" == true ]]; then
        connector="└──"
    fi
    echo "${prefix}${connector} $package"
    
    # 获取直接依赖
    local deps
    deps=$(apt-cache depends "$package" 2>/dev/null | grep "Depends:" | awk '{print $2}' | head -10)
    
    local dep_count=0
    local dep_array=()
    while IFS= read -r dep; do
        [[ -n "$dep" ]] && dep_array+=("$dep")
    done <<< "$deps"
    dep_count=${#dep_array[@]}
    
    # 递归显示子依赖
    local new_prefix="${prefix}    "
    if [[ "$is_last" == true ]]; then
        new_prefix="${prefix}    "
    else
        new_prefix="${prefix}│   "
    fi
    
    for ((i=0; i<dep_count; i++)); do
        local is_last_child=false
        if [[ $((i + 1)) -eq $dep_count ]]; then
            is_last_child=true
        fi
        _visualize_deb_tree "${dep_array[$i]}" "$new_prefix" "$is_last_child" $((depth - 1))
    done
}

# =============================================
# 计算依赖统计信息
# 用法：calculate_dependency_stats "package_list" "repo_file" "release_ver" "pkg_type"
# =============================================
calculate_dependency_stats(){
    local -a packages=($1)
    local repo_file="$2"
    local release_ver="$3"
    local pkg_type="$4"
    
    local total_direct=0
    local total_transitive=0
    local -A all_deps_map=()
    
    for pkg in "${packages[@]}"; do
        local deps=""
        if [[ "$pkg_type" == "rpm" ]]; then
            deps=$(resolve_rpm_dependencies "$pkg" "$repo_file" "$release_ver" 2)
        else
            deps=$(resolve_deb_dependencies "$pkg" 2)
        fi
        
        local dep_count
        dep_count=$(echo "$deps" | wc -l)
        ((total_direct++))
        ((total_transitive += dep_count))
        
        # 收集所有依赖
        for dep in $deps; do
            all_deps_map["$dep"]=1
        done
    done
    
    local unique_deps=${#all_deps_map[@]}
    
    echo ""
    print_section "依赖统计"
    echo "  直接包数: ${#packages[@]}"
    echo "  总依赖数（含重复）: $total_transitive"
    echo "  唯一依赖数: $unique_deps"
    echo "  平均依赖数: $((total_transitive / ${#packages[@]})) 每包"
    echo ""
}

# =============================================
# 检测循环依赖
# 用法：detect_circular_dependencies "package" "repo_file" "release_ver"
# =============================================
detect_circular_dependencies(){
    local package="$1"
    local repo_file="$2"
    local release_ver="$3"
    
    local -A visited=()
    local -A in_stack=()
    local -a cycles=()
    
    _dfs_detect_cycle "$package" "$repo_file" "$release_ver" "" visited in_stack cycles
    
    if [[ ${#cycles[@]} -gt 0 ]]; then
        log "[警告] 检测到循环依赖:"
        for cycle in "${cycles[@]}"; do
            echo "  $cycle"
        done
        return 1
    else
        log "[依赖] 未检测到循环依赖"
        return 0
    fi
}

# =============================================
# DFS检测循环依赖（内部函数）
# =============================================
_dfs_detect_cycle(){
    local node="$1"
    local repo_file="$2"
    local release_ver="$3"
    local path="$4"
    local -n ref_visited=$5
    local -n ref_in_stack=$6
    local -n ref_cycles=$7
    
    # 标记为已访问和在栈中
    ref_visited["$node"]=1
    ref_in_stack["$node"]=1
    
    # 获取依赖
    local deps
    deps=$(dnf repoquery \
        --config="$repo_file" \
        --disablerepo='*' \
        --enablerepo="$(offline_temp_repo_selector)" \
        --releasever="$release_ver" \
        --requires \
        "$node" 2>/dev/null | head -10 | grep -E '\.' | sed 's/-[0-9].*//')
    
    for dep in $deps; do
        if [[ -z "${ref_visited[$dep]:-}" ]]; then
            # 未访问，递归
            _dfs_detect_cycle "$dep" "$repo_file" "$release_ver" "$path -> $dep" ref_visited ref_in_stack ref_cycles
        elif [[ "${ref_in_stack[$dep]:-}" == "1" ]]; then
            # 发现循环
            ref_cycles+=("$path -> $dep (循环)")
        fi
    done
    
    # 从栈中移除
    ref_in_stack["$node"]=0
}

# =============================================
# 导出函数
# =============================================
export -f resolve_rpm_dependencies
export -f resolve_deb_dependencies
export -f expand_package_group
export -f visualize_dependency_tree
export -f calculate_dependency_stats
export -f detect_circular_dependencies
export -f resolve_single_rpm_dep
export -f _visualize_rpm_tree
export -f _visualize_deb_tree
export -f _dfs_detect_cycle
