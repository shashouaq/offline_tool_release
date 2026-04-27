# Architecture Decisions (ADR)

Use this file to merge key decisions across all conversations.

## Template

### ADR-YYYYMMDD-XX: <short-title>
- Date:
- Owner:
- Scope:
- Context:
- Decision:
- Alternatives considered:
- Tradeoffs:
- Impacted files/modules:
- Rollback plan:
- Validation evidence (logs/tests):

### ADR-20260424-01: Merge Session 019db7ca Into Project Baseline
- Date: 2026-04-24
- Owner: codex + wei.qiao
- Scope: offline_tools_v1 workflow and remote validation path
- Context:
  - Session `019db7ca-9731-7e43-b07a-3048ce515631` defined the project target as end-to-end `download -> bundle -> offline install`.
  - The same session established SSH-based remote validation as acceptable for real Linux package-manager checks.
- Decision:
  - Keep end-to-end workflow as the release acceptance baseline, not isolated helper success.
  - Use four-machine online/offline RPM+DEB topology as default regression topology when available.
  - Preserve hardened behaviors from that session as non-regression requirements:
    - non-interactive language control via `OFFLINE_TOOLS_LANG`
    - controlled temp workspace and cleanup (`OFFLINE_TOOLS_WORK_DIR`)
    - safe tar extraction and safer config parsing
    - package-manager-driven directory install path
- Alternatives considered:
  - local Windows-only dry-run validation
  - password-only remote access
- Tradeoffs:
  - remote validation increases setup cost, but materially improves confidence for package-manager behavior.
- Impacted files/modules:
  - `offline_tools_v1.sh`
  - `lib/security.sh`
  - `lib/config.sh`
  - `lib/metadata/metadata_install.sh`
  - `lib/signature.sh`
  - `lib/downloader.sh`
- Rollback plan:
  - none; these are baseline workflow decisions.
- Validation evidence (logs/tests):
  - memory rollout summary: `2026-04-23T00-43-20-fPSF-offline_tool_hardening_and_ssh_test_env_guidance.md`

### ADR-20260425-01: Promote User Requirement Docs Into Project Baseline
- Date: 2026-04-25
- Owner: codex + wei.qiao
- Scope: future workflow, validation, packaging, install, and regression work for offline tool release
- Context:
  - User reorganized business requirements under `瑕佹眰/`.
  - Repeated iterations showed drift risk when decisions lived only in conversation.
- Decision:
  - Treat `docs/project-memory.md` as the project-local durable baseline.
  - Treat the tool as an offline local-repository delivery workflow, not a raw downloader.
  - Require target-environment-driven logic, isolated dependency resolution, local-repo install, manifest-based compatibility checks, and preserved failure evidence.
  - Prefer autonomous SSH-based regression before asking the user for repeated manual testing.
- Alternatives considered:
  - keep requirements only in chat history
  - rely on ad hoc developer recollection
- Tradeoffs:
  - adds process overhead, but reduces drift and repeated regressions.
- Impacted files/modules:
  - `docs/project-memory.md`
  - `skills/offline-package-domain/SKILL.md`
  - `skills/regression-menu-test/SKILL.md`
  - `skills/shell-quality/SKILL.md`
  - `utils/run_autonomous_validation.sh`
- Rollback plan:
  - revert doc/skill/script additions if a different project governance model is chosen.
- Validation evidence (logs/tests):
  - requirement source files in `瑕佹眰/`
  - local quality gate after integration
