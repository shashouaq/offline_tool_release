#!/bin/bash
# =====================================================
# 版本一致性检查和自动调节模块 - version_check.sh
# 功能：确保下载环境和安装环境的版本一致性，自动检测和调节
# =====================================================

# =============================================
# 检测当前系统信息
# 用法：detect_current_system
# 输出：设置全局变量 CURRENT_*
# =============================================
detect_current_system(){
    export CURRENT_OS_NAME=""
    export CURRENT_OS_ID=""
    export CURRENT_OS_VERSION=""
    export CURRENT_OS_VERSION_ID=""
    export CURRENT_ARCH=""
    export CURRENT_KERNEL=""
    export CURRENT_PKG_MANAGER=""
    
    # 读取os-release
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        CURRENT_OS_NAME="${NAME:-unknown}"
        CURRENT_OS_ID="${ID:-unknown}"
        CURRENT_OS_VERSION="${VERSION:-unknown}"
        CURRENT_OS_VERSION_ID="${VERSION_ID:-unknown}"
    fi
    
    # 检测架构
    CURRENT_ARCH=$(uname -m)
    
    # 检测内核
    CURRENT_KERNEL=$(uname -r)
    
    # 检测包管理器
    if command -v dnf &>/dev/null; then
        CURRENT_PKG_MANAGER="dnf"
    elif command -v yum &>/dev/null; then
        CURRENT_PKG_MANAGER="yum"
    elif command -v apt-get &>/dev/null; then
        CURRENT_PKG_MANAGER="apt"
    elif command -v zypper &>/dev/null; then
        CURRENT_PKG_MANAGER="zypper"
    else
        CURRENT_PKG_MANAGER="unknown"
    fi
    
    log "[检测] 系统: $CURRENT_OS_NAME $CURRENT_OS_VERSION"
    log "[检测] ID: $CURRENT_OS_ID, 版本ID: $CURRENT_OS_VERSION_ID"
    log "[检测] 架构: $CURRENT_ARCH, 内核: $CURRENT_KERNEL"
    log "[检测] 包管理器: $CURRENT_PKG_MANAGER"
}

# =============================================
# 验证目标系统与当前系统兼容性
# 用法：verify_system_compatibility "target_os" "target_arch"
# 返回：0=兼容，1=不兼容但有警告，2=完全不兼容
# =============================================
verify_system_compatibility(){
    local target_os="$1"
    local target_arch="$2"
    
    detect_current_system
    
    local compatibility=0
    local warnings=()
    
    # 检查架构兼容性
    if [[ "$target_arch" != "$CURRENT_ARCH" ]]; then
        # 跨架构下载需要特殊处理
        if [[ "$CURRENT_PKG_MANAGER" == "dnf" ]] || [[ "$CURRENT_PKG_MANAGER" == "yum" ]]; then
            # DNF/YUM支持--forcearch
            warnings+=("架构不匹配: 当前=$CURRENT_ARCH, 目标=$target_arch (将使用--forcearch)")
            compatibility=1
        else
            warnings+=("架构不匹配且包管理器不支持跨架构下载")
            compatibility=2
        fi
    fi
    
    # 检查系统系列兼容性
    local target_family=""
    case "$target_os" in
        openEuler*|Rocky*|CentOS*|AliOS*|Tlinux*|openAnolis*)
            target_family="rpm-redhat"
            ;;
        Ubuntu*|Kylin*|Debian*)
            target_family="deb-debian"
            ;;
        *)
            target_family="unknown"
            ;;
    esac
    
    local current_family=""
    case "$CURRENT_OS_ID" in
        ol|centos|rocky|almalinux|fedora|openeuler|anolis|tlinux)
            current_family="rpm-redhat"
            ;;
        ubuntu|debian|kylin|kali)
            current_family="deb-debian"
            ;;
        *)
            current_family="unknown"
            ;;
    esac
    
    if [[ "$target_family" != "$current_family" ]]; then
        warnings+=("系统系列不匹配: 当前=$current_family, 目标=$target_family")
        compatibility=2
    fi
    
    # 显示警告
    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo ""
        print_warning "系统兼容性警告"
        for warning in "${warnings[@]}"; do
            echo "  ⚠ $warning"
        done
        echo ""
        
        if [[ $compatibility -eq 2 ]]; then
            confirm_dialog "检测到严重兼容性问题，是否继续？" "n" "continue" || return 2
        fi
    fi
    
    return $compatibility
}

