#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${1:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

clean_repo() {
  git reset --hard HEAD
  git clean -ffd -e fblog_system/node_modules -e fblog_system/target

  git submodule foreach --recursive '
    set -e
    git reset --hard HEAD
    if [ "$name" = "fblog_system" ]; then
      git clean -ffd -e node_modules -e target
    else
      git clean -ffd
    fi
  '
}

cd "$REPO_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: $REPO_DIR is not a git repository" >&2
  exit 1
fi

log "Cleaning repository before pull"
clean_repo

log "Updating repository"
git pull --ff-only --recurse-submodules

git submodule sync --recursive
git submodule update --init --recursive --jobs 8

log "Resetting repository to clean state"
clean_repo

git submodule update --init --recursive --jobs 8

MISE_BIN="${MISE_BIN:-$(command -v mise || true)}"
if [ -z "$MISE_BIN" ]; then
  for candidate in /usr/bin/mise "$HOME/.local/bin/mise" "$HOME/bin/mise"; do
    if [ -x "$candidate" ]; then
      MISE_BIN="$candidate"
      break
    fi
  done
fi

if [ -z "$MISE_BIN" ]; then
  echo "ERROR: mise command not found" >&2
  exit 1
fi

log "Running mise trust/install/deploy"
"$MISE_BIN" trust -y -a
"$MISE_BIN" install -y
"$MISE_BIN" run deploy

log "Finished"
