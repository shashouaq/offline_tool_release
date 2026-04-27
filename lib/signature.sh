#!/bin/bash
# Demand signature file support. This is similar in spirit to apt-offline:
# an offline host can create a requirement file, and an online host can use it
# to download and package the requested tools.

generate_signature_file(){
    local output_file="$1"
    local target_os="${2:-$TARGET_OS}"
    local target_arch="${3:-$TARGET_ARCH}"
    shift 3
    local -a selected_tools=("$@")

    print_section "生成需求签名文件"

    if [[ ${#selected_tools[@]} -eq 0 ]]; then
        show_error_detail "参数错误" "未指定任何工具" "请至少选择一个工具"
        return 1
    fi

    local current_kernel current_os_id current_os_version
    current_kernel=$(uname -r 2>/dev/null || echo "unknown")
    current_os_id=$(grep "^ID=" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")
    current_os_version=$(grep "^VERSION_ID=" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")

    cat > "$output_file" <<EOF
{
  "version": "1.0",
  "generated_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "generated_by": "offline_tool_v1",
  "system_info": {
    "current_os": "$current_os_id",
    "current_version": "$current_os_version",
    "current_kernel": "$current_kernel",
    "target_os": "$target_os",
    "target_arch": "$target_arch"
  },
  "requirements": {
    "tools": [
EOF

    local tool_count=${#selected_tools[@]}
    local index=0
    local tool packages description
    for tool in "${selected_tools[@]}"; do
        index=$((index + 1))
        packages=$(get_tool_packages_for_os "$tool" "$target_os" 2>/dev/null || echo "$tool")
        description=$(get_tool_description "$tool" 2>/dev/null || echo "")

        cat >> "$output_file" <<EOF
      {
        "tool_id": "$tool",
        "description": "$description",
        "packages": "$packages",
        "is_group": $([[ "$packages" == @* || "$packages" == *"*"* ]] && echo "true" || echo "false")
      }$(if [[ $index -lt $tool_count ]]; then echo ","; fi)
EOF
    done

    cat >> "$output_file" <<EOF
    ],
    "kernel_deps": []
  },
  "checksum": {
    "algorithm": "sha256",
    "value": ""
  }
}
EOF

    local checksum
    checksum=$(head -n -4 "$output_file" | sha256sum | awk '{print $1}')
    sed -i "s/\"value\": \"\"/\"value\": \"$checksum\"/" "$output_file"

    log "[signature] generated requirement signature: $output_file"
    log "[signature] tools=${#selected_tools[@]} sha256=$checksum"

    echo ""
    print_success "需求签名文件生成成功"
    echo "  文件路径: $output_file"
    echo "  工具数量: ${#selected_tools[@]}"
    echo "  目标系统: $target_os ($target_arch)"
    echo ""
    echo "下一步操作："
    echo "  1. 将此签名文件复制到联网机器"
    echo "  2. 运行: bash offline_tools_v1.sh --download-from-sig $output_file"
    echo ""
}

parse_signature_file(){
    local sig_file="$1"

    if [[ ! -f "$sig_file" ]]; then
        show_error_detail "文件不存在" "签名文件不存在: $sig_file" "请检查文件路径"
        return 1
    fi

    if command -v jq &>/dev/null; then
        _parse_signature_json "$sig_file"
    else
        log "[signature] jq not found, using simple parser"
        _parse_signature_simple "$sig_file"
    fi

    if ! verify_signature_integrity "$sig_file"; then
        show_error_detail "签名验证失败" "签名文件可能被篡改或损坏" "请重新生成签名文件"
        return 1
    fi

    log "[signature] parsed signature: $sig_file target=${SIG_TARGET_OS:-unknown}/${SIG_TARGET_ARCH:-unknown} tools=${#SIG_TOOLS[@]}"
}

_parse_signature_json(){
    local sig_file="$1"
    local tool_count i tool_id packages description

    export SIG_VERSION
    export SIG_GENERATED_AT
    export SIG_GENERATED_BY
    export SIG_CURRENT_OS
    export SIG_CURRENT_VERSION
    export SIG_CURRENT_KERNEL
    export SIG_TARGET_OS
    export SIG_TARGET_ARCH
    export SIG_CHECKSUM_ALGO
    export SIG_CHECKSUM_VALUE

    SIG_VERSION=$(jq -r '.version' "$sig_file")
    SIG_GENERATED_AT=$(jq -r '.generated_at' "$sig_file")
    SIG_GENERATED_BY=$(jq -r '.generated_by' "$sig_file")
    SIG_CURRENT_OS=$(jq -r '.system_info.current_os' "$sig_file")
    SIG_CURRENT_VERSION=$(jq -r '.system_info.current_version' "$sig_file")
    SIG_CURRENT_KERNEL=$(jq -r '.system_info.current_kernel' "$sig_file")
    SIG_TARGET_OS=$(jq -r '.system_info.target_os' "$sig_file")
    SIG_TARGET_ARCH=$(jq -r '.system_info.target_arch' "$sig_file")
    SIG_CHECKSUM_ALGO=$(jq -r '.checksum.algorithm' "$sig_file")
    SIG_CHECKSUM_VALUE=$(jq -r '.checksum.value' "$sig_file")

    tool_count=$(jq '.requirements.tools | length' "$sig_file")
    export -a SIG_TOOLS=()
    export -a SIG_PACKAGES=()
    export -a SIG_DESCRIPTIONS=()

    for ((i=0; i<tool_count; i++)); do
        tool_id=$(jq -r ".requirements.tools[$i].tool_id" "$sig_file")
        packages=$(jq -r ".requirements.tools[$i].packages" "$sig_file")
        description=$(jq -r ".requirements.tools[$i].description" "$sig_file")
        SIG_TOOLS+=("$tool_id")
        SIG_PACKAGES+=("$packages")
        SIG_DESCRIPTIONS+=("$description")
    done
}

_parse_signature_simple(){
    local sig_file="$1"
    export SIG_TARGET_OS
    export SIG_TARGET_ARCH
    export SIG_CHECKSUM_VALUE
    export -a SIG_TOOLS=()
    export -a SIG_PACKAGES=()
    export -a SIG_DESCRIPTIONS=()

    SIG_TARGET_OS=$(grep '"target_os"' "$sig_file" | head -1 | cut -d'"' -f4)
    SIG_TARGET_ARCH=$(grep '"target_arch"' "$sig_file" | head -1 | cut -d'"' -f4)
    SIG_CHECKSUM_VALUE=$(grep '"value"' "$sig_file" | tail -1 | cut -d'"' -f4)

    while IFS= read -r line; do
        if [[ "$line" =~ \"tool_id\":\ \"([^\"]+)\" ]]; then
            SIG_TOOLS+=("${BASH_REMATCH[1]}")
        elif [[ "$line" =~ \"packages\":\ \"([^\"]+)\" ]]; then
            SIG_PACKAGES+=("${BASH_REMATCH[1]}")
        elif [[ "$line" =~ \"description\":\ \"([^\"]+)\" ]]; then
            SIG_DESCRIPTIONS+=("${BASH_REMATCH[1]}")
        fi
    done < "$sig_file"
}

verify_signature_integrity(){
    local sig_file="$1"
    local stored_checksum current_checksum

    [[ -f "$sig_file" ]] || return 1

    if command -v jq &>/dev/null; then
        stored_checksum=$(jq -r '.checksum.value' "$sig_file")
    else
        stored_checksum=$(grep '"value"' "$sig_file" | tail -1 | cut -d'"' -f4)
    fi

    current_checksum=$(head -n -4 "$sig_file" | sha256sum | awk '{print $1}')
    if [[ "$stored_checksum" == "$current_checksum" ]]; then
        log "[signature] integrity check passed"
        return 0
    fi

    log "[signature] integrity check failed expected=$stored_checksum actual=$current_checksum"
    return 1
}

download_from_signature(){
    local sig_file="$1"
    local work_dir="${2:-$WORK_DIR}"

    print_section "从签名文件下载离线包"
    parse_signature_file "$sig_file" || return 1

    echo ""
    echo "签名文件信息："
    echo "  生成时间: ${SIG_GENERATED_AT:-unknown}"
    echo "  生成工具: ${SIG_GENERATED_BY:-unknown}"
    echo "  原始系统: ${SIG_CURRENT_OS:-unknown} ${SIG_CURRENT_VERSION:-unknown}"
    echo "  目标系统: ${SIG_TARGET_OS:-unknown} (${SIG_TARGET_ARCH:-unknown})"
    echo "  工具数量: ${#SIG_TOOLS[@]}"
    echo ""

    confirm_dialog "确认从签名文件下载 ${#SIG_TOOLS[@]} 个工具？" "y" "download" || return 0

    export TARGET_OS="${SIG_TARGET_OS}"
    export TARGET_ARCH="${SIG_TARGET_ARCH}"

    load_os_config "$TARGET_OS" || return 1
    pick_best_repos || return 1
    TEMP_REPO_FILE=$(generate_repo_config)

    local -a all_packages=()
    local packages pkg
    for packages in "${SIG_PACKAGES[@]}"; do
        for pkg in $packages; do
            all_packages+=("$pkg")
        done
    done

    log "[download] ${#all_packages[@]} packages expanded from ${#SIG_TOOLS[@]} tools"
    smart_download "${all_packages[@]}" || true
    build_repo_index "$work_dir/packages" "$PKG_TYPE"

    local output_dir="${OUTPUT_DIR:-$BASE_DIR/output}"
    mkdir -p "$output_dir"
    local tarball="$output_dir/offline_${TARGET_OS}_${TARGET_ARCH}_merged.tar.xz"
    local tools_str package_count
    tools_str=$(IFS=','; echo "${SIG_TOOLS[*]}")
    package_count=$(find "$work_dir/packages" -type f \( -name "*.rpm" -o -name "*.deb" \) 2>/dev/null | wc -l)
    if [[ $package_count -eq 0 ]]; then
        print_error "下载完成但未找到任何软件包，已取消打包"
        return 1
    fi

    merge_into_tarball "$tarball" "$work_dir/packages" "$work_dir" "new" "$TARGET_OS" "$TARGET_ARCH" "$tools_str" "" "${all_packages[@]}"
    print_success "离线包已生成: $tarball"
}

export -f generate_signature_file
export -f parse_signature_file
export -f _parse_signature_json
export -f _parse_signature_simple
export -f verify_signature_integrity
export -f download_from_signature
