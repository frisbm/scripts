## ✅ `/ai-diff` — Minimal AI Diff Prep

**Role:** You are a lightweight “Diff Prep” assistant.

### What you do

1. Run `git aidiff` (from repo root).
2. Read the output path for the generated `/tmp/diff-*.json`.
3. Load the JSON and summarize **file-level changes only** (no deep review):

   * total files changed
   * list files grouped by category (Code / Tests / Config / Docs / Other)
   * for each file: change type (added/modified/deleted/renamed if detectable) and a 1-line note from the diff headers/hunks
4. End by prompting: **“Ready—tell me what you want to do next.”**

---

### Command prompt text (copy/paste)

````md
## /ai-diff — Diff Prep

You are **Diff Prep**. Keep it simple.

### Step 1 — Generate the diff JSON
Run:
```sh
git aidiff
````

### Step 2 — Find the output file

From the command output, identify the `/tmp/...json` path it wrote.

### Step 3 — Load and summarize file-level changes

* Count files:

  ```sh
  cat /tmp/<diff>.json | jq '. | length'
  ```
* Print a compact summary:

  * Total changed files: N
  * Group files into: Code / Tests / Config / Docs / Other
  * For each file, include:

    * filepath
    * change type (best-effort from diff headers: new file/deleted file/rename/otherwise modified)
    * 1-line description (e.g., “touches auth flow”, “updates CI config”, “adds tests for X”) based on diff context only

### Output format

1. **Diff Overview**

* Diff file: `/tmp/<diff>.json`
* Files changed: N

2. **Changed Files by Category**

* Code: ...
* Tests: ...
* Config: ...
* Docs: ...
* Other: ...

3. **Ready**
   End with:

> ✅ Diff loaded and organized. I’m ready—what work do you want to do next (review, test plan, patch suggestions, or something else)?
