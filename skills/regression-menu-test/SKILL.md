# Skill: regression-menu-test

Purpose: run menu interaction regression and remote validation with scripted input to verify UI visibility, input handling, and basic regression health.

## Scope
- Main menu visibility
- OS/ARCH/SSL selection menus
- Environment self-check menu
- Dependency choice menu prompts

## Workflow
1. Ensure `expect` is installed on target machine.
2. For one machine, run `utils/run_menu_regression.sh`.
3. For the standard 4-host topology, run `utils/run_autonomous_validation.sh`.
4. Collect output from:
   - `logs/menu_visibility_expect.out`
   - `logs/*.log`
   - `logs/autonomous_validation/*.log`
5. Confirm pass criteria:
   - Menu sections are visible.
   - Choice prompts are visible.
   - Input is accepted and flow proceeds.
6. Write findings to `docs/test-findings.md`.

## Pass/Fail Rules
- PASS: script prints `PASS: menu visibility regression`.
- FAIL: script prints explicit `FAIL: <reason>`.

## Extension
- Add more expect cases for each menu branch.
- Keep remote validation key-based by default.
- Prefer autonomous test collection before asking the user to rerun manual steps.