# =============================================
# 自动选择最佳下载策略
# 用法：select_download_strategy "target_os" "target_arch"
# 输出：设置全局变量 DOWNLOAD_STRATEGY_*
# =============================================
select_download_strategy(){
    local target_os="$1"
    local target_arch="$2"
    
    detect_current_system
    
    export DOWNLOAD_STRATEGY_METHOD=""
    export DOWNLOAD_STRATEGY_FLAGS=""
    export DOWNLOAD_STRATEGY_NOTES=""
    
    # 判断是否为同系统下载
    local is_same_system=false
    if [[ "$CURRENT_OS_ID" != "unknown" ]]; then
        case "$target_os" in
            openEuler*)
                [[ "$CURRENT_OS_ID" =~ ^(ol|centos|rocky|fedora|openeuler)$ ]] && is_same_system=true
                ;;
            Ubuntu*)
                [[ "$CURRENT_OS_ID" == "ubuntu" ]] && is_same_system=true
                ;;
            Kylin*)
                [[ "$CURRENT_OS_ID" == "kylin" ]] && is_same_system=true
                ;;
        esac
    fi
    
    if [[ "$is_same_system" == true ]] && [[ "$target_arch" == "$CURRENT_ARCH" ]]; then
        # 同系统同架构：直接下载
        DOWNLOAD_STRATEGY_METHOD="direct"
        DOWNLOAD_STRATEGY_FLAGS=""
        DOWNLOAD_STRATEGY_NOTES="使用本地包管理器直接下载（最快）"
    elif [[ "$CURRENT_PKG_MANAGER" == "dnf" ]] || [[ "$CURRENT_PKG_MANAGER" == "yum" ]]; then
        # RPM系统：使用--forcearch跨架构下载
        DOWNLOAD_STRATEGY_METHOD="forcearch"
        DOWNLOAD_STRATEGY_FLAGS="--forcearch=$target_arch"
        DOWNLOAD_STRATEGY_NOTES="使用DNF --forcearch跨架构下载"
    elif [[ "$CURRENT_PKG_MANAGER" == "apt" ]]; then
        # DEB系统：使用qemu-user-static模拟
        DOWNLOAD_STRATEGY_METHOD="emulation"
        DOWNLOAD_STRATEGY_FLAGS=""
        DOWNLOAD_STRATEGY_NOTES="需要配置多架构支持或容器环境"
    else
        # 未知策略：使用容器
        DOWNLOAD_STRATEGY_METHOD="container"
        DOWNLOAD_STRATEGY_FLAGS=""
        DOWNLOAD_STRATEGY_NOTES="建议使用Docker/Podman容器进行下载"
    fi
    
    log "[策略] 下载方法: $DOWNLOAD_STRATEGY_METHOD"
    log "[策略] 标志: $DOWNLOAD_STRATEGY_FLAGS"
    log "[策略] 说明: $DOWNLOAD_STRATEGY_NOTES"
}

# =============================================
# 检查包版本可用性
# 用法：check_package_version_available "package" "version" "repo_file" "release_ver"
# 返回：0=可用，1=不可用
# =============================================
check_package_version_available(){
    local package="$1"
    local version="$2"
    local repo_file="$3"
    local release_ver="$4"
    
    if [[ "$PKG_TYPE" == "rpm" ]]; then
        # RPM系统
        local result
        result=$(dnf repoquery \
            --config="$repo_file" \
            --disablerepo='*' \
            --enablerepo="$(offline_temp_repo_selector)" \
            --releasever="$release_ver" \
            --qf "%{name}-%{version}-%{release}" \
            "$package" 2>/dev/null | head -1)
        
        if [[ -n "$result" ]]; then
            if [[ "$version" == "latest" ]] || [[ "$result" == *"$version"* ]]; then
                log "[版本] 包 $package 版本可用: $result"
                return 0
            else
                log "[版本] 包 $package 版本不匹配 (需要: $version, 可用: $result)"
                return 1
            fi
        else
            log "[版本] 包 $package 在仓库中不存在"
            return 1
        fi
    else
        # DEB系统
        local result
        result=$(apt-cache policy "$package" 2>/dev/null | grep "Candidate:" | awk '{print $2}')
        
        if [[ -n "$result" ]]; then
            if [[ "$version" == "latest" ]] || [[ "$result" == "$version" ]]; then
                log "[版本] 包 $package 版本可用: $result"
                return 0
            else
                log "[版本] 包 $package 版本不匹配 (需要: $version, 可用: $result)"
                return 1
            fi
        else
            log "[版本] 包 $package 在仓库中不存在"
            return 1
        fi
    fi
}

# =============================================
# 自动生成系统匹配报告
# 用法：generate_system_match_report "target_os" "target_arch"
# =============================================
generate_system_match_report(){
    local target_os="$1"
    local target_arch="$2"
    
    detect_current_system
    select_download_strategy "$target_os" "$target_arch"
    
    print_section "系统匹配报告"
    
    echo ""
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│ 当前系统（下载环境）                                     │"
    echo "├─────────────────────────────────────────────────────────┤"
    printf "│ 操作系统: %-45s│\n" "$CURRENT_OS_NAME"
    printf "│ 系统ID: %-48s│\n" "$CURRENT_OS_ID"
    printf "│ 版本: %-50s│\n" "$CURRENT_OS_VERSION"
    printf "│ 架构: %-50s│\n" "$CURRENT_ARCH"
    printf "│ 内核: %-50s│\n" "$CURRENT_KERNEL"
    printf "│ 包管理器: %-46s│\n" "$CURRENT_PKG_MANAGER"
    echo "├─────────────────────────────────────────────────────────┤"
    echo "│ 目标系统（安装环境）                                     │"
    echo "├─────────────────────────────────────────────────────────┤"
    printf "│ 目标OS: %-48s│\n" "$target_os"
    printf "│ 目标架构: %-46s│\n" "$target_arch"
    echo "├─────────────────────────────────────────────────────────┤"
    echo "│ 下载策略                                                 │"
    echo "├─────────────────────────────────────────────────────────┤"
    printf "│ 方法: %-50s│\n" "$DOWNLOAD_STRATEGY_METHOD"
    printf "│ 说明: %-50s│\n" "$DOWNLOAD_STRATEGY_NOTES"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""
}

