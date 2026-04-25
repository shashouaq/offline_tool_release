# Test Findings

Use this file to collect each test round in one place.

## Round Template

### Round: <id or date>
- Environment:
  - OS:
  - Arch:
  - Online/Offline:
- Build/Script version:
- Test scope:
- Result summary:
  - Passed:
  - Failed:
- Failures:
  1. Symptom:
  2. Repro steps:
  3. Expected:
  4. Actual:
  5. Root cause:
  6. Fix:
  7. Re-test result:
- Logs:
  - Path:
  - Key lines:

### Round: round-20260424-A
- Environment:
  - OS: mixed
  - Arch: mixed
  - Online/Offline: mixed
- Build/Script version: offline_tools_v14.sh
- Test scope: auto summary from logs
- Result summary:
  - logs_20260424.log: menu_hits=0, select_ok=0, err_hits=0
  - openeulerlogs_20260423.log: menu_hits=0, select_ok=1, err_hits=477
  - ubuntulogs_20260423.log: menu_hits=0, select_ok=2, err_hits=287
  - Passed: 1
  - Failed: 2
- Failures:
  1. Symptom: see per-log err_hits > 0
  2. Repro steps: run with same script and menu inputs
  3. Expected: menu visible and flow continues
  4. Actual: determined by log metrics above
  5. Root cause: pending manual confirmation for each failed log
  6. Fix: align menu rendering + input handling + logging
  7. Re-test result: pending
- Logs:
  - Path: logs/logs_20260424.log
  - Key lines: pending manual extract
  - Path: logs/openeulerlogs_20260423.log
  - Key lines: repeated invalid_input entries
  - Path: logs/ubuntulogs_20260423.log
  - Key lines: repeated invalid_input entries

### Round: session-019db7ca-baseline-merge
- Environment:
  - OS: Windows host + WSL Bash for syntax/tests; Linux remote planned for full run
  - Arch: mixed (target-dependent)
  - Online/Offline: mixed topology required
- Build/Script version: offline_tools_v14.sh (session baseline)
- Test scope: baseline merge from historical session into current thread
- Result summary:
  - Passed: baseline requirements extracted and merged into docs
  - Failed: none at merge step
- Failures:
  1. Symptom: historical records contain mojibake in parts of text
  2. Repro steps: parse old session JSONL directly in Windows PowerShell
  3. Expected: fully readable Chinese text in all payloads
  4. Actual: partial garbled text in legacy entries
  5. Root cause: mixed encoding/locale rendering in old records
  6. Fix: merge by durable technical facts + memory summary references
  7. Re-test result: merge completed
- Logs:
  - Path: C:\Users\wei.qiao\.codex\sessions\2026\04\23\rollout-2026-04-23T08-43-20-019db7ca-9731-7e43-b07a-3048ce515631.jsonl
  - Key lines:
    - session_meta.id = 019db7ca-9731-7e43-b07a-3048ce515631
    - user objective = offline RPM/DEB workflow hardening and optimization

### Round: round-20260425-autonomous-validation
- Environment:
  - OS: 4 hosts (RPM online, DEB online, RPM offline, DEB offline)
  - Arch: mixed
  - Online/Offline: mixed
- Build/Script version: offline_tools_v14.sh + utils/run_autonomous_validation.sh
- Test scope: local quality gate + remote sync + menu regression/autonomous validation
- Result summary:
  - rpm_online(172.18.10.61): PASS, menu_hits=5
  - deb_online(172.18.10.62): PASS, menu_hits=5
  - rpm_offline(172.18.10.64): PASS, menu_hits=0, menu regression skipped because `expect` missing on offline host
  - deb_offline(172.18.10.65): PASS, menu_hits=0, menu regression skipped because `expect` missing on offline host
- Failures:
  1. Symptom: autonomous validation previously stalled on offline hosts
  2. Repro steps: run old `utils/run_autonomous_validation.sh`
  3. Expected: offline hosts must not attempt online dependency bootstrap
  4. Actual: old script tried to install `expect` over the network on offline hosts
  5. Root cause: script did not distinguish online/offline host roles
  6. Fix: classify hosts by connectivity, skip package bootstrap on offline hosts, and mark menu regression as skipped when `expect` is unavailable
  7. Re-test result: fixed; script completed across all 4 hosts
- Logs:
  - Path: logs/autonomous_validation/results_20260425_112317.tsv
  - Key lines:
    - rpm_online PASS
    - deb_online PASS
    - rpm_offline PASS with skip
    - deb_offline PASS with skip

### Round: round-20260425-manual-and-encoding-pass
- Environment:
  - OS: Windows host + WSL + 4 remote validation hosts
  - Arch: mixed
  - Online/Offline: mixed
- Build/Script version: offline_tools_v14.sh + refreshed package/metadata modules + user manual export
- Test scope: package-manager/metadata text cleanup, PDF manual export, autonomous validation rerun
- Result summary:
  - Local syntax gate: PASS
  - Local PDF export: PASS
  - rpm_online(172.18.10.61): PASS, menu_hits=7
  - deb_online(172.18.10.62): PASS, menu_hits=7
  - rpm_offline(172.18.10.64): PASS
  - deb_offline(172.18.10.65): PASS
- Failures:
  1. Symptom: package-manager and metadata logs still contained mojibake from legacy file encoding damage
  2. Repro steps: inspect `lib/package_manager.sh`, `lib/metadata/metadata_core.sh`, then review runtime logs
  3. Expected: high-frequency repo/metadata logs and helper text should be readable and stable
  4. Actual: old modules emitted garbled text into logs and UI paths
  5. Root cause: legacy source files had already been encoding-damaged and were still reused in runtime
  6. Fix: rewrote both modules as clean UTF-8/LF shell files and added a generated Chinese user manual plus PDF export script
  7. Re-test result: syntax passed, PDF generated successfully, autonomous validation passed on all 4 hosts
- Logs:
  - Path: logs/autonomous_validation/results_20260425_134449.tsv
  - Key lines:
    - rpm_online PASS
    - deb_online PASS
    - rpm_offline PASS
    - deb_offline PASS
  - Path: docs/offline_tools_user_manual_zh_CN.pdf
  - Key lines:
    - generated from `docs/offline_tools_user_manual_zh_CN.md`
