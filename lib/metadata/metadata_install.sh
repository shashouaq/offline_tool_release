#!/bin/bash
# =====================================================
# 元数据安装模块 - metadata_install.sh
# 离线包的安装功能（选择性安装、RPM/DEB安装）
# =====================================================

# =============================================
# 安装目录中的全部离线包
# =============================================
install_package_directory(){
    local pkg_dir="$1"
    local pkg_type="$2"

    if [[ ! -d "$pkg_dir" ]]; then
        print_error "$(t ERROR): $(t CAUSE_NOT_FOUND): $pkg_dir"
        return 1
    fi

    if [[ "$pkg_type" == "rpm" ]]; then
        local -a rpm_files=()
        while IFS= read -r -d '' file; do
            rpm_files+=("$file")
        done < <(find "$pkg_dir" -type f -name "*.rpm" -print0 2>/dev/null | sort -z)

        if [[ ${#rpm_files[@]} -eq 0 ]]; then
            print_error "$(t ERROR): $(t CAUSE_NOT_FOUND) RPM $(t PACK_FILES)"
            return 1
        fi

        build_repo_index "$pkg_dir" "rpm" >/dev/null 2>&1 || true

        if command -v dnf &>/dev/null; then
            dnf install -y --nogpgcheck "${rpm_files[@]}" >> "$LOG_FILE" 2>&1
            return $?
        elif command -v yum &>/dev/null; then
            yum localinstall -y --nogpgcheck "${rpm_files[@]}" >> "$LOG_FILE" 2>&1
            return $?
        elif command -v rpm &>/dev/null; then
            rpm -Uvh "${rpm_files[@]}" >> "$LOG_FILE" 2>&1
            return $?
        fi
    else
        local -a deb_files=()
        while IFS= read -r -d '' file; do
            deb_files+=("$file")
        done < <(find "$pkg_dir" -type f -name "*.deb" -print0 2>/dev/null | sort -z)

        if [[ ${#deb_files[@]} -eq 0 ]]; then
            print_error "$(t ERROR): $(t CAUSE_NOT_FOUND) DEB $(t PACK_FILES)"
            return 1
        fi

        if command -v apt-get &>/dev/null; then
            (
                cd "$pkg_dir" || exit 1
                apt-get install -y ./*.deb
            ) >> "$LOG_FILE" 2>&1
            return $?
        elif command -v dpkg &>/dev/null; then
            dpkg -i "${deb_files[@]}" >> "$LOG_FILE" 2>&1
            return $?
        fi
    fi

    print_error "$(t ERROR): 未找到可用的包管理器"
    return 1
}

# =============================================
# 安装单个包文件
# =============================================
install_single_package(){
    local pkg_file="$1"
    local pkg_type="$2"
    local pkg_dir
    pkg_dir=$(dirname "$pkg_file")

    if [[ ! -f "$pkg_file" ]]; then
        print_error "$(t ERROR): $(t CAUSE_NOT_FOUND): $pkg_file"
        return 1
    fi

    if [[ "$pkg_type" == "rpm" ]]; then
        build_repo_index "$pkg_dir" "rpm" >/dev/null 2>&1 || true

        if command -v dnf &>/dev/null; then
            dnf install -y --nogpgcheck --disablerepo='*' "$pkg_file" >> "$LOG_FILE" 2>&1
            return $?
        elif command -v yum &>/dev/null; then
            yum localinstall -y --nogpgcheck "$pkg_file" >> "$LOG_FILE" 2>&1
            return $?
        elif command -v rpm &>/dev/null; then
            rpm -Uvh "$pkg_file" >> "$LOG_FILE" 2>&1
            return $?
        fi
    else
        if command -v dpkg &>/dev/null; then
            dpkg -i "$pkg_file" >> "$LOG_FILE" 2>&1
            local rc=$?
            if [[ $rc -ne 0 ]] && command -v apt-get &>/dev/null; then
                apt-get install -f -y >> "$LOG_FILE" 2>&1 || true
            fi
            return $rc
        fi
    fi

    print_error "$(t ERROR): 未找到可用的包管理器"
    return 1
}

# =============================================
# 安装选中的工具
# =============================================
install_selected_tools(){
    local pkg_dir="$1"
    shift
    local pkg_type="$1"
    shift
    local -a selected_tools=("$@")

    # 验证pkg_type参数
    if [[ "$pkg_type" != "rpm" ]] && [[ "$pkg_type" != "deb" ]]; then
        local rpm_count deb_count
        rpm_count=$(find "$pkg_dir" -name "*.rpm" 2>/dev/null | wc -l)
        deb_count=$(find "$pkg_dir" -name "*.deb" 2>/dev/null | wc -l)

        if [[ $rpm_count -gt 0 ]]; then
            pkg_type="rpm"
            log "[修复] pkg_type参数错误，已自动修正为rpm"
        elif [[ $deb_count -gt 0 ]]; then
            pkg_type="deb"
            log "[修复] pkg_type参数错误，已自动修正为deb"
        else
            print_error "$(t ERROR): $(t CAUSE_NOT_FOUND)$(t PACK_FILES)"
            return 1
        fi
    fi

    # 验证必需命令
    if [[ "$pkg_type" == "rpm" ]]; then
        if ! command -v rpm &>/dev/null; then
            print_error "$(t ERROR): rpm $(t CAUSE_NOT_FOUND)"
            return 1
        fi
    elif [[ "$pkg_type" == "deb" ]]; then
        if ! command -v dpkg &>/dev/null; then
            print_error "$(t ERROR): dpkg $(t CAUSE_NOT_FOUND)"
            return 1
        fi
    fi

    print_info "$(t INSTALLING) ${#selected_tools[@]} $(t PACK_FILES) [$(echo $pkg_type | tr 'a-z' 'A-Z')]..."
    echo ""

    local success=0 failed=0
    local -a failed_tools=()

    for tool in "${selected_tools[@]}"; do
        local found=0
        local -a matching_pkgs=()

        while IFS= read -r pkg; do
            [[ -n "$pkg" ]] && matching_pkgs+=("$pkg")
        done < <(find "$pkg_dir" -type f \( -name "${tool}-*.rpm" -o -name "${tool}_[0-9]*.deb" -o -name "${tool}_*.deb" \) 2>/dev/null)

        if [[ ${#matching_pkgs[@]} -eq 0 ]]; then
            while IFS= read -r pkg; do
                [[ -n "$pkg" ]] && matching_pkgs+=("$pkg")
            done < <(find "$pkg_dir" -type f \( -name "*${tool}*.rpm" -o -name "*${tool}*.deb" \) 2>/dev/null)
        fi

        if [[ ${#matching_pkgs[@]} -gt 0 ]]; then
            found=1
            local pkg="${matching_pkgs[0]}"
            print_info "$(t INSTALLING): $(basename "$pkg")"

            if [[ "$pkg_type" == "rpm" ]]; then
                if rpm -ivh --force --nodeps "$pkg" >> "$LOG_FILE" 2>&1; then
                    print_success "  $(t STATUS_OK) $(t INSTALL_SUCCESS) (rpm)"
                    ((success++))
                else
                    if command -v dnf &>/dev/null && dnf localinstall -y "$pkg" >> "$LOG_FILE" 2>&1; then
                        print_success "  $(t STATUS_OK) $(t INSTALL_SUCCESS) (dnf)"
                        ((success++))
                        continue
                    elif command -v yum &>/dev/null && yum localinstall -y "$pkg" >> "$LOG_FILE" 2>&1; then
                        print_success "  $(t STATUS_OK) $(t INSTALL_SUCCESS) (yum)"
                        ((success++))
                        continue
                    fi
                    print_error "  $(t STATUS_ERROR) $(t INSTALL_FAILED)"
                    ((failed++))
                    failed_tools+=("$tool")
                fi
            else
                if dpkg -i "$pkg" >> "$LOG_FILE" 2>&1; then
                    print_success "  $(t STATUS_OK) $(t INSTALL_SUCCESS) (dpkg)"
                    ((success++))
                elif apt-get install -f -y >> "$LOG_FILE" 2>&1; then
                    print_success "  $(t STATUS_OK) $(t INSTALL_SUCCESS) (apt-fixed)"
                    ((success++))
                else
                    print_error "  $(t STATUS_ERROR) $(t INSTALL_FAILED)"
                    ((failed++))
                    failed_tools+=("$tool")
                fi
            fi
        else
            print_warning "  $(t STATUS_WARN) $(t CAUSE_NOT_FOUND): $tool"
            ((failed++))
            failed_tools+=("$tool")
        fi
    done

    echo ""
    print_section "$(t INSTALL_COMPLETE)"
    print_color "$COLOR_GREEN" "  $(t INSTALL_SUCCESS): $success $(t PACK_FILES)"
    if [[ $failed -gt 0 ]]; then
        print_color "$COLOR_RED" "  $(t INSTALL_FAILED): $failed $(t PACK_FILES)"
        echo ""
        echo "  $(t INSTALL_FAILED)$(t TOOLS_TITLE):"
        for tool in "${failed_tools[@]}"; do
            echo "    - $tool"
        done
        echo ""
        echo "  $(t SOLUTION_CHECK_LOG): $LOG_FILE"
    fi
}

# =============================================
# 导出函数
# =============================================
export -f install_selected_tools
export -f install_single_package
export -f install_package_directory
