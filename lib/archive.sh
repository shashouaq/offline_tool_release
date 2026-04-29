#!/bin/bash

_archive_msg(){ local zh="$1" en="$2"; lang_pick "$zh" "$en"; }

_parse_csv_tools(){
    local csv="$1" item
    IFS=',' read -ra _items <<< "$csv"
    for item in "${_items[@]}"; do
        item="${item//$'\r'/}"
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        [[ -n "$item" ]] && printf '%s\n' "$item"
    done
}

generate_checksum_file(){
    local tarball="$1"
    [[ -f "$tarball" ]] || return 1
    local checksum_file="${tarball}.sha256" old_pwd
    old_pwd=$(pwd)
    cd "$(dirname "$tarball")" || return 1
    sha256sum "$(basename "$tarball")" > "$(basename "$checksum_file")"
    cd "$old_pwd" >/dev/null || true
    return 0
}

verify_tarball(){
    local tarball="$1" checksum_file="${tarball}.sha256" expected actual
    [[ -f "$checksum_file" ]] || return 0
    expected=$(awk 'NF {print $1; exit}' "$checksum_file")
    actual=$(sha256sum "$tarball" | awk '{print $1}')
    [[ -n "$expected" && "$expected" == "$actual" ]]
}

_run_tar_with_progress(){
    local tarball="$1" src_dir="$2" src_name="$3" label="$4"
    local total_files done rc tpid
    total_files=$(find "$src_dir/$src_name" -type f 2>/dev/null | wc -l)
    [[ "$total_files" -le 0 ]] && total_files=1
    init_progress "$total_files" "$label"
    (tar -cJf "$tarball" -C "$src_dir" "$src_name") &
    tpid=$!
    done=0
    while kill -0 "$tpid" 2>/dev/null; do
        if [[ $done -lt $total_files ]]; then
            done=$((done + 1))
            [[ $done -gt $total_files ]] && done=$total_files
            update_progress 1 "$label step=${done}/${total_files}"
        fi
        sleep 0.2
    done
    wait "$tpid"
    rc=$?
    [[ $rc -eq 0 ]] && show_progress_complete
    return $rc
}

