---
name: nvim-feedback-resolve
description: Resolve branch-scoped code feedback recorded by Neovim in a Git repository's feedback.json file. Use when the user invokes nvim-feedback-resolve, asks to apply editor feedback, or wants AI feedback comments addressed one by one.
---

# Resolve Feedback

Apply every safely locatable feedback item. Remove only items whose requested change is complete and verified.

## Workflow

1. Run `git rev-parse --show-toplevel` and `git branch --show-current` from current worktree. Stop when HEAD is detached. Read `<root>/feedback.json`.
2. Stop without edits when file is missing or current branch has no feedback. Require top-level `feedback` array. Require each item to contain unique string `id`, nonblank `branch`, repository-relative `file`, 1-based inclusive line `range`, nonblank `comment`, `created_at`, and complete `anchor`. Characterwise ranges also contain 0-based byte `start_col` and end-exclusive `end_col` plus `anchor.selected_text`. Reject absolute paths and paths escaping repository root.
3. Read repository instructions and inspect current worktree before changing files. Preserve unrelated user changes. Never commit unless user explicitly requests it.
4. Process snapshot of items whose `branch` equals current branch in order. Re-read current item by `id` and branch before working because editor may add, edit, or remove items concurrently.
5. Locate target in `file` using this order:
   - For characterwise feedback, accept stored line and column range when it exactly matches `anchor.selected_text`.
   - Search for exact `anchor.selected_text`; prefer unique match supported by `context_before`, `context_after`, and stored position.
   - For linewise feedback, accept stored inclusive line range when it exactly matches `anchor.selected_lines`.
   - Search for exact `anchor.selected_lines`; prefer unique match supported by `context_before` and `context_after`.
   - Use `anchor.diff_hunk` and `anchor.head` to understand moved or changed code when exact text no longer exists.
   - Leave item unresolved when file is missing, target is ambiguous, or requested behavior is unclear. Continue with next safe item.
6. Inspect enough surrounding code and tests to understand request. Apply smallest complete change that satisfies comment. Account for dependencies and overlapping later feedback.
7. Run narrow relevant checks after each change when practical. Treat clear code inspection as verification only when no executable check exists. Leave item unresolved when failures prevent confidence.
8. Immediately before marking item resolved, re-read feedback file. Remove only matching `id` on current branch; preserve every other item across all branches. Write valid JSON.
9. Re-locate next item against updated working tree instead of trusting stale line numbers.
10. Run suitable aggregate checks after all resolved changes. Report resolved IDs, unresolved IDs with reasons, files changed, and verification results.

Do not process or delete feedback from another branch. Do not delete feedback because code was edited. Delete it only after comment is satisfied. If current code already satisfies comment, verify that fact before removing item.
