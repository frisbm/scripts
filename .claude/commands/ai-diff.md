## /ai-diff — Branch Diff Loader (aidiff JSON)

You are **Diff Prep**. Load a branch diff vs `main` into context and explain what was done.

### Step 1 — Generate the diff JSON
From repo root, run:
```sh
git aidiff
```

### Step 2 — Identify the output JSON path
From the command output, find the generated file path:
`/tmp/diff-*.json`

### Step 3 — Count files + list filepaths (no summary yet)
Count changed files:
```sh
cat /tmp/<diff>.json | jq 'length'
```

List filepaths:
```sh
cat /tmp/<diff>.json | jq -r '.[].filepath'
```

### Step 4 — Load each file’s diff individually (REQUIRED)
For each index `i` from `0` to `N-1`, load ONLY that entry and extract:
- filepath
- change type (added / modified / deleted / renamed) inferred from the diff headers
- the per-file diff text (from `.diff`)

Commands:
```sh
# Inspect the entry
cat /tmp/<diff>.json | jq ".[${i}]"

# Print filepath
cat /tmp/<diff>.json | jq -r ".[${i}].filepath"

# Print diff (unified diff text for that file)
cat /tmp/<diff>.json | jq -r ".[${i}].diff"
```

Infer change type from `.diff` using these cues (best effort):
- Added: contains `new file mode` OR `--- /dev/null`
- Deleted: contains `deleted file mode` OR `+++ /dev/null`
- Renamed: contains `rename from` / `rename to`
- Otherwise: Modified

While processing each file, build a mental model of what the change is doing (but do NOT deep review).

### Step 5 — Pull full-file context ONLY when needed (targeted)
Only fetch full file contents when the diff hunks are insufficient to understand intent, e.g.:
- a change references symbols/types not visible in the hunk
- behavior depends on surrounding code/config not shown
- a new file is large and purpose isn’t obvious from the diff header/hunks

When needed, use `git show` to view versions:
- main version:
```sh
git show main:<filepath>
```
- branch (current) version:
```sh
git show HEAD:<filepath>
```

If the file is new, only show `HEAD:<filepath>`.
If deleted, only show `main:<filepath>`.
Keep context minimal: only the relevant sections (or whole file if small).

### Step 6 — Output ONLY a 4–5 sentence summary (REQUIRED)
At the end, output ONLY a 4–5 sentence summary describing:
- the high-level goal of the branch
- the major areas touched (group by subsystem/theme, not a file list)
- what behavior/tooling changes as a result
- how it’s validated (tests/lint/CI/dev workflow changes if any)
- any notable risk/follow-up implied by the diff

Do NOT include a long file list. No deep code review.
After all operations are completed, I will review the summary and provide new tasks for you based on the state of the branch so its very important that your review is thorough, accurate, and complete.
