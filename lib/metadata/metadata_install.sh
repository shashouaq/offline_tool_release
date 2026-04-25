#!/bin/bash
# Legacy metadata install helpers kept for compatibility with older flows.

install_package_directory(){
    local pkg_dir="$1"
    local pkg_type="$2"

    if [[ ! -d "$pkg_dir" ]]; then
        print_error "$(t ERROR): $(t CAUSE_NOT_FOUND): $pkg_dir"
        return 1
    fi

    local -a files=()
    if [[ "$pkg_type" == "rpm" ]]; then
        while IFS= read -r -d '' file; do
            files+=("$file")
        done < <(find "$pkg_dir" -type f -name "*.rpm" -print0 2>/dev/null | sort -z)
    else
        while IFS= read -r -d '' file; do
            files+=("$file")
        done < <(find "$pkg_dir" -type f -name "*.deb" -print0 2>/dev/null | sort -z)
    fi

    if [[ ${#files[@]} -eq 0 ]]; then
        print_error "$(t ERROR): $(t CAUSE_NOT_FOUND) $(t PACK_FILES)"
        return 1
    fi

    build_repo_index "$pkg_dir" "$pkg_type" >/dev/null 2>&1 || true
    install_files "$pkg_type" "${files[@]}"
}

install_single_package(){
    local pkg_file="$1"
    local pkg_type="$2"

    if [[ ! -f "$pkg_file" ]]; then
        print_error "$(t ERROR): $(t CAUSE_NOT_FOUND): $pkg_file"
        return 1
    fi

    build_repo_index "$(dirname "$pkg_file")" "$pkg_type" >/dev/null 2>&1 || true
    install_files "$pkg_type" "$pkg_file"
}

install_selected_tools(){
    local pkg_dir="$1"
    shift
    local pkg_type="$1"
    shift
    local -a selected_tools=("$@")

    if [[ "$pkg_type" != "rpm" && "$pkg_type" != "deb" ]]; then
        if find "$pkg_dir" -name "*.rpm" -print -quit 2>/dev/null | grep -q .; then
            pkg_type="rpm"
        elif find "$pkg_dir" -name "*.deb" -print -quit 2>/dev/null | grep -q .; then
            pkg_type="deb"
        else
            print_error "$(t ERROR): $(t CAUSE_NOT_FOUND)$(t PACK_FILES)"
            return 1
        fi
    fi

    print_info "$(t INSTALLING) ${#selected_tools[@]} $(t PACK_FILES) [$(echo "$pkg_type" | tr 'a-z' 'A-Z')]..."
    echo ""

    local -a found_files=()
    local tool pkg
    for tool in "${selected_tools[@]}"; do
        while IFS= read -r pkg; do
            [[ -n "$pkg" ]] && found_files+=("$pkg")
        done < <(find "$pkg_dir" -type f \( -name "${tool}-*.rpm" -o -name "${tool}_[0-9]*.deb" -o -name "${tool}_*.deb" -o -name "*${tool}*.rpm" -o -name "*${tool}*.deb" \) 2>/dev/null)
    done

    if [[ ${#found_files[@]} -eq 0 ]]; then
        print_error "$(t INSTALL_FAILED)"
        return 1
    fi

    install_files "$pkg_type" "${found_files[@]}"
}

export -f install_selected_tools
export -f install_single_package
export -f install_package_directory
