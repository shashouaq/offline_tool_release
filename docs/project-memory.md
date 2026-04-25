# Project Memory

This file is the durable baseline for `D:\arm\offline_tool\offline_tool_release`.
Future changes should be checked against this file before implementation.

## Core Goal

The project is an offline local-repository delivery tool, not a simple RPM/DEB downloader.
Success means:

- Download on an online machine against a user-selected target environment.
- Produce a portable offline package with local repository metadata.
- Install on a fully offline target using only the local repository.

## Non-Negotiable Business Rules

1. Separate download host from target offline host.
2. Target selection must drive behavior:
   `OS`, `version`, `SP/minor`, `arch`, `package type`, `repo config`.
3. Do not use the download host's current environment as the package target by default.
4. Do not mix artifacts across different `OS + version + SP + arch + package type`.
5. Do not mix `x86_64` and `aarch64` bundles.
6. Install mode must use local offline repositories only.
7. Directory names are not trusted metadata.
   `manifest.json` is the only trusted install entry.

## Dependency Rules

1. Do not download only explicitly listed packages.
2. Resolve a full dependency closure for single packages and groups.
3. Include group `mandatory/default` packages and policy-driven `optional` packages.
4. Include `Depends`, `Pre-Depends`, `Requires`, and policy-driven weak deps/recommends.
5. Account for module stream and post-install tool requirements.
6. Avoid "download host already has dependency installed" leakage:
   - RPM: use empty `installroot`
   - DEB: use empty `dpkg status` or equivalent isolated resolver state

## Packaging Rules

1. Offline package must contain local repository metadata.
2. Packaging success must reflect tool-level success, not partial dependency download noise.
3. Failed tools must not be marked as packaged success.
4. Package presentation should show tools supported by the bundle, not every dependency.
5. Incremental packaging is allowed only when these match:
   `OS`, `version`, `SP`, `arch`, `package type`, `repo source set`, dependency policy, module stream, and security policy.
6. If the baseline differs, force full rebuild instead of merge.

## Install Rules

1. Do not install by raw `rpm -Uvh *.rpm` or `dpkg -i *.deb` as the primary path.
2. Install through `dnf/yum` or `apt` against the local offline repository.
3. Run compatibility checks from `manifest.json`.
4. Support:
   - exact match: allow
   - compatible match: warn and confirm
   - incompatible match: block

## Validation Rules

1. Run local repository dry-run validation before claiming success.
2. Preserve failure evidence:
   `workdir`, cache, logs, manifest, resolved package list, failing command, return code, stderr summary.
3. Logging must cover:
   - target environment
   - selected tools/groups
   - repo source
   - command/result
   - success/failure summary
   - failure reason classification
   - final artifact path
4. Menu visibility, bilingual coverage, and package/install summaries are release criteria, not cosmetic issues.

## UX Rules

1. Chinese/English behavior must both work.
2. Menus must be visible before input is requested.
3. Progress bars should reflect current action, current tool/group, and source when relevant.
4. Selection and install pages should show tool/group names, not dependency explosions.

## Testing Rules

1. Prefer autonomous remote validation over manual user repetition.
2. Use the 4-host topology when available:
   - `172.18.10.61` RPM online
   - `172.18.10.62` DEB online
   - `172.18.10.64` RPM offline
   - `172.18.10.65` DEB offline
3. Default validation order:
   - local syntax and LF gate
   - remote sync
   - menu regression
   - focused download/install regression
   - log review

## Current Development Priority

1. Correct end-to-end offline repository workflow.
2. Stable target selection and dependency closure.
3. Dry-run validation and manifest-based install compatibility.
4. Clean failure classification and log quality.
5. UX polish only after the workflow is defensible.
