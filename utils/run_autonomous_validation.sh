#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
KEY_PATH="${KEY_PATH:-/mnt/c/Users/wei.qiao/Hkzy@8000}"
REMOTE_DIR="${REMOTE_DIR:-/root/offline_tool_release_v1}"
SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
RESULT_DIR="${ROOT_DIR}/logs/autonomous_validation"
RESULT_TSV="${RESULT_DIR}/results_$(date +%Y%m%d_%H%M%S).tsv"

HOSTS=(
  "rpm_online|172.18.10.61|rpm|online"
  "deb_online|172.18.10.62|deb|online"
  "rpm_offline|172.18.10.64|rpm|offline"
  "deb_offline|172.18.10.65|deb|offline"
)

need_cmd(){
  command -v "$1" >/dev/null 2>&1 || {
    echo "[auto-validate] missing command: $1"
    exit 2
  }
}

tmp_key=""
cleanup(){
  [[ -n "$tmp_key" && -f "$tmp_key" ]] && rm -f "$tmp_key"
}
trap cleanup EXIT

prepare_key(){
  if [[ ! -f "$KEY_PATH" ]]; then
    echo "[auto-validate] key not found: $KEY_PATH"
    exit 2
  fi
  tmp_key="$(mktemp /tmp/offline_tool_key.XXXXXX)"
  cp "$KEY_PATH" "$tmp_key"
  chmod 600 "$tmp_key"
}

ssh_run(){
  local host="$1"
  local cmd="$2"
  ssh -i "$tmp_key" -p "$SSH_PORT" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o BatchMode=yes \
    "${SSH_USER}@${host}" "$cmd"
}

host_prepare_packages(){
  local host="$1"
  local family="$2"
  local connectivity="$3"

  if [[ "$connectivity" != "online" ]]; then
    ssh_run "$host" "command -v expect >/dev/null 2>&1 && echo '[auto-validate] expect present on offline host' || echo '[auto-validate] expect missing on offline host; menu regression will be skipped'"
    return 0
  fi

  if [[ "$family" == "rpm" ]]; then
    ssh_run "$host" "command -v expect >/dev/null 2>&1 || (dnf install -y expect || yum install -y expect)"
  else
    ssh_run "$host" "command -v expect >/dev/null 2>&1 || (apt-get update -y && apt-get install -y expect)"
  fi
}

run_menu_regression_if_possible(){
  local host="$1"
  local connectivity="$2"

  if [[ "$connectivity" == "online" ]]; then
    ssh_run "$host" "cd '${REMOTE_DIR}' && chmod +x ./utils/run_menu_regression.sh ./offline_tools_v1.sh ./utils/test_menu_visibility.expect && ./utils/run_menu_regression.sh"
    return 0
  fi

  ssh_run "$host" "if command -v expect >/dev/null 2>&1; then cd '${REMOTE_DIR}' && chmod +x ./utils/run_menu_regression.sh ./offline_tools_v1.sh ./utils/test_menu_visibility.expect && ./utils/run_menu_regression.sh; else echo '[auto-validate] SKIP: offline host without expect'; fi"
}

run_one_host(){
  local label="$1"
  local host="$2"
  local family="$3"
  local connectivity="$4"
  local out_file="${RESULT_DIR}/${label}_$(date +%Y%m%d_%H%M%S).log"
  local status="PASS"

  {
    echo "[auto-validate] host=${host} label=${label} family=${family} connectivity=${connectivity}"
    echo "[auto-validate] time=$(date '+%F %T')"
    host_prepare_packages "$host" "$family" "$connectivity"
    ssh_run "$host" "cd '${REMOTE_DIR}' && bash -n offline_tools_v1.sh lib/*.sh"
    run_menu_regression_if_possible "$host" "$connectivity"
    ssh_run "$host" "cd '${REMOTE_DIR}' && if ls logs/*.log >/dev/null 2>&1; then tail -n 120 logs/*.log; fi"
  } >"$out_file" 2>&1 || status="FAIL"

  local menu_hits
  local err_hits
  menu_hits="$(grep -Eci 'PASS: menu visibility regression|dep_check/menu_render|Environment self-check|Select \[1/0\]|Select \[1/2/0\]' "$out_file" || true)"
  err_hits="$(grep -Eci 'FAIL|failed|ERROR|syntax error|command not found' "$out_file" || true)"
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$label" "$host" "$family" "$connectivity" "$status" "$menu_hits" "$err_hits" "$out_file" >> "$RESULT_TSV"
}

main(){
  need_cmd wsl.exe
  need_cmd ssh
  need_cmd scp
  mkdir -p "$RESULT_DIR"
  : > "$RESULT_TSV"
  prepare_key

  echo "[auto-validate] local quality gate"
  wsl.exe bash -lc "cd /mnt/d/arm/offline_tool/offline_tool_release && ./utils/quality_gate.sh"

  echo "[auto-validate] sync project to remote hosts"
  wsl.exe bash -lc "cd /mnt/d/arm/offline_tool/offline_tool_release && ./utils/sync_to_test_hosts.sh '$KEY_PATH' '$REMOTE_DIR'"

  local item label host family connectivity
  for item in "${HOSTS[@]}"; do
    IFS='|' read -r label host family connectivity <<< "$item"
    run_one_host "$label" "$host" "$family" "$connectivity"
    echo "[auto-validate] ${label} complete"
  done

  echo "[auto-validate] results: $RESULT_TSV"
}

main "$@"
