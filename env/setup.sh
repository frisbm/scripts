#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ Failed at line $LINENO: $BASH_COMMAND" >&2' ERR

# ---- knobs (same defaults as newer script) ----
: "${DEPS_FILE:=./deps.json}"
: "${DRY_RUN:=0}"
: "${QUIET:=1}"
: "${PIP_VENV:=$HOME/.venv}"
: "${PYTHON_BIN:=/opt/homebrew/bin/python3.13}"
: "${MAX_JOBS:=4}"
: "${UPGRADE_BREW:=1}"
: "${RECREATE_VENV:=1}"
: "${NVM_INSTALL_DEFAULT:=1}"
: "${GCLOUD_COMPONENTS_INSTALL:=1}"

run() { echo "+ $*" >&2; [[ "$DRY_RUN" -eq 1 ]] || "$@"; }
have() { command -v "$1" &>/dev/null; }
deps() { jq -c --raw-output ".${1}[]? // empty" "$DEPS_FILE"; }

# ---- deps.json required + valid ----
[[ -f "$DEPS_FILE" ]] || { echo "ERROR: deps file not found: $DEPS_FILE" >&2; exit 1; }
run jq empty "$DEPS_FILE" >/dev/null

# ---- Xcode CLI tools (macOS) ----
if have xcode-select && ! xcode-select -p &>/dev/null; then
  echo "Xcode CLI Tools not found. Triggering install prompt..." >&2
  run xcode-select --install
  echo "Re-run after Xcode CLI Tools finish installing (if needed)." >&2
fi

# ---- Homebrew ----
if ! have brew; then
  echo "Homebrew not found. Installing..." >&2
  run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# Apple Silicon path fix (same behavior as newer script)
if ! have brew && [[ -x /opt/homebrew/bin/brew ]]; then export PATH="/opt/homebrew/bin:$PATH"; fi
have brew || { echo "ERROR: brew still not available after install" >&2; exit 1; }

if [[ "$UPGRADE_BREW" -eq 1 ]]; then
  echo "Updating and upgrading Homebrew packages..." >&2
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "+ brew update" >&2
    echo "+ brew upgrade --cask --greedy" >&2
    echo "+ brew upgrade" >&2
  else
    brew update
    brew upgrade --cask --greedy
    brew upgrade
  fi
fi

# jq is required
if ! have jq; then
  echo "Installing jq..." >&2
  run brew install jq
fi

# ---- brew formulae ----
echo "Installing brew formulae..." >&2
deps brew | while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  if brew list "$p" &>/dev/null; then
    echo "✓ brew already installed: $p" >&2
  else
    [[ "$QUIET" -eq 1 ]] && run brew install -q "$p" || run brew install "$p"
  fi
done

# ---- brew casks ----
echo "Installing brew casks..." >&2
deps brewcask | while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  if brew list --cask "$p" &>/dev/null; then
    echo "✓ cask already installed: $p" >&2
  else
    [[ "$QUIET" -eq 1 ]] && run brew install -q --cask "$p" || run brew install --cask "$p"
  fi
done

# ---- custom commands (no eval; same as newer script) ----
echo "Running custom installers/commands..." >&2
deps custom | while IFS= read -r entry; do
  [[ -n "$entry" ]] || continue
  name="$(jq -r '.name' <<<"$entry")"
  cmd="$(jq -r '.command' <<<"$entry")"
  [[ -n "$name" && -n "$cmd" ]] || { echo "ERROR: Invalid custom entry: $entry" >&2; exit 1; }

  echo "→ custom: $name" >&2
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "+ bash -lc \"$cmd\"" >&2
  else
    bash -lc "$cmd" >/dev/null 2>&1 || { echo "ERROR: custom command failed: $name" >&2; exit 1; }
  fi
done

# ---- go tools (parallel; uses go env GOPATH like newer script) ----
if have go; then
  echo "Installing/upgrading go tools..." >&2
  GOPATH_ACTUAL="$(go env GOPATH)"
  [[ -n "$GOPATH_ACTUAL" ]] || { echo "ERROR: go env GOPATH returned empty" >&2; exit 1; }
  export PATH="$GOPATH_ACTUAL/bin:$PATH"

  deps go | xargs -I{} -P "$MAX_JOBS" bash -lc '
    set -Eeuo pipefail
    pkg="$1"
    echo "→ go install $pkg@latest" >&2
    go install "$pkg"@latest
  ' _ {}
else
  echo "Go not found; skipping go installs." >&2
fi

# ---- gcloud components ----
if [[ "$GCLOUD_COMPONENTS_INSTALL" -eq 1 ]]; then
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
fi

# ---- nvm/node ----
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && . "$NVM_DIR/bash_completion" || true

if have nvm && [[ "$NVM_INSTALL_DEFAULT" -eq 1 ]]; then
  echo "Installing node versions via nvm..." >&2
  deps nvm | while IFS= read -r v; do
    [[ -n "$v" ]] || continue
    [[ "$DRY_RUN" -eq 1 ]] && echo "+ nvm install \"$v\"" >&2 || nvm install "$v"
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

# ---- python venv + pip (single-shot; recreate toggle) ----
if [[ "$RECREATE_VENV" -eq 1 && -d "$PIP_VENV" ]]; then
  echo "Removing venv at $PIP_VENV (RECREATE_VENV=1)..." >&2
  run rm -rf "$PIP_VENV"
fi

if [[ ! -d "$PIP_VENV" ]]; then
  echo "Creating venv at $PIP_VENV ..." >&2
  [[ -x "$PYTHON_BIN" ]] || { echo "ERROR: Python not executable at $PYTHON_BIN" >&2; exit 1; }
  run "$PYTHON_BIN" -m venv "$PIP_VENV"
fi

# shellcheck disable=SC1090
source "$PIP_VENV/bin/activate"

echo "Ensuring pip is up to date..." >&2
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "+ python -m ensurepip --upgrade" >&2
  echo "+ pip install -U pip" >&2
else
  python -m ensurepip --upgrade
  pip install -U pip
fi

echo "Installing/upgrading pip packages..." >&2
PIP_PKGS="$(jq -r '.pip[]? // empty' "$DEPS_FILE" | tr '\n' ' ')"
if [[ -n "$PIP_PKGS" ]]; then
  [[ "$DRY_RUN" -eq 1 ]] && echo "+ pip install -qU $PIP_PKGS" >&2 || pip install -qU $PIP_PKGS
else
  echo "No pip packages listed." >&2
fi

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

# ---- sdkman (relaxed subshell; tolerate benign failures like newer script) ----
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

echo "✅ Done." >&2
