#!/bin/bash
# Package manager helpers for RPM and DEB workflows.

CRITICAL_PKGS=(
    "glibc" "glibc-common" "glibc-langpack" "glibc-minimal-langpack"
    "glibc-tools" "glibc-all-langpacks"
    "systemd" "systemd-libs" "systemd-udev"
    "kernel" "kernel-core" "kernel-modules" "kernel-modules-core"
    "bash" "openssl" "openssh" "openssh-server"
    "gcc" "gcc-c++" "libgcc"
    "libstdc++" "glib2"
)

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

detect_current_os(){
    local os_release="/etc/os-release"
    [[ ! -f "$os_release" ]] && return 1

    local id="" id_like="" version_id=""
    while IFS='=' read -r key val; do
        val="${val//\"/}"
        val="${val%$'\r'}"
        case "$key" in
            ID) id="$val" ;;
            ID_LIKE) id_like="$val" ;;
            VERSION_ID) version_id="$val" ;;
        esac
    done < "$os_release"

    case "$id" in
        openEuler)
            [[ "$version_id" == 22.03* ]] && echo "openEuler22.03" && return 0
            [[ "$version_id" == 24.03* ]] && echo "openEuler24.03" && return 0
            [[ "$version_id" == 25.03* ]] && echo "openEuler25.03" && return 0
            echo "openEuler22.03"
            return 0
            ;;
        rocky)
            [[ "$version_id" == 9* ]] && echo "Rocky9" && return 0
            echo "Rocky8"
            return 0
            ;;
        centos)
            [[ "$version_id" == 8* ]] && echo "CentOS8.2" && return 0
            echo "CentOS7.6"
            return 0
            ;;
        almalinux|alinux)
            echo "AliOS3"
            return 0
            ;;
        ubuntu)
            [[ "$version_id" == 24.04* ]] && echo "Ubuntu24.04" && return 0
            [[ "$version_id" == 22.04* ]] && echo "Ubuntu22.04" && return 0
            [[ "$version_id" == 20.04* ]] && echo "Ubuntu20.04" && return 0
            echo "Ubuntu22.04"
            return 0
            ;;
        kylin)
            echo "Kylin"
            return 0
            ;;
    esac

    case "$id_like" in
        *rhel*|*centos*|*rocky*|*anolis*)
            [[ "$version_id" == 9* ]] && echo "Rocky9" && return 0
            echo "Rocky8"
            return 0
            ;;
    esac

    return 1
}

detect_current_arch(){
    case "$(uname -m)" in
        x86_64) echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        loongarch64) echo "loongarch64" ;;
        *) echo "x86_64" ;;
    esac
}

already_downloaded(){
    local tool="$1"
    find "$PKG_DIR" -type f \( -name "${tool}-*.rpm" -o -name "${tool}_*.deb" \) 2>/dev/null | grep -q .
}

is_critical_package(){
    local pkg="$1"
    local pkg_name="${pkg%%-*}"
    pkg_name="${pkg_name%%.*}"

    local critical
    for critical in "${CRITICAL_PKGS[@]}"; do
        [[ "$pkg_name" == "$critical" ]] && return 0
    done
    return 1
}

get_releasever(){
    case "$1" in
        openEuler22.03) echo "22.03LTS" ;;
        openEuler24.03) echo "24.03LTS" ;;
        openEuler25.03) echo "25.03" ;;
        Rocky8) echo "8" ;;
        Rocky9) echo "9" ;;
        CentOS7.6) echo "7" ;;
        CentOS8.2) echo "8" ;;
        AliOS3) echo "3" ;;
        Tlinux31) echo "3.1" ;;
        Tlinux32) echo "4.2" ;;
        openAnolis84) echo "8.4" ;;
        Ubuntu20.04) echo "20.04" ;;
        Ubuntu22.04) echo "22.04" ;;
        Ubuntu24.04) echo "24.04" ;;
        Ubuntu25.10) echo "25.10" ;;
        Kylin) echo "10" ;;
        *) echo "unknown" ;;
    esac
}

