#!/bin/bash
# Unified structured logger for all actions.

LOG_LEVEL_INFO="INFO"
LOG_LEVEL_WARN="WARN"
LOG_LEVEL_ERROR="ERROR"
LOG_LEVEL_DEBUG="DEBUG"
LOG_LEVEL_MENU="MENU"
LOG_LEVEL_INTERACTION="INTERACTION"

LOG_SESSION_ID="${LOG_SESSION_ID:-$(date +%Y%m%d%H%M%S)-$$}"
LOG_SEQ=0

_log_ts(){
    date '+%F %T'
}

_log_next_seq(){
    LOG_SEQ=$((LOG_SEQ + 1))
    echo "$LOG_SEQ"
}

_log_write(){
    local line="$1"
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "$line" >> "$LOG_FILE"
    else
        echo "$line" >&2
    fi
}

log_event(){
    local level="$1" stage="$2" action="$3" message="$4"
    shift 4
    local seq ts kv_part=""
    seq=$(_log_next_seq)
    ts=$(_log_ts)

    if [[ $# -gt 0 ]]; then
        kv_part=" | $*"
    fi

    _log_write "[$ts] [$level] [${stage}/${action}] #${seq} sid=${LOG_SESSION_ID} ${message}${kv_part}"
}

log(){
    local message="$*"
    log_event "$LOG_LEVEL_INFO" "general" "note" "$message"
}

log_interaction(){
    local action="$1" detail="$2"
    log_event "$LOG_LEVEL_INTERACTION" "ui" "$action" "$detail"
}

log_menu_selection(){
    local menu_name="$1" selection="$2" description="${3:-}"
    log_event "$LOG_LEVEL_MENU" "menu" "$menu_name" "selection" "choice=$selection" "desc=${description:-none}"
}

log_user_input(){
    local prompt="$1" value="$2"
    if [[ "$prompt" =~ [Pp]assword|[Ss]ecret|[Tt]oken|[Kk]ey ]]; then
        value="***SENSITIVE***"
    fi
    [[ ${#value} -gt 200 ]] && value="${value:0:200}...(truncated)"
    log_event "$LOG_LEVEL_INTERACTION" "input" "capture" "user input" "prompt=$prompt" "value=$value"
}

log_download(){
    local action="$1" tool="$2" detail="${3:-}"
    log_event "$LOG_LEVEL_INFO" "download" "$action" "$tool" "detail=${detail:-none}"
}

log_install(){
    local action="$1" package="$2" method="${3:-}"
    log_event "$LOG_LEVEL_INFO" "install" "$action" "$package" "method=${method:-unknown}"
}

log_system_state(){
    local component="$1" status="$2" detail="${3:-}"
    log_event "$LOG_LEVEL_INFO" "system" "$component" "$status" "detail=${detail:-none}"
}

log_error_detail(){
    local error_type="$1" message="$2" context="${3:-}" suggestion="${4:-}"
    log_event "$LOG_LEVEL_ERROR" "error" "$error_type" "$message" "context=${context:-none}" "suggestion=${suggestion:-none}"
}

log_performance(){
    local operation="$1" duration_ms="$2" detail="${3:-}"
    log_event "$LOG_LEVEL_DEBUG" "perf" "$operation" "timing" "duration_ms=$duration_ms" "detail=${detail:-none}"
}

log_action_begin(){
    local stage="$1" action="$2"
    log_event "$LOG_LEVEL_INFO" "$stage" "$action" "begin"
}

log_action_end(){
    local stage="$1" action="$2" result="${3:-ok}" detail="${4:-}"
    log_event "$LOG_LEVEL_INFO" "$stage" "$action" "end" "result=$result" "detail=${detail:-none}"
}

log_session_start(){
    local user host arch kernel
    user=$(whoami 2>/dev/null || echo "unknown")
    host=$(hostname 2>/dev/null || echo "unknown")
    arch=$(uname -m 2>/dev/null || echo "unknown")
    kernel=$(uname -r 2>/dev/null || echo "unknown")
    log_event "$LOG_LEVEL_INFO" "session" "start" "session start" "user=${user}@${host}" "arch=$arch" "kernel=$kernel"
}

log_session_end(){
    local exit_code="${1:-0}"
    log_event "$LOG_LEVEL_INFO" "session" "end" "session end" "exit_code=$exit_code"
}

export -f log_event
export -f log
export -f log_interaction
export -f log_menu_selection
export -f log_user_input
export -f log_download
export -f log_install
export -f log_system_state
export -f log_error_detail
export -f log_performance
export -f log_action_begin
export -f log_action_end
export -f log_session_start
export -f log_session_end

