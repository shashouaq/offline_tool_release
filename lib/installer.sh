#!/bin/bash
# Offline package installer.

declare -a INSTALL_FILES=()
declare -a INSTALLED_PACKAGES=()
declare -a PENDING_PACKAGES=()
declare -a INSTALLED_TOOLS=()
declare -a PENDING_TOOLS=()
declare -a TOOL_MAP_TOOLS=()
declare -A TOOL_MAP_PACKAGES=()
declare -a UPGRADE_FILES=()
declare -a SAMEVER_FILES=()
declare -a DOWNGRADE_FILES=()
declare -a COMPATIBLE_BUNDLES=()
declare -a COMPATIBLE_BUNDLE_STATUS=()

BUNDLE_TARGET_OS=""
BUNDLE_TARGET_ARCH=""
BUNDLE_PKG_TYPE=""
BUNDLE_RELEASE_VER=""
BUNDLE_PACKAGE_COUNT=""

parse_target_from_tarball_name(){
    local tarball="$1"
    local name base os arch
    name="$(basename "$tarball")"
    base="${name%.tar.xz}"
    base="${base#offline_}"
    base="${base%_merged}"

    case "$base" in
        *_x86_64)
            arch="x86_64"
            os="${base%_x86_64}"
            ;;
        *_aarch64)
            arch="aarch64"
            os="${base%_aarch64}"
            ;;
        *_loongarch64)
            arch="loongarch64"
            os="${base%_loongarch64}"
            ;;
        *)
            arch="${base##*_}"
            os="${base%_*}"
            ;;
    esac
    [[ -n "$os" && -n "$arch" ]] || return 1
    echo "$os|$arch"
}

find_bundle_package_dir(){
    local extract_root="$1"
    local fallback="$extract_root/packages"
    [[ -d "$fallback" ]] && { echo "$fallback"; return 0; }

    local first_file
    first_file=$(find "$extract_root" -type f \( -name "*.rpm" -o -name "*.deb" \) -print -quit 2>/dev/null || true)
    if [[ -n "$first_file" ]]; then
        dirname "$first_file"
        return 0
    fi
    return 1
}

resolve_bundle_package_dir(){
    local extract_root="$1"
    local pkg_dir=""
    local first_file=""
    pkg_dir=$(find_bundle_package_dir "$extract_root" 2>/dev/null || true)
    if [[ -n "$pkg_dir" && -d "$pkg_dir" ]]; then
        echo "$pkg_dir"
        return 0
    fi
    first_file=$(find "$extract_root" -type f \( -name "*.rpm" -o -name "*.deb" \) -print -quit 2>/dev/null || true)
    if [[ -n "$first_file" ]]; then
        dirname "$first_file"
        return 0
    fi
    echo "$extract_root"
}

reset_bundle_manifest(){
    BUNDLE_TARGET_OS=""
    BUNDLE_TARGET_ARCH=""
    BUNDLE_PKG_TYPE=""
    BUNDLE_RELEASE_VER=""
    BUNDLE_PACKAGE_COUNT=""
}

detect_current_pkg_type(){
    if command -v dnf &>/dev/null || command -v yum &>/dev/null; then
        echo "rpm"
    elif command -v apt-get &>/dev/null; then
        echo "deb"
    else
        echo ""
    fi
}

load_tarball_manifest_summary(){
    local tarball="$1"
    reset_bundle_manifest
    ensure_bundle_header "$tarball" 2>/dev/null || true
    BUNDLE_TARGET_OS=$(tarball_manifest_value "$tarball" "target_os")
    BUNDLE_TARGET_ARCH=$(tarball_manifest_value "$tarball" "target_arch")
    BUNDLE_PKG_TYPE=$(tarball_manifest_value "$tarball" "pkg_type")
    BUNDLE_RELEASE_VER=$(tarball_manifest_value "$tarball" "release_ver")
    BUNDLE_PACKAGE_COUNT=$(tarball_manifest_number "$tarball" "package_count")
    [[ -n "$BUNDLE_TARGET_OS" && -n "$BUNDLE_TARGET_ARCH" && -n "$BUNDLE_PKG_TYPE" ]]
}

get_bundle_compatibility(){
    local tarball="$1" current_os="$2" current_arch="$3" current_pkg_type="$4"
    load_tarball_manifest_summary "$tarball" || { echo "invalid"; return 0; }
    manifest_compatibility_status \
        "$current_os" \
        "$current_arch" \
        "$BUNDLE_TARGET_OS" \
        "$BUNDLE_TARGET_ARCH" \
        "$current_pkg_type" \
        "$BUNDLE_PKG_TYPE"
}

reset_tool_map(){
    TOOL_MAP_TOOLS=()
    TOOL_MAP_PACKAGES=()
}

