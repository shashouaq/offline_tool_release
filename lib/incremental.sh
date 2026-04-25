#!/bin/bash
# =====================================================
# 增量更新和断点续传模块 - incremental.sh
# 功能：支持增量更新、断点续传、智能合并
# 参考：apt-offline的增量更新机制
# =====================================================

# =============================================
# 初始化增量更新缓存
# =============================================
init_incremental_cache(){
    local cache_dir="${1:-$WORK_DIR/incremental_cache}"
    mkdir -p "$cache_dir"
    
    # 创建包清单文件
    if [[ ! -f "$cache_dir/package_manifest.json" ]]; then
        echo '{"packages": {}, "last_updated": "", "version": "1.0"}' > "$cache_dir/package_manifest.json"
    fi
    
    export INCREMENTAL_CACHE_DIR="$cache_dir"
    log "[增量] 初始化增量缓存: $cache_dir"
}

# =============================================
# 检查包是否已存在且未过期
# 用法：check_package_cached "package_name" "package_version" "max_age_days"
# 返回：0=缓存有效，1=需要更新
# =============================================
check_package_cached(){
    local pkg_name="$1"
    local pkg_version="${2:-latest}"
    local max_age_days="${3:-30}"
    
    local cache_dir="$INCREMENTAL_CACHE_DIR"
    local manifest="$cache_dir/package_manifest.json"
    
    if [[ ! -f "$manifest" ]]; then
        return 1
    fi
    
    # 检查包是否在清单中
    local cached_info=""
    if command -v jq &>/dev/null; then
        cached_info=$(jq -r ".packages[\"$pkg_name\"] // empty" "$manifest")
    else
        # 简单文本搜索
        cached_info=$(grep "\"$pkg_name\"" "$manifest" | head -1)
    fi
    
    if [[ -z "$cached_info" ]]; then
        log "[增量] 包 $pkg_name 不在缓存中"
        return 1
    fi
    
    # 检查版本是否匹配
    local cached_version=""
    if command -v jq &>/dev/null; then
        cached_version=$(echo "$cached_info" | jq -r '.version // empty')
    fi
    
    if [[ -n "$pkg_version" ]] && [[ "$pkg_version" != "latest" ]] && [[ "$cached_version" != "$pkg_version" ]]; then
        log "[增量] 包 $pkg_name 版本不匹配 (缓存: $cached_version, 需要: $pkg_version)"
        return 1
    fi
    
    # 检查缓存年龄
    local cached_time=""
    if command -v jq &>/dev/null; then
        cached_time=$(echo "$cached_info" | jq -r '.cached_at // empty')
    fi
    
    if [[ -n "$cached_time" ]]; then
        local cached_epoch
        cached_epoch=$(date -d "$cached_time" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$cached_time" +%s 2>/dev/null || echo 0)
        local current_epoch
        current_epoch=$(date +%s)
        local age_days=$(( (current_epoch - cached_epoch) / 86400 ))
        
        if [[ $age_days -gt $max_age_days ]]; then
            log "[增量] 包 $pkg_name 缓存已过期 (${age_days}天 > ${max_age_days}天)"
            return 1
        fi
    fi
    
    # 检查文件是否存在
    local pkg_file="$cache_dir/packages/${pkg_name}_*.rpm"
    local deb_file="$cache_dir/packages/${pkg_name}_*.deb"
    
    if ls $pkg_file 1>/dev/null 2>&1 || ls $deb_file 1>/dev/null 2>&1; then
        log "[增量] 包 $pkg_name 缓存有效"
        return 0
    else
        log "[增量] 包 $pkg_name 缓存文件丢失"
        return 1
    fi
}

# =============================================
# 添加包到增量缓存
# 用法：add_to_incremental_cache "package_file" "package_name" "version"
# =============================================
add_to_incremental_cache(){
    local pkg_file="$1"
    local pkg_name="$2"
    local pkg_version="${3:-unknown}"
    
    local cache_dir="$INCREMENTAL_CACHE_DIR"
    local packages_dir="$cache_dir/packages"
    mkdir -p "$packages_dir"
    
    # 复制包文件到缓存
    local dest_file="$packages_dir/$(basename "$pkg_file")"
    cp "$pkg_file" "$dest_file" 2>/dev/null || {
        log "[增量] 复制包文件失败: $pkg_file"
        return 1
    }
    
    # 更新清单
    local manifest="$cache_dir/package_manifest.json"
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local file_size
    file_size=$(stat -c%s "$dest_file" 2>/dev/null || stat -f%z "$dest_file" 2>/dev/null || echo 0)
    local checksum
    checksum=$(sha256sum "$dest_file" | awk '{print $1}')
    
    if command -v jq &>/dev/null; then
        # 使用jq更新JSON
        local temp_manifest
        temp_manifest=$(mktemp)
        jq --arg name "$pkg_name" \
           --arg version "$pkg_version" \
           --arg cached_at "$timestamp" \
           --arg size "$file_size" \
           --arg checksum "$checksum" \
           --arg file "$(basename "$dest_file")" \
           '.packages[$name] = {
               "version": $version,
               "cached_at": $cached_at,
               "size": ($size | tonumber),
               "checksum": $checksum,
               "file": $file
           } | .last_updated = $timestamp' "$manifest" > "$temp_manifest"
        mv "$temp_manifest" "$manifest"
    else
        # 简单追加（不推荐）
        log "[警告] 未找到jq，跳过清单更新"
    fi
    
    log "[增量] 已缓存包: $pkg_name ($pkg_version)"
    return 0
}

