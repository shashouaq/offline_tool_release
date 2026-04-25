#!/bin/bash
# Bundle manifest helpers. manifest.json is the trusted install contract.

MANIFEST_FILE=""

init_manifest(){
    local work_dir="$1"
    MANIFEST_FILE="$work_dir/manifest.json"
}

json_escape(){
    local value="${1:-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/}"
    value="${value//$'\t'/\\t}"
    printf '%s' "$value"
}

csv_to_json_array(){
    local csv="${1:-}"
    local -a items=()
    local item
    IFS=',' read -ra items <<< "$csv"

    printf '['
    local first=1
    for item in "${items[@]}"; do
        item="${item//$'\r'/}"
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        [[ -z "$item" ]] && continue
        if [[ $first -eq 0 ]]; then
            printf ', '
        fi
        printf '"%s"' "$(json_escape "$item")"
        first=0
    done
    printf ']'
}

repo_sources_to_json_array(){
    local repo_file="${1:-${TEMP_REPO_FILE:-}}"
    local -a urls=()
    local url

    if [[ -n "$repo_file" && -f "$repo_file" ]]; then
        while IFS='=' read -r key value; do
            [[ "$key" == "baseurl" ]] || continue
            value="${value//$'\r'/}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
            [[ -n "$value" ]] && urls+=("$value")
        done < "$repo_file"
    fi

    printf '['
    local first=1
    for url in "${urls[@]}"; do
        if [[ $first -eq 0 ]]; then
            printf ', '
        fi
        printf '"%s"' "$(json_escape "$url")"
        first=0
    done
    printf ']'
}

write_manifest_json(){
    local output_file="$1"
    local target_os="$2"
    local target_arch="$3"
    local pkg_type="$4"
    local release_ver="$5"
    local tools_csv="$6"
    local kernel_deps_csv="$7"
    local pkg_dir="$8"

    local generated_at package_count source_label
    generated_at=$(date '+%Y-%m-%dT%H:%M:%S%z')
    package_count=$(find "$pkg_dir" -type f \( -name "*.rpm" -o -name "*.deb" \) 2>/dev/null | wc -l)
    source_label="${DOWNLOAD_SOURCE_LABEL:-repo}"

    mkdir -p "$(dirname "$output_file")"
    cat > "$output_file" <<EOF
{
  "schema_version": "1.0",
  "generated_at": "$(json_escape "$generated_at")",
  "bundle": {
    "target_os": "$(json_escape "$target_os")",
    "target_arch": "$(json_escape "$target_arch")",
    "pkg_type": "$(json_escape "$pkg_type")",
    "release_ver": "$(json_escape "$release_ver")",
    "source_label": "$(json_escape "$source_label")",
    "dependency_policy": "full_closure_isolated_resolver",
    "install_mode": "local_repo_only",
    "package_count": $package_count,
    "tools": $(csv_to_json_array "$tools_csv"),
    "kernel_dependencies": $(csv_to_json_array "$kernel_deps_csv"),
    "repo_sources": $(repo_sources_to_json_array)
  }
}
EOF
}

sync_manifest(){
    local selected_tools_str="$1"
    local kernel_deps_str="$2"
    local target_arch="${3:-${TARGET_ARCH:-unknown}}"
    local target_os="${4:-${TARGET_OS:-unknown}}"
    local pkg_type="${5:-${PKG_TYPE:-unknown}}"
    local release_ver="${6:-${RELEASE_VER:-unknown}}"
    local pkg_dir="${7:-${PKG_DIR:-}}"
    local output_file="${8:-${MANIFEST_FILE:-}}"

    if [[ -z "$pkg_dir" || ! -d "$pkg_dir" ]]; then
        echo "manifest package directory missing: $pkg_dir" >&2
        return 1
    fi
    if [[ -z "$output_file" ]]; then
        echo "manifest output file not initialized" >&2
        return 1
    fi

    write_manifest_json \
        "$output_file" \
        "$target_os" \
        "$target_arch" \
        "$pkg_type" \
        "$release_ver" \
        "$selected_tools_str" \
        "$kernel_deps_str" \
        "$pkg_dir"
}

