# Skill: shell-quality

Purpose: enforce reliable shell engineering quality for this project.

## Scope
- Bash syntax checks
- Optional static lint (`shellcheck`)
- Optional format check (`shfmt`)
- Line ending policy (LF only for `.sh`)
- Quick smoke run for entry script

## Workflow
1. Run `utils/quality_gate.sh`.
2. If syntax fails, stop and fix syntax first.
3. If lint/format tools are installed, fix all reported issues.
4. Re-run quality gate until all enabled checks pass.
5. If remote validation is part of the change, run `utils/run_autonomous_validation.sh`.
6. Record evidence in `docs/test-findings.md`.

## Rules
- Never skip syntax check.
- Do not commit CRLF in shell scripts.
- Keep error handling explicit (`set -euo pipefail` where applicable).
- Keep user-facing messages deterministic and grep-friendly.

## Outputs
- Terminal summary from `utils/quality_gate.sh`
- Remote validation summary from `utils/run_autonomous_validation.sh`
- Findings added to `docs/test-findings.md`
