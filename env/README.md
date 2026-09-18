# env

Personal-layer machine setup: dotfile-adjacent tooling, personal CLIs, Cloudsmith SDKs,
gcloud components, the Python venv.

This is **not** a from-zero provisioner. Machine-level setup (Homebrew, git, gh, jq, asdf,
`gh auth login`, cloning the repos) is `helmhealth/onboarding-scripts` → `make setup`.

## Clean machine, in order

1. **Org bootstrap first** — `helmhealth/onboarding-scripts`, `make setup`.
   Its own manual prerequisites: `xcode-select --install`, and a GitHub SSH key
   SSO-authorized for the `helmhealth` org.
2. **Cloudsmith credential.** `deps.private.json` is gitignored and holds the private pip
   index URLs. Without it the SDKs are skipped — the run will say so and exit non-zero.
   Copy it from a password manager or another machine; it is never committed.
3. **`bash setup.sh`** — this repo's layer.
4. **`buf registry login`** — the protos repos need a BSR credential. Nothing here sets it up.

## Everyday use

```bash
bash setup.sh            # install/upgrade everything declared, then verify
bash setup.sh --audit    # verify only; changes nothing
DRY_RUN=1 bash setup.sh  # print what would run
```

`--audit` answers "is every declared dependency actually installed":

- **declared but missing → ERROR**, non-zero exit.
- **installed but undeclared → WARNING**, never affects the exit code.

That asymmetry is deliberate. `deps.json` is a **want-list, not a snapshot** of the machine.
One-off installs (`gimp`, `poppler`, …) should warn, not fail, or the exit code becomes
something you learn to ignore — which is how this file drifted ~35 undeclared packages
in the first place. Drift is a signal to triage, not a worklist to apply.

## deps.json

| key | meaning |
|---|---|
| `brew` / `brewcask` | Homebrew formulae and casks |
| `go` | `go install <pkg>@latest` into `$GOPATH_DIR/bin` (default `~/golang/bin`) |
| `gcloud` | `gcloud components install` |
| `nvm` / `npm` | node versions, global npm packages |
| `pip` | installed into `$PIP_VENV` (default `~/.venv`) |
| `pip_private` | **`deps.private.json` only** — Cloudsmith index URLs with credentials |
| `custom` | `name` + `command` + `probe`; `probe` is the idempotency check *and* what `--audit` asserts |
| `jupyter` | server extensions to enable |

Adding a `custom` entry without a `probe` means it re-runs every time and `--audit` cannot
check it. Always set one.

## Knobs

`DRY_RUN=1`, `RECREATE_VENV=1`, `PIP_VENV`, `GOPATH_DIR`, `MAX_JOBS`, `DEPS_FILE`.

`RECREATE_VENV` defaults to **0** on purpose. The venv is auto-activated by `.zshrc` and holds
the Cloudsmith SDKs; wiping it at the start of a run means any later failure leaves the machine
worse than before it ran. Recovery from a partial run is "just re-run it" — every step is
idempotent — and that is only true while nothing destroys working state up front.

## Token rotation

The Cloudsmith token currently exists as four independent plaintext copies:
`~/.zshrc`, `deps.private.json`, `~/.npmrc`, `~/.cloudsmith/credentials.ini`.
Rotating means editing all four. Consolidating them to a single sourced file
(`~/.config/helm/secrets.env`, mode 600) is the recommended fix and is **not** done yet.

⚠️ **`frisbm/scripts` is a PUBLIC GitHub repository.** No credential may be committed to it.
`deps.private.json` is gitignored; keep it that way, and never symlink a `~/.zshrc` that
contains an inline token into this repo.

## Not covered here

Dotfiles in `env/` (`.zshrc`, `.p10k.zsh`, `.zshenv`, `.claude.json`) are **not deployed** by
`setup.sh` — they are hand-copied, and the copy here has drifted from the live one. On a clean
machine `.zshrc` will fail on `source ~/.zshenv` (not in this repo) until that is reconciled.
