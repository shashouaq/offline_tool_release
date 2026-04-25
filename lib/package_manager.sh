#!/bin/bash
# =====================================================
# 包管理器模块 - package_manager.sh
# 统一管理 RPM/DEB 包的下载、验证、安装等操作
# =====================================================

# 危险包列表（系统关键包，禁止安装）
CRITICAL_PKGS=(
    "glibc" "glibc-common" "glibc-langpack" "glibc-minimal-langpack"
    "glibc-tools" "glibc-all-langpacks"
    "systemd" "systemd-libs" "systemd-udev"
    "kernel" "kernel-core" "kernel-modules" "kernel-modules-core"
    "bash" "openssl" "openssh" "openssh-server"
    "gcc" "gcc-c++" "libgcc"
    "libstdc++" "glib2"
)

# =============================================
# 检测当前系统的包管理器
# =============================================
detect_pkg_manager(){
    if command -v dnf &>/dev/null; then
        echo "dnf"
        return 0
    elif command -v yum &>/dev/null; then
        echo "yum"
        return 0
    elif command -v apt-get &>/dev/null; then
        echo "apt"
        return 0
    fi
    return 1
}

# =============================================
# 检测当前操作系统
# =============================================
detect_current_os(){
    local os_release="/etc/os-release"
    [[ ! -f "$os_release" ]] && return 1

    local id="" id_like="" version_id=""
    while IFS='=' read -r key val; do
        val="${val//\"/}"
        val="${val%$'\r'}"
        case "$key" in
            ID)         id="$val";;
            ID_LIKE)   id_like="$val";;
            VERSION_ID) version_id="$val";;
        esac
    done < "$os_release"

    case "$id" in
        openEuler)
            [[ "$version_id" == 22.03* ]] && echo "openEuler22.03" && return 0
            [[ "$version_id" == 24.03* ]] && echo "openEuler24.03" && return 0
            [[ "$version_id" == 25.03* ]] && echo "openEuler25.03" && return 0
            echo "openEuler22.03"; return 0;;
        rocky)
            [[ "$version_id" == 9* ]] && echo "Rocky9" && return 0
            echo "Rocky8"; return 0;;
        centos)
            [[ "$version_id" == 8* ]] && echo "CentOS8.2" && return 0
            echo "CentOS7.6"; return 0;;
        almalinux|alinux) echo "AliOS3"; return 0;;
        ubuntu)
            [[ "$version_id" == 24.04* ]] && echo "Ubuntu24.04" && return 0
            [[ "$version_id" == 22.04* ]] && echo "Ubuntu22.04" && return 0
            [[ "$version_id" == 20.04* ]] && echo "Ubuntu20.04" && return 0
            echo "Ubuntu22.04"; return 0;;
        kylin)  echo "Kylin"; return 0;;
    esac

    case "$id_like" in
        *rhel*|*centos*|*rocky*|*anolis*)
            [[ "$version_id" == 9* ]] && echo "Rocky9" && return 0
            echo "Rocky8"; return 0;;
    esac

    return 1
}

# =============================================
# 检测当前系统架构
# =============================================
detect_current_arch(){
    case "$(uname -m)" in
        x86_64)       echo "x86_64";;
        aarch64|arm64) echo "aarch64";;
        loongarch64)  echo "loongarch64";;
        *)            echo "x86_64";;
    esac
}

# =============================================
# 检查包是否已下载
# =============================================
already_downloaded(){
    local tool="$1"
    find "$PKG_DIR" -type f \( -name "${tool}-*.rpm" -o -name "${tool}_*.deb" \) 2>/dev/null | grep -q .
    return $?
}

# =============================================
# 检查是否为危险包
# =============================================
is_critical_package(){
    local pkg="$1"
    # 提取包名（去除版本和架构信息）
    local pkg_name="${pkg%%-*}"
    pkg_name="${pkg_name%%.*}"

    for critical in "${CRITICAL_PKGS[@]}"; do
        if [[ "$pkg_name" == "$critical" ]]; then
            return 0
        fi
    done
    return 1
}

# =============================================
# 获取 Release 版本
# =============================================
get_releasever(){
    case "$1" in
        openEuler22.03) echo "22.03LTS";;
        openEuler24.03) echo "24.03LTS";;
        openEuler25.03) echo "25.03";;
        Rocky8)         echo "8";;
        Rocky9)         echo "9";;
        CentOS7.6)      echo "7";;
        CentOS8.2)      echo "8";;
        AliOS3)         echo "3";;
        Tlinux31)       echo "3.1";;
        Tlinux32)       echo "4.2";;
        openAnolis84)   echo "8.4";;
        Ubuntu20.04)    echo "20.04";;
        Ubuntu22.04)    echo "22.04";;
        Ubuntu24.04)    echo "24.04";;
        Ubuntu25.10)    echo "25.10";;
        Kylin)          echo "10";;
        *)              echo "unknown";;
    esac
}