build_repo_index(){
    local pkg_dir="$1"
    local pkg_type="$2"

    local count
    count=$(find "$pkg_dir" -type f \( -name "*.rpm" -o -name "*.deb" \) 2>/dev/null | wc -l)
    if [[ "$count" -eq 0 ]]; then
        log "[repo] packages directory is empty"
        return 1
    fi

    log "[repo] building local repository index (packages=$count, type=$pkg_type)"

    if [[ "$pkg_type" == "rpm" ]]; then
        if command -v createrepo_c &>/dev/null; then
            createrepo_c --database "$pkg_dir" >> "$LOG_FILE" 2>&1
        elif command -v createrepo &>/dev/null; then
            createrepo "$pkg_dir" >> "$LOG_FILE" 2>&1
        else
            log "[repo] createrepo tool not found"
            return 1
        fi
    else
        (cd "$pkg_dir" && dpkg-scanpackages . > Packages 2>/dev/null) || true
        (cd "$pkg_dir" && gzip -kf Packages 2>/dev/null) || true
    fi

    log "[repo] local repository index complete"
    return 0
}

install_rpm_safe(){
    local pkg_dir="$1"
    local -a safe_rpms=()
    local -a critical_rpms=()
    local rpm_file bn

    while IFS= read -r rpm_file; do
        bn=$(basename "$rpm_file" .rpm | rev | cut -d- -f4- | rev)
        if is_critical_package "$bn"; then
            critical_rpms+=("$rpm_file")
            log "[install] skipped critical rpm: $(basename "$rpm_file")"
        else
            safe_rpms+=("$rpm_file")
        fi
    done < <(find "$pkg_dir" -name "*.rpm" 2>/dev/null | sort)

    echo ""
    show_status "info" "safe rpm packages: ${#safe_rpms[@]}"
    show_status "warn" "skipped critical rpm packages: ${#critical_rpms[@]}"
    echo ""

    if [[ ${#safe_rpms[@]} -eq 0 ]]; then
        show_error_detail "No installable packages" "All RPM packages were filtered as critical packages" "Check bundle contents or policy"
        return 1
    fi

    confirm_batch_operation "Install RPM packages" "${#safe_rpms[@]}" || return 1
    print_info "Building local repository..."
    build_repo_index "$pkg_dir" "rpm" || return 1

    local lrepo="/etc/yum.repos.d/offline_install.repo"
    cat > "$lrepo" <<REPO
[offline-install]
name=Offline Install
baseurl=file://$pkg_dir
enabled=1
gpgcheck=0
REPO

    print_info "Starting RPM install..."
    local pkg_names=""
    local rpm
    for rpm in "${safe_rpms[@]}"; do
        pkg_names+=" $(basename "$rpm" .rpm)"
    done
    pkg_names=$(echo "$pkg_names" | tr ' ' '\n' | awk 'NF' | sort -u | tr '\n' ' ')

    dnf install -y --disablerepo='*' --enablerepo='offline-install' $pkg_names 2>&1 | tail -30
    local rc=$?
    rm -f "$lrepo"

    if [[ $rc -eq 0 ]]; then
        print_success "RPM install completed"
    else
        print_error "RPM install failed (rc=$rc)"
    fi
    return $rc
}

install_deb_safe(){
    local pkg_dir="$1"
    local -a safe_debs=()
    local -a critical_debs=()
    local deb_file bn

    while IFS= read -r deb_file; do
        bn=$(basename "$deb_file" .deb | cut -d_ -f1)
        if is_critical_package "$bn"; then
            critical_debs+=("$deb_file")
            log "[install] skipped critical deb: $(basename "$deb_file")"
        else
            safe_debs+=("$deb_file")
        fi
    done < <(find "$pkg_dir" -name "*.deb" 2>/dev/null | sort)

    echo ""
    show_status "info" "safe deb packages: ${#safe_debs[@]}"
    show_status "warn" "skipped critical deb packages: ${#critical_debs[@]}"
    echo ""

    if [[ ${#safe_debs[@]} -eq 0 ]]; then
        show_error_detail "No installable packages" "All DEB packages were filtered as critical packages" "Check bundle contents or policy"
        return 1
    fi

    confirm_batch_operation "Install DEB packages" "${#safe_debs[@]}" || return 1

    print_info "Starting DEB install..."
    dpkg -i "${safe_debs[@]}" 2>&1 | tail -20
    local rc=$?

    if [[ $rc -ne 0 ]]; then
        print_warning "Attempting dependency repair..."
        apt-get install -f -y 2>&1 | tail -10
    fi

    if [[ $rc -eq 0 ]]; then
        print_success "DEB install completed"
    else
        print_error "DEB install failed (rc=$rc)"
    fi
    return $rc
}

export -f detect_pkg_manager
export -f detect_current_os
export -f detect_current_arch
export -f already_downloaded
export -f is_critical_package
export -f get_releasever
export -f build_repo_index
export -f install_rpm_safe
export -f install_deb_safe
