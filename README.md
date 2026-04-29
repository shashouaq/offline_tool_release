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

- `offline_tools_v1.sh`

Key directories:

- `conf/` configuration and language files
- `lib/` shell modules
- `utils/` validation and sync helpers
- `docs/` project memory, decisions, and test findings
- `skills/` project-local Codex skills

User documents:

- `docs/offline_tools_user_manual_zh_CN.md` detailed Chinese user manual
- `docs/offline_tools_user_manual_zh_CN.pdf` printable detailed manual
- `docs/offline_tools_a4_quick_guide_zh_CN.pdf` one-page A4 quick guide

Build Windows distribution package:

```powershell
powershell -ExecutionPolicy Bypass -File .\utils\package_windows_release.ps1 -Version v1.0
```
