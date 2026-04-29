#!/bin/bash

RUNTIME_CONFIG_FILE="${RUNTIME_CONFIG_FILE:-$CONF_DIR/timeout.conf}"

load_runtime_config(){
    local file="${1:-$RUNTIME_CONFIG_FILE}"
    [[ -f "$file" ]] || return 0
    local key value
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        key="${key%%#*}"
        key="${key//$'\r'/}"
        value="${value%%#*}"
        value="${value//$'\r'/}"
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        [[ -z "$key" ]] && continue
        case "$key" in
            REPO_PROBE_TIMEOUT|DOWNLOAD_RETRY_COUNT|DOWNLOAD_RETRY_DELAY|APT_UPDATE_TIMEOUT|DNF_QUERY_TIMEOUT|TMP_REQUIRED_GB|MIRROR_CACHE_TTL)
                export "$key=$value"
                ;;
        esac
    done < "$file"
}

load_runtime_config

export -f load_runtime_config
