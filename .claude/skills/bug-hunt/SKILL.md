---
name: bug-hunt
description: Deep Go bug hunt across the claims-engine monorepo. Use when the user invokes /bug-hunt or asks for a bug hunt, bug sweep, deep audit for bugs, or to find bugs in one or more services. Scopes via interview, fans out 1-5 subagents, proves every bug with a failing test.
---

Orchestrate a proof-driven bug hunt over this Go monorepo (one module per
service under `services/`, plus `shared/`, tied together by `go.work`).
You are the **orchestrator**: you interview, partition, fan out subagents,
and synthesize the report. **Never do the hunt inline** — all searching and
test-writing happens in subagents whose prompts are built from
`~/.claude/skills/bug-hunt/subagent-prompt.md`.

All other paths are relative to the repo root.

## Phase 1 — Scoping interview (always first, before any analysis)

Discover targets at runtime — never hardcode the service list:

```bash
ls ./services
```

Then use **AskUserQuestion** (one call, two questions):

1. **Targets** (multiSelect: true): one option per directory in
   `./services`, **plus** one more option for `shared`. AskUserQuestion
   allows max 4 options per question — with ~12 targets, offer grouped
   options (e.g. "All services + shared", "Pipeline core: claims-pipeline,
   claims-ingestor, data-mapper", "APIs: claims-api, claims-api-worker",
   "Everything else + shared") and let "Other" capture custom picks; the
   user can name any combination in free text.
2. **Focus**: "Complete bug hunt" (default) vs. a specific focus — a
   feature, a package, a bug class (concurrency, nil-safety, DB handling),
   or a recent change.

A **complete bug hunt** means look EVERYWHERE in the selected targets:
every function and method, exported and unexported, is a unit to examine —
AND each one's call paths are traced **upward** (all callers, including
across service/shared module boundaries) and **downward** (all callees), so
bugs that only manifest through a call chain are caught: wrong invariants
between layers, errors dropped mid-chain, contexts not propagated, locks
held across calls.

## Phase 2 — Subagent fan-out (mandatory)

Spawn **1–5 subagents scaled to scope**, all in a single message so they
run concurrently:

| Scope | Subagents | Partition by |
|---|---|---|
| One service / narrow focus | 1–2 | disjoint package clusters |
| 2–4 services | 3–4 | service |
| All services, complete hunt | 5 | disjoint service groups |

**Partitions must be package-disjoint** — no two subagents may write tests
into the same Go package. Subagents add their proving tests to the
**existing standard test file** for the code under test (`foo.go` →
`foo_test.go`, same package), so overlapping partitions would clobber each
other's edits. This rules out bug-class lenses that cut across shared
packages; if you want a cross-cutting lens, hand each lens a disjoint set
of packages.

Partition so coverage doesn't overlap wastefully. Build each subagent's
prompt from `subagent-prompt.md` in this skill directory: read it, fill in
the `{{PARTITION}}` / `{{FOCUS}}` / `{{SLUG}}` placeholders (`{{SLUG}}` is
a short unique CamelCase tag per subagent, e.g. `Pipeline`, `Api`,
`Shared`, used only for the subagent's findings file and identity — it
does **not** appear in test names or file names), and pass the whole
thing. It already contains the call-path tracing requirement, the bug
taxonomy, the proof-by-test protocol, and the output contract — do not
trim those.

Use `subagent_type: general-purpose` (they must write and run tests).

**Shared-tree rules (subagents run concurrently in ONE checkout):**