read_tool_package_map(){
    local pkg_dir="$1"
    local map_file="$pkg_dir/.tool_pkg_map"
    reset_tool_map
    [[ -f "$map_file" ]] || return 1

    local line tool pkgs
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        tool="${line%%|*}"
        pkgs="${line#*|}"
        tool="${tool//$'\r'/}"
        tool="${tool#"${tool%%[![:space:]]*}"}"
        tool="${tool%"${tool##*[![:space:]]}"}"
        pkgs="${pkgs//$'\r'/}"
        [[ -z "$tool" ]] && continue
        TOOL_MAP_TOOLS+=("$tool")
        TOOL_MAP_PACKAGES["$tool"]="$pkgs"
    done < "$map_file"

    [[ ${#TOOL_MAP_TOOLS[@]} -gt 0 ]]
}

read_selected_tools_file(){
    local pkg_dir="$1"
    local f="$pkg_dir/.selected_tools"
    [[ -f "$f" ]] || return 1
    local csv line item
    csv=$(tr -d '\r' < "$f")
    IFS=',' read -ra _items <<< "$csv"
    TOOL_MAP_TOOLS=()
    for item in "${_items[@]}"; do
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        [[ -n "$item" ]] && TOOL_MAP_TOOLS+=("$item")
    done
    [[ ${#TOOL_MAP_TOOLS[@]} -gt 0 ]]
}

is_group_installed_rpm(){
    local group_name="$1"
    dnf group list --installed --ids 2>/dev/null | grep -qE "(^|[[:space:]])\\(${group_name}\\)($|[[:space:]])|(^|[[:space:]])${group_name}($|[[:space:]])"
}

is_spec_installed(){
    local pkg_type="$1" spec="$2"

    [[ -z "$spec" ]] && return 0
    if [[ "$pkg_type" == "rpm" ]]; then
        if [[ "$spec" == @* || "$spec" =~ -(environment|desktop|group)$ ]]; then
            local group_name="${spec#@}"
            is_group_installed_rpm "$group_name"
            return $?
        fi
        if [[ "$spec" == *"*"* || "$spec" == *"?"* ]]; then
            rpm -qa "$spec" 2>/dev/null | grep -q .
            return $?
        fi
        rpm -q "$spec" &>/dev/null
    else
        if [[ "$spec" == *"*"* || "$spec" == *"?"* ]]; then
            local prefix="${spec%\*}"
            dpkg-query -W "${prefix}*" 2>/dev/null | grep -q '^'
            return $?
        fi
        dpkg-query -W -f='${Status}' "$spec" 2>/dev/null | grep -q "install ok installed"
    fi
}

is_tool_installed(){
    local tool="$1" pkg_type="$2"
    local pkg_csv="${TOOL_MAP_PACKAGES[$tool]:-}"
    local spec
    [[ -z "$pkg_csv" ]] && return 1
    IFS=',' read -ra _specs <<< "$pkg_csv"
    for spec in "${_specs[@]}"; do
        spec="${spec#"${spec%%[![:space:]]*}"}"
        spec="${spec%"${spec##*[![:space:]]}"}"
        is_spec_installed "$pkg_type" "$spec" || return 1
    done
    return 0
}

build_tool_install_plan(){
    local pkg_type="$1"
    INSTALLED_TOOLS=()
    PENDING_TOOLS=()

    if [[ ${#TOOL_MAP_TOOLS[@]} -eq 0 ]]; then
        INSTALLED_TOOLS=("${INSTALLED_PACKAGES[@]}")
        PENDING_TOOLS=("${PENDING_PACKAGES[@]}")
        return 0
    fi

    local tool
    for tool in "${TOOL_MAP_TOOLS[@]}"; do
        if is_tool_installed "$tool" "$pkg_type"; then
            INSTALLED_TOOLS+=("$tool")
        else
            PENDING_TOOLS+=("$tool")
        fi
    done
}

collect_install_files_by_tools(){
    local pkg_dir="$1" pkg_type="$2"
    shift 2
    local -a selected_tools=("$@")
    local -a specs=()
    local tool spec

    for tool in "${selected_tools[@]}"; do
        IFS=',' read -ra _specs <<< "${TOOL_MAP_PACKAGES[$tool]:-}"
        for spec in "${_specs[@]}"; do
            spec="${spec#"${spec%%[![:space:]]*}"}"
            spec="${spec%"${spec##*[![:space:]]}"}"
            [[ -n "$spec" ]] && specs+=("$spec")
        done
    done

    INSTALL_FILES=()
    local file base
    while IFS= read -r -d '' file; do
        base=$(package_name_from_file "$file")
        for spec in "${specs[@]}"; do
            if [[ "$spec" == @* || "$spec" =~ -(environment|desktop|group)$ || "$spec" == *"*"* || "$spec" == *"?"* ]]; then
                INSTALL_FILES+=("$file")
                break
            fi
            [[ "$base" == "$spec" ]] && { INSTALL_FILES+=("$file"); break; }
        done
    done < <(find "$pkg_dir" -type f \( -name "*.rpm" -o -name "*.deb" \) -print0 2>/dev/null | sort -z)

    # Dedup
    local -A seen=()
    local -a uniq=()
    for file in "${INSTALL_FILES[@]}"; do
        if [[ -z "${seen[$file]+x}" ]]; then
            seen[$file]=1
            uniq+=("$file")
        fi
    done
    INSTALL_FILES=("${uniq[@]}")
}

install_mode(){
    local output_dir="${1:-$OUTPUT_DIR}"
    log_action_begin "install" "mode"
    print_header "$(t INSTALL_TITLE)"

    local cur_os cur_arch cur_os_pretty
    cur_os=$(detect_current_os 2>/dev/null || true)
    cur_arch=$(detect_current_arch)
    if [[ -f /etc/os-release ]]; then
        cur_os_pretty=$(. /etc/os-release && echo "${PRETTY_NAME:-unknown}")
    else
        cur_os_pretty="unknown"
    fi

    echo ""
    print_info "$(t INSTALL_CURRENT_OS):"
    echo "  $(t INSTALL_OS_NAME): $cur_os_pretty"
    echo "  $(t INSTALL_OS_ID): ${cur_os:-unknown}"
    echo "  $(t INSTALL_ARCH): $cur_arch"
    echo "  $(t INSTALL_KERNEL): $(uname -r)"
    echo ""

    if [[ -z "$cur_os" ]]; then
        print_warning "$(t INSTALL_AUTO_DETECT)"
        list_all_packages_with_details "$output_dir"
        show_back_prompt
        log_action_end "install" "mode" "cancel" "auto_detect_failed"
        return 0
    fi

    if [[ $(find_compatible_packages_silent "$cur_os" "$cur_arch" "$output_dir") -eq 0 ]]; then
        print_warning "$(t INSTALL_NOT_FOUND): $cur_os / $cur_arch"
        list_all_packages_with_details "$output_dir"
        show_back_prompt
        log_action_end "install" "mode" "cancel" "no_compatible_package"
        return 0
    fi

    if select_and_install_package "$cur_os" "$cur_arch" "$output_dir"; then
        log_action_end "install" "mode" "ok" "${cur_os}/${cur_arch}"
        return 0
    fi
    log_action_end "install" "mode" "failed" "${cur_os}/${cur_arch}"
    return 1
}

list_all_packages_with_details(){
    local output_dir="${1:-$OUTPUT_DIR}"
    local -a packages=()
    print_section "$(lang_pick "所有离线包" "All offline bundles")"
    while IFS= read -r -d '' file; do
        packages+=("$file")
    done < <(find "$output_dir" -maxdepth 1 -name "offline_*.tar.xz" ! -name "*.sha256" -print0 2>/dev/null | sort -z)

    if [[ ${#packages[@]} -eq 0 ]]; then
        echo "  $(t INSTALL_NO_PACKAGES)"
        return 0
    fi

    local i=1
    for pkg in "${packages[@]}"; do
        echo "  $i) $(basename "$pkg") ($(du -sh "$pkg" 2>/dev/null | cut -f1))"
        ((i++))
    done
}

find_compatible_packages_silent(){
    local target_os="$1" target_arch="$2" output_dir="${3:-$OUTPUT_DIR}"
    local target_pkg_type
    target_pkg_type=$(detect_current_pkg_type)
    local count=0
    local tarball status guessed guessed_os guessed_arch
    while IFS= read -r -d '' tarball; do
        guessed=$(parse_target_from_tarball_name "$tarball" 2>/dev/null || true)
        if [[ -n "$guessed" ]]; then
            guessed_os="${guessed%%|*}"
            guessed_arch="${guessed##*|}"
            [[ "$guessed_arch" != "$target_arch" ]] && continue
            [[ "$guessed_os" != "$target_os" ]] && continue
        fi
        status=$(get_bundle_compatibility "$tarball" "$target_os" "$target_arch" "$target_pkg_type")
        if [[ "$status" == "exact" || "$status" == "compatible" ]]; then
            count=$((count + 1))
        elif [[ "$status" == "invalid" && -n "$guessed" ]]; then
            count=$((count + 1))
        fi
    done < <(find "$output_dir" -maxdepth 1 -name "offline_*.tar.xz" ! -name "*.sha256" -print0 2>/dev/null | sort -z)
    echo "$count"
}

select_and_install_package(){
    local cur_os="$1" cur_arch="$2" output_dir="${3:-$OUTPUT_DIR}"
    local cur_pkg_type
    cur_pkg_type=$(detect_current_pkg_type)
    local -a compatible_packages=()
    local -a compatible_status=()
    local file status guessed guessed_os guessed_arch

    while IFS= read -r -d '' file; do
        guessed=$(parse_target_from_tarball_name "$file" 2>/dev/null || true)
        if [[ -n "$guessed" ]]; then
            guessed_os="${guessed%%|*}"
            guessed_arch="${guessed##*|}"
            [[ "$guessed_arch" != "$cur_arch" ]] && continue
            [[ "$guessed_os" != "$cur_os" ]] && continue
        fi
        status=$(get_bundle_compatibility "$file" "$cur_os" "$cur_arch" "$cur_pkg_type")
        case "$status" in
            exact|compatible)
                compatible_packages+=("$file")
                compatible_status+=("$status")
                ;;
            invalid)
                if [[ -n "$guessed" ]]; then
                    compatible_packages+=("$file")
                    compatible_status+=("name_match")
                fi
                ;;
        esac
    done < <(find "$output_dir" -maxdepth 1 -name "offline_*.tar.xz" ! -name "*.sha256" -print0 2>/dev/null | sort -z)

    if [[ ${#compatible_packages[@]} -eq 0 ]]; then
        print_warning "$(t INSTALL_NOT_FOUND): $cur_os / $cur_arch"
        return 0
    fi

    print_section "$(t INSTALL_COMPATIBLE)"
    local i
    for i in "${!compatible_packages[@]}"; do
        load_tarball_manifest_summary "${compatible_packages[$i]}" || true
        echo "  $((i+1))) $(basename "${compatible_packages[$i]}") ($(du -sh "${compatible_packages[$i]}" 2>/dev/null | cut -f1))"
        echo "      target: ${BUNDLE_TARGET_OS:-unknown} / ${BUNDLE_TARGET_ARCH:-unknown} / ${BUNDLE_PKG_TYPE:-unknown}"
        echo "      status: ${compatible_status[$i]}"
    done
    echo "  0) $(t BACK_MENU)"
    echo ""
    read -p "$(t MENU_SELECT) [1/0]: " choice
    choice=${choice:-1}

    [[ "$choice" == "0" ]] && return 0
    if [[ "$choice" =~ ^[0-9]+$ && $choice -ge 1 && $choice -le ${#compatible_packages[@]} ]]; then
        show_package_install_menu "${compatible_packages[$((choice-1))]}" "$output_dir"
        return $?
    else
        print_error "$(t TOOL_INVALID_INPUT)"
        sleep 1
        select_and_install_package "$cur_os" "$cur_arch" "$output_dir"
        return $?
    fi
}

show_full_package_contents(){
    local tarball="$1"
    tarball="${tarball//$'\r'/}"
    local temp_dir="/tmp/offline_view_$$"
    mkdir -p "$temp_dir"
    print_section "$(t INSTALL_TOOLS_TITLE)"
    echo "  $(basename "$tarball")"
    if safe_extract_tarball "$tarball" "$temp_dir" 2>/dev/null; then
        local pkg_dir
        pkg_dir=$(resolve_bundle_package_dir "$temp_dir")
        if ! list_package_files "$pkg_dir" "$temp_dir/manifest.json"; then
            print_error "$(lang_pick "离线包缺少工具清单（manifest/tools map），请重新打包" "Offline bundle missing tool manifest/list; please rebuild bundle")"
        fi
    else
        print_error "$(t INSTALL_VERIFY_FAILED)"
    fi
    rm -rf -- "$temp_dir"
    show_back_prompt
}

show_package_install_menu(){
    local tarball="$1" output_dir="$2"
    tarball="${tarball//$'\r'/}"
    print_section "$(t INSTALL_TOOLS_TITLE)"
    echo "  $(basename "$tarball")"
    echo "  $(t PACKAGE_SIZE): $(du -sh "$tarball" 2>/dev/null | cut -f1)"
    echo ""

    load_tarball_manifest_summary "$tarball" || true
    local quick_pkg_count=0
    quick_pkg_count="${BUNDLE_PACKAGE_COUNT:-0}"
    if [[ "${quick_pkg_count:-0}" -eq 0 ]]; then
        quick_pkg_count=$(tar -tJf "$tarball" 2>/dev/null | awk '/\.rpm$|\.deb$/{c++} END{print c+0}')
    fi
    if [[ -n "${BUNDLE_PACKAGE_COUNT:-}" && "${BUNDLE_PACKAGE_COUNT:-0}" -eq 0 && "$quick_pkg_count" -gt 0 ]]; then
        BUNDLE_PACKAGE_COUNT="$quick_pkg_count"
    fi
    echo "$(t PACKAGE_COUNT): ${BUNDLE_PACKAGE_COUNT:-$quick_pkg_count}"
    if [[ "${BUNDLE_PACKAGE_COUNT:-0}" -eq 0 && "$quick_pkg_count" -eq 0 ]]; then
        print_error "$(lang_pick "该离线包不包含可安装软件包，请重新下载打包" "This offline bundle has no installable packages; please rebuild it")"
        return 1
    fi

    echo ""
    echo "  1) $(t INSTALL_ALL)"
    echo "  2) $(t INSTALL_SELECTIVE)"
    echo "  0) $(t BACK_MENU)"
    echo ""
    read -p "$(t MENU_SELECT) [1/2/0]: " choice
    choice=${choice:-1}
    case "$choice" in
        1) install_offline_package "$tarball"; return $? ;;
        2) selective_install_from_package "$tarball"; return $? ;;
        0) return 0 ;;
        *) print_error "$(t TOOL_INVALID_INPUT)"; sleep 1; show_package_install_menu "$tarball" "$output_dir"; return $? ;;
    esac
}

post_install_next_action(){
    echo "  1) $(lang_pick "继续安装其他工具包" "Install another package")"
    echo "  0) $(t NAV_RETURN_MAIN)"
    echo ""
    local post_choice
    read -r -p "$(lang_pick "请选择 [1/0]: " "Select [1/0]: ")" post_choice
    post_choice=${post_choice:-0}
    if [[ "$post_choice" == "1" ]]; then
        select_and_install_package "$(detect_current_os 2>/dev/null || true)" "$(detect_current_arch)" "${OUTPUT_DIR:-$BASE_DIR/output}"
    fi
}

list_package_files(){
    local pkg_dir="$1" manifest_file="${2:-}"
    reset_tool_map
    read_tool_package_map "$pkg_dir" || true
    if [[ ${#TOOL_MAP_TOOLS[@]} -eq 0 ]]; then
        read_selected_tools_file "$pkg_dir" || true
    fi
    if [[ ${#TOOL_MAP_TOOLS[@]} -eq 0 && -n "$manifest_file" && -f "$manifest_file" ]]; then
        while IFS= read -r item; do
            [[ -n "$item" ]] && TOOL_MAP_TOOLS+=("$item")
        done < <(manifest_tools_from_file "$manifest_file" 2>/dev/null || true)
    fi
    if [[ ${#TOOL_MAP_TOOLS[@]} -eq 0 ]]; then
        return 1
    fi
    local tool
    for tool in "${TOOL_MAP_TOOLS[@]}"; do
        printf "  %-32s\n" "$tool"
    done
    echo ""
    echo "$(t PACKAGE_COUNT): ${#TOOL_MAP_TOOLS[@]}"
    return 0
}

package_name_from_file(){
    local file="$1" name
    if [[ "$file" == *.rpm ]]; then
        if command -v rpm &>/dev/null; then
            rpm -qp --qf '%{NAME}\n' "$file" 2>/dev/null && return 0
        fi
        name=$(basename "$file" .rpm)
        echo "$name" | sed -E 's/-[0-9][^-]*-[^-]*\.[^.]+$//'
    else
        if command -v dpkg-deb &>/dev/null; then
            dpkg-deb -f "$file" Package 2>/dev/null && return 0
        fi
        name=$(basename "$file" .deb)
        echo "${name%%_*}"
    fi
}

is_package_installed(){
    local pkg="$1" pkg_type="$2"
    if [[ "$pkg_type" == "rpm" ]]; then
        rpm -q "$pkg" &>/dev/null
    else
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"
    fi
}

get_file_pkg_version(){
    local file="$1" pkg_type="$2"
    if [[ "$pkg_type" == "rpm" ]]; then
        if command -v rpm &>/dev/null; then
            local v
            v=$(rpm -qp --qf '%{EPOCH}:%{VERSION}-%{RELEASE}\n' "$file" 2>/dev/null | head -n1)
            v="${v#(none):}"
            echo "$v"
            return 0
        fi
    else
        if command -v dpkg-deb &>/dev/null; then
            dpkg-deb -f "$file" Version 2>/dev/null | head -n1
            return 0
        fi
    fi
    echo ""
}

get_installed_pkg_version(){
    local pkg="$1" pkg_type="$2"
    if [[ "$pkg_type" == "rpm" ]]; then
        if command -v rpm &>/dev/null; then
            local v
            v=$(rpm -q --qf '%{EPOCH}:%{VERSION}-%{RELEASE}\n' "$pkg" 2>/dev/null | head -n1)
            v="${v#(none):}"
            echo "$v"
            return 0
        fi
    else
        if command -v dpkg-query &>/dev/null; then
            dpkg-query -W -f='${Version}\n' "$pkg" 2>/dev/null | head -n1
            return 0
        fi
    fi
    echo ""
}

candidate_is_newer(){
    local pkg_type="$1" installed_ver="$2" candidate_ver="$3"
    [[ -z "$installed_ver" || -z "$candidate_ver" ]] && return 1
    if [[ "$pkg_type" == "deb" ]] && command -v dpkg &>/dev/null; then
        dpkg --compare-versions "$candidate_ver" gt "$installed_ver"
        return $?
    fi
    if [[ "$candidate_ver" == "$installed_ver" ]]; then
        return 1
    fi
    local max_ver
    max_ver=$(printf '%s\n%s\n' "$installed_ver" "$candidate_ver" | sort -V | tail -n 1)
    [[ "$max_ver" == "$candidate_ver" ]]
}

build_installed_version_plan(){
    local pkg_dir="$1" pkg_type="$2"
    UPGRADE_FILES=()
    SAMEVER_FILES=()
    DOWNGRADE_FILES=()

    local file pkg installed_ver candidate_ver
    while IFS= read -r -d '' file; do
        pkg=$(package_name_from_file "$file")
        is_package_installed "$pkg" "$pkg_type" || continue

        installed_ver=$(get_installed_pkg_version "$pkg" "$pkg_type")
        candidate_ver=$(get_file_pkg_version "$file" "$pkg_type")
        if [[ -z "$installed_ver" || -z "$candidate_ver" ]]; then
            SAMEVER_FILES+=("$file")
            continue
        fi

        if candidate_is_newer "$pkg_type" "$installed_ver" "$candidate_ver"; then
            UPGRADE_FILES+=("$file")
        elif [[ "$candidate_ver" == "$installed_ver" ]]; then
            SAMEVER_FILES+=("$file")
        else
            DOWNGRADE_FILES+=("$file")
        fi
    done < <(find "$pkg_dir" -type f \( -name "*.rpm" -o -name "*.deb" \) -print0 2>/dev/null | sort -z)
}

append_unique_files(){
    local -n base_ref=$1
    shift
    local -a add_ref=("$@")
    local -A seen=()
    local f
    for f in "${base_ref[@]}"; do
        seen["$f"]=1
    done
    for f in "${add_ref[@]}"; do
        if [[ -z "${seen[$f]+x}" ]]; then
            base_ref+=("$f")
            seen["$f"]=1
        fi
    done
}

collect_install_plan(){
    local pkg_dir="$1" pkg_type="$2" include_filter="${3:-}"
    INSTALL_FILES=()
    INSTALLED_PACKAGES=()
    PENDING_PACKAGES=()

    local file pkg
    while IFS= read -r -d '' file; do
        pkg=$(package_name_from_file "$file")
        [[ -n "$include_filter" && " $include_filter " != *" $pkg "* ]] && continue
        if is_package_installed "$pkg" "$pkg_type"; then
            INSTALLED_PACKAGES+=("$pkg")
        else
            PENDING_PACKAGES+=("$pkg")
            INSTALL_FILES+=("$file")
        fi
    done < <(find "$pkg_dir" -type f \( -name "*.rpm" -o -name "*.deb" \) -print0 2>/dev/null | sort -z)

    read_tool_package_map "$pkg_dir" || true
    build_tool_install_plan "$pkg_type"
}

print_install_plan(){
    local -a show_installed=("${INSTALLED_TOOLS[@]}")
    local -a show_pending=("${PENDING_TOOLS[@]}")
    if [[ ${#show_installed[@]} -gt 0 ]]; then
        print_warning "$(t INSTALL_ALREADY_INSTALLED): ${#show_installed[@]}"
        printf '  %s\n' "${show_installed[@]}"
        echo ""
    fi
    if [[ ${#show_pending[@]} -gt 0 ]]; then
        print_info "$(t INSTALL_PENDING): ${#show_pending[@]}"
        printf '  %s\n' "${show_pending[@]}"
        echo ""
    fi
}

detect_pkg_type_in_dir(){
    local pkg_dir="$1"
    if find "$pkg_dir" -name "*.deb" -print -quit 2>/dev/null | grep -q .; then
        echo "deb"
    else
        echo "rpm"
    fi
}

has_installable_packages(){
    local pkg_dir="$1"
    [[ -d "$pkg_dir" ]] || return 1
    find "$pkg_dir" -type f \( -name "*.rpm" -o -name "*.deb" \) -print -quit 2>/dev/null | grep -q .
}

validate_bundle_manifest_for_host(){
    local manifest_file="$1" current_os="$2" current_arch="$3"
    local current_pkg_type bundle_os bundle_arch bundle_pkg_type status
    current_pkg_type=$(detect_current_pkg_type)
    bundle_os=$(file_manifest_value "$manifest_file" "target_os")
    bundle_arch=$(file_manifest_value "$manifest_file" "target_arch")
    bundle_pkg_type=$(file_manifest_value "$manifest_file" "pkg_type")
    status=$(manifest_compatibility_status "$current_os" "$current_arch" "$bundle_os" "$bundle_arch" "$current_pkg_type" "$bundle_pkg_type")

    case "$status" in
        exact)
            log_event "INFO" "install" "compatibility" "exact manifest match" "os=$bundle_os" "arch=$bundle_arch" "pkg_type=$bundle_pkg_type"
            return 0
            ;;
        compatible)
            print_warning "$(lang_pick "离线包与当前系统非完全一致，将按兼容模式继续" "Bundle differs from current system; proceeding in compatibility mode")"
            echo "  bundle: ${bundle_os} / ${bundle_arch} / ${bundle_pkg_type}"
            echo "  host:   ${current_os} / ${current_arch} / ${current_pkg_type:-unknown}"
            echo "  1) $(lang_pick "继续安装" "Continue install")"
            echo "  0) $(t BACK_MENU)"
            read -r -p "$(lang_pick "请选择 [1/0]: " "Select [1/0]: ")" compat_choice
            compat_choice=${compat_choice:-0}
            [[ "$compat_choice" == "0" ]] && return 1
            [[ "$compat_choice" == "1" ]] || return 1
            log_event "WARN" "install" "compatibility" "compatible manifest accepted by user" "os=$bundle_os" "arch=$bundle_arch" "pkg_type=$bundle_pkg_type"
            return 0
            ;;
        *)
            print_error "$(lang_pick "离线包与当前系统不兼容，已阻止安装" "Bundle is incompatible with current system; install blocked")"
            echo "  bundle: ${bundle_os:-unknown} / ${bundle_arch:-unknown} / ${bundle_pkg_type:-unknown}"
            echo "  host:   ${current_os} / ${current_arch} / ${current_pkg_type:-unknown}"
            log_action_end "install" "compatibility" "failed" "incompatible_bundle"
            return 1
            ;;
    esac
}

install_files(){
    local pkg_type="$1"
    shift
    local -a files=("$@")
    [[ ${#files[@]} -eq 0 ]] && return 0
    local pkg_dir
    pkg_dir=$(dirname "${files[0]}")
    local install_target=""
    local pkg_name=""
    local file=""

    for file in "${files[@]}"; do
        pkg_name=$(package_name_from_file "$file")
        [[ -n "$pkg_name" ]] || continue
        if [[ -z "$install_target" ]]; then
            install_target="$pkg_name"
        else
            install_target="${install_target},${pkg_name}"
        fi
    done
    log_event "INFO" "install" "apply" "install_begin" "pkg_type=$pkg_type" "pkg_dir=$pkg_dir" "targets=$install_target"

    if [[ "$pkg_type" == "rpm" ]]; then
        local repo_id="offline-local"
        local -a pkg_names=()
        local f
        for f in "${files[@]}"; do
            pkg_names+=("$(package_name_from_file "$f")")
        done
        if command -v dnf &>/dev/null; then
            dnf install -y --nogpgcheck --disablerepo='*' --repofrompath="${repo_id},file://${pkg_dir}" --enablerepo="$repo_id" "${pkg_names[@]}"
        elif command -v yum &>/dev/null; then
            yum install -y --nogpgcheck --disablerepo='*' --repofrompath="${repo_id},file://${pkg_dir}" --enablerepo="$repo_id" "${pkg_names[@]}"
        else
            rpm -Uvh "${files[@]}"
        fi
        local rc=$?
        if [[ $rc -eq 0 ]]; then
            log_event "INFO" "install" "apply" "install_complete" "pkg_type=$pkg_type" "targets=$install_target"
        else
            log_event "ERROR" "install" "apply" "install_failed" "pkg_type=$pkg_type" "targets=$install_target" "rc=$rc"
        fi
        return $rc
    else
        local apt_tmp="/tmp/offline_apt_$$"
        mkdir -p "$apt_tmp/state/lists/partial" "$apt_tmp/cache/archives/partial"
        cat > "$apt_tmp/sources.list" <<EOF
deb [trusted=yes] file:${pkg_dir} ./
EOF
        apt-get \
            -o Dir::Etc::sourcelist="$apt_tmp/sources.list" \
            -o Dir::Etc::sourceparts="-" \
            -o Dir::State="$apt_tmp/state" \
            -o Dir::Cache="$apt_tmp/cache" \
            -o Acquire::Retries=0 \
            -o Acquire::Languages=none \
            update >/dev/null 2>&1 || {
                rm -rf -- "$apt_tmp"
                return 1
            }

        local -a pkg_names=()
        local f
        for f in "${files[@]}"; do
            pkg_names+=("$(package_name_from_file "$f")")
        done
        apt-get \
            -y \
            --no-download \
            -o Dir::Etc::sourcelist="$apt_tmp/sources.list" \
            -o Dir::Etc::sourceparts="-" \
            -o Dir::State="$apt_tmp/state" \
            -o Dir::Cache="$apt_tmp/cache" \
            install "${pkg_names[@]}"
        local rc=$?
        rm -rf -- "$apt_tmp"
        if [[ $rc -eq 0 ]]; then
            log_event "INFO" "install" "apply" "install_complete" "pkg_type=$pkg_type" "targets=$install_target"
        else
            log_event "ERROR" "install" "apply" "install_failed" "pkg_type=$pkg_type" "targets=$install_target" "rc=$rc"
        fi
        return $rc
    fi
}

install_offline_package(){
    local tarball="$1"
    tarball="${tarball//$'\r'/}"
    local temp_dir="/tmp/offline_install_$$"
    local current_os current_arch manifest_file
    current_os=$(detect_current_os 2>/dev/null || true)
    current_arch=$(detect_current_arch)
    mkdir -p "$temp_dir"
    print_section "$(t INSTALL_TITLE)"

    if [[ -f "${tarball}.sha256" ]]; then
        verify_tarball "$tarball" || { print_error "$(t INSTALL_VERIFY_FAILED)"; rm -rf -- "$temp_dir"; return 1; }
    fi

    safe_extract_tarball "$tarball" "$temp_dir" 2>/dev/null || { print_error "$(t INSTALL_EXTRACT_FAILED)"; rm -rf -- "$temp_dir"; return 1; }
    manifest_file="$temp_dir/manifest.json"
    if [[ ! -f "$manifest_file" ]]; then
        print_error "$(lang_pick "离线包缺少 manifest.json，已拒绝安装" "Offline bundle is missing manifest.json; install rejected")"
        rm -rf -- "$temp_dir"
        log_action_end "install" "offline_package" "failed" "manifest_missing"
        return 1
    fi
    validate_bundle_manifest_for_host "$manifest_file" "$current_os" "$current_arch" || {
        rm -rf -- "$temp_dir"
        log_action_end "install" "offline_package" "failed" "compatibility_blocked"
        return 1
    }
    local pkg_dir pkg_count root_count
    pkg_dir=$(resolve_bundle_package_dir "$temp_dir")
    pkg_count=$(find "$pkg_dir" -type f \( -name "*.rpm" -o -name "*.deb" \) 2>/dev/null | wc -l)
    root_count=$(find "$temp_dir" -type f \( -name "*.rpm" -o -name "*.deb" \) 2>/dev/null | wc -l)
    log_event "INFO" "install" "bundle_scan" "install_all_scan" "pkg_dir=$pkg_dir" "pkg_count=$pkg_count" "root_count=$root_count"
    if [[ "${pkg_count:-0}" -eq 0 && "${root_count:-0}" -gt 0 ]]; then
        pkg_dir="$temp_dir"
        pkg_count="$root_count"
    fi
    if [[ "${pkg_count:-0}" -eq 0 ]]; then
        print_error "$(lang_pick "离线包中未找到可安装的软件包（packages目录为空）" "No installable package files found in offline bundle (packages directory is empty)")"
        rm -rf -- "$temp_dir"
        log_action_end "install" "offline_package" "failed" "packages_empty"
        return 1
    fi
    local pkg_type
    pkg_type=$(detect_pkg_type_in_dir "$pkg_dir")

    build_repo_index "$pkg_dir" "$pkg_type" || true
    collect_install_plan "$pkg_dir" "$pkg_type"
    print_install_plan
    build_installed_version_plan "$pkg_dir" "$pkg_type"

    if [[ ${#INSTALLED_TOOLS[@]} -gt 0 ]]; then
        print_section "$(lang_pick "已安装工具处理" "Installed tool handling")"
        echo "  $(lang_pick "1) 跳过已安装工具（推荐）" "1) Skip installed tools (Recommended)")"
        echo "  $(lang_pick "2) 升级已安装工具（仅升级更高版本）" "2) Upgrade installed tools (newer version only)")"
        echo "  $(lang_pick "0) 返回" "0) Back")"
        echo ""
        echo "  $(lang_pick "可升级包数量" "Upgradable package count"): ${#UPGRADE_FILES[@]}"
        echo "  $(lang_pick "同版本包数量" "Same-version package count"): ${#SAMEVER_FILES[@]}"
        echo "  $(lang_pick "低版本包数量" "Lower-version package count"): ${#DOWNGRADE_FILES[@]}"
        echo ""
        local installed_action
        read -r -p "$(lang_pick "请选择 [1/2/0]: " "Select [1/2/0]: ")" installed_action
        installed_action=${installed_action:-1}
        case "$installed_action" in
            0)
                rm -rf -- "$temp_dir"
                return 0
                ;;
            2)
                if [[ ${#UPGRADE_FILES[@]} -eq 0 ]]; then
                    print_warning "$(lang_pick "没有可升级的已安装包，将仅安装未安装包" "No upgradable installed packages; only pending packages will be installed")"
                else
                    append_unique_files INSTALL_FILES "${UPGRADE_FILES[@]}"
                fi
                ;;
            *)
                ;;
        esac
    fi

    if [[ ${#INSTALL_FILES[@]} -eq 0 ]]; then
        print_success "$(t INSTALL_ALL_ALREADY_INSTALLED)"
        rm -rf -- "$temp_dir"
        log_action_end "install" "offline_package" "ok" "already_installed"
        return 0
    fi

    echo "  1) $(lang_pick "确认安装" "Confirm install")"
    echo "  0) $(t BACK_MENU)"
    read -r -p "$(lang_pick "请选择 [1/0]: " "Select [1/0]: ")" confirm
    confirm=${confirm:-0}
    if [[ "$confirm" != "1" ]]; then
        rm -rf -- "$temp_dir"
        log_action_end "install" "offline_package" "cancel" "user_declined"
        return 0
    fi

    if install_files "$pkg_type" "${INSTALL_FILES[@]}"; then
        print_success "$(t INSTALL_COMPLETE)"
        rm -rf -- "$temp_dir"
        log_action_end "install" "offline_package" "ok" "install_complete"
        return 0
    fi

    print_error "$(t INSTALL_FAILED)"
    rm -rf -- "$temp_dir"
    log_action_end "install" "offline_package" "failed" "install_failed"
    return 1
}

selective_install_from_package(){
    local tarball="$1"
    tarball="${tarball//$'\r'/}"
    local temp_dir="/tmp/offline_selective_$$"
    local current_os current_arch manifest_file
    current_os=$(detect_current_os 2>/dev/null || true)
    current_arch=$(detect_current_arch)
    mkdir -p "$temp_dir"
    print_section "$(t INSTALL_SELECTIVE)"

    safe_extract_tarball "$tarball" "$temp_dir" 2>/dev/null || { print_error "$(t INSTALL_EXTRACT_FAILED)"; rm -rf -- "$temp_dir"; return 1; }
    manifest_file="$temp_dir/manifest.json"
    if [[ ! -f "$manifest_file" ]]; then
        print_error "$(lang_pick "离线包缺少 manifest.json，已拒绝安装" "Offline bundle is missing manifest.json; install rejected")"
        rm -rf -- "$temp_dir"
        return 1
    fi
    validate_bundle_manifest_for_host "$manifest_file" "$current_os" "$current_arch" || {
        rm -rf -- "$temp_dir"
        return 1
    }
    local pkg_dir pkg_count root_count
    pkg_dir=$(resolve_bundle_package_dir "$temp_dir")
    pkg_count=$(find "$pkg_dir" -type f \( -name "*.rpm" -o -name "*.deb" \) 2>/dev/null | wc -l)
    root_count=$(find "$temp_dir" -type f \( -name "*.rpm" -o -name "*.deb" \) 2>/dev/null | wc -l)
    log_event "INFO" "install" "bundle_scan" "selective_scan" "pkg_dir=$pkg_dir" "pkg_count=$pkg_count" "root_count=$root_count"
    if [[ "${pkg_count:-0}" -eq 0 && "${root_count:-0}" -gt 0 ]]; then
        pkg_dir="$temp_dir"
        pkg_count="$root_count"
    fi
    if [[ "${pkg_count:-0}" -eq 0 ]]; then
        print_error "$(lang_pick "离线包中未找到可安装的软件包（packages目录为空）" "No installable package files found in offline bundle (packages directory is empty)")"
        rm -rf -- "$temp_dir"
        return 1
    fi
    local pkg_type
    pkg_type=$(detect_pkg_type_in_dir "$pkg_dir")

    reset_tool_map
    read_tool_package_map "$pkg_dir" || true
    if [[ ${#TOOL_MAP_TOOLS[@]} -eq 0 ]]; then
        read_selected_tools_file "$pkg_dir" || true
    fi
    if [[ ${#TOOL_MAP_TOOLS[@]} -eq 0 ]]; then
        while IFS= read -r item; do
            [[ -n "$item" ]] && TOOL_MAP_TOOLS+=("$item")
        done < <(manifest_tools_from_file "$manifest_file" 2>/dev/null || true)
    fi
    local -a available=("${TOOL_MAP_TOOLS[@]}")
    if [[ ${#available[@]} -eq 0 ]]; then
        print_error "$(lang_pick "离线包缺少工具清单（manifest/tools map），请重新打包" "Offline bundle missing tool manifest/list; please rebuild bundle")"
        rm -rf -- "$temp_dir"
        return 1
    fi

    local i
    for i in "${!available[@]}"; do
        echo "  $((i+1))) ${available[$i]}"
    done
    echo "  a) $(t TOOLS_ALL)"
    echo "  0) $(t BACK_MENU)"
    echo ""
    read -p "$(t INSTALL_SELECT_TOOLS): " selection

    [[ "$selection" == "0" ]] && { rm -rf -- "$temp_dir"; return 0; }

    local -a selected=()
    if [[ "$selection" == "a" || "$selection" == "A" ]]; then
        selected=("${available[@]}")
    else
        IFS=',' read -ra parts <<< "$selection"
        local part idx start end
        for part in "${parts[@]}"; do
            if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                start=${BASH_REMATCH[1]}
                end=${BASH_REMATCH[2]}
                for ((idx=start; idx<=end; idx++)); do
                    [[ $idx -ge 1 && $idx -le ${#available[@]} ]] && selected+=("${available[$((idx-1))]}")
                done
            elif [[ "$part" =~ ^[0-9]+$ ]]; then
                idx=$part
                [[ $idx -ge 1 && $idx -le ${#available[@]} ]] && selected+=("${available[$((idx-1))]}")
            fi
        done
    fi

    if [[ ${#selected[@]} -eq 0 ]]; then
        print_warning "$(t TOOL_NO_SELECTION)"
        rm -rf -- "$temp_dir"
        return 0
    fi

    if [[ ${#TOOL_MAP_TOOLS[@]} -gt 0 ]]; then
        collect_install_files_by_tools "$pkg_dir" "$pkg_type" "${selected[@]}"
        INSTALLED_TOOLS=()
        PENDING_TOOLS=()
        local tool
        for tool in "${selected[@]}"; do
            if is_tool_installed "$tool" "$pkg_type"; then
                INSTALLED_TOOLS+=("$tool")
            else
                PENDING_TOOLS+=("$tool")
            fi
        done
        print_install_plan
    else
        local include_filter="${selected[*]}"
        collect_install_plan "$pkg_dir" "$pkg_type" "$include_filter"
        print_install_plan
    fi

    build_installed_version_plan "$pkg_dir" "$pkg_type"
    if [[ ${#INSTALLED_TOOLS[@]} -gt 0 ]]; then
        print_section "$(lang_pick "已安装工具处理" "Installed tool handling")"
        echo "  $(lang_pick "1) 跳过已安装工具（推荐）" "1) Skip installed tools (Recommended)")"
        echo "  $(lang_pick "2) 升级已安装工具（仅升级更高版本）" "2) Upgrade installed tools (newer version only)")"
        echo "  $(lang_pick "0) 返回" "0) Back")"
        echo ""
        local installed_action
        read -r -p "$(lang_pick "请选择 [1/2/0]: " "Select [1/2/0]: ")" installed_action
        installed_action=${installed_action:-1}
        case "$installed_action" in
            0)
                rm -rf -- "$temp_dir"
                return 0
                ;;
            2)
                if [[ ${#UPGRADE_FILES[@]} -eq 0 ]]; then
                    print_warning "$(lang_pick "没有可升级的已安装包，将仅安装未安装包" "No upgradable installed packages; only pending packages will be installed")"
                else
                    append_unique_files INSTALL_FILES "${UPGRADE_FILES[@]}"
                fi
                ;;
            *)
                ;;
        esac
    fi

    if [[ ${#INSTALL_FILES[@]} -eq 0 ]]; then
        print_success "$(t INSTALL_ALL_ALREADY_INSTALLED)"
        rm -rf -- "$temp_dir"
        post_install_next_action
        return 0
    fi

    echo "  1) $(lang_pick "确认安装" "Confirm install")"
    echo "  0) $(t BACK_MENU)"
    read -r -p "$(lang_pick "请选择 [1/0]: " "Select [1/0]: ")" confirm
    confirm=${confirm:-0}
    if [[ "$confirm" != "1" ]]; then
        rm -rf -- "$temp_dir"
        return 0
    fi

    install_files "$pkg_type" "${INSTALL_FILES[@]}"
    local rc=$?
    rm -rf -- "$temp_dir"

    if [[ $rc -eq 0 ]]; then
        print_success "$(t INSTALL_COMPLETE)"
        post_install_next_action
    else
        print_error "$(t INSTALL_FAILED)"
    fi

    return $rc
}

selective_tool_installation(){
    selective_install_from_package "$@"
}

export -f install_mode list_all_packages_with_details find_compatible_packages_silent
export -f select_and_install_package show_full_package_contents show_package_install_menu post_install_next_action
export -f list_package_files package_name_from_file is_package_installed collect_install_plan
export -f print_install_plan detect_pkg_type_in_dir install_files install_offline_package
export -f selective_install_from_package selective_tool_installation
export -f reset_tool_map read_tool_package_map is_group_installed_rpm is_spec_installed
export -f is_tool_installed build_tool_install_plan collect_install_files_by_tools
export -f get_file_pkg_version get_installed_pkg_version candidate_is_newer
export -f build_installed_version_plan append_unique_files
export -f has_installable_packages
