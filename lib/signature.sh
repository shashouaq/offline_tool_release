#!/bin/bash
# =====================================================
# 需求签名文件模块 - signature.sh
# 功能：生成和解析离线包需求签名文件（类似apt-offline的.sig）
# 参考：apt-offline的设计模式
# =====================================================

# =============================================
# 生成需求签名文件
# 用法：generate_signature_file "output.sig" "target_os" "target_arch" "tools..."
# =============================================
generate_signature_file(){
    local output_file="$1"
    local target_os="${2:-$TARGET_OS}"
    local target_arch="${3:-$TARGET_ARCH}"
    shift 3
    local -a selected_tools=("$@")
    
    print_section "生成需求签名文件"
    
    # 验证参数
    if [[ ${#selected_tools[@]} -eq 0 ]]; then
        show_error_detail "参数错误" "未指定任何工具" "请至少选择一个工具"
        return 1
    fi
    
    # 获取系统信息
    local current_kernel
    current_kernel=$(uname -r 2>/dev/null || echo "unknown")
    local current_os_id
    current_os_id=$(grep "^ID=" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")
    local current_os_version
    current_os_version=$(grep "^VERSION_ID=" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")
    
    # 创建签名文件（JSON格式）
    cat > "$output_file" <<EOF
{
  "version": "1.0",
  "generated_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "generated_by": "offline_tool_v14",
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
    
    # 添加工具列表及其依赖信息
    local tool_count=${#selected_tools[@]}
    local index=0
    for tool in "${selected_tools[@]}"; do
        ((index++))
        
        # 获取工具的包名和描述
        local packages
        packages=$(get_tool_packages_for_os "$tool" "$target_os" 2>/dev/null || echo "$tool")
        local description
        description=$(get_tool_description "$tool" 2>/dev/null || echo "")
        
        # 写入JSON
        cat >> "$output_file" <<EOF
      {
        "tool_id": "$tool",
        "description": "$description",
        "packages": "$packages",
        "is_group": $([[ "$packages" == @* || "$packages" == *"*"* ]] && echo "true" || echo "false")
      }$(if [[ $index -lt $tool_count ]]; then echo ","; fi)
EOF
    done
    
    # 完成JSON
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
    
    # 计算校验和（排除checksum字段本身）
    local checksum
    checksum=$(head -n -4 "$output_file" | sha256sum | awk '{print $1}')
    
    # 更新校验和
    sed -i "s/\"value\": \"\"/\"value\": \"$checksum\"/" "$output_file"
    
    log "[签名] 已生成需求签名文件: $output_file"
    log "[签名] 包含 ${#selected_tools[@]} 个工具"
    log "[签名] SHA256: $checksum"
    
    echo ""
    print_success "需求签名文件生成成功"
    echo "  文件路径: $output_file"
    echo "  工具数量: ${#selected_tools[@]}"
    echo "  目标系统: $target_os ($target_arch)"
    echo ""
    echo "下一步操作："
    echo "  1. 将此签名文件复制到联网机器"
    echo "  2. 运行: bash offline_tools_v14.sh --download-from-sig $output_file"
    echo ""
    
    return 0
}

# =============================================
# 解析需求签名文件
# 用法：parse_signature_file "input.sig"
# 输出：设置全局变量 SIG_*
# =============================================
parse_signature_file(){
    local sig_file="$1"
    
    if [[ ! -f "$sig_file" ]]; then
        show_error_detail "文件不存在" "签名文件不存在: $sig_file" "请检查文件路径"
        return 1
    fi
    
    # 检查是否为有效的JSON格式
    if ! command -v jq &>/dev/null; then
        # 如果没有jq，使用简单的文本解析
        log "[警告] 未找到jq命令，使用简化解析模式"
        _parse_signature_simple "$sig_file"
    else
        # 使用jq解析JSON
        _parse_signature_json "$sig_file"
    fi
    
    # 验证签名文件完整性
    if ! verify_signature_integrity "$sig_file"; then
        show_error_detail "签名验证失败" "签名文件可能被篡改或损坏" "请重新生成签名文件"
        return 1
    fi
    
    log "[签名] 已解析签名文件: $sig_file"
    log "[签名] 目标系统: ${SIG_TARGET_OS:-unknown}"
    log "[签名] 工具数量: ${#SIG_TOOLS[@]}"
    
    return 0
}

# =============================================
# 使用jq解析签名文件（推荐）
# =============================================
_parse_signature_json(){
    local sig_file="$1"
    
    # 解析基本信息
    export SIG_VERSION=$(jq -r '.version' "$sig_file")
    export SIG_GENERATED_AT=$(jq -r '.generated_at' "$sig_file")
    export SIG_GENERATED_BY=$(jq -r '.generated_by' "$sig_file")
    
    # 解析系统信息
    export SIG_CURRENT_OS=$(jq -r '.system_info.current_os' "$sig_file")
    export SIG_CURRENT_VERSION=$(jq -r '.system_info.current_version' "$sig_file")
    export SIG_CURRENT_KERNEL=$(jq -r '.system_info.current_kernel' "$sig_file")
    export SIG_TARGET_OS=$(jq -r '.system_info.target_os' "$sig_file")
    export SIG_TARGET_ARCH=$(jq -r '.system_info.target_arch' "$sig_file")
    
    # 解析工具列表
    local tool_count
    tool_count=$(jq '.requirements.tools | length' "$sig_file")
    
    export -a SIG_TOOLS=()
    export -a SIG_PACKAGES=()
    export -a SIG_DESCRIPTIONS=()
    
    for ((i=0; i<tool_count; i++)); do
        local tool_id
        tool_id=$(jq -r ".requirements.tools[$i].tool_id" "$sig_file")
        local packages
        packages=$(jq -r ".requirements.tools[$i].packages" "$sig_file")
        local description
        description=$(jq -r ".requirements.tools[$i].description" "$sig_file")
        
        SIG_TOOLS+=("$tool_id")
        SIG_PACKAGES+=("$packages")
        SIG_DESCRIPTIONS+=("$description")
    done
    
    # 解析校验和
    export SIG_CHECKSUM_ALGO=$(jq -r '.checksum.algorithm' "$sig_file")
    export SIG_CHECKSUM_VALUE=$(jq -r '.checksum.value' "$sig_file")
}

# =============================================
# 简单文本解析签名文件（备用）
# =============================================
_parse_signature_simple(){
    local sig_file="$1"
    
    # 提取关键信息
    export SIG_TARGET_OS=$(grep '"target_os"' "$sig_file" | head -1 | cut -d'"' -f4)
    export SIG_TARGET_ARCH=$(grep '"target_arch"' "$sig_file" | head -1 | cut -d'"' -f4)
    export SIG_CHECKSUM_VALUE=$(grep '"value"' "$sig_file" | tail -1 | cut -d'"' -f4)
    
    # 提取工具列表
    export -a SIG_TOOLS=()
    export -a SIG_PACKAGES=()
    export -a SIG_DESCRIPTIONS=()
    
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

# =============================================
# 验证签名文件完整性
# =============================================
verify_signature_integrity(){
    local sig_file="$1"
    
    if [[ ! -f "$sig_file" ]]; then
        return 1
    fi
    
    # 读取存储的校验和
    local stored_checksum=""
    if command -v jq &>/dev/null; then
        stored_checksum=$(jq -r '.checksum.value' "$sig_file")
    else
        stored_checksum=$(grep '"value"' "$sig_file" | tail -1 | cut -d'"' -f4)
    fi
    
    # 计算当前文件的校验和（排除checksum字段）
    local current_checksum
    current_checksum=$(head -n -4 "$sig_file" | sha256sum | awk '{print $1}')
    
    # 比较校验和
    if [[ "$stored_checksum" == "$current_checksum" ]]; then
        log "[验证] 签名文件完整性验证通过"
        return 0
    else
        log "[验证] 签名文件完整性验证失败"
        log "[验证] 期望: $stored_checksum"
        log "[验证] 实际: $current_checksum"
        return 1
    fi
}

# =============================================
# 从签名文件下载并打包
# 用法：download_from_signature "sig_file" "work_dir"
# =============================================
download_from_signature(){
    local sig_file="$1"
    local work_dir="${2:-$WORK_DIR}"
    
    print_section "从签名文件下载离线包"
    
    # 解析签名文件
    parse_signature_file "$sig_file" || return 1
    
    # 显示签名文件信息
    echo ""
    echo "签名文件信息："
    echo "  生成时间: ${SIG_GENERATED_AT:-unknown}"
    echo "  生成工具: ${SIG_GENERATED_BY:-unknown}"
    echo "  原始系统: ${SIG_CURRENT_OS:-unknown} ${SIG_CURRENT_VERSION:-unknown}"
    echo "  目标系统: ${SIG_TARGET_OS:-unknown} (${SIG_TARGET_ARCH:-unknown})"
    echo "  工具数量: ${#SIG_TOOLS[@]}"
    echo ""
    
    # 确认下载
    confirm_dialog "确认从签名文件下载 ${#SIG_TOOLS[@]} 个工具？" "y" "download" || return 0
    
    # 设置目标系统
    export TARGET_OS="${SIG_TARGET_OS}"
    export TARGET_ARCH="${SIG_TARGET_ARCH}"
    
    # 加载配置
    load_os_config "$TARGET_OS" || return 1
    
    # 选择最佳镜像源
    pick_best_repos || return 1
    
    # 生成repo配置
    TEMP_REPO_FILE=$(generate_repo_config)
    
    # 展开所有包名（处理包组和通配符）
    local -a all_packages=()
    for packages in "${SIG_PACKAGES[@]}"; do
        for pkg in $packages; do
            all_packages+=("$pkg")
        done
    done
    
    log "[下载] 共 ${#all_packages[@]} 个包待下载（从 ${#SIG_TOOLS[@]} 个工具展开）"
    
    # 执行下载
    smart_download "${all_packages[@]}" || true
    
    # 构建仓库索引
    build_repo_index "$work_dir/packages" "$PKG_TYPE"

    # 打包。原实现调用了不存在的 create_offline_package，导致签名下载流程最后失败。
    local output_dir="${OUTPUT_DIR:-$BASE_DIR/output}"
    mkdir -p "$output_dir"
    local tarball="$output_dir/offline_${TARGET_OS}_${TARGET_ARCH}_merged.tar.xz"
    local tools_str
    tools_str=$(IFS=','; echo "${SIG_TOOLS[*]}")
    local package_count
    package_count=$(find "$work_dir/packages" -type f \( -name "*.rpm" -o -name "*.deb" \) 2>/dev/null | wc -l)
    if [[ $package_count -eq 0 ]]; then
        print_error "下载完成但未找到任何软件包，已取消打包"
        return 1
    fi

    merge_into_tarball "$tarball" "$work_dir/packages" "$work_dir" "new" "$TARGET_OS" "$TARGET_ARCH" "$tools_str" "" "${all_packages[@]}"
    print_success "离线包已生成: $tarball"
    
    return 0
}

# =============================================
# 导出函数
# =============================================
export -f generate_signature_file
export -f parse_signature_file
export -f _parse_signature_json
export -f _parse_signature_simple
export -f verify_signature_integrity
export -f download_from_signature
