#!/bin/bash
# Personal-layer machine setup. Run AFTER the org bootstrap (helmhealth/onboarding-scripts),
# which installs Homebrew/git/gh/jq/asdf and clones the repos. See README.md.
set -Eeuo pipefail
trap 'echo "❌ Failed at line $LINENO: $BASH_COMMAND" >&2' ERR

# ---- knobs ----
: "${DEPS_FILE:=./deps.json}"
: "${PRIVATE_DEPS_FILE:=./deps.private.json}"
: "${DRY_RUN:=0}"
: "${PIP_VENV:=$HOME/.venv}"
: "${MAX_JOBS:=4}"
: "${RECREATE_VENV:=1}"
# Must match the GOPATH the deployed .zshrc exports, or `go install` writes somewhere
# that is never on PATH.
: "${GOPATH_DIR:=$HOME/golang}"

AUDIT_ONLY=0
[[ "${1:-}" == "--audit" ]] && AUDIT_ONLY=1

run() { echo "+ $*" >&2; [[ "$DRY_RUN" -eq 1 ]] || "$@"; }
have() { command -v "$1" &>/dev/null; }

# ---- bootstrap: Xcode CLI, Homebrew, jq ----
# MUST precede any jq use. Everything below parses deps.json.
if [[ "$AUDIT_ONLY" -eq 0 ]]; then
  if have xcode-select && ! xcode-select -p &>/dev/null; then
    echo "Xcode CLI Tools not found. Triggering install prompt..." >&2
    run xcode-select --install
    echo "Re-run after Xcode CLI Tools finish installing (if needed)." >&2
  fi

  if ! have brew; then
    echo "Homebrew not found. Installing..." >&2
    run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
fi
# Apple Silicon path fix
if ! have brew && [[ -x /opt/homebrew/bin/brew ]]; then export PATH="/opt/homebrew/bin:$PATH"; fi
have brew || { echo "ERROR: brew still not available after install" >&2; exit 1; }

if [[ "$AUDIT_ONLY" -eq 0 ]]; then
  if ! have jq; then
    echo "Installing jq..." >&2
    run brew install -q jq
  fi
fi
have jq || { echo "ERROR: jq is required" >&2; exit 1; }

# ---- deps files ----
[[ -f "$DEPS_FILE" ]] || { echo "ERROR: deps file not found: $DEPS_FILE" >&2; exit 1; }
jq empty "$DEPS_FILE" >/dev/null
[[ -f "$PRIVATE_DEPS_FILE" ]] && jq empty "$PRIVATE_DEPS_FILE" >/dev/null

# Emit entries for a dep kind: public file first, then private.
# The `|| true` matters: without it an absent private file makes this return 1,
# and under `pipefail` that kills every `deps X | while ...` pipeline.
deps() {
  jq -c --raw-output ".${1}[]? // empty" "$DEPS_FILE"
  [[ -f "$PRIVATE_DEPS_FILE" ]] && jq -c --raw-output ".${1}[]? // empty" "$PRIVATE_DEPS_FILE" || true
}

# ---------------------------------------------------------------------------
# verify: is everything DECLARED actually installed?
#   declared but missing -> ERROR, non-zero exit.
# Installed-but-undeclared is deliberately NOT reported: deps.json is a want-list,
# not a snapshot, and one-off installs should not generate noise.
# ---------------------------------------------------------------------------
VERIFY_ERRORS=0
_miss() { echo "  ✗ MISSING ($1): $2" >&2; VERIFY_ERRORS=$((VERIFY_ERRORS + 1)); }

