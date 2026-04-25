#!/bin/bash
# UI helpers: color output, status lines, and dynamic progress bar.

COLOR_RESET="\033[0m"
COLOR_RED="\033[31m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_BLUE="\033[34m"
COLOR_CYAN="\033[36m"
COLOR_BOLD="\033[1m"

PROGRESS_TOTAL=0
PROGRESS_CURRENT=0
PROGRESS_LABEL=""
PROGRESS_ACTIVE=0
PROGRESS_LAST_WIDTH=0
PROGRESS_SPIN_INDEX=0
PROGRESS_SPINNER='|/-\'

_ui_has_tty(){
    [[ -t 1 ]]
}

lang_pick(){
    local zh="$1" en="$2"
    if [[ "${CURRENT_LANG:-zh_CN}" == "zh_CN" ]]; then
        echo "$zh"
    else
        echo "$en"
    fi
}

_ui_reset_progress_state(){
    PROGRESS_TOTAL=0
    PROGRESS_CURRENT=0
    PROGRESS_LABEL=""
    PROGRESS_ACTIVE=0
    PROGRESS_LAST_WIDTH=0
    PROGRESS_SPIN_INDEX=0
}

_ui_progress_newline_if_needed(){
    if [[ $PROGRESS_ACTIVE -eq 1 ]] && _ui_has_tty; then
        printf "\n"
        PROGRESS_ACTIVE=0
    fi
}

print_color(){
    local color="$1"
    shift
    _ui_progress_newline_if_needed
    echo -e "${color}$*${COLOR_RESET}"
}

print_success(){ print_color "$COLOR_GREEN" "[OK] $*"; }
print_error(){ print_color "$COLOR_RED" "[ERR] $*"; }
print_warning(){ print_color "$COLOR_YELLOW" "[WARN] $*"; }
print_info(){ print_color "$COLOR_CYAN" "[INFO] $*"; }

print_header(){
    _ui_progress_newline_if_needed
    echo ""
    print_color "$COLOR_BOLD$COLOR_CYAN" "============================================================"
    print_color "$COLOR_BOLD$COLOR_CYAN" "  $*"
    print_color "$COLOR_BOLD$COLOR_CYAN" "============================================================"
    echo ""
}

print_section(){
    _ui_progress_newline_if_needed
    echo ""
    print_color "$COLOR_BOLD$COLOR_BLUE" "------------------------------------------------------------"
    print_color "$COLOR_BOLD$COLOR_BLUE" "  $*"
    print_color "$COLOR_BOLD$COLOR_BLUE" "------------------------------------------------------------"
    echo ""
}

_ui_render_progress(){
    [[ $PROGRESS_TOTAL -le 0 ]] && return 0

    local percent=$((PROGRESS_CURRENT * 100 / PROGRESS_TOTAL))
    (( percent > 100 )) && percent=100
    local bar_width=36
    local filled=$((percent * bar_width / 100))
    local empty=$((bar_width - filled))
    local spin_char="${PROGRESS_SPINNER:$PROGRESS_SPIN_INDEX:1}"
    PROGRESS_SPIN_INDEX=$(((PROGRESS_SPIN_INDEX + 1) % 4))

    local bar filled_bar empty_bar line
    filled_bar=$(printf '%*s' "$filled" '' | tr ' ' '#')
    empty_bar=$(printf '%*s' "$empty" '' | tr ' ' '-')
    bar="${filled_bar}${empty_bar}"
    line="  ${PROGRESS_LABEL} ${spin_char} [${bar}] ${percent}% (${PROGRESS_CURRENT}/${PROGRESS_TOTAL})"

    if _ui_has_tty; then
        printf "\r%-*s" "$PROGRESS_LAST_WIDTH" ""
        printf "\r%s" "$line"
        PROGRESS_LAST_WIDTH=${#line}
        PROGRESS_ACTIVE=1
    else
        echo "$line"
    fi

    if [[ $PROGRESS_CURRENT -ge $PROGRESS_TOTAL ]]; then
        if _ui_has_tty; then
            printf "\n"
        fi
        PROGRESS_ACTIVE=0
    fi
}

init_progress(){
    local total="${1:-0}"
    PROGRESS_TOTAL=$((total))
    PROGRESS_CURRENT=0
    PROGRESS_LABEL="${2:-progress}"
    PROGRESS_ACTIVE=0
    PROGRESS_LAST_WIDTH=0
    PROGRESS_SPIN_INDEX=0
    [[ $PROGRESS_TOTAL -le 0 ]] && PROGRESS_TOTAL=1
    _ui_render_progress
}

update_progress(){
    local step="${1:-1}"
    local label="${2:-}"
    [[ -n "$label" ]] && PROGRESS_LABEL="$label"

    PROGRESS_CURRENT=$((PROGRESS_CURRENT + step))
    (( PROGRESS_CURRENT < 0 )) && PROGRESS_CURRENT=0
    (( PROGRESS_CURRENT > PROGRESS_TOTAL )) && PROGRESS_CURRENT=$PROGRESS_TOTAL
    _ui_render_progress
}

show_progress_complete(){
    PROGRESS_CURRENT=$PROGRESS_TOTAL
    _ui_render_progress
}

confirm_action(){
    local message="$1"
    local default="${2:-n}"
    local prompt response

    _ui_progress_newline_if_needed
    if [[ "$default" == "y" ]]; then
        prompt="${message} [Y/n]: "
        read -r -p "$(echo -e "${COLOR_YELLOW}${prompt}${COLOR_RESET}")" response
        response=${response:-y}
    else
        prompt="${message} [y/N]: "
        read -r -p "$(echo -e "${COLOR_YELLOW}${prompt}${COLOR_RESET}")" response
        response=${response:-n}
    fi

    [[ "$response" =~ ^[Yy]$ ]]
}

show_menu(){
    local title="$1"
    shift
    local -a options=("$@")
    local i

    print_section "$title"
    for i in "${!options[@]}"; do
        printf "  %2d) %s\n" "$((i+1))" "${options[$i]}"
    done
    echo ""
}

select_single(){
    local prompt="$1"
    local default="${2:-1}"
    local choice

    _ui_progress_newline_if_needed
    read -r -p "$(echo -e "${COLOR_CYAN}${prompt} [${default}]: ${COLOR_RESET}")" choice
    choice=${choice:-$default}

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -gt 0 ]]; then
        echo "$choice"
        return 0
    fi
    return 1
}

