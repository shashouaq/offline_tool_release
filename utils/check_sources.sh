#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
CONF_FILE="${1:-$ROOT_DIR/conf/os_sources.conf}"
LOG_DIR="$ROOT_DIR/logs"
TIMEOUT="${SOURCE_CHECK_TIMEOUT:-10}"
DEFAULT_RPM_ARCHES="${SOURCE_CHECK_RPM_ARCHES:-x86_64 aarch64}"

mkdir -p "$LOG_DIR"
OUT_FILE="$LOG_DIR/source_check_$(date '+%Y%m%d_%H%M%S').tsv"

trim(){
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

probe_url(){
    local url="$1"
    curl -fsSLk --retry 2 --retry-delay 1 --retry-all-errors --max-time "$TIMEOUT" -o /dev/null "$url" >/dev/null 2>&1
}

check_one_repo(){
    local os="$1" pkg_type="$2" release="$3" arch="$4" repo="$5"
    local expanded probe status="FAIL"

    expanded="${repo//\$ARCH/$arch}"
    expanded="${expanded//\$RELEASEVER/$release}"

    if [[ "$pkg_type" == "rpm" ]]; then
        probe="${expanded%/}/repodata/repomd.xml"
        probe_url "$probe" && status="OK"
    else
        probe="${expanded%/}/dists/${release}/InRelease"
        if probe_url "$probe"; then
            status="OK"
        else
            probe="${expanded%/}/dists/${release}/Release"
            probe_url "$probe" && status="OK"
        fi
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$status" "$os" "$pkg_type" "${arch:-native}" "$probe" "$expanded" | tee -a "$OUT_FILE" >/dev/null
    [[ "$status" == "OK" ]]
}

flush_section(){
    local arch repo ok=0 fail=0
    [[ -n "${section:-}" ]] || return 0
    [[ ${#repos[@]} -gt 0 ]] || return 0

    if [[ "$pkg_type" == "rpm" ]]; then
        local arches="${supported_arches:-$DEFAULT_RPM_ARCHES}"
        for arch in $arches; do
            for repo in "${repos[@]}"; do
                if check_one_repo "$section" "$pkg_type" "$releasever" "$arch" "$repo"; then
                    ok=$((ok + 1))
                else
                    fail=$((fail + 1))
                fi
            done
        done
    else
        for repo in "${repos[@]}"; do
            if check_one_repo "$section" "$pkg_type" "$releasever" "" "$repo"; then
                ok=$((ok + 1))
            else
                fail=$((fail + 1))
            fi
        done
    fi

    section_ok=$((section_ok + ok))
    section_fail=$((section_fail + fail))
}

if [[ ! -f "$CONF_FILE" ]]; then
    echo "[source-check] config not found: $CONF_FILE" >&2
    exit 2
fi

printf 'status\tos\tpkg_type\tarch\tprobe_url\trepo_url\n' > "$OUT_FILE"

section=""
pkg_type=""
releasever=""
supported_arches=""
repos=()
section_ok=0
section_fail=0

while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue

    if [[ "$line" =~ ^\[([A-Za-z0-9._-]+)\]$ ]]; then
        flush_section
        section="${BASH_REMATCH[1]}"
        pkg_type=""
        releasever=""
        supported_arches=""
        repos=()
        continue
    fi

    if [[ "$line" =~ ^PKG_TYPE=(.+)$ ]]; then
        pkg_type="$(trim "${BASH_REMATCH[1]}")"
    elif [[ "$line" =~ ^RELEASEVER=(.+)$ ]]; then
        releasever="$(trim "${BASH_REMATCH[1]}")"
    elif [[ "$line" =~ ^SUPPORTED_ARCHES=(.+)$ ]]; then
        supported_arches="$(trim "${BASH_REMATCH[1]}")"
    elif [[ "$line" =~ \"([^\"]+)\" ]]; then
        repos+=("${BASH_REMATCH[1]}")
    fi
done < "$CONF_FILE"
flush_section

echo "[source-check] result: $OUT_FILE"
echo "[source-check] ok=$section_ok failed=$section_fail"

if [[ $section_fail -gt 0 ]]; then
    exit 1
fi
