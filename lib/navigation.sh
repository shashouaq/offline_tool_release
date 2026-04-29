#!/bin/bash
# Unified navigation/menu helpers.

show_back_prompt(){
    echo ""
    print_color "$COLOR_CYAN" "$(t PRESS_ENTER)"
    read -r
}

show_navigation_menu(){
    local return_target="${1:-main_menu}"

    echo ""
    print_section "$(t NAV_SELECT_PROMPT)"
    echo "  1) $(t NAV_RETURN_MAIN)"
    if [[ "$return_target" != "main_menu" ]]; then
        echo "  2) $(t NAV_RETURN_PARENT)"
    fi
    echo "  0) $(t NAV_EXIT)"
    echo ""

    local choice
    read -r -p "$(t NAV_SELECT_PROMPT) [0]: " choice
    choice=${choice:-0}

    case "$choice" in
        1)
            if declare -f main_menu &>/dev/null; then
                main_menu
            else
                exit 0
            fi
            ;;
        2)
            if [[ "$return_target" != "main_menu" ]] && declare -f "$return_target" &>/dev/null; then
                "$return_target"
            else
                show_back_prompt
            fi
            ;;
        0)
            print_color "$COLOR_GREEN" "$(t MENU_EXIT)!"
            exit 0
            ;;
        *)
            print_error "$(t TOOL_INVALID_INPUT): $choice"
            sleep 1
            show_navigation_menu "$return_target"
            ;;
    esac
}

confirm_dialog(){
    local message="$1"
    local default="${2:-n}"
    local context="${3:-install}"
    local confirm_text confirm

    echo ""
    print_color "$COLOR_YELLOW" "$message"

    if [[ "$context" == "download" ]]; then
        confirm_text="$(t DOWNLOAD_CONFIRM)"
    else
        confirm_text="$(t INSTALL_CONFIRM)"
    fi

    echo "  1) $(lang_pick "确认继续" "Confirm")"
    echo "  0) $(t BACK_MENU)"
    read -r -p "$confirm_text [1/0]: " confirm
    case "${confirm:-1}" in
        1|y|Y) return 0 ;;
        *) return 1 ;;
    esac
}

export -f show_back_prompt
export -f show_navigation_menu
export -f confirm_dialog
