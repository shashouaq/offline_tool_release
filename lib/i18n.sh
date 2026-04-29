#!/bin/bash
# Fast i18n helper. Language files are loaded once per language.

CURRENT_LANG="${CURRENT_LANG:-zh_CN}"
LANG_DIR="${LANG_DIR:-}"
declare -gA I18N_TEXT=()
I18N_LOADED_LANG=""

get_lang_dir(){
    if [[ -z "$LANG_DIR" ]]; then
        if [[ -n "${BASE_DIR:-}" && -d "$BASE_DIR/conf/lang" ]]; then
            LANG_DIR="$BASE_DIR/conf/lang"
        else
            LANG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)/conf/lang"
        fi
    fi
    echo "$LANG_DIR"
}

trim_i18n_value(){
    local value="$1"
    value="${value//$'\r'/}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    echo "$value"
}

load_language_cache(){
    local lang="${1:-$CURRENT_LANG}"
    local lang_dir lang_file k v
    lang_dir=$(get_lang_dir)
    lang_file="$lang_dir/${lang}.conf"

    if [[ ! -f "$lang_file" ]]; then
        lang="zh_CN"
        lang_file="$lang_dir/zh_CN.conf"
    fi

    [[ "$I18N_LOADED_LANG" == "$lang" && ${#I18N_TEXT[@]} -gt 0 ]] && return 0

    I18N_TEXT=()
    while IFS='=' read -r k v || [[ -n "$k" ]]; do
        k=$(trim_i18n_value "$k")
        [[ -z "$k" || "$k" == \#* ]] && continue
        [[ -n "${I18N_TEXT[$k]+x}" ]] && continue
        I18N_TEXT["$k"]="$(trim_i18n_value "$v")"
    done < "$lang_file"

    I18N_LOADED_LANG="$lang"
    CURRENT_LANG="$lang"
}

t(){
    local key="$1"
    if [[ "$I18N_LOADED_LANG" != "$CURRENT_LANG" || ${#I18N_TEXT[@]} -eq 0 ]]; then
        load_language_cache "$CURRENT_LANG"
    fi
    echo "${I18N_TEXT[$key]:-$key}"
}

get_text(){
    t "$@"
}

set_language(){
    local lang="$1"
    case "$lang" in
        zh|zh_CN|chinese|cn)
            CURRENT_LANG="zh_CN"
            ;;
        en|en_US|english)
            CURRENT_LANG="en_US"
            ;;
        *)
            CURRENT_LANG="zh_CN"
            ;;
    esac

    I18N_LOADED_LANG=""
    load_language_cache "$CURRENT_LANG"
    echo "$CURRENT_LANG" > /tmp/offline_tools_lang_state.txt
}

get_current_language(){
    echo "$CURRENT_LANG"
}

show_language_menu(){
    echo ""
    echo "========================================"
    echo "  $(t LANG_SELECT_TITLE)"
    echo "========================================"
    echo ""
    echo "  1) $(t LANG_ZH)"
    echo "  2) $(t LANG_EN)"
    echo "  0) $(t MENU_EXIT)"
    echo ""
    read -r -p "$(t LANG_SELECT_PROMPT) [1/2/0]: " lang_choice
    lang_choice=${lang_choice:-1}

    case "$lang_choice" in
        1) set_language "zh_CN" ;;
        2) set_language "en_US" ;;
        0) return 1 ;;
        *) set_language "zh_CN" ;;
    esac

    echo ""
    echo "  $(t STATUS_OK) $(t LANG_SELECTED): $CURRENT_LANG"
}

init_language(){
    case "${OFFLINE_TOOLS_LANG:-${CURRENT_LANG:-zh_CN}}" in
        en|en_US|english)
            CURRENT_LANG="en_US"
            ;;
        *)
            CURRENT_LANG="zh_CN"
            ;;
    esac
    I18N_LOADED_LANG=""
    load_language_cache "$CURRENT_LANG"
}

export -f get_lang_dir
export -f trim_i18n_value
export -f load_language_cache
export -f t
export -f get_text
export -f set_language
export -f get_current_language
export -f show_language_menu
export -f init_language