verify() {
  echo "── verify ─────────────────────────────────────────────" >&2

  local declared installed
  # Check against every installed formula, not `leaves`: gnupg/sqlite/k9s are installed
  # but are not leaves, and comparing against leaves reports them missing.
  declared="$(deps brew | sed 's|.*/||' | sort -u)"
  installed="$(brew list --formula 2>/dev/null | sed 's|.*/||' | sort -u)"
  while IFS= read -r p; do [[ -n "$p" ]] && _miss brew "$p"; done < <(comm -23 <(echo "$declared") <(echo "$installed"))

  declared="$(deps brewcask | sed 's|.*/||' | sort -u)"
  installed="$(brew list --cask 2>/dev/null | sort -u)"
  while IFS= read -r p; do [[ -n "$p" ]] && _miss cask "$p"; done < <(comm -23 <(echo "$declared") <(echo "$installed"))

  # go tools: declared by module path, installed as a bare binary name.
  declared="$(deps go | sed 's|.*/||' | sort -u)"
  installed="$(ls "$GOPATH_DIR/bin" 2>/dev/null | sort -u)"
  while IFS= read -r p; do [[ -n "$p" ]] && _miss go "$p"; done < <(comm -23 <(echo "$declared") <(echo "$installed"))

  # pip + the private SDKs, inside the declared venv.
  if [[ -x "$PIP_VENV/bin/pip" ]]; then
    installed="$("$PIP_VENV/bin/pip" list --format=freeze 2>/dev/null | cut -d= -f1 | tr 'A-Z_' 'a-z-' | sort -u)"
    declared="$(deps pip | sed 's|\[.*||' | tr 'A-Z_' 'a-z-' | sort -u)"
    while IFS= read -r p; do [[ -n "$p" ]] && _miss pip "$p"; done < <(comm -23 <(echo "$declared") <(echo "$installed"))
  else
    _miss pip "venv absent at $PIP_VENV"
  fi

  # Private SDKs are the thing most likely to be silently absent on a clean machine.
  local n_priv
  n_priv="$(deps pip_private | wc -l | tr -d ' ')"
  if [[ "$n_priv" -eq 0 ]]; then
    _miss sdk "no pip_private entries declared — Cloudsmith SDKs will not be installed (see README)"
  else
    while IFS= read -r entry; do
      [[ -n "$entry" ]] || continue
      local vname vcmd
      vname="$(jq -r '.name' <<<"$entry")"
      vcmd="$(jq -r '.verify // empty' <<<"$entry")"
      [[ -n "$vcmd" ]] || continue
      (source "$PIP_VENV/bin/activate" && bash -c "$vcmd") &>/dev/null || _miss sdk "$vname"
    done < <(deps pip_private)
  fi

  if [[ "$VERIFY_ERRORS" -gt 0 ]]; then
    echo "❌ verify: $VERIFY_ERRORS declared dependency/dependencies missing." >&2
    return 1
  fi
  echo "✅ verify: everything declared is installed." >&2
  return 0
}

if [[ "$AUDIT_ONLY" -eq 1 ]]; then
  trap - ERR   # a failed verify is a reported result, not an unhandled error
  verify
  exit $?
fi

# ---- private deps ----
# Deliberately NOT auto-scaffolded to an empty file. Doing so produced a green run
# on a clean machine that installed zero Cloudsmith SDKs.
if [[ ! -f "$PRIVATE_DEPS_FILE" ]]; then
  echo "WARNING: $PRIVATE_DEPS_FILE not found — Cloudsmith SDKs will be skipped." >&2
  echo "         See README.md; verify at the end of this run will fail loudly." >&2
fi

echo "Updating and upgrading Homebrew packages..." >&2
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "+ brew update && brew upgrade --cask --greedy && brew upgrade" >&2
else
  brew update
  brew upgrade --cask --greedy
  brew upgrade
fi

# ---- brew formulae ----
echo "Installing brew formulae..." >&2
deps brew | while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  if brew list "$p" &>/dev/null; then
    echo "✓ brew already installed: $p" >&2
  else
    run brew install -q "$p"
  fi
done

# ---- brew casks ----
echo "Installing brew casks..." >&2
deps brewcask | while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  if brew list --cask "$p" &>/dev/null; then
    echo "✓ cask already installed: $p" >&2
  else
    run brew install -q --cask "$p"
  fi
done