# =============================================
# 构建本地仓库索引
# =============================================
build_repo_index(){
    local pkg_dir="$1"
    local pkg_type="$2"

    local count
    count=$(find "$pkg_dir" -type f \( -name "*.rpm" -o -name "*.deb" \) 2>/dev/null | wc -l)

    if [[ "$count" -eq 0 ]]; then
        log "[错误] packages 目录为空"
        return 1
    fi

    log "构建本地仓库索引（$count 个包）..."

    if [[ "$pkg_type" == "rpm" ]]; then
        if command -v createrepo_c &>/dev/null; then
            createrepo_c --database "$pkg_dir" >> "$LOG_FILE" 2>&1
        elif command -v createrepo &>/dev/null; then
            createrepo "$pkg_dir" >> "$LOG_FILE" 2>&1
        else
            log "[警告] 未找到 createrepo 工具"
            return 1
        fi
    else
        (cd "$pkg_dir" && dpkg-scanpackages . > Packages 2>/dev/null) || true
        (cd "$pkg_dir" && gzip -k Packages 2>/dev/null) || true
    fi

    log "仓库索引构建完成"
    return 0
}

# =============================================
# 安装 RPM 包（安全模式）
# =============================================
install_rpm_safe(){
    local pkg_dir="$1"
    local -a safe_rpms=()
    local -a critical_rpms=()

    # 分类包
    for rpm_file in $(find "$pkg_dir" -name "*.rpm" 2>/dev/null | sort); do
        local bn
        bn=$(basename "$rpm_file" .rpm | rev | cut -d- -f4- | rev)

        if is_critical_package "$bn"; then
            critical_rpms+=("$rpm_file")
            log "[跳过危险包] $(basename "$rpm_file")"
        else
            safe_rpms+=("$rpm_file")
        fi
    done

    echo ""
    show_status "info" "安全包: ${#safe_rpms[@]} 个"
    show_status "warn" "已跳过: ${#critical_rpms[@]} 个危险包"
    echo ""

    if [[ ${#safe_rpms[@]} -eq 0 ]]; then
        show_error_detail "无可用包" "所有包都被标记为危险包" "检查包列表或联系管理员"
        return 1
    fi

    # 显示操作确认
    confirm_batch_operation "安装 RPM 包" "${#safe_rpms[@]}" || return 1

    # 构建本地仓库
    print_info "构建本地仓库..."
    build_repo_index "$pkg_dir" "rpm"

    # 创建临时 repo 配置
    local lrepo="/etc/yum.repos.d/offline_install.repo"
    cat > "$lrepo" <<REPO
[offline-install]
name=Offline Install
baseurl=file://$pkg_dir
enabled=1
gpgcheck=0
REPO

    # 安装包
    print_info "开始安装..."
    local pkg_names=""
    for rpm in "${safe_rpms[@]}"; do
        pkg_names+=" $(basename "$rpm" .rpm)"
    done

    # 去重
    pkg_names=$(echo "$pkg_names" | tr ' ' '\n' | sort -u | tr '\n' ' ')

    dnf install -y --disablerepo='*' --enablerepo='offline-install' $pkg_names 2>&1 | tail -30

    local rc=$?
    rm -f "$lrepo"

    if [[ $rc -eq 0 ]]; then
        print_success "安装完成"
    else
        print_error "安装失败 (退出码: $rc)"
    fi

    return $rc
}

# =============================================
# 安装 DEB 包（安全模式）
# =============================================
install_deb_safe(){
    local pkg_dir="$1"
    local -a safe_debs=()
    local -a critical_debs=()

    # 分类包
    for deb_file in $(find "$pkg_dir" -name "*.deb" 2>/dev/null | sort); do
        local bn
        bn=$(basename "$deb_file" .deb | cut -d_ -f1)

        if is_critical_package "$bn"; then
            critical_debs+=("$deb_file")
            log "[跳过危险包] $(basename "$deb_file")"
        else
            safe_debs+=("$deb_file")
        fi
    done

    echo ""
    show_status "info" "安全包: ${#safe_debs[@]} 个"
    show_status "warn" "已跳过: ${#critical_debs[@]} 个危险包"
    echo ""

    if [[ ${#safe_debs[@]} -eq 0 ]]; then
        show_error_detail "无可用包" "所有包都被标记为危险包" "检查包列表或联系管理员"
        return 1
    fi

    # 显示操作确认
    confirm_batch_operation "安装 DEB 包" "${#safe_debs[@]}" || return 1

    # 安装包
    print_info "开始安装..."
    dpkg -i "${safe_debs[@]}" 2>&1 | tail -20

    local rc=$?

    # 修复依赖
    if [[ $rc -ne 0 ]]; then
        print_warning "尝试修复依赖..."
        apt-get install -f -y 2>&1 | tail -10
    fi

    if [[ $rc -eq 0 ]]; then
        print_success "安装完成"
    else
        print_error "安装失败 (退出码: $rc)"
    fi

    return $rc
}

# =============================================
# 导出函数
# =============================================
export -f detect_pkg_manager
export -f detect_current_os
export -f detect_current_arch
export -f already_downloaded
export -f is_critical_package
export -f get_releasever
export -f build_repo_index
export -f install_rpm_safe
export -f install_deb_safe
