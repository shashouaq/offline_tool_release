#!/bin/bash
# Security helpers: whitelist validation, checksum verification, and safe extraction.

declare -a TOOL_WHITELIST=()
CHECKSUM_CACHE_FILE="${CHECKSUM_CACHE_FILE:-/tmp/offline_tools_checksum_cache.txt}"

_security_log(){
    if declare -F log >/dev/null 2>&1; then
        log "$1"
    else
        echo "[$(date '+%F %T')] $1" >&2
    fi
}

init_tool_whitelist(){
    local conf_file="$1"
    local tool_name src_file
    local -a conf_files=()

    [[ -f "$conf_file" ]] && conf_files+=("$conf_file")
    if [[ -d "$CONF_DIR/tools.d" ]]; then
        while IFS= read -r src_file; do
            conf_files+=("$src_file")
        done < <(find "$CONF_DIR/tools.d" -maxdepth 1 -type f -name '*.conf' | sort)
    fi
    [[ ${#conf_files[@]} -gt 0 ]] || return 1

    TOOL_WHITELIST=()
    for src_file in "${conf_files[@]}"; do
        while IFS='|' read -r tool_name _desc _rest; do
            [[ "$tool_name" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${tool_name// }" ]] && continue
            tool_name=$(echo "$tool_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [[ -n "$tool_name" ]] && TOOL_WHITELIST+=("$tool_name")
        done < "$src_file"
    done

    _security_log "[security] loaded ${#TOOL_WHITELIST[@]} whitelist tools"
    return 0
}

validate_tool_name(){
    local tool="$1"
    local allowed

    for allowed in "${TOOL_WHITELIST[@]}"; do
        [[ "$allowed" == "$tool" ]] && return 0
    done

    _security_log "[security] rejected tool outside whitelist: $tool"
    return 1
}

calculate_sha256(){
    local file="$1"
    [[ -f "$file" ]] || return 1

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        _security_log "[security] sha256 tool not available"
        return 1
    fi
}

save_package_checksum(){
    local pkg_file="$1"
    local checksum pkg_name

    checksum=$(calculate_sha256 "$pkg_file") || return 1
    pkg_name=$(basename "$pkg_file")
    echo "${checksum}  ${pkg_name}" >> "$CHECKSUM_CACHE_FILE"
    _security_log "[security] cached checksum for ${pkg_name}: ${checksum:0:16}..."
    return 0
}

verify_package_integrity(){
    local pkg_file="$1"
    local expected_checksum="$2"
    local actual_checksum

    [[ -f "$pkg_file" ]] || {
        _security_log "[security] package missing: $pkg_file"
        return 1
    }

    actual_checksum=$(calculate_sha256 "$pkg_file") || return 1
    if [[ "$actual_checksum" == "$expected_checksum" ]]; then
        _security_log "[security] checksum ok: $(basename "$pkg_file")"
        return 0
    fi

    _security_log "[security] checksum mismatch: $(basename "$pkg_file")"
    _security_log "  expected: $expected_checksum"
    _security_log "  actual:   $actual_checksum"
    return 1
}

security_generate_checksum_file(){
    local target_file="$1"
    local checksum_file="${target_file}.sha256"
    local checksum filename

    [[ -f "$target_file" ]] || {
        _security_log "[security] target file missing: $target_file"
        return 1
    }

    checksum=$(calculate_sha256 "$target_file") || return 1
    filename=$(basename "$target_file")
    echo "${checksum}  ${filename}" > "$checksum_file"
    _security_log "[security] checksum file generated: $checksum_file"
    return 0
}

verify_tarball_integrity(){
    local tarball="$1"
    local checksum_file="${tarball}.sha256"
    local expected_checksum expected_filename actual_filename

    [[ -f "$checksum_file" ]] || {
        _security_log "[security] checksum file missing: $checksum_file"
        return 1
    }

    expected_checksum=$(awk 'NF {print $1; exit}' "$checksum_file")
    expected_filename=$(awk 'NF {print $2; exit}' "$checksum_file")
    actual_filename=$(basename "$tarball")

    if [[ -n "$expected_filename" && "$expected_filename" != "$actual_filename" ]]; then
        _security_log "[security] checksum filename mismatch: expected=$expected_filename actual=$actual_filename"
    fi

    verify_package_integrity "$tarball" "$expected_checksum"
}

verify_rpm_signature(){
    local rpm_file="$1"
    local sig_check

    if ! command -v rpm >/dev/null 2>&1; then
        _security_log "[security] rpm command missing; skip signature verification"
        return 0
    fi

    sig_check=$(rpm -K "$rpm_file" 2>&1)
    if echo "$sig_check" | grep -q "digests signatures OK"; then
        _security_log "[security] rpm signature ok: $(basename "$rpm_file")"
        return 0
    fi
    if echo "$sig_check" | grep -q "NOT OK"; then
        _security_log "[security] rpm signature failed: $(basename "$rpm_file"): $sig_check"
        return 1
    fi

    _security_log "[security] rpm signature unavailable or unsigned: $(basename "$rpm_file")"
    return 0
}

batch_verify_packages(){
    local pkg_dir="$1"
    local pkg_type="$2"
    local total=0 passed=0 failed=0
    local pkg

    _security_log "[security] batch verify start: dir=$pkg_dir type=$pkg_type"

    if [[ "$pkg_type" == "rpm" ]]; then
        for pkg in "$pkg_dir"/*.rpm; do
            [[ -f "$pkg" ]] || continue
            total=$((total + 1))
            if verify_rpm_signature "$pkg"; then
                passed=$((passed + 1))
            else
                failed=$((failed + 1))
            fi
        done
    else
        for pkg in "$pkg_dir"/*.deb; do
            [[ -f "$pkg" ]] || continue
            total=$((total + 1))
            if dpkg-deb --info "$pkg" >/dev/null 2>&1; then
                _security_log "[security] deb structure ok: $(basename "$pkg")"
                passed=$((passed + 1))
            else
                _security_log "[security] deb structure failed: $(basename "$pkg")"
                failed=$((failed + 1))
            fi
        done
    fi

    _security_log "[security] batch verify result: total=$total passed=$passed failed=$failed"
    [[ $failed -eq 0 ]]
}

safe_extract_tarball(){
    local tarball="$1"
    local extract_dir="$2"

    [[ -f "$tarball" ]] || {
        _security_log "[security] tarball missing: $tarball"
        return 1
    }

    if tar -tJf "$tarball" 2>/dev/null | grep -qE '(^/|(^|/)\.\.(/|$))'; then
        _security_log "[security] path traversal detected in tarball: $tarball"
        return 1
    fi

    mkdir -p "$extract_dir"
    tar -xJf "$tarball" -C "$extract_dir" --no-same-owner --no-same-permissions 2>/dev/null
}

export -f init_tool_whitelist
export -f validate_tool_name
export -f calculate_sha256
export -f save_package_checksum
export -f verify_package_integrity
export -f security_generate_checksum_file
export -f verify_tarball_integrity
export -f verify_rpm_signature
export -f batch_verify_packages
export -f safe_extract_tarball