# =============================================
# 智能合并离线包
# 用法：merge_offline_packages "existing_package.tar.gz" "new_packages_dir" "output_package.tar.gz"
# =============================================
merge_offline_packages(){
    local existing_pkg="$1"
    local new_packages_dir="$2"
    local output_pkg="$3"
    
    print_section "智能合并离线包"
    
    # 验证输入
    if [[ ! -f "$existing_pkg" ]]; then
        show_error_detail "文件不存在" "现有离线包不存在: $existing_pkg"
        return 1
    fi
    
    if [[ ! -d "$new_packages_dir" ]]; then
        show_error_detail "目录不存在" "新包目录不存在: $new_packages_dir"
        return 1
    fi
    
    # 创建临时工作目录
    local temp_dir
    temp_dir=$(mktemp -d)
    local extract_dir="$temp_dir/extracted"
    local merge_dir="$temp_dir/merged"
    mkdir -p "$extract_dir" "$merge_dir"
    
    log "[合并] 解压现有离线包..."
    tar -xzf "$existing_pkg" -C "$extract_dir" 2>/dev/null || {
        show_error_detail "解压失败" "无法解压现有离线包"
        rm -rf "$temp_dir"
        return 1
    }
    
    # 复制现有包
    local packages_dir="$extract_dir/packages"
    if [[ -d "$packages_dir" ]]; then
        cp -a "$packages_dir/"* "$merge_dir/" 2>/dev/null || true
    fi
    
    # 合并新包（去重）
    local new_count=0
    local skip_count=0
    local total_new=0
    
    for new_pkg in "$new_packages_dir"/*; do
        [[ -f "$new_pkg" ]] || continue
        ((total_new++))
        
        local basename
        basename=$(basename "$new_pkg")
        local dest="$merge_dir/$basename"
        
        # 检查是否已存在
        if [[ -f "$dest" ]]; then
            # 比较校验和
            local existing_checksum
            existing_checksum=$(sha256sum "$dest" | awk '{print $1}')
            local new_checksum
            new_checksum=$(sha256sum "$new_pkg" | awk '{print $1}')
            
            if [[ "$existing_checksum" == "$new_checksum" ]]; then
                log "[合并] 跳过重复包: $basename"
                ((skip_count++))
                continue
            else
                log "[合并] 覆盖不同版本: $basename"
            fi
        fi
        
        # 复制新包
        cp "$new_pkg" "$dest"
        ((new_count++))
        log "[合并] 添加新包: $basename"
    done
    
    # 重新打包
    log "[合并] 重新打包..."
    local merged_packages="$extract_dir/packages"
    rm -rf "$merged_packages"
    mkdir -p "$merged_packages"
    cp -a "$merge_dir/"* "$merged_packages/" 2>/dev/null || true
    
    # 更新元数据
    local pkg_count
    pkg_count=$(find "$merged_packages" -type f \( -name "*.rpm" -o -name "*.deb" \) | wc -l)
    
    # 更新metadata.json
    local metadata_file="$extract_dir/metadata.json"
    if [[ -f "$metadata_file" ]] && command -v jq &>/dev/null; then
        local temp_meta
        temp_meta=$(mktemp)
        jq --arg count "$pkg_count" \
           --arg merged "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
           '.package_count = ($count | tonumber) | .last_merged = $merged' \
           "$metadata_file" > "$temp_meta"
        mv "$temp_meta" "$metadata_file"
    fi
    
    # 创建新的tar.gz
    tar -czf "$output_pkg" -C "$extract_dir" . 2>/dev/null || {
        show_error_detail "打包失败" "无法创建合并后的离线包"
        rm -rf "$temp_dir"
        return 1
    }
    
    # 清理
    rm -rf "$temp_dir"
    
    # 显示结果
    echo ""
    print_success "离线包合并成功"
    echo "  输出文件: $output_pkg"
    echo "  总包数量: $pkg_count"
    echo "  新增包数: $new_count"
    echo "  跳过重复: $skip_count"
    echo "  处理总数: $total_new"
    echo ""
    
    log "[合并] 完成: 新增=$new_count, 跳过=$skip_count, 总计=$pkg_count"
    return 0
}

# =============================================
# 断点续传下载
# 用法：resume_download "url" "output_file" "max_retries"
# =============================================
resume_download(){
    local url="$1"
    local output_file="$2"
    local max_retries="${3:-3}"
    
    local retry_count=0
    local success=false
    
    while [[ $retry_count -lt $max_retries ]]; do
        ((retry_count++))
        
        # 检查文件是否部分存在
        local resume_arg=""
        if [[ -f "$output_file" ]]; then
            local existing_size
            existing_size=$(stat -c%s "$output_file" 2>/dev/null || stat -f%z "$output_file" 2>/dev/null || echo 0)
            if [[ $existing_size -gt 0 ]]; then
                resume_arg="-C $existing_size"
                log "[续传] 从 $existing_size 字节继续下载"
            fi
        fi
        
        # 执行下载（支持断点续传）
        if curl -L -k -o "$output_file" $resume_arg --retry 2 --retry-delay 5 "$url" 2>&1; then
            success=true
            break
        else
            log "[续传] 下载失败 (尝试 $retry_count/$max_retries)"
            sleep 2
        fi
    done
    
    if [[ "$success" == true ]]; then
        log "[续传] 下载成功: $output_file"
        return 0
    else
        log "[续传] 下载失败: $url"
        return 1
    fi
}

# =============================================
# 清理过期的增量缓存
# 用法：cleanup_incremental_cache "max_age_days"
# =============================================
cleanup_incremental_cache(){
    local max_age_days="${1:-90}"
    local cache_dir="$INCREMENTAL_CACHE_DIR"
    
    if [[ ! -d "$cache_dir" ]]; then
        log "[清理] 增量缓存目录不存在"
        return 0
    fi
    
    print_section "清理过期增量缓存"
    
    local cleaned_count=0
    local freed_space=0
    
    # 查找并删除过期的包文件
    while IFS= read -r -d '' old_file; do
        local file_size
        file_size=$(stat -c%s "$old_file" 2>/dev/null || stat -f%z "$old_file" 2>/dev/null || echo 0)
        rm -f "$old_file"
        ((cleaned_count++))
        ((freed_space += file_size))
        log "[清理] 删除过期包: $(basename "$old_file")"
    done < <(find "$cache_dir/packages" -type f -mtime +$max_age_days -print0 2>/dev/null)
    
    # 显示结果
    local freed_mb=$((freed_space / 1024 / 1024))
    echo ""
    print_success "缓存清理完成"
    echo "  删除文件数: $cleaned_count"
    echo "  释放空间: ${freed_mb} MB"
    echo ""
    
    log "[清理] 完成: 删除=$cleaned_count, 释放=${freed_mb}MB"
    return 0
}

# =============================================
# 导出函数
# =============================================
export -f init_incremental_cache
export -f check_package_cached
export -f add_to_incremental_cache
export -f merge_offline_packages
export -f resume_download
export -f cleanup_incremental_cache
