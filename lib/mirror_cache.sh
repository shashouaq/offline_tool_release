#!/bin/bash
# =====================================================
# 镜像源缓存管理模块
# 功能：缓存镜像源连通性检测结果，避免重复检测
# =====================================================

MIRROR_CACHE_DIR="/tmp/offline_tools_mirror_cache"
MIRROR_CACHE_TTL=86400  # 缓存有效期：24小时（秒）

# =============================================
# 初始化缓存目录
# =============================================
init_mirror_cache(){
    mkdir -p "$MIRROR_CACHE_DIR"
}

# =============================================
# 生成缓存文件路径
# =============================================
get_cache_file(){
    local os_key="$1"
    local arch="${2:-$(uname -m)}"
    echo "$MIRROR_CACHE_DIR/${os_key}_${arch}.cache"
}

# =============================================
# 保存镜像源检测结果到缓存
# =============================================
save_mirror_cache(){
    local os_key="$1"
    local arch="${2:-$(uname -m)}"
    shift 2
    local -a valid_mirrors=("$@")
    
    init_mirror_cache
    
    local cache_file
    cache_file=$(get_cache_file "$os_key" "$arch")
    local timestamp
    timestamp=$(date +%s)
    
    # 保存缓存
    {
        echo "# 镜像源缓存"
        echo "# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# 系统: $os_key"
        echo "# 架构: $arch"
        echo "TIMESTAMP=$timestamp"
        echo "VALID_COUNT=${#valid_mirrors[@]}"
        for i in "${!valid_mirrors[@]}"; do
            echo "MIRROR_$i=${valid_mirrors[$i]}"
        done
    } > "$cache_file"
    
    echo "[缓存] 已保存镜像源检测结果到缓存"
}

# =============================================
# 从缓存加载镜像源检测结果
# =============================================
load_mirror_cache(){
    local os_key="$1"
    local arch="${2:-$(uname -m)}"
    
    local cache_file
    cache_file=$(get_cache_file "$os_key" "$arch")
    
    # 检查缓存文件是否存在
    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi
    
    # 检查缓存是否过期
    local cache_time
    cache_time=$(grep "^TIMESTAMP=" "$cache_file" | cut -d= -f2)
    local current_time
    current_time=$(date +%s)
    
    if [[ -z "$cache_time" ]]; then
        return 1
    fi
    
    local age=$((current_time - cache_time))
    if [[ $age -gt $MIRROR_CACHE_TTL ]]; then
        echo "[缓存] 缓存已过期（${age}秒 > ${MIRROR_CACHE_TTL}秒），将重新检测"
        rm -f "$cache_file"
        return 1
    fi
    
    # 读取缓存的镜像列表
    local -a cached_mirrors=()
    local count
    count=$(grep "^VALID_COUNT=" "$cache_file" | cut -d= -f2)
    
    for ((i=0; i<count; i++)); do
        local mirror
        mirror=$(grep "^MIRROR_$i=" "$cache_file" | cut -d= -f2-)
        if [[ -n "$mirror" ]]; then
            cached_mirrors+=("$mirror")
        fi
    done
    
    if [[ ${#cached_mirrors[@]} -gt 0 ]]; then
        # 将缓存的镜像设置到全局变量
        REPOS=("${cached_mirrors[@]}")
        echo "[缓存] 使用缓存的镜像源检测结果（${#cached_mirrors[@]} 个可用源，缓存年龄: ${age}秒）"
        return 0
    else
        return 1
    fi
}

# =============================================
# 清除所有镜像源缓存
# =============================================
clear_mirror_cache(){
    if [[ -d "$MIRROR_CACHE_DIR" ]]; then
        rm -rf "$MIRROR_CACHE_DIR"
        mkdir -p "$MIRROR_CACHE_DIR"
        echo "[缓存] 已清除所有镜像源缓存"
    fi
}

# =============================================
# 清除指定系统的镜像源缓存
# =============================================
clear_os_mirror_cache(){
    local os_key="$1"
    local arch="${2:-$(uname -m)}"
    
    local cache_file
    cache_file=$(get_cache_file "$os_key" "$arch")
    
    if [[ -f "$cache_file" ]]; then
        rm -f "$cache_file"
        echo "[缓存] 已清除 $os_key ($arch) 的镜像源缓存"
    fi
}

# =============================================
# 显示缓存状态
# =============================================
show_mirror_cache_status(){
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  镜像源缓存状态"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if [[ ! -d "$MIRROR_CACHE_DIR" ]] || [[ -z "$(ls -A "$MIRROR_CACHE_DIR" 2>/dev/null)" ]]; then
        echo "  暂无缓存数据"
        echo ""
        return
    fi
    
    local current_time
    current_time=$(date +%s)
    
    for cache_file in "$MIRROR_CACHE_DIR"/*.cache; do
        [[ -f "$cache_file" ]] || continue
        
        local basename
        basename=$(basename "$cache_file")
        local os_info="${basename%.cache}"
        
        local cache_time
        cache_time=$(grep "^TIMESTAMP=" "$cache_file" | cut -d= -f2)
        local count
        count=$(grep "^VALID_COUNT=" "$cache_file" | cut -d= -f2)
        local generate_time
        generate_time=$(grep "^# 生成时间:" "$cache_file" | cut -d: -f2-)
        
        local age=$((current_time - cache_time))
        local age_hours=$((age / 3600))
        local age_minutes=$(( (age % 3600) / 60 ))
        
        echo "  系统: $os_info"
        echo "  生成时间:$generate_time"
        echo "  可用源数: $count 个"
        echo "  缓存年龄: ${age_hours}小时${age_minutes}分钟"
        
        if [[ $age -lt $MIRROR_CACHE_TTL ]]; then
            echo "  状态: ✓ 有效"
        else
            echo "  状态: ✗ 已过期"
        fi
        echo ""
    done
}

# =============================================
# 导出函数
# =============================================
export -f init_mirror_cache
export -f get_cache_file
export -f save_mirror_cache
export -f load_mirror_cache
export -f clear_mirror_cache
export -f clear_os_mirror_cache
export -f show_mirror_cache_status
