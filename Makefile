SHELL := /bin/bash

.PHONY: lint test pack replay-log summarize remote-test

lint:
	bash utils/check_lf.sh
	bash utils/quality_gate.sh

test:
	bash utils/run_menu_regression.sh

remote-test:
	bash utils/run_regression_all_hosts.sh

summarize:
	bash utils/summarize_test_findings.sh

pack:
	powershell -ExecutionPolicy Bypass -File .\utils\package_windows_release.ps1

replay-log:
	@echo "Latest logs:"
	@ls -lt logs/*.log 2>/dev/null | head -n 10 || true

