#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
KEY_PATH="${1:-/mnt/c/Users/wei.qiao/Hkzy@8000}"
REMOTE_DIR="${2:-/root/offline_tool_release_v1}"
TMP_KEY="$(mktemp /tmp/offline_sync_key.XXXXXX)"
cp "$KEY_PATH" "$TMP_KEY"
chmod 600 "$TMP_KEY"
trap 'rm -f "$TMP_KEY"' EXIT

SSH_OPTS=(-i "$TMP_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10)

HOSTS=(
  "172.18.10.61"
  "172.18.10.62"
  "172.18.10.64"
  "172.18.10.65"
)

if [[ ! -f "$KEY_PATH" ]]; then
  echo "[sync] key not found: $KEY_PATH" >&2
  exit 1
fi

cd "$ROOT_DIR"
for host in "${HOSTS[@]}"; do
  echo "[sync] -> $host:$REMOTE_DIR"
  tar -czf - \
    offline_tools_v1.sh \
    conf \
    lib \
    utils \
    Makefile \
    test_fixes.sh \
    test_package_groups.sh \
    2>/dev/null \
    | ssh "${SSH_OPTS[@]}" "root@$host" \
      "mkdir -p '$REMOTE_DIR' && tar -xzf - -C '$REMOTE_DIR'"
  echo "[sync] ok: $host"
done

echo "[sync] all hosts updated"
