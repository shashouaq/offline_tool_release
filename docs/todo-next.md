# Next TODO

Use this file as the single source of next actions.

## Priority P0 (Blockers)
- [ ] Make dependency resolution conform to `docs/project-memory.md`: isolated resolver state, full closure, and local-repo dry-run as release criteria.
- [ ] Replace weak manifest handling with `manifest.json` as the install-time source of truth.
- [ ] Enforce incremental packaging compatibility gates before merge.

## Priority P1 (Important)
- [ ] Refactor cache keying by target identity to prevent x86 selection state leaking into ARM runs.
- [ ] Add unified action logging framework for detect/select/download/package/install with stable error codes.
- [ ] Improve dynamic progress bars for download and packaging with current tool, source, ETA.
- [ ] Add autonomous remote regression beyond menu visibility: focused download/install cases on 61/62/64/65.
- [ ] Add post-install prompt in selective install flow: continue installing other tools vs back to main menu.

## Priority P2 (Enhancement)
- [ ] Add a "session merge checklist" command to sync historical session decisions into docs automatically.

## Backlog
- [ ] Windows distributable packaging after current release passes full remote validation.

## Notes
- Keep items concrete: "<module>/<function> + expected behavior".
- Each completed item should reference a log line or test result.
