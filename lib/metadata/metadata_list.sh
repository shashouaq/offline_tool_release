#!/bin/bash
# Metadata-based bundle listing helpers. Prefer manifest.json when available.

[[ -z "$METADATA_DIR" ]] && METADATA_DIR="$OUTPUT_DIR/.metadata"

_bundle_tools_count_from_tarball(){
    local tarball="$1"
    local count
    count=$(tar -xJOf "$tarball" "$(detect_manifest_member_in_tarball "$tarball")" 2>/dev/null \
        | grep -oE '"tools"[[:space:]]*:[[:space:]]*\[[^]]*\]' \
        | grep -oE '"[^"]+"' \
        | sed '1d' \
        | wc -l)
    echo "$count"
}

_bundle_tools_from_tarball(){
    local tarball="$1"
    tar -xJOf "$tarball" "$(detect_manifest_member_in_tarball "$tarball")" 2>/dev/null \
        | grep -oE '"tools"[[:space:]]*:[[:space:]]*\[[^]]*\]' \
        | grep -oE '"[^"]+"' \
        | sed '1d; s/^"//; s/"$//'
}

list_available_packages(){
    local found=0
    echo ""
    print_section "Available Offline Bundles"

    local tarball os arch size tool_count
    while IFS= read -r -d '' tarball; do
        os=$(tarball_manifest_value "$tarball" "target_os" 2>/dev/null || true)
        arch=$(tarball_manifest_value "$tarball" "target_arch" 2>/dev/null || true)
        size=$(du -sh "$tarball" 2>/dev/null | cut -f1)
        tool_count=$(_bundle_tools_count_from_tarball "$tarball")
        found=$((found + 1))
        printf "  %2d) %-25s %-12s size: %-8s tools: %s\n" "$found" "${os:-unknown}" "${arch:-unknown}" "$size" "$tool_count"
    done < <(find "$OUTPUT_DIR" -maxdepth 1 -name "offline_*.tar.xz" ! -name "*.sha256" -print0 2>/dev/null | sort -z)

    if [[ $found -eq 0 ]]; then
        echo "  $(t INSTALL_NOT_FOUND)"
    fi
    echo ""
    return 0
}

find_compatible_packages(){
    local cur_os cur_arch cur_pkg_type
    cur_os=$(detect_current_os 2>/dev/null || true)
    cur_arch=$(detect_current_arch)
    cur_pkg_type=$(detect_current_pkg_type 2>/dev/null || true)

    if [[ -z "$cur_os" ]]; then
        echo ""
        print_warning "$(t INSTALL_AUTO_DETECT)"
        return 1
    fi

    local found=0 tarball status
    echo ""
    print_section "$(t INSTALL_COMPATIBLE) ($cur_os / $cur_arch)"
    while IFS= read -r -d '' tarball; do
        status=$(get_bundle_compatibility "$tarball" "$cur_os" "$cur_arch" "$cur_pkg_type")
        [[ "$status" == "exact" || "$status" == "compatible" ]] || continue
        found=$((found + 1))
        local os arch size tool_count
        os=$(tarball_manifest_value "$tarball" "target_os" 2>/dev/null || true)
        arch=$(tarball_manifest_value "$tarball" "target_arch" 2>/dev/null || true)
        size=$(du -sh "$tarball" 2>/dev/null | cut -f1)
        tool_count=$(_bundle_tools_count_from_tarball "$tarball")
        printf "  %2d) %-25s %-12s size: %-8s tools: %s status: %s\n" "$found" "${os:-unknown}" "${arch:-unknown}" "$size" "$tool_count" "$status"
    done < <(find "$OUTPUT_DIR" -maxdepth 1 -name "offline_*.tar.xz" ! -name "*.sha256" -print0 2>/dev/null | sort -z)

    if [[ $found -eq 0 ]]; then
        echo "  $(t INSTALL_NOT_FOUND) $cur_os / $cur_arch"
        echo "  $(t MENU_DOWNLOAD)"
    fi
    echo ""
    return 0
}

find_compatible_packages_silent(){
    local os="$1"
    local arch="$2"
    local current_pkg_type
    current_pkg_type=$(detect_current_pkg_type 2>/dev/null || true)

    local count=0 tarball status
    while IFS= read -r -d '' tarball; do
        status=$(get_bundle_compatibility "$tarball" "$os" "$arch" "$current_pkg_type")
        [[ "$status" == "exact" || "$status" == "compatible" ]] && count=$((count + 1))
    done < <(find "$OUTPUT_DIR" -maxdepth 1 -name "offline_*.tar.xz" ! -name "*.sha256" -print0 2>/dev/null | sort -z)

    echo "$count"
    [[ "$count" -gt 0 ]]
}

list_all_packages_with_details(){
    print_section "$(t INSTALL_SELECT_PACKAGE)"
    local found=0 tarball
    while IFS= read -r -d '' tarball; do
        found=$((found + 1))
        local os arch rel pkg_type pkg_count size
        os=$(tarball_manifest_value "$tarball" "target_os" 2>/dev/null || true)
        arch=$(tarball_manifest_value "$tarball" "target_arch" 2>/dev/null || true)
        rel=$(tarball_manifest_value "$tarball" "release_ver" 2>/dev/null || true)
        pkg_type=$(tarball_manifest_value "$tarball" "pkg_type" 2>/dev/null || true)
        pkg_count=$(tarball_manifest_number "$tarball" "package_count" 2>/dev/null || true)
        size=$(du -sh "$tarball" 2>/dev/null | cut -f1)

        echo ""
        printf "  %d. %s / %s\n" "$found" "${os:-unknown}" "${arch:-unknown}"
        echo "     $(t PACKAGE_SIZE): $size"
        echo "     Release: ${rel:-unknown}"
        echo "     $(t PKG_TYPE): ${pkg_type:-unknown}"
        echo "     $(t PACKAGE_COUNT): ${pkg_count:-unknown} $(t PACK_FILES)"
        echo "     $(t INSTALL_TOOLS_TITLE):"
        local tool col=0
        while IFS= read -r tool; do
            [[ -z "$tool" ]] && continue
            printf "       %-20s" "$tool"
            col=$((col + 1))
            [[ $((col % 4)) -eq 0 ]] && echo ""
        done < <(_bundle_tools_from_tarball "$tarball")
        [[ $((col % 4)) -ne 0 ]] && echo ""
    done < <(find "$OUTPUT_DIR" -maxdepth 1 -name "offline_*.tar.xz" ! -name "*.sha256" -print0 2>/dev/null | sort -z)

    if [[ $found -eq 0 ]]; then
        echo ""
        echo "  $(t INSTALL_NOT_FOUND)"
        echo "  $(t MENU_DOWNLOAD)"
    fi
    echo ""
}

export -f list_available_packages
export -f find_compatible_packages
export -f find_compatible_packages_silent
export -f list_all_packages_with_details
export -f _bundle_tools_count_from_tarball
export -f _bundle_tools_from_tarball
