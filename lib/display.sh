#!/bin/bash
# Display helpers for tool lists and prompts.

: "${COLOR_BOLD:=}"
: "${COLOR_RESET:=}"
: "${COLOR_CYAN:=}"
: "${COLOR_YELLOW:=}"

display_tools_with_packages(){
    local target_os="$1"
    shift
    local -a entries=("$@")
    local i entry tool_id desc packages pkg_display desc_display

    echo ""
    printf "  ${COLOR_BOLD}%-4s %-20s %-35s %s${COLOR_RESET}\n" "No." "Tool" "Description" "Packages"
    printf "  %-4s %-20s %-35s %s\n" "----" "--------------------" "-----------------------------------" "---------------------------"

    for ((i=0; i<${#entries[@]}; i++)); do
        entry="${entries[$i]}"
        tool_id="${entry%%|*}"
        desc="${entry#*|}"
        packages=$(get_tool_packages_for_os "$tool_id" "$target_os" 2>/dev/null || echo "$tool_id")
        pkg_display="$packages"
        desc_display="$desc"
        [[ ${#pkg_display} -gt 27 ]] && pkg_display="${pkg_display:0:24}..."
        [[ ${#desc_display} -gt 35 ]] && desc_display="${desc_display:0:32}..."
        printf "  ${COLOR_BOLD}%2d)${COLOR_RESET} %-20s %-35s %s\n" "$i" "$tool_id" "$desc_display" "$pkg_display"
    done
    echo ""
}

display_tools_multicolumn(){
    local args=("$@")
    local num_args=${#args[@]}
    local cols=4
    local -a tools=()
    local i count=0

    if [[ $num_args -gt 0 ]] && [[ "${args[$((num_args-1))]}" =~ ^[0-9]+$ ]]; then
        cols="${args[$((num_args-1))]}"
        for ((i=0; i<num_args-1; i++)); do
            tools+=("${args[$i]}")
        done
    else
        tools=("${args[@]}")
    fi

    echo ""
    for i in "${!tools[@]}"; do
        printf "  ${COLOR_BOLD}%2d)${COLOR_RESET} %-18s" "$i" "${tools[$i]}"
        ((count++))
        [[ $((count % cols)) -eq 0 ]] && echo ""
    done
    [[ $((count % cols)) -ne 0 ]] && echo ""
}

display_tools_with_desc(){
    local args=("$@")
    local num_args=${#args[@]}
    local -a tools=()
    local i tool desc

    if [[ $num_args -gt 0 ]] && [[ "${args[$((num_args-1))]}" =~ ^[0-9]+$ ]]; then
        for ((i=0; i<num_args-1; i++)); do
            tools+=("${args[$i]}")
        done
    else
        tools=("${args[@]}")
    fi

    echo ""
    for i in "${!tools[@]}"; do
        tool="${tools[$i]}"
        desc=$(get_tool_description "$tool" 2>/dev/null || echo "tool")
        printf "  ${COLOR_BOLD}%2d)${COLOR_RESET} %-18s - %s\n" "$i" "$tool" "$desc"
    done
    echo ""
}

interactive_tool_selection(){
    local title="${1:-Select tools}"
    local input item start end i tool
    print_section "$title"
    display_tools_multicolumn "${AVAILABLE_TOOLS[@]}" 4

    echo ""
    echo "  all  all"
    echo "  none none"
    echo ""

    read -r -p "Input indexes (space-separated, range like 0-5) [0]: " input
    input=${input:-0}
    SELECTED_TOOLS=()

    if [[ "$input" == "all" ]]; then
        SELECTED_TOOLS=("${AVAILABLE_TOOLS[@]}")
    elif [[ "$input" != "none" ]]; then
        for item in $input; do
            if [[ "$item" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                start="${BASH_REMATCH[1]}"
                end="${BASH_REMATCH[2]}"
                for ((i=start; i<=end && i<${#AVAILABLE_TOOLS[@]}; i++)); do
                    SELECTED_TOOLS+=("${AVAILABLE_TOOLS[$i]}")
                done
            elif [[ "$item" =~ ^[0-9]+$ ]] && [[ $item -ge 0 ]] && [[ $item -lt ${#AVAILABLE_TOOLS[@]} ]]; then
                SELECTED_TOOLS+=("${AVAILABLE_TOOLS[$item]}")
            fi
        done
    fi

    if [[ ${#SELECTED_TOOLS[@]} -gt 0 ]]; then
        local -a unique_tools=()
        local -A seen=()
        for tool in "${SELECTED_TOOLS[@]}"; do
            if [[ -z "${seen[$tool]:-}" ]]; then
                unique_tools+=("$tool")
                seen[$tool]=1
            fi
        done
        SELECTED_TOOLS=("${unique_tools[@]}")
    fi
}

show_selected_tools(){
    local -a tools=("$@")
    local col=0

    if [[ ${#tools[@]} -eq 0 ]]; then
        print_warning "$(t TOOL_NO_SELECTION)"
        return
    fi

    echo ""
    print_section "$(lang_pick "已选择工具" "Selected tools") (${#tools[@]})"
    for tool in "${tools[@]}"; do
        printf "  * %-20s" "$tool"
        ((col++))
        [[ $((col % 4)) -eq 0 ]] && echo ""
    done
    echo ""
}

display_confirm_dialog(){
    local message="$1"
    local default="${2:-n}"
    local _context="${3:-generic}"
    local response

    echo ""
    print_color "$COLOR_YELLOW" "------------------------------------------------------------"
    print_color "$COLOR_BOLD$COLOR_YELLOW" "  $message"
    print_color "$COLOR_YELLOW" "------------------------------------------------------------"
    echo ""

    if [[ "$default" == "y" ]]; then
        read -r -p "$(echo -e "${COLOR_CYAN}Continue [Y/n]: ${COLOR_RESET}")" response
        response=${response:-y}
    else
        read -r -p "$(echo -e "${COLOR_CYAN}Continue [y/N]: ${COLOR_RESET}")" response
        response=${response:-n}
    fi

    [[ "$response" =~ ^[Yy]$ ]]
}

display_show_back_prompt(){
    echo ""
    print_color "$COLOR_CYAN" "Press Enter to return..."
    read -r
}

show_operation_result(){
    local success="$1"
    local message="$2"
    echo ""
    [[ "$success" == "true" ]] && print_success "$message" || print_error "$message"
    echo ""
}

export -f display_tools_with_packages
export -f display_tools_multicolumn
export -f display_tools_with_desc
export -f interactive_tool_selection
export -f show_selected_tools
export -f display_confirm_dialog
export -f display_show_back_prompt
export -f show_operation_result
