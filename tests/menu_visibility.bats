#!/usr/bin/env bats

@test "menu visibility regression script exists" {
  [ -f "${BATS_TEST_DIRNAME}/../utils/run_menu_regression.sh" ]
}

@test "menu visibility regression command is callable" {
  run bash "${BATS_TEST_DIRNAME}/../utils/run_menu_regression.sh"
  # In environments without expect, script returns non-zero with clear hint.
  [ "$status" -eq 0 ] || [[ "$output" == *"expect not installed"* ]]
}

