#!/bin/bash

MIRROR_CACHE_DIR="${MIRROR_CACHE_DIR:-/tmp/offline_tools_mirror_cache}"
MIRROR_CACHE_TTL="${MIRROR_CACHE_TTL:-86400}"

init_mirror_cache(){
    mkdir -p "$MIRROR_CACHE_DIR"
}

_mirror_cache_repo_hash(){
    local joined=""
    if [[ ${#REPOS[@]} -gt 0 ]]; then
        joined=$(printf '%s\n' "${REPOS[@]}" | tr -d '\r')
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$joined" | sha256sum | awk '{print substr($1,1,16)}'
    else
        printf '%s' "$joined" | cksum | awk '{print $1}'
    fi
}

get_cache_file(){
    local os_key="$1"
    local arch="${2:-$(uname -m)}"
    local pkg_type="${3:-${PKG_TYPE:-unknown}}"
    local release_ver="${4:-${RELEASE_VER:-unknown}}"
    local repo_hash="${5:-$(_mirror_cache_repo_hash)}"
    echo "$MIRROR_CACHE_DIR/${os_key}_${arch}_${pkg_type}_${release_ver}_${repo_hash}.cache"
}

save_mirror_cache(){
    local os_key="$1"
    local arch="${2:-$(uname -m)}"
    local pkg_type="${3:-${PKG_TYPE:-unknown}}"
    local release_ver="${4:-${RELEASE_VER:-unknown}}"
    shift 4
    local -a valid_mirrors=("$@")
    init_mirror_cache
    local cache_file repo_hash timestamp
    repo_hash=$(_mirror_cache_repo_hash)
    cache_file=$(get_cache_file "$os_key" "$arch" "$pkg_type" "$release_ver" "$repo_hash")
    timestamp=$(date +%s)
    {
        echo "TIMESTAMP=$timestamp"
        echo "OS=$os_key"
        echo "ARCH=$arch"
        echo "PKG_TYPE=$pkg_type"
        echo "RELEASE_VER=$release_ver"
        echo "REPO_HASH=$repo_hash"
        echo "VALID_COUNT=${#valid_mirrors[@]}"
        local i
        for i in "${!valid_mirrors[@]}"; do
            echo "MIRROR_$i=${valid_mirrors[$i]}"
        done
    } > "$cache_file"
    log_event "INFO" "mirror_cache" "save" "saved reachable mirrors" "os=$os_key" "arch=$arch" "pkg_type=$pkg_type" "release=$release_ver" "count=${#valid_mirrors[@]}"
}

load_mirror_cache(){
    local os_key="$1"
    local arch="${2:-$(uname -m)}"
    local pkg_type="${3:-${PKG_TYPE:-unknown}}"
    local release_ver="${4:-${RELEASE_VER:-unknown}}"
    local cache_file cache_time current_time age count mirror i
    cache_file=$(get_cache_file "$os_key" "$arch" "$pkg_type" "$release_ver")
    [[ -f "$cache_file" ]] || return 1
    cache_time=$(awk -F= '/^TIMESTAMP=/{print $2; exit}' "$cache_file")
    [[ -n "$cache_time" ]] || return 1
    current_time=$(date +%s)
    age=$((current_time - cache_time))
    if [[ $age -gt $MIRROR_CACHE_TTL ]]; then
        rm -f "$cache_file"
        log_event "INFO" "mirror_cache" "expired" "mirror cache expired" "file=$cache_file" "age=$age"
        return 1
    fi
    count=$(awk -F= '/^VALID_COUNT=/{print $2; exit}' "$cache_file")
    REPOS=()
    for ((i=0; i<count; i++)); do
        mirror=$(awk -F= -v n="$i" '$1=="MIRROR_" n {sub(/^[^=]*=/,""); print; exit}' "$cache_file")
        [[ -n "$mirror" ]] && REPOS+=("$mirror")
    done
    [[ ${#REPOS[@]} -gt 0 ]] || return 1
    log_event "INFO" "mirror_cache" "load" "loaded reachable mirrors from cache" "os=$os_key" "arch=$arch" "pkg_type=$pkg_type" "release=$release_ver" "count=${#REPOS[@]}" "age=$age"
    return 0
}

clear_mirror_cache(){
    rm -rf "$MIRROR_CACHE_DIR"
    mkdir -p "$MIRROR_CACHE_DIR"
    log_event "INFO" "mirror_cache" "clear" "cleared all mirror cache"
}

clear_os_mirror_cache(){
    local os_key="$1"
    local arch="${2:-$(uname -m)}"
    local pkg_type="${3:-${PKG_TYPE:-unknown}}"
    local release_ver="${4:-${RELEASE_VER:-unknown}}"
    local cache_file
    cache_file=$(get_cache_file "$os_key" "$arch" "$pkg_type" "$release_ver")
    [[ -f "$cache_file" ]] && rm -f "$cache_file"
    log_event "INFO" "mirror_cache" "clear_os" "cleared mirror cache for target" "os=$os_key" "arch=$arch" "pkg_type=$pkg_type" "release=$release_ver"
}

show_mirror_cache_status(){
    print_section "$(lang_pick "镜像源缓存状态" "Mirror cache status")"
    [[ -d "$MIRROR_CACHE_DIR" ]] || { echo "  $(lang_pick "暂无缓存数据" "No cache data")"; return 0; }
    local found=0 cache_file count age current_time ts
    current_time=$(date +%s)
    while IFS= read -r -d '' cache_file; do
        found=1
        ts=$(awk -F= '/^TIMESTAMP=/{print $2; exit}' "$cache_file")
        count=$(awk -F= '/^VALID_COUNT=/{print $2; exit}' "$cache_file")
        age=$((current_time - ts))
        echo "  $(basename "$cache_file")"
        echo "    $(lang_pick "可用源数量" "Reachable mirrors"): ${count:-0}"
        echo "    $(lang_pick "缓存年龄" "Cache age"): ${age}s"
    done < <(find "$MIRROR_CACHE_DIR" -maxdepth 1 -name '*.cache' -print0 2>/dev/null)
    [[ $found -eq 0 ]] && echo "  $(lang_pick "暂无缓存数据" "No cache data")"
}

export -f init_mirror_cache
export -f get_cache_file
export -f save_mirror_cache
export -f load_mirror_cache
export -f clear_mirror_cache
export -f clear_os_mirror_cache
export -f show_mirror_cache_status
