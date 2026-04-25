# Professionalization Kit

This project now includes a minimum collaboration and quality kit.

## 1) Conversation merge (project-level)
- `docs/decisions.md`
- `docs/test-findings.md`
- `docs/todo-next.md`

These three files replace fragmented chat history with durable engineering context.
- `docs/project-memory.md`

`docs/project-memory.md` is the non-negotiable business baseline for future changes.

## 2) Skills (project-local skeletons)
- `skills/shell-quality/SKILL.md`
- `skills/offline-package-domain/SKILL.md`
- `skills/regression-menu-test/SKILL.md`
- `skills/patch-first-edit/SKILL.md`

Editing policy for efficiency:
- Prefer incremental `apply_patch` updates (function/block level).
- Avoid full-file rewrite unless corruption or explicit structural rewrite is required.

## 3) Quality gate
- Script: `utils/quality_gate.sh`
- Run:
  - `bash utils/quality_gate.sh`

Checks included:
- `bash -n` syntax
- CRLF detection for `.sh`
- optional `shellcheck`
- optional `shfmt -d`
- optional `./offline_tools_v14.sh --version` smoke

## 4) Menu visibility regression
- Scripts:
  - `utils/run_menu_regression.sh`
  - `utils/test_menu_visibility.expect`
- Run:
  - `bash utils/run_menu_regression.sh`

Prerequisite:
- `expect` installed on Linux test machine.

## 5) Multi-host regression (61/62/64/65)
- Script:
  - `utils/run_regression_all_hosts.sh`
  - `utils/run_autonomous_validation.sh`
- Run:
  - `bash utils/run_regression_all_hosts.sh`
  - `bash utils/run_autonomous_validation.sh`
- Prerequisites:
  - key-based SSH for the 4 hosts is preferred
  - target hosts reachable by SSH
  - `expect` will be installed automatically when missing

## 6) Auto log summary to findings doc
- Script:
  - `utils/summarize_test_findings.sh`
- Run:
  - `bash utils/summarize_test_findings.sh`
  - optional round id:
    - `bash utils/summarize_test_findings.sh round-20260424-A`
