#!/usr/bin/env bash

set -eu

LAST_TAG=$(git describe --tags --abbrev=0)
echo "Last tag: $LAST_TAG"
V_PREFIX=false
if [[ $LAST_TAG == v* ]]; then
    V_PREFIX=true
    LAST_TAG="${LAST_TAG#v}"  # Remove the 'v' prefix
fi

IFS='.' read -r LAST_MAJOR LAST_MINOR LAST_PATCH <<< "$LAST_TAG"

FEATURES=$(git log "$(git describe --tags --abbrev=0)"..HEAD --oneline --grep='feat:')
FIXES=$(git log "$(git describe --tags --abbrev=0)"..HEAD --oneline --grep='fix:')
CHORES=$(git log "$(git describe --tags --abbrev=0)"..HEAD --oneline --grep='chore:')

if [[ -z "$FEATURES" && -z "$FIXES" && -z "$CHORES" ]]; then
  echo "No changes since last tag"
  exit 0
fi

# Check if feature is not empty
if [[ -n "$FEATURES" ]]; then
  echo "Minor version bump"
  NEXT_MAJOR=$LAST_MAJOR
  NEXT_MINOR="$((10#$LAST_MINOR + 1))"
  NEXT_PATCH="0"
elif [[ -n "$FIXES" || -n "$CHORES" ]]; then
  echo "Patch version bump"
  NEXT_MAJOR=$LAST_MAJOR
  NEXT_MINOR=$LAST_MINOR
  NEXT_PATCH="$((10#$LAST_PATCH + 1))"
fi

NEXT_TAG="$NEXT_MAJOR.$NEXT_MINOR.$NEXT_PATCH"
if [[ $V_PREFIX == true ]]; then
    NEXT_TAG="v$NEXT_TAG"
fi
echo "Next tag: $NEXT_TAG"

git tag -a "$NEXT_TAG" -m "$NEXT_TAG"
git push origin "$NEXT_TAG"
