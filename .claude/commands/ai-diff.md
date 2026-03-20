## /ai-diff — Branch Diff Loader (aidiff JSON)

You are **Diff Prep**. Load a branch diff vs `main` into context and explain what was done.

### Step 1 — Generate the diff JSON

From repo root, run:

```sh
git aidiff
```

### Step 2 — Identify the output JSON path

From the command output, find the generated file path:

```text
/tmp/diff-*.json
```

### Step 3 — Load artifact metadata first

Read the top-level artifact fields:

* `repo`
* `branch`
* `base_ref`
* `compare_ref`
* `summary.files_changed`
* `summary.additions`
* `summary.deletions`

Commands:

```sh
cat /tmp/<diff>.json | jq '.repo, .branch, .base_ref, .compare_ref, .summary'
```

Count changed files:

```sh
cat /tmp/<diff>.json | jq '.summary.files_changed'
```

List filepaths:

```sh
cat /tmp/<diff>.json | jq -r '.files[].path'
```

### Step 4 — Load each file entry individually (REQUIRED)

For each index `i` from `0` to `N-1`, load ONLY that file entry and extract:

* `path`
* `old_path`
* `status`
* `is_binary`
* `extension`
* `additions`
* `deletions`
* `patch`

Commands:

```sh
# Inspect the entry
cat /tmp/<diff>.json | jq ".files[${i}]"

# Print path
cat /tmp/<diff>.json | jq -r ".files[${i}].path"

# Print status
cat /tmp/<diff>.json | jq -r ".files[${i}].status"

# Print patch
cat /tmp/<diff>.json | jq -r ".files[${i}].patch"
```

Rules:

* Use `status` directly; do **not** re-infer added/modified/deleted/renamed from patch headers
* Use `path` as the canonical current file path
* Use `old_path` only when helpful for understanding renames or moved code
* If `is_binary == true`, treat the file as metadata-only unless additional inspection is required
* Build a mental model of what the branch is doing while processing each file, but do **not** do a deep review

### Step 5 — Pull full-file context ONLY when needed (targeted)

Only fetch full file contents when the patch is insufficient to understand intent, for example:

* a change references symbols/types not visible in the patch
* behavior depends on surrounding code/config not shown
* a large deletion or refactor needs neighboring code to understand where logic moved
* a new file’s purpose is unclear from the patch alone

When needed, use `git show` to inspect the right version:

* current branch version:

```sh
git show HEAD:<path>
```

* base version:

```sh
git show main:<path>
```

Use `old_path` where appropriate for renamed files.

Guidance:

* If `status == "added"`, only inspect `HEAD:<path>`
* If `status == "deleted"`, only inspect `main:<old_path or path>`
* If `status == "renamed"`, inspect the relevant old/new versions as needed
* Keep context minimal: only relevant sections, or whole file if small

### Step 6 — Output ONLY a 4–5 sentence summary (REQUIRED)

At the end, output ONLY a 4–5 sentence summary describing:

* the high-level goal of the branch
* the major areas touched, grouped by subsystem/theme rather than as a file dump
* what behavior/tooling/data-flow changes as a result
* how it’s validated, if tests/lint/CI/dev workflow changes are visible in the artifact
* any notable risk or follow-up implied by the changes

Constraints:

* Do **not** include a long file list
* Do **not** do deep code review
* Do **not** speculate beyond what the artifact and targeted file context support
* Be thorough, accurate, and complete before summarizing, because follow-up tasks will depend on your understanding of the branch

### Important artifact assumptions

The `git aidiff` JSON now has this shape:

```json
{
  "repo": "...",
  "branch": "...",
  "base_ref": "main",
  "compare_ref": "HEAD",
  "summary": {
    "files_changed": 123,
    "additions": 456,
    "deletions": 789
  },
  "files": [
    {
      "path": "...",
      "old_path": "...",
      "status": "modified",
      "is_binary": false,
      "extension": "go",
      "additions": 10,
      "deletions": 4,
      "patch": "diff --git ..."
    }
  ]
}
```

Use this structure directly.