show_loading(){
    local message="${1:-loading}"
    local pid=$!
    local spin='|/-\'
    local i=0

    _ui_progress_newline_if_needed
    printf "  %b%s%b " "$COLOR_CYAN" "$message" "$COLOR_RESET"
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i + 1) % 4 ))
        printf "\b%s" "${spin:$i:1}"
        sleep 0.1
    done
    printf "\b%b[OK]%b\n" "$COLOR_GREEN" "$COLOR_RESET"
}

show_status(){
    local status="$1"
    local message="$2"
    local prefix color

    case "$status" in
        ok)    prefix="[OK]";   color="$COLOR_GREEN" ;;
        error) prefix="[ERR]";  color="$COLOR_RED" ;;
        warn)  prefix="[WARN]"; color="$COLOR_YELLOW" ;;
        info)  prefix="[INFO]"; color="$COLOR_CYAN" ;;
        skip)  prefix="[SKIP]"; color="$COLOR_BLUE" ;;
        *)     prefix="[INFO]"; color="$COLOR_CYAN" ;;
    esac
    print_color "$color" "  ${prefix} ${message}"
}

print_table_header(){
    _ui_progress_newline_if_needed
    printf "  ${COLOR_BOLD}%-32s %-15s %-10s${COLOR_RESET}\n" "Name" "Arch" "Status"
    printf "  %-32s %-15s %-10s\n" "$(printf '%0.s-' {1..32})" "$(printf '%0.s-' {1..15})" "$(printf '%0.s-' {1..10})"
}

print_table_row(){
    local name="$1" arch="$2" status="$3" color="$COLOR_RESET"
    case "$status" in
        downloaded|success|installed) color="$COLOR_GREEN" ;;
        failed|error) color="$COLOR_RED" ;;
        skipped) color="$COLOR_YELLOW" ;;
    esac
    _ui_progress_newline_if_needed
    printf "  %-32s %-15s ${color}%-10s${COLOR_RESET}\n" "$name" "$arch" "$status"
}

confirm_batch_operation(){
    local operation="$1"
    local count="$2"
    print_section "Batch confirmation"
    print_info "Operation: $operation"
    print_info "Items: $count"
    confirm_action "Continue?" "n"
}

show_error_detail(){
    local error_type="$1"
    local error_msg="$2"
    local suggestion="$3"
    print_section "Error: $error_type"
    print_error "$error_msg"
    [[ -n "$suggestion" ]] && print_warning "$suggestion"
}

export -f print_color
export -f print_success
export -f print_error
export -f print_warning
export -f print_info
export -f print_header
export -f print_section
export -f init_progress
export -f update_progress
export -f show_progress_complete
export -f confirm_action
export -f show_menu
export -f select_single
export -f show_loading
export -f show_status
export -f print_table_header
export -f print_table_row
export -f confirm_batch_operation
export -f show_error_detail
export -f lang_pick
