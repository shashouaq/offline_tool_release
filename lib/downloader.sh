#!/bin/bash
# Download manager for offline package bundles.

DOWNLOAD_CACHE_DIR="/tmp/offline_tools_download_cache"
MAX_PARALLEL_DOWNLOADS=${MAX_PARALLEL_DOWNLOADS:-3}
declare -a DOWNLOAD_QUEUE=()
declare -A DOWNLOAD_STATUS=()
declare -A DOWNLOAD_FAIL_REASON=()
declare -A DOWNLOAD_FAIL_DETAIL=()
LAST_DOWNLOAD_EVENT=""
DOWNLOAD_ANIMATE=${DOWNLOAD_ANIMATE:-0}
DOWNLOAD_SOURCE_LABEL=""

is_rpm_package_group(){
    local name="$1"
    [[ "$name" == @* ]] || [[ "$name" =~ -(environment|desktop|group)$ ]]
}

rpm_group_name(){
    local name="$1"
    echo "${name#@}"
}

make_dnf_task_dir(){
    local label="$1"
    local safe_label
    safe_label=$(echo "$label" | tr -c 'A-Za-z0-9._-' '_')
    mktemp -d "$WORK_DIR/dnf_${safe_label}_XXXXXX"
}

verify_download_safety(){
    local cmd_type="$1"
    if [[ "$cmd_type" == "dnf" ]]; then
        command -v dnf &>/dev/null || { echo "[safety] ERROR: dnf not found" >> "$LOG_FILE"; return 1; }
        echo "[safety] dnf download-only mode" >> "$LOG_FILE"
    elif [[ "$cmd_type" == "apt" ]]; then
        command -v apt-get &>/dev/null || { echo "[safety] ERROR: apt-get not found" >> "$LOG_FILE"; return 1; }
        echo "[safety] apt download-only mode" >> "$LOG_FILE"
    fi
    return 0
}

classify_download_failure(){
    local tool="$1" pkg_type="$2" repo_file="$3" release_ver="$4" forcearch="$5"
    local reason="UNKNOWN" detail="unknown error"

    if [[ "$pkg_type" == "rpm" ]]; then
        local cur_arch fa_arg out rc
        cur_arch=$(uname -m)
        fa_arg=""
        if [[ -n "$forcearch" && "$forcearch" != "$cur_arch" ]]; then
            fa_arg="--forcearch=$forcearch"
        fi
        out=$(dnf repoquery --config="$repo_file" --disablerepo='*' --enablerepo='offline-temp' --releasever="$release_ver" $fa_arg "$tool" 2>&1)
        rc=$?
        if echo "$out" | grep -qiE "No match for argument|Unable to find a match|No matching Packages to list"; then
            reason="PACKAGE_OR_GROUP_NOT_FOUND"
            detail="package/group not found in enabled repos"
        elif [[ $rc -eq 0 ]] && [[ -z "$(echo "$out" | grep -E '^[A-Za-z0-9_.+-]+\\.' | head -n1)" ]]; then
            # repoquery sometimes returns rc=0 with empty/non-package output for missing names.
            reason="PACKAGE_OR_GROUP_NOT_FOUND"
            detail="package/group not found in enabled repos (empty repoquery result)"
        elif [[ $rc -ne 0 ]]; then
            if echo "$out" | grep -qiE "Config file .* does not exist|Cannot open file|failed loading|No such file"; then
                reason="REPO_CONFIG_ERROR"
                detail="$(echo "$out" | tail -n 1 | tr -d '\r')"
            elif echo "$out" | grep -qiE "No match for argument|Unable to find a match|No matching Packages to list"; then
                reason="PACKAGE_OR_GROUP_NOT_FOUND"
                detail="package/group not found in enabled repos"
            elif echo "$out" | grep -qiE "Could not resolve host|Cannot download repomd|All mirrors were tried|Timeout|SSL|curl error|failed to download"; then
                reason="SOURCE_UNREACHABLE"
                detail="mirror unreachable or metadata fetch failed"
            else
                reason="REPO_QUERY_FAILED"
                detail="$(echo "$out" | tail -n 1 | tr -d '\r')"
            fi
        else
            reason="DEPENDENCY_RESOLVE_FAILED"
            detail="package exists but dependency resolution/download failed"
        fi
    else
        local out rc
        out=$(apt-cache policy "$tool" 2>&1)
        rc=$?
        if [[ $rc -ne 0 ]] || echo "$out" | grep -qi "Unable to locate package"; then
            reason="PACKAGE_NOT_FOUND"
            detail="package not found in apt sources"
        elif echo "$out" | grep -qiE "Temporary failure resolving|Connection failed|Could not resolve|404"; then
            reason="SOURCE_UNREACHABLE"
            detail="apt source unreachable"
        else
            reason="APT_DOWNLOAD_FAILED"
            detail="$(echo "$out" | tail -n 1 | tr -d '\r')"
        fi
    fi

    DOWNLOAD_FAIL_REASON["$tool"]="$reason"
    DOWNLOAD_FAIL_DETAIL["$tool"]="$detail"
    log_event "WARN" "download" "classify_failure" "$tool" "reason=$reason" "detail=$detail"
}