merge_into_tarball(){
    local tarball="$1" pkg_dir="$2" work_dir="$3" merge_mode="${4:-new}" target_os="$5" target_arch="$6" selected_tools_str="$7" kernel_deps_str="$8"
    shift 8
    mkdir -p "$pkg_dir"
    local pkg_count merge_dir tar_rc pkg_size size
    pkg_count=$(find "$pkg_dir" -type f \( -name "*.rpm" -o -name "*.deb" \) 2>/dev/null | wc -l)
    if [[ "$pkg_count" -eq 0 ]]; then
        print_error "$(_archive_msg 'packages 目录为空，无法打包' 'packages directory is empty, cannot package')"
        return 1
    fi

    if [[ "$merge_mode" == "merge" && -f "$tarball" ]]; then
        print_section "$(_archive_msg '增量合并离线包' 'Merge Offline Package')"
        merge_dir="/tmp/offline_merge_$$"
        mkdir -p "$merge_dir"
        safe_extract_tarball "$tarball" "$merge_dir" 2>/dev/null || true
        mkdir -p "$merge_dir/packages"
        if command -v rsync &>/dev/null; then
            rsync -a "$pkg_dir/" "$merge_dir/packages/" >/dev/null 2>&1
        else
            cp -rn "$pkg_dir/"* "$merge_dir/packages/" 2>/dev/null || true
        fi
        sync_manifest "$selected_tools_str" "$kernel_deps_str" "$target_arch" "$target_os" "${PKG_TYPE:-unknown}" "${RELEASE_VER:-unknown}" "$merge_dir/packages" "$merge_dir/manifest.json" || return 1
        _run_tar_with_progress "$tarball" "$merge_dir" "." "$(_archive_msg '打包中' 'Packing')"
        tar_rc=$?
        pkg_count=$(find "$merge_dir/packages" -type f \( -name "*.rpm" -o -name "*.deb" \) 2>/dev/null | wc -l)
        rm -rf -- "$merge_dir"
        [[ $tar_rc -ne 0 ]] && return $tar_rc
        update_package_metadata "$target_os" "$target_arch" "$selected_tools_str" "$kernel_deps_str"
    else
        print_section "$(_archive_msg '创建新离线包' 'Create Offline Package')"
        sync_manifest "$selected_tools_str" "$kernel_deps_str" "$target_arch" "$target_os" "${PKG_TYPE:-unknown}" "${RELEASE_VER:-unknown}" "$pkg_dir" "$work_dir/manifest.json" || return 1
        _run_tar_with_progress "$tarball" "$work_dir" "." "$(_archive_msg '打包中' 'Packing')" || return $?
        pkg_size=$(du -sh "$tarball" 2>/dev/null | cut -f1)
        save_package_metadata "$target_os" "$target_arch" "$selected_tools_str" "$kernel_deps_str" "$pkg_count" "$pkg_size"
    fi

    generate_checksum_file "$tarball" || return 1
    write_bundle_header "$tarball" "$target_os" "$target_arch" "${PKG_TYPE:-unknown}" "${RELEASE_VER:-unknown}" "$selected_tools_str" "$kernel_deps_str" "$pkg_count" || true
    size=$(du -sh "$tarball" 2>/dev/null | cut -f1)
    show_status "ok" "$(_archive_msg '离线包文件' 'Offline package'): $tarball"
    show_status "ok" "$(_archive_msg '包大小' 'Package size'): $size"
    show_status "ok" "$(_archive_msg '校验文件' 'Checksum file'): ${tarball}.sha256"
    print_section "$(t TOOLS_PACKAGE_TITLE)"
    local -a tools=()
    local t
    while IFS= read -r t; do [[ -n "$t" ]] && tools+=("$t"); done < <(_parse_csv_tools "$selected_tools_str")
    if [[ ${#tools[@]} -eq 0 ]]; then
        print_warning "$(_archive_msg '未解析到工具清单' 'Tool list not found in metadata')"
    else
        for t in "${tools[@]}"; do echo "  - $t"; done
        show_status "ok" "$(_archive_msg '支持安装工具数' 'Installable tools'): ${#tools[@]}"
    fi
    echo ""
    return 0
}

list_tarball_contents(){
    local tarball="$1" filter="${2:-}"
    [[ -f "$tarball" ]] || return 1
    if [[ -n "$filter" ]]; then tar -tJf "$tarball" 2>/dev/null | grep "$filter"; else tar -tJf "$tarball" 2>/dev/null; fi
}

extract_tarball(){
    local tarball="$1" dest_dir="$2" strip_components="${3:-0}"
    [[ -f "$tarball" ]] || return 1
    mkdir -p "$dest_dir"
    if [[ "$strip_components" -gt 0 ]]; then
        tar -xJf "$tarball" -C "$dest_dir" --strip-components="$strip_components" --no-same-owner --no-same-permissions
    else
        safe_extract_tarball "$tarball" "$dest_dir"
    fi
}

get_tarball_info(){
    local tarball="$1"
    [[ -f "$tarball" ]] || return 1
    local size file_count pkg_count
    size=$(du -sh "$tarball" 2>/dev/null | cut -f1)
    file_count=$(tar -tJf "$tarball" 2>/dev/null | wc -l)
    pkg_count=$(tar -tJf "$tarball" 2>/dev/null | grep -E '\.(rpm|deb)$' | wc -l)
    echo "file: $(basename "$tarball")"
    echo "size: $size"
    echo "entries: $file_count"
    echo "packages: $pkg_count"
}

export -f merge_into_tarball
export -f generate_checksum_file
export -f verify_tarball
export -f list_tarball_contents
export -f extract_tarball
export -f get_tarball_info