- **Exactly one subagent owns `shared/`** (if it's in scope). Only the
  owner may write `_test.go` files there. All others, when call-path
  tracing leads them into `shared/`, report the finding **without a test**
  (status `needs-shared-owner`). After collection, if any such findings
  exist and weren't covered by the owner, spawn **one follow-up subagent**
  to write the proving tests for just those findings.
- Subagents must **never run bare `go test ./...`** across a module they
  share with another subagent — they'd hit the other agent's newly-added
  (currently failing) tests and chase phantom bugs. Run only the **specific
  package(s) the subagent owns**, e.g. `go test ./internal/handler/`.
  Within a subagent's own packages, the only new failing tests are its own.
- Each subagent adds its tests to the **standard test file for the code
  under test** — `foo.go` → `foo_test.go` in the same package, creating the
  file only if it doesn't exist — matching the package's existing test
  conventions. Because partitions are package-disjoint, no two subagents
  ever edit the same file.

## Verified commands (what subagents run)

Each service and `shared` is its own Go module; tests run **from inside the
module dir** with `-mod=vendor` (matches the Makefile):

```bash
cd shared && go test ./retry/... -count=1 -mod=vendor
```

Proving test for a concurrency finding (race detector output confirmed
working on this machine, darwin/arm64, go 1.26.3) — scope to the package
under test, and to the new test's real name while iterating:

```bash
cd shared && go test ./retry/ -run 'TestRetry_ConcurrentReset' -race -count=1 -mod=vendor
```

Cross-boundary caller tracing (verified — e.g. who uses `shared/dbpool`):

```bash
grep -rln "dbpool\." services --include="*.go" | grep -v vendor
```

Cheap seed pass per module:

```bash
cd services/sob-mapping && go vet ./...
```

## Proof-by-test protocol (non-negotiable)

For EVERY suspected bug, the subagent writes a unit test that asserts the
**correct, intended behavior** of the function — so it **fails now because
of the bug** (under `go test`, plus `-race` for concurrency findings) and
will **pass once the bug is fixed**, leaving a permanent regression guard.
These are ordinary Go tests: they live in the standard test file for the
code under test (`foo.go` → `foo_test.go`, same package), are named like
the package's other tests (e.g. `TestProcessClaim_NilPayloadReturnsError`),
follow that package's existing conventions and `shared/testutil` /
`test/testutil` helpers, and carry only a normal doc comment describing the
behavior under test. **No "bug hunt" / `TestBug_` naming, no `BUGHUNT`
marker, no separate bughunt files** — they must be indistinguishable from
the rest of the suite.

**Prediction first:** before writing the test, the subagent must state the
predicted failure mechanism — panic type, race-detector stack location,
or "got X, want Y" with concrete values. The test counts as proof ONLY if
the actual failure output matches that prediction. Compile errors, setup
panics, and failures for any other reason are **never** proof — fix the
test or discard the finding.

- Test fails as predicted → **proven**. The test stays in the tree — it is
  a deliverable. Do NOT delete it.
- Test passes → the bug isn't real. Discard the finding (or downgrade to a
  note). This is the false-positive filter; apply it ruthlessly.
- Genuinely untestable without live infra → report as **unproven** with
  reasoning for why a unit test can't reach it.

**Hard constraint: production code is read-only.** No fault-injection
hooks, flags, or test-only endpoints in any service or shared code. Only
new/modified `_test.go` files are allowed. A bug that can only be "proven"
by editing prod code is reported unproven instead.

## Phase 3 — Final report (in chat, not a file)

Each subagent writes its full findings to
`tmp/bug-hunt/findings-<slug>.md` and returns only a summary + path
(see the output contract). Read every findings file, then synthesize:

1. **Summary table**: bug · location (`file:line`) · severity
   (critical/high/medium/low) · proven/unproven.
2. **Per bug**: description; the call path it lives on; real-world impact
   (data corruption, panic, stuck claims, leak, …); the proving test and
   its failure output; and **at least one concrete fix**, with trade-offs
   when multiple approaches exist.
3. **Coverage**: aggregate the subagents' coverage statements — packages
   examined vs. skipped and why. A subagent that returned clean but
   skipped half its partition is a gap, not a pass; say so.
4. **Tests added to the tree** — full list of every test added, as
   `file:line` + test name. Because these are ordinary-looking tests, this
   list is the *only* record of which reds are the hunt's deliverables —
   make it complete.
5. **End with an explicit warning**: `make test` / CI is now red — list
   every newly-added test that is currently failing (file + name). Each one
   asserts the function's intended behavior and **will go green when the
   corresponding bug is fixed**; until then it is a known open bug, not a
   regression. Do not delete them.
6. **Do NOT fix the bugs.** Report and discuss fixes only.

If two subagents report the same bug, merge into one entry.

## Gotchas

- **Integration tests need Docker** (testcontainers). They self-skip under
  `-short` ("skipping integration test in short mode"). Proving tests must
  be plain unit tests; if a full-package run hangs, add `-short`.
- `-count=1` always — cached results hide newly-introduced failing tests.
- `gotestsum` is what the Makefile uses, but plain `go test` works fine for
  subagents and gives cleaner failure output.
- `go.work` links all modules, so cross-module references resolve in
  editors/grep — but `go test` still runs per-module with `-mod=vendor`.
- Race detector findings print `WARNING: DATA RACE` with goroutine stacks;
  capture that output verbatim for the report.
- Don't run `make test` (all modules, slow, needs Docker) to validate one
  proving test — run the single package, scoped with `-run`.
- **After a hunt the tree is red.** The newly-added tests assert intended
  behavior and fail because the bugs are real; they look like ordinary
  tests, so the report's "tests added" list is the record of which reds are
  open bugs. They go green when the bugs are fixed — do not skip or delete
  them as if they were regressions.