detect_manifest_member_in_tarball(){
    local tarball="$1"
    tar -tJf "$tarball" 2>/dev/null | awk '/(^|\/)(\.\/)?manifest\.json$/ {print; exit}'
}

tarball_has_manifest(){
    local tarball="$1"
    [[ -n "$(detect_manifest_member_in_tarball "$tarball")" ]]
}

manifest_value_from_stream(){
    local key="$1"
    sed -n -E "s/^[[:space:]]*\"${key}\":[[:space:]]*\"([^\"]*)\".*/\\1/p" | head -n 1
}

manifest_number_from_stream(){
    local key="$1"
    sed -n -E "s/^[[:space:]]*\"${key}\":[[:space:]]*([0-9]+).*/\\1/p" | head -n 1
}

tarball_manifest_value(){
    local tarball="$1"
    local key="$2"
    local member
    member=$(detect_manifest_member_in_tarball "$tarball")
    [[ -n "$member" ]] || return 1
    tar -xJOf "$tarball" "$member" 2>/dev/null | manifest_value_from_stream "$key"
}

tarball_manifest_number(){
    local tarball="$1"
    local key="$2"
    local member
    member=$(detect_manifest_member_in_tarball "$tarball")
    [[ -n "$member" ]] || return 1
    tar -xJOf "$tarball" "$member" 2>/dev/null | manifest_number_from_stream "$key"
}

file_manifest_value(){
    local manifest_file="$1"
    local key="$2"
    [[ -f "$manifest_file" ]] || return 1
    manifest_value_from_stream "$key" < "$manifest_file"
}

file_manifest_number(){
    local manifest_file="$1"
    local key="$2"
    [[ -f "$manifest_file" ]] || return 1
    manifest_number_from_stream "$key" < "$manifest_file"
}

manifest_tools_from_file(){
    local manifest_file="$1"
    [[ -f "$manifest_file" ]] || return 1
    sed -n '/"tools"[[:space:]]*:/,/]/p' "$manifest_file" \
        | tr -d '\r' \
        | tr -d '\n' \
        | sed -E 's/.*"tools"[[:space:]]*:[[:space:]]*\[(.*)\].*/\1/' \
        | tr ',' '\n' \
        | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//; s/^[[:space:]]+//; s/[[:space:]]+$//' \
        | awk 'NF'
}

manifest_compatibility_status(){
    local current_os="$1"
    local current_arch="$2"
    local bundle_os="$3"
    local bundle_arch="$4"
    local current_pkg_type="$5"
    local bundle_pkg_type="$6"

    [[ -z "$bundle_os" || -z "$bundle_arch" || -z "$bundle_pkg_type" ]] && { echo "invalid"; return 0; }
    [[ "$current_arch" != "$bundle_arch" ]] && { echo "incompatible"; return 0; }
    [[ -n "$current_pkg_type" && "$current_pkg_type" != "$bundle_pkg_type" ]] && { echo "incompatible"; return 0; }
    [[ "$current_os" == "$bundle_os" ]] && { echo "exact"; return 0; }

    local current_family bundle_family
    current_family=$(printf '%s' "$current_os" | sed -E 's/[0-9].*$//')
    bundle_family=$(printf '%s' "$bundle_os" | sed -E 's/[0-9].*$//')
    if [[ -n "$current_family" && "$current_family" == "$bundle_family" ]]; then
        echo "compatible"
    else
        echo "incompatible"
    fi
}

export -f init_manifest
export -f json_escape
export -f csv_to_json_array
export -f repo_sources_to_json_array
export -f write_manifest_json
export -f sync_manifest
export -f detect_manifest_member_in_tarball
export -f tarball_has_manifest
export -f tarball_manifest_value
export -f tarball_manifest_number
export -f file_manifest_value
export -f file_manifest_number
export -f manifest_tools_from_file
export -f manifest_compatibility_status
