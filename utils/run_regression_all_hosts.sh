#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
PROJECT_NAME="offline_tool_release"
REMOTE_BASE="/tmp/${PROJECT_NAME}"

SSH_USER="${SSH_USER:-root}"
SSH_PASS="${SSH_PASS:-Hkzy@8000}"
SSH_PORT="${SSH_PORT:-22}"
MAX_PARALLEL="${MAX_PARALLEL:-4}"

RESULT_DIR="${ROOT_DIR}/logs/remote_regression"
RESULT_TSV="${RESULT_DIR}/results_$(date +%Y%m%d_%H%M%S).tsv"
SUMMARY_DOC="${ROOT_DIR}/docs/test-findings.md"

# label|ip|family(rpm/deb)
HOSTS=(
  "rpm_online|172.18.10.61|rpm"
  "deb_online|172.18.10.62|deb"
  "rpm_offline|172.18.10.64|rpm"
  "deb_offline|172.18.10.65|deb"
)

need_cmd(){
  command -v "$1" >/dev/null 2>&1 || { echo "[all-hosts] missing command: $1"; exit 2; }
}

run_remote(){
  local host="$1" cmd="$2"
  sshpass -p "$SSH_PASS" ssh -p "$SSH_PORT" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "${SSH_USER}@${host}" "$cmd"
}

copy_to_remote(){
  local host="$1"
  sshpass -p "$SSH_PASS" scp -P "$SSH_PORT" -q -r \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$ROOT_DIR" "${SSH_USER}@${host}:${REMOTE_BASE}_incoming"
}

prepare_remote(){
  local host="$1" family="$2"
  run_remote "$host" "rm -rf '${REMOTE_BASE}' '${REMOTE_BASE}_incoming' && mkdir -p '${REMOTE_BASE}'"
  copy_to_remote "$host"
  run_remote "$host" "mv '${REMOTE_BASE}_incoming' '${REMOTE_BASE}'"

  if [[ "$family" == "rpm" ]]; then
    run_remote "$host" "command -v expect >/dev/null 2>&1 || (dnf install -y expect || yum install -y expect)"
  else
    run_remote "$host" "command -v expect >/dev/null 2>&1 || (apt-get update -y && apt-get install -y expect)"
  fi
}

run_one_host(){
  local label="$1" host="$2" family="$3"
  local out_file="${RESULT_DIR}/${label}_$(date +%Y%m%d_%H%M%S).log"
  local status="PASS"

  {
    echo "[all-hosts] host=${host} label=${label} family=${family}"
    echo "[all-hosts] time=$(date '+%F %T')"
    prepare_remote "$host" "$family"
    run_remote "$host" "cd '${REMOTE_BASE}' && chmod +x ./utils/run_menu_regression.sh ./offline_tools_v1.sh && ./utils/run_menu_regression.sh"
    run_remote "$host" "cd '${REMOTE_BASE}' && if ls logs/*.log >/dev/null 2>&1; then tail -n 200 logs/*.log; fi"
  } >"$out_file" 2>&1 || status="FAIL"

  local menu_hits err_hits
  menu_hits="$(grep -Eci 'dep_check/menu_render|Environment self-check|Select \[1/2/0\]|PASS: menu visibility regression' "$out_file" || true)"
  err_hits="$(grep -Eci 'FAIL|failed|ERROR|invalid_input' "$out_file" || true)"

  printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$label" "$host" "$family" "$status" "$menu_hits" "$out_file" >> "$RESULT_TSV"
  if [[ "$status" == "PASS" ]]; then
    echo "[all-hosts] PASS: ${label} (${host})"
  else
    echo "[all-hosts] FAIL: ${label} (${host})"
  fi
  echo "[all-hosts] log: $out_file (menu_hits=$menu_hits err_hits=$err_hits)"
}

append_summary(){
  local round_id="remote-regression-$(date +%Y%m%d_%H%M%S)"
  local passed failed
  passed="$(awk -F'\t' '$4=="PASS"{c++} END{print c+0}' "$RESULT_TSV")"
  failed="$(awk -F'\t' '$4=="FAIL"{c++} END{print c+0}' "$RESULT_TSV")"

  {
    echo ""
    echo "### Round: ${round_id}"
    echo "- Environment:"
    echo "  - OS: mixed (4 hosts)"
    echo "  - Arch: mixed"
    echo "  - Online/Offline: mixed"
    echo "- Build/Script version: offline_tools_v1.sh"
    echo "- Test scope: remote menu regression all hosts"
    echo "- Result summary:"
    while IFS=$'\t' read -r label host family status menu_hits log_file; do
      [[ -z "${label:-}" ]] && continue
      echo "  - ${label}(${host},${family}): status=${status}, menu_hits=${menu_hits}"
    done < "$RESULT_TSV"
    echo "  - Passed: ${passed}"
    echo "  - Failed: ${failed}"
    echo "- Failures:"
    echo "  1. Symptom: see status=FAIL entries"
    echo "  2. Repro steps: rerun utils/run_regression_all_hosts.sh with same host set"
    echo "  3. Expected: all hosts status=PASS and menu_hits>0"
    echo "  4. Actual: see per-host summary above"
    echo "  5. Root cause: check each host log tail"
    echo "  6. Fix: host-specific follow-up"
    echo "  7. Re-test result: pending"
    echo "- Logs:"
    while IFS=$'\t' read -r label host family status menu_hits log_file; do
      [[ -z "${label:-}" ]] && continue
      echo "  - Path: ${log_file#${ROOT_DIR}/}"
      echo "  - Key lines:"
      grep -Ei 'PASS: menu visibility regression|FAIL|failed|dep_check/menu_render|Environment self-check|invalid_input|ERROR' "$log_file" | tail -n 8 | sed 's/^/    - /' || true
    done < "$RESULT_TSV"
  } >> "$SUMMARY_DOC"
}

main(){
  need_cmd sshpass
  need_cmd ssh
  need_cmd scp

  mkdir -p "$RESULT_DIR"
  : > "$RESULT_TSV"

  local item label host family
  local pids=()
  for item in "${HOSTS[@]}"; do
    IFS='|' read -r label host family <<< "$item"
    run_one_host "$label" "$host" "$family" &
    pids+=("$!")
    while [[ "$(jobs -rp | wc -l)" -ge "$MAX_PARALLEL" ]]; do
      sleep 0.2
    done
  done

  local rc=0
  local pid
  for pid in "${pids[@]}"; do
    wait "$pid" || rc=1
  done

  append_summary
  local failures
  failures="$(awk -F'\t' '$4=="FAIL"{c++} END{print c+0}' "$RESULT_TSV")"
  echo "[all-hosts] done. failures=${failures}"
  echo "[all-hosts] result_tsv: $RESULT_TSV"
  echo "[all-hosts] summary_doc: $SUMMARY_DOC"
  [[ "$failures" -eq 0 && "$rc" -eq 0 ]]
}

main "$@"

