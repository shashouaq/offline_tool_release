#!/bin/bash
# =====================================================
# 安全增强模块 - security.sh
# 提供包完整性校验、白名单验证等功能
# =====================================================

# 工具白名单（从 tools.conf 动态加载）
declare -a TOOL_WHITELIST=()

# 校验和缓存文件
CHECKSUM_CACHE_FILE="/tmp/offline_tools_checksum_cache.txt"

# =============================================
# 初始化工具白名单
# =============================================
init_tool_whitelist(){
    local conf_file="$1"
    [[ ! -f "$conf_file" ]] && return 1

    TOOL_WHITELIST=()
    while IFS='|' read -r tool_name _desc; do
        # 跳过注释和空行
        [[ "$tool_name" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${tool_name// }" ]] && continue
        # 清理空格
        tool_name=$(echo "$tool_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -n "$tool_name" ]] && TOOL_WHITELIST+=("$tool_name")
    done < "$conf_file"

    log "[安全] 已加载 ${#TOOL_WHITELIST[@]} 个白名单工具"
    return 0
}

# =============================================
# 验证工具是否在白名单中
# =============================================
validate_tool_name(){
    local tool="$1"

    for allowed in "${TOOL_WHITELIST[@]}"; do
        if [[ "$allowed" == "$tool" ]]; then
            return 0
        fi
    done

    log "[安全警告] 工具 '$tool' 不在白名单中，已拒绝"
    return 1
}

# =============================================
# 计算包的 SHA256 校验和
# =============================================
calculate_sha256(){
    local file="$1"
    [[ ! -f "$file" ]] && return 1

    if command -v sha256sum &>/dev/null; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        log "[警告] 未找到 sha256sum 或 shasum 命令"
        return 1
    fi
}

# =============================================
# 保存包的校验和到缓存
# =============================================
save_package_checksum(){
    local pkg_file="$1"
    local checksum
    checksum=$(calculate_sha256 "$pkg_file") || return 1

    local pkg_name
    pkg_name=$(basename "$pkg_file")
    echo "${checksum}  ${pkg_name}" >> "$CHECKSUM_CACHE_FILE"
    log "[校验] 已保存 ${pkg_name} 的 SHA256: ${checksum:0:16}..."
}

# =============================================
# 验证包的完整性
# =============================================
verify_package_integrity(){
    local pkg_file="$1"
    local expected_checksum="$2"

    if [[ ! -f "$pkg_file" ]]; then
        log "[错误] 包文件不存在: $pkg_file"
        return 1
    fi

    local actual_checksum
    actual_checksum=$(calculate_sha256 "$pkg_file") || return 1

    if [[ "$actual_checksum" == "$expected_checksum" ]]; then
        log "[验证通过] $(basename "$pkg_file")"
        return 0
    else
        log "[验证失败] $(basename "$pkg_file")"
        log "  期望: $expected_checksum"
        log "  实际: $actual_checksum"
        return 1
    fi
}

# =============================================
# 生成离线包的校验和文件
# =============================================
generate_checksum_file(){
    local tarball="$1"
    local checksum_file="${tarball}.sha256"

    if [[ ! -f "$tarball" ]]; then
        log "[错误] 离线包不存在: $tarball"
        return 1
    fi

    local checksum
    checksum=$(calculate_sha256 "$tarball") || return 1
    local filename
    filename=$(basename "$tarball")

    echo "${checksum}  ${filename}" > "$checksum_file"
    log "[校验] 已生成校验和文件: $checksum_file"
    log "  SHA256: $checksum"
    return 0
}

# =============================================
# 验证离线包的完整性
# =============================================
verify_tarball_integrity(){
    local tarball="$1"
    local checksum_file="${tarball}.sha256"

    if [[ ! -f "$checksum_file" ]]; then
        log "[警告] 校验和文件不存在: $checksum_file"
        log "  建议重新下载以获取校验和文件"
        return 1
    fi

    local expected_checksum
    expected_checksum=$(awk '{print $1}' "$checksum_file")
    local expected_filename
    expected_filename=$(awk '{print $2}' "$checksum_file")

    local actual_filename
    actual_filename=$(basename "$tarball")

    if [[ "$expected_filename" != "$actual_filename" ]]; then
        log "[警告] 文件名不匹配"
        log "  期望: $expected_filename"
        log "  实际: $actual_filename"
    fi

    verify_package_integrity "$tarball" "$expected_checksum"
}

# =============================================
# 检查 RPM 包的 GPG 签名
# =============================================
verify_rpm_signature(){
    local rpm_file="$1"

    if ! command -v rpm &>/dev/null; then
        log "[警告] rpm 命令不可用，跳过签名验证"
        return 0
    fi

    local sig_check
    sig_check=$(rpm -K "$rpm_file" 2>&1)

    if echo "$sig_check" | grep -q "digests signatures OK"; then
        log "[GPG验证通过] $(basename "$rpm_file")"
        return 0
    elif echo "$sig_check" | grep -q "NOT OK"; then
        log "[GPG验证失败] $(basename "$rpm_file"): $sig_check"
        return 1
    else
        log "[GPG警告] $(basename "$rpm_file"): 无签名或无法验证"
        return 0  # 允许无签名的包
    fi
}

# =============================================
# 批量验证包目录中的所有包
# =============================================
batch_verify_packages(){
    local pkg_dir="$1"
    local pkg_type="$2"
    local total=0 passed=0 failed=0 skipped=0

    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "批量验证包完整性 ($pkg_type)"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ "$pkg_type" == "rpm" ]]; then
        for pkg in "$pkg_dir"/*.rpm; do
            [[ ! -f "$pkg" ]] && continue
            ((total++))

            if verify_rpm_signature "$pkg"; then
                ((passed++))
            else
                ((failed++))
            fi
        done
    else
        for pkg in "$pkg_dir"/*.deb; do
            [[ ! -f "$pkg" ]] && continue
            ((total++))

            # DEB 包验证（检查包结构）
            if dpkg-deb --info "$pkg" &>/dev/null; then
                log "[验证通过] $(basename "$pkg")"
                ((passed++))
            else
                log "[验证失败] $(basename "$pkg")"
                ((failed++))
            fi
        done
    fi

    log ""
    log "验证结果: 总计=$total 通过=$passed 失败=$failed"
    [[ $failed -gt 0 ]] && return 1
    return 0
}

# =============================================
# 安全检查：防止路径遍历攻击
# =============================================
safe_extract_tarball(){
    local tarball="$1"
    local extract_dir="$2"

    if [[ ! -f "$tarball" ]]; then
        log "[安全错误] 离线包不存在: $tarball"
        return 1
    fi

    # 检查归档成员是否包含绝对路径或任意层级的 .. 路径段。
    if tar -tJf "$tarball" 2>/dev/null | grep -qE '(^/|(^|/)\.\.(/|$))'; then
        log "[安全错误] 检测到路径遍历攻击尝试"
        return 1
    fi

    # 安全解压
    mkdir -p "$extract_dir"
    tar -xJf "$tarball" -C "$extract_dir" --no-same-owner --no-same-permissions 2>/dev/null
    return $?
}

# =============================================
# 导出函数
# =============================================
export -f init_tool_whitelist
export -f validate_tool_name
export -f calculate_sha256
export -f save_package_checksum
export -f verify_package_integrity
export -f generate_checksum_file
export -f verify_tarball_integrity
export -f verify_rpm_signature
export -f batch_verify_packages
export -f safe_extract_tarball
