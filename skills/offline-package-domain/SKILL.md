# Skill: offline-package-domain

Purpose: enforce the business baseline for offline package download, packaging, validation, and offline installation in this project.

## Required Baseline
- Read `docs/project-memory.md` before changing workflow logic.
- Treat the tool as an offline local-repository delivery system, not a raw package downloader.
- Separate download host assumptions from target offline environment requirements.
- Keep all decisions scoped by target `OS + version + SP/minor + arch + package type`.

## Domain Rules
- Package output must be isolated by `OS + ARCH`, and in practice by full target identity.
- Do not mix x86 and arm artifacts in the same bundle.
- Do not mix different OS versions or package families in the same bundle.
- Selection UI should display tool or group names, not full dependency expansion.
- Install path must use local offline repository only; no online fallback.
- Failed tools must not be marked as packaged success.
- Failure reason must be visible in UI and written to logs.
- Existing tool bundles should be detected before download.
- Incremental packaging is valid only when manifest baseline fields match.
- `manifest.json` is the trusted install contract; directory name is not.

## Dependency Rules
- Resolve complete dependency closure.
- Do not rely on dependencies already installed on the download host.
- RPM path should prefer isolated `installroot`.
- DEB path should prefer isolated resolver state.
- Require local-repo dry-run validation before claiming workflow success.

## Workflow
1. Read `docs/project-memory.md`.
2. Confirm target `OS + version + SP/minor + arch + package type`.
3. Load and validate tool compatibility rules (`conf/tool_os_rules*.conf`).
4. Probe mirrors and keep only reachable sources for the actual download stage.
5. Download with reason-classified failures.
6. Package only successful tools and write metadata.
7. Validate install path in offline mode through the local repository.
8. Record evidence in `docs/test-findings.md`.

## Verification Checklist
- [ ] Target environment selection is explicit.
- [ ] Existing package detection works before tool selection.
- [ ] Duplicate tools are skipped with a clear message.
- [ ] Failure reason is shown and logged.
- [ ] Package content list shows tools only.
- [ ] Install path uses local repository only.
- [ ] Bilingual key coverage has no missing keys.
- [ ] Failure preserves enough evidence for follow-up.
