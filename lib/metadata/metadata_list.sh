#!/bin/bash
# =====================================================
# 元数据列表模块 - metadata_list.sh
# 离线包的查找、列出、显示功能
# =====================================================

# 确保依赖已加载
[[ -z "$METADATA_DIR" ]] && METADATA_DIR="$OUTPUT_DIR/.metadata"

# =============================================
# 列出所有可用的离线包
# =============================================
list_available_packages(){
    init_metadata_dir

    local found=0
    echo ""
    print_section "可用的离线包"

    for meta_file in "$METADATA_DIR"/*.meta; do
        [[ ! -f "$meta_file" ]] && continue

        # 安全读取元数据
        local OS="" ARCH="" TOOLS="" PKG_SIZE=""
        while IFS='=' read -r key value; do
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${key// }" ]] && continue
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
            case "$key" in
                OS) OS="$value";;
                ARCH) ARCH="$value";;
                TOOLS) TOOLS="$value";;
                PKG_SIZE) PKG_SIZE="$value";;
            esac
        done < "$meta_file"

        local tarball="$OUTPUT_DIR/offline_${OS}_${ARCH}_merged.tar.xz"

        if [[ -f "$tarball" ]]; then
            ((found++))
            local size="${PKG_SIZE:-$(du -sh "$tarball" 2>/dev/null | cut -f1)}"
            printf "  ${COLOR_BOLD}%2d)${COLOR_RESET} %-25s %-12s 大小: %-8s 工具: %d 个\n" \
                "$found" "$OS" "$ARCH" "$size" "$(echo "$TOOLS" | tr ',' '\n' | wc -l)"
        fi
    done

    if [[ $found -eq 0 ]]; then
        echo "  $(t INSTALL_NOT_FOUND)"
    fi

    echo ""
    return $found
}

# =============================================
# 查找适用于当前系统的离线包
# =============================================
find_compatible_packages(){
    local cur_os
    cur_os=$(detect_current_os 2>/dev/null)
    local cur_arch
    cur_arch=$(detect_current_arch)

    if [[ -z "$cur_os" ]]; then
        echo ""
        print_warning "$(t INSTALL_AUTO_DETECT)"
        return 1
    fi

    init_metadata_dir

    local found=0
    echo ""
    print_section "$(t INSTALL_COMPATIBLE) ($cur_os / $cur_arch)"

    local meta_file
    meta_file=$(get_metadata_file "$cur_os" "$cur_arch")

    if [[ -f "$meta_file" ]]; then
        local OS="" ARCH="" TOOLS="" KERNEL_DEPS="" PKG_SIZE=""
        while IFS='=' read -r key value; do
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${key// }" ]] && continue
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
            case "$key" in
                OS) OS="$value";;
                ARCH) ARCH="$value";;
                TOOLS) TOOLS="$value";;
                KERNEL_DEPS) KERNEL_DEPS="$value";;
                PKG_SIZE) PKG_SIZE="$value";;
            esac
        done < "$meta_file"

        local tarball="$OUTPUT_DIR/offline_${OS}_${ARCH}_merged.tar.xz"

        if [[ -f "$tarball" ]]; then
            ((found++))
            local size="${PKG_SIZE:-$(du -sh "$tarball" 2>/dev/null | cut -f1)}"
            printf "  ${COLOR_BOLD}%2d)${COLOR_RESET} %-25s %-12s 大小: %-8s 工具: %d 个\n" \
                "$found" "$OS" "$ARCH" "$size" "$(echo "$TOOLS" | tr ',' '\n' | wc -l)"
            echo ""
            echo "  $(t INSTALL_TOOLS_TITLE):"
            IFS=',' read -ra tool_array <<< "$TOOLS"
            local col=0
            for tool in "${tool_array[@]}"; do
                printf "      %-20s" "$tool"
                ((col++))
                if [[ $((col % 4)) -eq 0 ]]; then
                    echo ""
                fi
            done
            echo ""

            if [[ -n "$KERNEL_DEPS" ]]; then
                echo ""
                echo "  $(t KERNEL_DEPS_TITLE):"
                IFS=',' read -ra dep_array <<< "$KERNEL_DEPS"
                for dep in "${dep_array[@]}"; do
                    printf "      %-20s" "$dep"
                done
                echo ""
            fi
        fi
    fi

    if [[ $found -eq 0 ]]; then
        echo "  $(t INSTALL_NOT_FOUND) $cur_os / $cur_arch"
        echo "  $(t MENU_DOWNLOAD)"
    fi

    echo ""
    return $found
}

# =============================================
# 查找适用于当前系统的离线包（静默版本）
# =============================================
find_compatible_packages_silent(){
    local os="$1"
    local arch="$2"

    init_metadata_dir

    local meta_file
    meta_file=$(get_metadata_file "$os" "$arch")

    if [[ -f "$meta_file" ]]; then
        local tarball="$OUTPUT_DIR/offline_${os}_${arch}_merged.tar.xz"
        if [[ -f "$tarball" ]]; then
            echo "1"
            return 0
        fi
    fi

    echo "0"
    return 1
}

# =============================================
# 列出所有离线包的详细信息（交互式）
# =============================================
list_all_packages_with_details(){
    init_metadata_dir

    print_section "$(t INSTALL_SELECT_PACKAGE)"

    local found=0
    for meta_file in "$METADATA_DIR"/*.meta; do
        [[ ! -f "$meta_file" ]] && continue

        local OS="" ARCH="" TOOLS="" KERNEL_DEPS="" PKG_COUNT="" PKG_SIZE="" CREATED_DATE=""
        while IFS='=' read -r key value; do
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${key// }" ]] && continue
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
            case "$key" in
                OS) OS="$value";;
                ARCH) ARCH="$value";;
                TOOLS) TOOLS="$value";;
                KERNEL_DEPS) KERNEL_DEPS="$value";;
                PKG_COUNT) PKG_COUNT="$value";;
                PKG_SIZE) PKG_SIZE="$value";;
                CREATED_DATE) CREATED_DATE="$value";;
            esac
        done < "$meta_file"

        local tarball="$OUTPUT_DIR/offline_${OS}_${ARCH}_merged.tar.xz"

        if [[ -f "$tarball" ]]; then
            ((found++))
            local size="${PKG_SIZE:-$(du -sh "$tarball" 2>/dev/null | cut -f1)}"

            echo ""
            printf "  ${COLOR_BOLD}%d. %s / %s${COLOR_RESET}\n" "$found" "$OS" "$ARCH"
            echo "     $(t PACKAGE_SIZE): $size"
            echo "     $(t CREATED_DATE): ${CREATED_DATE:-未知}"
            echo "     $(t PACKAGE_COUNT): ${PKG_COUNT:-$(echo "$TOOLS" | tr ',' '\n' | wc -l)} $(t PACK_FILES)"

            if [[ -n "$TOOLS" ]]; then
                echo "     $(t INSTALL_TOOLS_TITLE):"
                IFS=',' read -ra tool_array <<< "$TOOLS"
                local col=0
                for tool in "${tool_array[@]}"; do
                    printf "       %-20s" "$tool"
                    ((col++))
                    if [[ $((col % 4)) -eq 0 ]]; then
                        echo ""
                    fi
                done
                [[ $((col % 4)) -ne 0 ]] && echo ""
            fi

            if [[ -n "$KERNEL_DEPS" ]]; then
                echo "     $(t KERNEL_DEPS_TITLE):"
                IFS=',' read -ra dep_array <<< "$KERNEL_DEPS"
                for dep in "${dep_array[@]}"; do
                    printf "       %-20s" "$dep"
                done
                echo ""
            fi
        fi
    done

    if [[ $found -eq 0 ]]; then
        echo ""
        echo "  $(t INSTALL_NOT_FOUND)"
        echo "  $(t MENU_DOWNLOAD)"
    fi

    echo ""
}

# =============================================
# 导出函数
# =============================================
export -f list_available_packages
export -f find_compatible_packages
export -f find_compatible_packages_silent
export -f list_all_packages_with_details
