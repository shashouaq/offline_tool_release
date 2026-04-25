# offline_tool_release

Offline RPM/DEB tool bundle project for:

- downloading tool groups and packages in online environments
- building portable offline repository bundles
- installing from local offline repositories only

Current repo focus:

- manifest-based bundle compatibility
- bilingual menu and UX stability
- autonomous regression validation across the 4-host topology
- release hardening for RPM and DEB workflows

Main entry:

- `offline_tools_v14.sh`

Key directories:

- `conf/` configuration and language files
- `lib/` shell modules
- `utils/` validation and sync helpers
- `docs/` project memory, decisions, and test findings
- `skills/` project-local Codex skills
