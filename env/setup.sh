#!/bin/bash

set -eo pipefail

# This script installs all the dependencies from the deps.json file

# check if xcode cli tools are installed
if ! command -v xcode-select &>/dev/null; then
    echo You need to install xcode, please accept the prompt and allow it to install
    xcode-select --install
fi

# install homebrew if not present
if ! command -v brew &>/dev/null; then
    # homebrew is not installed, install it
    echo Installing homebrew
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Upgrade homebrew and all packages
brew update && brew upgrade --cask --greedy && brew upgrade

if ! command -v jq &>/dev/null; then
    echo Installing jq
    brew install jq
fi

function get_deps() {
    jq -c --raw-output ".$1[]" ./deps.json
}

get_deps "brew" | while read -r package; do
    # brew
    brew install -q $package
done

get_deps "brewcask" | while read -r package; do
    brew install -q --cask $package
done

get_deps "go" | while read -r package; do
    name=$(echo $package | rev | cut -d/ -f1 | rev)
    rm -f "$GOPATH/bin/$name" || true
    go install "$package"@latest
done

get_deps "gcloud" | while read -r package; do
    gcloud components install --quiet $package
done

get_deps "custom" | while read -r package; do
    name=$(echo "$package" | jq -r '.name')
    cmd=$(echo "$package" | jq -r '.command')

    eval "$cmd" >/dev/null 2>&1
done

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"                   # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion" # This loads nvm bash_completion
get_deps "nvm" | while read -r package; do
    nvm install "$package"
done

get_deps "npm" | while read -r package; do
    npm i -g "$package"
done

# if ~/.venv exists, delete it
if [ -d ~/.venv ]; then
    rm -rf ~/.venv || true
fi
/opt/homebrew/bin/python3 -m venv ~/.venv
source ~/.venv/bin/activate
python -m ensurepip --upgrade
pip install --upgrade pip
get_deps "pip" | while read -r package; do
    echo "Installing $package"
    pip install -qU $package
done

get_deps "jupyter" | while read -r package; do
    jupyter server extension enable --py $package
done

source "$HOME/.sdkman/bin/sdkman-init.sh"
get_deps "sdk" | while read -r package; do
    sdk install $package
    sdk default $package
    sdk use $package
done