# ---- custom commands ----
# Output is NOT swallowed: a failure here aborts the run, and a generic trap line
# with no log is unactionable.
echo "Running custom installers/commands..." >&2
export GOPATH="$GOPATH_DIR"
export PATH="$GOPATH_DIR/bin:$PATH"
deps custom | while IFS= read -r entry; do
  [[ -n "$entry" ]] || continue
  name="$(jq -r '.name' <<<"$entry")"
  cmd="$(jq -r '.command' <<<"$entry")"
  [[ -n "$name" && -n "$cmd" ]] || { echo "ERROR: Invalid custom entry: $entry" >&2; exit 1; }

  echo "→ custom: $name" >&2
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "+ bash -lc \"$cmd\"" >&2
  else
    bash -lc "$cmd" || { echo "ERROR: custom command failed: $name" >&2; exit 1; }
  fi
done

# ---- go tools ----
if have go; then
  echo "Installing/upgrading go tools..." >&2
  # Set GOPATH explicitly rather than inheriting: `go env GOPATH` is ~/go on a machine
  # whose .zshrc (which exports ~/golang) has not been deployed yet, and ~/go/bin is
  # never on PATH.
  export GOPATH="$GOPATH_DIR"
  export PATH="$GOPATH_DIR/bin:$PATH"

  deps go | xargs -I{} -P "$MAX_JOBS" bash -lc '
    set -Eeuo pipefail
    pkg="$1"
    echo "→ go install $pkg@latest" >&2
    go install "$pkg"@latest || { echo "ERROR: go install failed: $pkg" >&2; exit 1; }
  ' _ {}
else
  echo "Go not found; skipping go installs." >&2
fi

# ---- gcloud components ----
# The cask does not put gcloud on PATH; interactively that is done by the oh-my-zsh
# gcloud plugin, which this bash script never sources.
[[ -r /opt/homebrew/share/google-cloud-sdk/path.bash.inc ]] && \
  . /opt/homebrew/share/google-cloud-sdk/path.bash.inc
if have gcloud; then
  echo "Installing gcloud components..." >&2
  deps gcloud | while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "+ gcloud components install --quiet $c" >&2
    else
      gcloud components install --quiet "$c" || { echo "ERROR: gcloud component install failed: $c" >&2; exit 1; }
    fi
  done
else
  echo "gcloud not found; skipping gcloud components (install google-cloud-sdk first)." >&2
fi

# ---- nvm/node ----
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && . "$NVM_DIR/bash_completion" || true

if have nvm; then
  echo "Installing node versions via nvm..." >&2
  deps nvm | while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "+ nvm install \"$v\" && nvm alias default \"$v\"" >&2
    else
      nvm install "$v"
      nvm alias default "$v"
    fi
  done
else
  echo "Skipping nvm installs (nvm not available)." >&2
fi

# ---- npm globals ----
if have npm; then
  echo "Installing npm global packages..." >&2
  deps npm | while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    [[ "$DRY_RUN" -eq 1 ]] && echo "+ npm i -g \"$p\"" >&2 || npm i -g "$p"
  done
else
  echo "npm not found; skipping npm globals." >&2
fi

# ---- python venv + pip ----
if [[ "$RECREATE_VENV" -eq 1 && -d "$PIP_VENV" ]]; then
  echo "Removing venv at $PIP_VENV (RECREATE_VENV=1)..." >&2
  run rm -rf "$PIP_VENV"
fi

# Derive the interpreter from brew rather than hardcoding a path a `brew upgrade` can invalidate.
PYTHON_FORMULA="$(deps brew | grep -E '^python@' | head -1)"
: "${PYTHON_FORMULA:=python@3.13}"
PYTHON_BIN="${PYTHON_BIN:-$(brew --prefix "$PYTHON_FORMULA" 2>/dev/null)/bin/python${PYTHON_FORMULA#python@}}"

if [[ ! -d "$PIP_VENV" ]]; then
  echo "Creating venv at $PIP_VENV (from $PYTHON_BIN)..." >&2
  [[ -x "$PYTHON_BIN" ]] || { echo "ERROR: Python not executable at $PYTHON_BIN" >&2; exit 1; }
  run "$PYTHON_BIN" -m venv "$PIP_VENV"
