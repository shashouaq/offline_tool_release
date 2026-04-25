# Skill: patch-first-edit

Purpose: maximize change efficiency and minimize token/cost by using incremental patches instead of full-file rewrites.

## Default Editing Policy
1. Use function/block-level `apply_patch` edits by default.
2. Keep write scope minimal: only files required for the task.
3. Preserve existing structure, naming, and style unless task requires otherwise.
4. Avoid cosmetic refactors in the same change unless requested.

## Full-file Rewrite Is Allowed Only If
- File encoding/newline corruption prevents safe targeted edits.
- Requested change is structural and touches most lines anyway.
- User explicitly asks for a rewrite.

When full rewrite is used, log reason in commit/summary as:
- `rewrite_reason=<reason>`

## Execution Checklist
1. Read target file and identify exact edit anchors (function name or line segment).
2. Apply minimal patch.
3. Run local validation:
   - `bash -n` for modified shell files
   - related script/test only (not full suite unless required)
4. Report:
   - changed files
   - changed functions/sections
   - behavioral delta

## Guardrails
- No unrelated file churn.
- No blanket reformat across repository.
- No line-ending changes except target files (when required).
- Keep logs concise and grep-friendly.

