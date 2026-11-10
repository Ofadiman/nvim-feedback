---
name: nvim-feedback-resolve
description: Resolve the Neovim feedback comments on the current branch, applying each change request and answering each question.
disable-model-invocation: true
---

# Resolve feedback

Each feedback item is a **change request** or a **question**. An item is **resolved** once its change is applied and verified, or once its question is answered.

1. Run `git rev-parse --show-toplevel` and `git branch --show-current`, and stop when HEAD is detached. Read `<root>/feedback.json`. Stop without edits when the file is missing, has no top-level `feedback` array, or holds no item whose `branch` is the current branch.
2. Snapshot the current branch's items and process them in order. Before working on an item, re-read it by `id` and branch, because the editor may add, edit, or remove items while you work.
3. Validate the item. It carries a unique string `id`, a nonblank `branch`, a repository-relative `file`, a 1-based inclusive line `range`, a nonblank `comment`, `created_at`, and a complete `anchor`. A characterwise item also carries a 0-based byte `start_col`, an end-exclusive `end_col`, and `anchor.selected_text`. A blockwise item instead carries `range.columns`, holding one such `start_col` and `end_col` pair for each line of the range, and `anchor.selected_block`, holding the text each pair covers. An item that fails this check, or whose `file` is absolute or escapes the repository root, stays unresolved.
4. Locate the target in `file`, taking the first rule that succeeds:
   - Characterwise: the stored line and column range, when its text equals `anchor.selected_text`.
   - Characterwise: an exact match of `anchor.selected_text`, preferring the unique match that `context_before`, `context_after`, and the stored position support.
   - Linewise or blockwise: the stored line range, when its lines equal `anchor.selected_lines`.
   - Linewise or blockwise: an exact match of `anchor.selected_lines`, preferring the unique match that `context_before` and `context_after` support.
   - Any: `anchor.diff_hunk` and `anchor.head`, to trace code that moved or changed since the comment was written.

   On each located line, a blockwise target is only the text that the line's `range.columns` pair covers, which equals the matching `anchor.selected_block` entry. The item stays unresolved when the file is missing or the target is ambiguous.

5. Classify the comment by intent.
6. Change request: apply the smallest complete change that satisfies the comment, accounting for dependencies and for later items on the same code. Run the narrowest relevant checks; clear code inspection counts as verification only when no executable check exists. When the code already satisfies the comment, verify that and count the item resolved. The item stays unresolved when failures leave you unsure the change is right. Draft the change entry of a resolved item for the report in the shape of `report-template.md`.
7. Question: work out the answer from the code and its history, leaving the code as it is, and draft it for the report in the shape of `report-template.md`.
8. Remove each item as soon as it is resolved: re-read `feedback.json` and find the item by `id` on the current branch. When its `comment` differs from the text you resolved, process it again from step 4. Otherwise delete only that item, keep every other item on every branch, and write valid JSON.
9. Once every item is processed, run suitable aggregate checks if any code changed. Report a `Changes` section holding every drafted change entry and an `Answers` section holding every drafted answer, followed by the IDs of unresolved items with the reason for each, the files changed, and the verification results.