init_download_cache(){
    mkdir -p "$DOWNLOAD_CACHE_DIR"
    log "[cache] download cache: $DOWNLOAD_CACHE_DIR"
    if [[ "$PKG_TYPE" == "rpm" ]]; then
        verify_download_safety dnf || log "[WARN] dnf safety check failed"
    else
        verify_download_safety apt || log "[WARN] apt safety check failed"
    fi
}

reset_download_state(){
    DOWNLOAD_QUEUE=()
    DOWNLOAD_STATUS=()
    DOWNLOAD_FAIL_REASON=()
    DOWNLOAD_FAIL_DETAIL=()
    LAST_DOWNLOAD_EVENT=""
}

check_cache(){
    local pkg_name="$1"
    [[ -f "$DOWNLOAD_CACHE_DIR/${pkg_name}.cached" ]]
}

add_to_cache(){
    local pkg_name="$1"
    mkdir -p "$DOWNLOAD_CACHE_DIR"
    touch "$DOWNLOAD_CACHE_DIR/${pkg_name}.cached"
    echo "[$(date '+%F %T')] [cache] $pkg_name" >> "$LOG_FILE"
}

clear_download_cache(){
    rm -rf "$DOWNLOAD_CACHE_DIR"
    mkdir -p "$DOWNLOAD_CACHE_DIR"
    log "[cache] cleared"
}

validate_rpm_group_installable(){
    local group_name="$1"
    local repo_file="$2"
    local release_ver="$3"
    local forcearch="$4"
    local stage="${5:-download}"
    local cur_arch fa_arg group_list check_output

    cur_arch=$(uname -m)
    fa_arg=""
    if [[ -n "$forcearch" && "$forcearch" != "$cur_arch" ]]; then
        fa_arg="--forcearch=$forcearch"
    fi

    group_list=$(dnf group list --config="$repo_file" --disablerepo='*' --enablerepo='offline-temp' --releasever="$release_ver" $fa_arg 2>&1)
    if ! echo "$group_list" | grep -qiE "(^|[[:space:]])\\(${group_name}\\)($|[[:space:]])|(^|[[:space:]])${group_name}($|[[:space:]])"; then
        echo "[$(date '+%F %T')] [verify] RPM group id not found: $group_name (stage=$stage)" >> "$LOG_FILE"
        if [[ "$stage" != "precheck" || "${OFFLINE_TOOLS_VERBOSE_VERIFY:-0}" == "1" ]]; then
            echo "$group_list" >> "$LOG_FILE"
        fi
        return 1
    fi

    check_output=$(dnf group info --config="$repo_file" --disablerepo='*' --enablerepo='offline-temp' --releasever="$release_ver" $fa_arg "$group_name" 2>&1)
    if echo "$check_output" | grep -qiE "(no such group|no groups matched|is not available|nothing to do|error:)"; then
        echo "[$(date '+%F %T')] [verify] RPM group is not installable: $group_name (stage=$stage)" >> "$LOG_FILE"
        if [[ "$stage" != "precheck" || "${OFFLINE_TOOLS_VERBOSE_VERIFY:-0}" == "1" ]]; then
            echo "$check_output" >> "$LOG_FILE"
        fi
        return 1
    fi

    return 0
}