fi

# shellcheck disable=SC1091
source "$PIP_VENV/bin/activate"

echo "Ensuring pip is up to date..." >&2
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "+ python -m ensurepip --upgrade && pip install -U pip" >&2
else
  python -m ensurepip --upgrade
  pip install -U pip
fi

echo "Installing/upgrading pip packages..." >&2
# Array, not a bare string: `pandas[performance]` and `polars[...]` are bracket globs
# and would be rewritten by a matching filename in the CWD.
PIP_PKGS=()
while IFS= read -r p; do [[ -n "$p" ]] && PIP_PKGS+=("$p"); done < <(deps pip)
if [[ "${#PIP_PKGS[@]}" -gt 0 ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "+ pip install -qU ${PIP_PKGS[*]}" >&2
  else
    pip install -qU "${PIP_PKGS[@]}"
  fi
else
  echo "No pip packages listed." >&2
fi

# ---- private pip packages (Cloudsmith) ----
# Entries live in the gitignored private deps file:
#   { "name": "pkg", "index_url": "https://user:token@host/.../simple/", "verify": "python -c '...'" }
# PyPI is an extra index so the package's public dependencies resolve.
echo "Installing private pip packages..." >&2
deps pip_private | while IFS= read -r entry; do
  [[ -n "$entry" ]] || continue
  name="$(jq -r '.name // empty' <<<"$entry")"
  index_url="$(jq -r '.index_url // empty' <<<"$entry")"
  [[ -n "$name" && -n "$index_url" ]] || { echo "ERROR: invalid pip_private entry (need name + index_url): $entry" >&2; exit 1; }

  verify="$(jq -r '.verify // empty' <<<"$entry")"

  echo "→ private pip: $name" >&2
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "+ pip install --upgrade $name --index-url <redacted> --extra-index-url https://pypi.org/simple/" >&2
    [[ -n "$verify" ]] && echo "+ $verify" >&2
  else
    pip install --upgrade "$name" --index-url "$index_url" --extra-index-url https://pypi.org/simple/
    [[ -n "$verify" ]] && bash -c "$verify"
  fi
done

# ---- jupyter extensions ----
if have jupyter; then
  echo "Enabling Jupyter server extensions..." >&2
  deps jupyter | while IFS= read -r e; do
    [[ -n "$e" ]] || continue
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "+ jupyter server extension enable --py \"$e\"" >&2
    else
      jupyter server extension enable --py "$e" || { echo "ERROR: Failed enabling jupyter extension: $e" >&2; exit 1; }
    fi
  done
else
  echo "jupyter not found; skipping extensions." >&2
fi

# ---- sdkman ----
SDKMAN_INIT="$HOME/.sdkman/bin/sdkman-init.sh"
if [[ -s "$SDKMAN_INIT" ]]; then
  echo "Installing SDKMAN packages..." >&2
  (
    set +e +u +o pipefail
    trap - ERR

    : "${SDKMAN_OFFLINE_MODE:=false}"
    : "${SDKMAN_DEBUG_MODE:=false}"
    : "${SDKMAN_DIR:=$HOME/.sdkman}"
    export SDKMAN_NON_INTERACTIVE=true

    # shellcheck disable=SC1090
    source "$SDKMAN_INIT"

    deps sdk | while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "+ sdk install $p" >&2
        echo "+ sdk default $p" >&2
        echo "+ sdk use $p" >&2
      else
        sdk install $p || true
        sdk default $p || true
        sdk use $p || true
      fi
    done
  )
else
  echo "sdkman not installed; skipping SDKMAN section." >&2
fi

# ---- verify ----
# Every `have X → skip` branch above is an unconditional pass on a clean machine.
# This is what turns those silent skips into a non-zero exit.
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY_RUN: skipping verify." >&2
  echo "✅ Done (dry run)." >&2
  exit 0
fi

trap - ERR   # a failed verify is a reported result, not an unhandled error
verify || { echo "❌ Setup finished with missing dependencies (see above)." >&2; exit 1; }
echo "✅ Done." >&2
