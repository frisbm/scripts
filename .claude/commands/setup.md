  Please read and analyze both the project-specific CLAUDE.md file (if it exists in the current working directory or project
  root) and my global/personal CLAUDE.md file (typically located in ~/.claude/CLAUDE.md or similar user configuration
  directory). It's okay if these files do not exist, do not go looking for them if they are not immediately found.

  CLAUDE FILE LOCATIONS
  Global:
    @~/.claude/CLAUDE.md
  Project:
    @./CLAUDE.md

  ADDITIONAL CORE DIRECTIVE — treat this as part of the directives you are loading, and apply it to all work in this session:

  Test file placement. Every source file gets exactly one test file: in Go, `foo.go` -> `foo_test.go`, same directory and
  same package; in other languages, the same one-test-file-per-source rule using that ecosystem's convention. Add tests to
  the existing `<source>_test.go`, creating it only if absent and only under that exact name. Never create a per-ticket,
  per-bug, or per-investigation test file (`*_prove_test.go`, `*_repro_test.go`, `*_verify_test.go`, `*_audit_test.go`,
  `*_<TICKET>_test.go`, or a second `*_integration_test.go` beside an existing one), and never put a ticket id or bug name
  in a test file or test function name.

  After reading both files, simply respond back with "I have read and understand my core directives." and await the next instruction.