download_rpm_package(){
    local pkg="$1" repo_file="$2" pkg_dir="$3" release_ver="$4" forcearch="$5"
    local cur_arch fa_arg
    cur_arch=$(uname -m)
    fa_arg=""
    if [[ -n "$forcearch" && "$forcearch" != "$cur_arch" ]]; then
        fa_arg="--forcearch=$forcearch"
    fi

    if [[ "$pkg" == *"*"* || "$pkg" == *"?"* ]]; then
        local matches=()
        while IFS= read -r line; do
            [[ "$line" =~ ^([A-Za-z0-9._+-]+)\. ]] && matches+=("${BASH_REMATCH[1]}")
        done < <(dnf search --config="$repo_file" --disablerepo='*' --enablerepo='offline-temp' --releasever="$release_ver" $fa_arg "$pkg" 2>/dev/null)
        [[ ${#matches[@]} -eq 0 ]] && return 2
        local rc=0
        for match in "${matches[@]}"; do
            dnf download \
                --config="$repo_file" \
                --disablerepo='*' \
                --enablerepo='offline-temp' \
                --releasever="$release_ver" \
                $fa_arg \
                --resolve \
                --alldeps \
                --destdir="$pkg_dir" \
                "$match" >> "$LOG_FILE" 2>&1 && continue

            local task_dir fake_root dnf_cache
            task_dir=$(make_dnf_task_dir "$match")
            fake_root="$task_dir/installroot"
            dnf_cache="$task_dir/cache"
            mkdir -p "$fake_root" "$dnf_cache"
            dnf install \
                --config="$repo_file" \
                --disablerepo='*' \
                --enablerepo='offline-temp' \
                --releasever="$release_ver" \
                $fa_arg \
                --setopt=cachedir="$dnf_cache" \
                --installroot="$fake_root" \
                --downloadonly \
                --downloaddir="$pkg_dir" \
                --allowerasing \
                --best \
                -y \
                "$match" >> "$LOG_FILE" 2>&1 || rc=$?
            rm -rf "$task_dir"
        done
        return $rc
    fi

    if is_rpm_package_group "$pkg"; then
        local group_name task_dir fake_root dnf_cache rc=0
        group_name=$(rpm_group_name "$pkg")
        validate_rpm_group_installable "$group_name" "$repo_file" "$release_ver" "$forcearch" "download" || return 2
        task_dir=$(make_dnf_task_dir "$group_name")
        fake_root="$task_dir/installroot"
        dnf_cache="$task_dir/cache"
        mkdir -p "$fake_root" "$dnf_cache"
        dnf group install --config="$repo_file" --releasever="$release_ver" $fa_arg --setopt=cachedir="$dnf_cache" --installroot="$fake_root" --downloadonly --downloaddir="$pkg_dir" --allowerasing --best -y "$group_name" >> "$LOG_FILE" 2>&1 || rc=$?
        rm -rf "$task_dir"
        return $rc
    fi

    dnf repoquery --config="$repo_file" --disablerepo='*' --enablerepo='offline-temp' --releasever="$release_ver" $fa_arg "$pkg" &>/dev/null || return 2

    dnf download \
        --config="$repo_file" \
        --disablerepo='*' \
        --enablerepo='offline-temp' \
        --releasever="$release_ver" \
        $fa_arg \
        --resolve \
        --alldeps \
        --destdir="$pkg_dir" \
        "$pkg" >> "$LOG_FILE" 2>&1 && return 0

    local task_dir fake_root dnf_cache rc=0
    task_dir=$(make_dnf_task_dir "$pkg")
    fake_root="$task_dir/installroot"
    dnf_cache="$task_dir/cache"
    mkdir -p "$fake_root" "$dnf_cache"

    dnf install \
        --config="$repo_file" \
        --disablerepo='*' \
        --enablerepo='offline-temp' \
        --releasever="$release_ver" \
        $fa_arg \
        --setopt=cachedir="$dnf_cache" \
        --installroot="$fake_root" \
        --downloadonly \
        --downloaddir="$pkg_dir" \
        --allowerasing \
        --best \
        -y \
        "$pkg" >> "$LOG_FILE" 2>&1 || rc=$?

    rm -rf "$task_dir"
    return $rc
}

download_deb_package(){
    local pkg="$1" pkg_dir="$2"
    command -v apt-get &>/dev/null || return 1
    local targets=("$pkg")
    if command -v apt-cache &>/dev/null; then
        while IFS= read -r dep; do
            [[ -n "$dep" ]] && targets+=("$dep")
        done < <(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances "$pkg" 2>/dev/null | awk '/^[A-Za-z0-9][A-Za-z0-9+._:-]+$/ {print $1}' | sort -u)
    fi
    local rc=0
    for target in "${targets[@]}"; do
        (cd "$pkg_dir" && apt-get download "$target" >> "$LOG_FILE" 2>&1) || rc=$?
    done
    return $rc
}

download_single_package(){
    local tool="$1" repo_file="$2" pkg_dir="$3" pkg_type="$4" release_ver="$5" forcearch="$6"
    local max_retries=3 retry_count=0
    mkdir -p "$pkg_dir"

    while [[ $retry_count -lt $max_retries ]]; do
        ((retry_count++))
        echo "[$(date '+%F %T')] [download $retry_count/$max_retries] $tool" >> "$LOG_FILE"
        local prev_count new_count downloaded rc=0
        prev_count=$(find "$pkg_dir" -type f \( -name '*.rpm' -o -name '*.deb' \) 2>/dev/null | wc -l)

        if [[ "$DOWNLOAD_ANIMATE" == "1" ]]; then
            if [[ "$pkg_type" == "rpm" ]]; then
                ( download_rpm_package "$tool" "$repo_file" "$pkg_dir" "$release_ver" "$forcearch" ) &
            else
                ( download_deb_package "$tool" "$pkg_dir" ) &
            fi
            local dpid=$!
            while kill -0 "$dpid" 2>/dev/null; do
                update_progress 0 "download ($tool @ ${DOWNLOAD_SOURCE_LABEL}, try ${retry_count}/${max_retries})"
                sleep 0.2
            done
            wait "$dpid" || rc=$?
        else
            if [[ "$pkg_type" == "rpm" ]]; then
                download_rpm_package "$tool" "$repo_file" "$pkg_dir" "$release_ver" "$forcearch" || rc=$?
            else
                download_deb_package "$tool" "$pkg_dir" || rc=$?
            fi
        fi

        new_count=$(find "$pkg_dir" -type f \( -name '*.rpm' -o -name '*.deb' \) 2>/dev/null | wc -l)
        downloaded=$((new_count - prev_count))
        if [[ $rc -eq 0 && $downloaded -gt 0 ]]; then
            add_to_cache "$tool"
            echo "[$(date '+%F %T')] [download] success: $tool, files=$downloaded" >> "$LOG_FILE"
            DOWNLOAD_FAIL_REASON["$tool"]=""
            DOWNLOAD_FAIL_DETAIL["$tool"]=""
            DOWNLOAD_STATUS["$tool"]="success"
            return 0
        fi
        [[ $rc -eq 2 ]] && { classify_download_failure "$tool" "$pkg_type" "$repo_file" "$release_ver" "$forcearch"; return 2; }
        sleep 2
    done

    echo "[$(date '+%F %T')] [download] failed after retries: $tool" >> "$LOG_FILE"
    classify_download_failure "$tool" "$pkg_type" "$repo_file" "$release_ver" "$forcearch"
    DOWNLOAD_STATUS["$tool"]="failed"
    return 1
}

wait_for_one_download(){
    local -n pids_ref=$1
    local -n pid_map_ref=$2
    local -n success_ref=$3
    local -n failed_ref=$4
    local -n failed_list_ref=$5
    [[ ${#pids_ref[@]} -eq 0 ]] && return 0
    local pid="${pids_ref[0]}" key="pid_${pids_ref[0]}" tool="${pid_map_ref[$key]:-}" rc=0
    wait "$pid" || rc=$?
    log "[download/wait] pid=$pid tool=${tool:-unknown} rc=$rc"
    if [[ $rc -eq 0 ]]; then
        DOWNLOAD_STATUS[$tool]="success"
        ((success_ref++))
        LAST_DOWNLOAD_EVENT="ok:$tool"
    else
        DOWNLOAD_STATUS[$tool]="failed"
        ((failed_ref++))
        failed_list_ref+=("$tool")
        LAST_DOWNLOAD_EVENT="error:$tool"
    fi
    unset 'pid_map_ref[$key]'
    unset 'pids_ref[0]'
    pids_ref=("${pids_ref[@]}")
}

download_parallel(){
    local -a tools=("$@") pids=() failed_tools_list=()
    local -A pid_to_tool=()
    local success=0 failed=0
    log "[download] parallel start: ${#tools[@]} items, max=$MAX_PARALLEL_DOWNLOADS"
    DOWNLOAD_ANIMATE=0
    init_progress "${#tools[@]}" "download"
    for tool in "${tools[@]}"; do
        while [[ ${#pids[@]} -ge $MAX_PARALLEL_DOWNLOADS ]]; do
            wait_for_one_download pids pid_to_tool success failed failed_tools_list
            if [[ "$LAST_DOWNLOAD_EVENT" == ok:* ]]; then
                update_progress 1 "download (${LAST_DOWNLOAD_EVENT#ok:})"
            else
                update_progress 1 "download (${LAST_DOWNLOAD_EVENT#error:}, failed)"
            fi
        done
        ( download_single_package "$tool" "$TEMP_REPO_FILE" "$PKG_DIR" "$PKG_TYPE" "$RELEASE_VER" "$FORCEARCH" ) &
        local pid=$!
        pids+=("$pid")
        pid_to_tool["pid_$pid"]="$tool"
        DOWNLOAD_STATUS[$tool]="downloading"
        log "[download] started $tool pid=$pid"
    done
    while [[ ${#pids[@]} -gt 0 ]]; do
        wait_for_one_download pids pid_to_tool success failed failed_tools_list
        if [[ "$LAST_DOWNLOAD_EVENT" == ok:* ]]; then
            update_progress 1 "download (${LAST_DOWNLOAD_EVENT#ok:})"
        else
            update_progress 1 "download (${LAST_DOWNLOAD_EVENT#error:}, failed)"
        fi
    done
    # Recalculate from status map to avoid stale/misbound per-PID accounting.
    success=0
    failed=0
    failed_tools_list=()
    local t st
    for t in "${tools[@]}"; do
        st="${DOWNLOAD_STATUS[$t]:-unknown}"
        case "$st" in
            success) ((success++)) ;;
            failed) ((failed++)); failed_tools_list+=("$t") ;;
            *)
                ((failed++))
                failed_tools_list+=("$t")
                DOWNLOAD_STATUS[$t]="failed"
                ;;
        esac
    done

    log "[download] complete: success=$success failed=$failed"
    [[ $failed -gt 0 ]] && log "[download] failed items: ${failed_tools_list[*]}"
    [[ $failed -eq 0 ]]
}

download_sequential(){
    local -a tools=("$@") failed_list=()
    local success=0 failed=0
    log "[download] sequential start: ${#tools[@]} items"
    DOWNLOAD_ANIMATE=1
    init_progress "${#tools[@]}" "download"
    for tool in "${tools[@]}"; do
        if download_single_package "$tool" "$TEMP_REPO_FILE" "$PKG_DIR" "$PKG_TYPE" "$RELEASE_VER" "$FORCEARCH"; then
            ((success++))
            DOWNLOAD_STATUS[$tool]="success"
            update_progress 1 "download ($tool)"
        else
            failed_list+=("$tool")
            ((failed++))
            DOWNLOAD_STATUS[$tool]="failed"
            update_progress 1 "download ($tool, failed)"
            show_status error "$tool"
        fi
    done
    log "[download] complete: success=$success failed=$failed"
    [[ $failed -eq 0 ]]
}

smart_download(){
    local -a tools=("$@")
    if [[ ${#tools[@]} -ge 5 ]]; then
        download_parallel "${tools[@]}"
    else
        download_sequential "${tools[@]}"
    fi
}

export -f is_rpm_package_group rpm_group_name make_dnf_task_dir validate_rpm_group_installable
export -f verify_download_safety init_download_cache check_cache add_to_cache clear_download_cache
export -f reset_download_state
export -f download_rpm_package download_deb_package download_single_package
export -f wait_for_one_download download_parallel download_sequential smart_download
export -f classify_download_failure