# =============================================
# 建议最佳实践
# 用法：suggest_best_practices "target_os"
# =============================================
suggest_best_practices(){
    local target_os="$1"
    
    print_section "最佳实践建议"
    
    echo ""
    case "$target_os" in
        openEuler*)
            echo "💡 openEuler 离线包下载建议："
            echo "  1. 最好在 openEuler 系统上进行下载"
            echo "  2. 确保 /etc/yum.repos.d/ 配置了正确的源"
            echo "  3. 运行 'dnf makecache' 更新元数据"
            echo "  4. 使用相同版本的系统进行下载和安装"
            ;;
        Ubuntu*)
            echo "💡 Ubuntu 离线包下载建议："
            echo "  1. 最好在 Ubuntu 系统上进行下载"
            echo "  2. 运行 'sudo apt-get update' 更新包索引"
            echo "  3. 确保 /etc/apt/sources.list 配置正确"
            echo "  4. 使用相同版本的系统进行下载和安装"
            ;;
        Rocky*|CentOS*)
            echo "💡 $target_os 离线包下载建议："
            echo "  1. 最好在同类RHEL系系统上进行下载"
            echo "  2. 确保配置了 BaseOS 和 AppStream 仓库"
            echo "  3. 运行 'dnf makecache' 更新元数据"
            echo "  4. 注意 minor version 的兼容性"
            ;;
        Kylin*)
            echo "💡 Kylin 离线包下载建议："
            echo "  1. 最好在 Kylin 系统上进行下载"
            echo "  2. 确认麒麟系统的版本（V10 SP1/SP2/SP3）"
            echo "  3. 配置正确的麒麟官方源或镜像源"
            echo "  4. 注意麒麟系统基于Ubuntu，使用APT包管理"
            ;;
        *)
            echo "💡 通用建议："
            echo "  1. 使用与目标系统相同的发行版进行下载"
            echo "  2. 保持系统版本一致（如 22.04 LTS）"
            echo "  3. 定期更新包管理器元数据"
            echo "  4. 测试离线包在目标系统上的安装"
            ;;
    esac
    echo ""
}

# =============================================
# 自动修复常见问题
# 用法：auto_fix_common_issues "target_os"
# =============================================
auto_fix_common_issues(){
    local target_os="$1"
    
    print_section "自动诊断和修复"
    
    local issues_fixed=0
    
    # 检查包管理器缓存
    if [[ "$PKG_TYPE" == "rpm" ]]; then
        if [[ ! -d /var/cache/dnf ]] && [[ ! -d /var/cache/yum ]]; then
            echo "⚠ DNF/YUM缓存目录不存在，正在创建..."
            mkdir -p /var/cache/dnf
            ((issues_fixed++))
        fi
        
        # 尝试更新元数据
        echo "🔄 更新DNF元数据..."
        if dnf makecache --refresh -y &>/dev/null; then
            echo "✓ DNF元数据更新成功"
        else
            echo "⚠ DNF元数据更新失败，请检查网络连接"
        fi
    elif [[ "$PKG_TYPE" == "deb" ]]; then
        # 检查APT列表
        if [[ ! -d /var/lib/apt/lists ]] || [[ -z "$(ls -A /var/lib/apt/lists 2>/dev/null)" ]]; then
            echo "⚠ APT包列表为空，正在更新..."
            if apt-get update -y &>/dev/null; then
                echo "✓ APT包列表更新成功"
                ((issues_fixed++))
            else
                echo "⚠ APT更新失败，请检查网络连接和sources.list"
            fi
        fi
    fi
    
    # 检查磁盘空间
    local available_space
    available_space=$(df -BG /tmp | tail -1 | awk '{print $4}' | sed 's/G//')
    if [[ $available_space -lt 5 ]]; then
        echo "⚠ 警告：可用磁盘空间不足 (${available_space}GB)"
        echo "  建议清理空间或更改WORK_DIR到其他分区"
    else
        echo "✓ 磁盘空间充足: ${available_space}GB"
    fi
    
    echo ""
    echo "已修复 $issues_fixed 个问题"
    echo ""
}

# =============================================
# 导出函数
# =============================================
export -f detect_current_system
export -f verify_system_compatibility
export -f select_download_strategy
export -f check_package_version_available
export -f generate_system_match_report
export -f suggest_best_practices
export -f auto_fix_common_issues
