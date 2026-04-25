#!/bin/bash
# =====================================================
# 元数据核心模块 - metadata_core.sh
# 元数据的保存、读取、更新、删除
# =====================================================

METADATA_DIR="$OUTPUT_DIR/.metadata"

# =============================================
# 初始化元数据目录
# =============================================
init_metadata_dir(){
    mkdir -p "$METADATA_DIR"
}

# =============================================
# 生成元数据文件名
# =============================================
get_metadata_file(){
    local os="$1"
    local arch="$2"
    echo "$METADATA_DIR/${os}_${arch}.meta"
}

# =============================================
# 检查离线包是否存在
# =============================================
check_offline_package_exists(){
    local os="$1"
    local arch="$2"
    local tarball="$OUTPUT_DIR/offline_${os}_${arch}_merged.tar.xz"
    [[ -f "$tarball" ]] && return 0
    return 1
}

# =============================================
# 保存包元数据
# =============================================
save_package_metadata(){
    local os="$1"
    local arch="$2"
    local tools="$3"
    local kernel_deps="$4"
    local pkg_count="$5"
    local pkg_size="$6"
    local created_date
    created_date=$(date '+%Y-%m-%d %H:%M:%S')

    local meta_file
    meta_file=$(get_metadata_file "$os" "$arch")

    cat > "$meta_file" <<META
# 离线包元数据
OS="$os"
ARCH="$arch"
TOOLS="$tools"
KERNEL_DEPS="$kernel_deps"
PKG_COUNT="$pkg_count"
PKG_SIZE="$pkg_size"
CREATED_DATE="$created_date"
UPDATED_DATE="$created_date"
META

    log "[元数据] 已保存: $meta_file"
}

# =============================================
# 读取包元数据（安全解析）
# =============================================
read_package_metadata(){
    local os="$1"
    local arch="$2"
    local meta_file
    meta_file=$(get_metadata_file "$os" "$arch")

    if [[ ! -f "$meta_file" ]]; then
        return 1
    fi

    local OS="" ARCH="" CREATED_DATE="" UPDATED_DATE="" PKG_COUNT="" PKG_SIZE="" TOOLS="" KERNEL_DEPS=""
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${key// }" ]] && continue
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
        case "$key" in
            OS) OS="$value";;
            ARCH) ARCH="$value";;
            CREATED_DATE) CREATED_DATE="$value";;
            UPDATED_DATE) UPDATED_DATE="$value";;
            PKG_COUNT) PKG_COUNT="$value";;
            PKG_SIZE) PKG_SIZE="$value";;
            TOOLS) TOOLS="$value";;
            KERNEL_DEPS) KERNEL_DEPS="$value";;
        esac
    done < "$meta_file"

    echo "$(t INSTALL_OS_NAME): $OS"
    echo "$(t INSTALL_ARCH): $ARCH"
    echo "$(t CREATED_DATE): $CREATED_DATE"
    echo "$(t UPDATED_DATE): $UPDATED_DATE"
    echo "$(t PACKAGE_COUNT): $PKG_COUNT"
    echo "$(t PACKAGE_SIZE): $PKG_SIZE"
    echo ""
    echo "$(t INSTALL_TOOLS_TITLE):"
    IFS=',' read -ra tool_array <<< "$TOOLS"
    for tool in "${tool_array[@]}"; do
        echo "  - $tool"
    done

    if [[ -n "$KERNEL_DEPS" ]]; then
        echo ""
        echo "$(t KERNEL_DEPS_TITLE):"
        IFS=',' read -ra dep_array <<< "$KERNEL_DEPS"
        for dep in "${dep_array[@]}"; do
            echo "  - $dep"
        done
    fi

    return 0
}

# =============================================
# 获取包中的工具列表
# =============================================
get_package_tools(){
    local os="$1"
    local arch="$2"
    local meta_file
    meta_file=$(get_metadata_file "$os" "$arch")

    if [[ ! -f "$meta_file" ]]; then
        return 1
    fi

    local TOOLS=""
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
        [[ "$key" == "TOOLS" ]] && TOOLS="$value" && break
    done < "$meta_file"

    echo "$TOOLS"
}

# =============================================
# 获取包中的内核依赖列表
# =============================================
get_package_kernel_deps(){
    local os="$1"
    local arch="$2"
    local meta_file
    meta_file=$(get_metadata_file "$os" "$arch")

    if [[ ! -f "$meta_file" ]]; then
        return 1
    fi

    local KERNEL_DEPS=""
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
        [[ "$key" == "KERNEL_DEPS" ]] && KERNEL_DEPS="$value" && break
    done < "$meta_file"

    echo "$KERNEL_DEPS"
}

# =============================================
# 更新包元数据
# =============================================
update_package_metadata(){
    local os="$1"
    local arch="$2"
    local tools="$3"
    local kernel_deps="$4"

    local meta_file
    meta_file=$(get_metadata_file "$os" "$arch")

    if [[ ! -f "$meta_file" ]]; then
        save_package_metadata "$os" "$arch" "$tools" "$kernel_deps" "0" "0"
        return
    fi

    local updated_date
    updated_date=$(date '+%Y-%m-%d %H:%M:%S')

    local tmpfile="${meta_file}.tmp"
    > "$tmpfile"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^TOOLS= ]]; then
            echo "TOOLS=\"$tools\"" >> "$tmpfile"
        elif [[ "$line" =~ ^KERNEL_DEPS= ]]; then
            echo "KERNEL_DEPS=\"$kernel_deps\"" >> "$tmpfile"
        elif [[ "$line" =~ ^UPDATED_DATE= ]]; then
            echo "UPDATED_DATE=\"$updated_date\"" >> "$tmpfile"
        else
            echo "$line" >> "$tmpfile"
        fi
    done < "$meta_file"

    mv "$tmpfile" "$meta_file"
    log "[元数据] 已更新: $meta_file"
}

# =============================================
# 删除包的元数据
# =============================================
delete_package_metadata(){
    local os="$1"
    local arch="$2"
    local meta_file
    meta_file=$(get_metadata_file "$os" "$arch")

    if [[ -f "$meta_file" ]]; then
        rm -f "$meta_file"
        log "[元数据] 已删除: $meta_file"
    fi
}

# =============================================
# 导出函数
# =============================================
export -f init_metadata_dir
export -f get_metadata_file
export -f check_offline_package_exists
export -f save_package_metadata
export -f read_package_metadata
export -f get_package_tools
export -f get_package_kernel_deps
export -f update_package_metadata
export -f delete_package_metadata
