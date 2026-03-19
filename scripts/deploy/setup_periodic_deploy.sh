#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-nicovideo-search-ap-deploy}"
DEPLOY_USER="${DEPLOY_USER:-nicovideo-ap}"
DEPLOY_HOME="${DEPLOY_HOME:-/var/lib/${DEPLOY_USER}}"
REPO_URL="${REPO_URL:-https://github.com/White-Green/nicovideo-search-ap}"
REPO_DIR="${REPO_DIR:-${DEPLOY_HOME}/nicovideo-search-ap}"
CREDENTIAL_DIR="${CREDENTIAL_DIR:-/etc/nicovideo-search-ap/credentials}"
CREDENTIAL_ACCOUNT_FILE="${CREDENTIAL_ACCOUNT_FILE:-${CREDENTIAL_DIR}/cloudflare_account_id}"
CREDENTIAL_TOKEN_FILE="${CREDENTIAL_TOKEN_FILE:-${CREDENTIAL_DIR}/cloudflare_api_token}"

log() {
  printf '[setup] %s\n' "$*"
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run as root (sudo)." >&2
    exit 1
  fi
}

ensure_user() {
  local nologin_shell current_home
  nologin_shell="$(command -v nologin || true)"
  if [ -z "$nologin_shell" ]; then
    nologin_shell="/usr/sbin/nologin"
  fi

  if id -u "$DEPLOY_USER" >/dev/null 2>&1; then
    log "user exists: $DEPLOY_USER"
    current_home="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
    if [ "$current_home" != "$DEPLOY_HOME" ]; then
      log "notice: existing home is ${current_home} (requested ${DEPLOY_HOME})"
    fi
  else
    log "creating system user: $DEPLOY_USER"
    useradd \
      --system \
      --home-dir "$DEPLOY_HOME" \
      --create-home \
      --shell "$nologin_shell" \
      "$DEPLOY_USER"
  fi

  mkdir -p "$DEPLOY_HOME"
  chown "$DEPLOY_USER:$DEPLOY_USER" "$DEPLOY_HOME"
}

clone_or_update_repo() {
  local parent_dir
  parent_dir="$(dirname "$REPO_DIR")"
  mkdir -p "$parent_dir"
  chown "$DEPLOY_USER:$DEPLOY_USER" "$parent_dir"

  if [ -d "$REPO_DIR/.git" ]; then
    log "updating repository: $REPO_DIR"
    runuser -u "$DEPLOY_USER" -- git -C "$REPO_DIR" fetch --prune --tags origin
    runuser -u "$DEPLOY_USER" -- git -C "$REPO_DIR" pull --ff-only --recurse-submodules
    runuser -u "$DEPLOY_USER" -- git -C "$REPO_DIR" submodule sync --recursive
    runuser -u "$DEPLOY_USER" -- git -C "$REPO_DIR" submodule update --init --recursive --jobs 8
  else
    log "cloning repository: $REPO_URL"
    runuser -u "$DEPLOY_USER" -- git clone --recurse-submodules "$REPO_URL" "$REPO_DIR"
  fi
}

copy_scripts_from_repo() {
  local repo_runner repo_service_template repo_timer_template
  repo_runner="$REPO_DIR/scripts/deploy/run_periodic_deploy.sh"
  repo_service_template="$REPO_DIR/scripts/deploy/systemd/nicovideo-search-ap-deploy.service.template"
  repo_timer_template="$REPO_DIR/scripts/deploy/systemd/nicovideo-search-ap-deploy.timer.template"

  if [ ! -f "$repo_runner" ] || [ ! -f "$repo_service_template" ] || [ ! -f "$repo_timer_template" ]; then
    echo "ERROR: required deploy files not found in cloned repository" >&2
    echo "Expected files:" >&2
    echo "  $repo_runner" >&2
    echo "  $repo_service_template" >&2
    echo "  $repo_timer_template" >&2
    exit 1
  fi

  chmod 755 "$repo_runner"
  chown "$DEPLOY_USER:$DEPLOY_USER" "$repo_runner"

  sed \
    -e "s|<DEPLOY_USER>|${DEPLOY_USER}|g" \
    -e "s|<DEPLOY_HOME>|${DEPLOY_HOME}|g" \
    -e "s|<REPO_DIR>|${REPO_DIR}|g" \
    -e "s|<CREDENTIAL_ACCOUNT_FILE>|${CREDENTIAL_ACCOUNT_FILE}|g" \
    -e "s|<CREDENTIAL_TOKEN_FILE>|${CREDENTIAL_TOKEN_FILE}|g" \
    "$repo_service_template" >"/etc/systemd/system/${SERVICE_NAME}.service"

  sed \
    -e "s|<SERVICE_NAME>|${SERVICE_NAME}|g" \
    "$repo_timer_template" >"/etc/systemd/system/${SERVICE_NAME}.timer"
}

write_credentials() {
  mkdir -p "$CREDENTIAL_DIR"
  chmod 700 "$CREDENTIAL_DIR"
  mkdir -p "$(dirname "$CREDENTIAL_ACCOUNT_FILE")"
  mkdir -p "$(dirname "$CREDENTIAL_TOKEN_FILE")"

  if [ ! -f "$CREDENTIAL_ACCOUNT_FILE" ]; then
    log "creating credential placeholder: $CREDENTIAL_ACCOUNT_FILE"
    printf '%s\n' 'REPLACE_ME' >"$CREDENTIAL_ACCOUNT_FILE"
    chmod 600 "$CREDENTIAL_ACCOUNT_FILE"
  else
    log "credential exists: $CREDENTIAL_ACCOUNT_FILE"
  fi

  if [ ! -f "$CREDENTIAL_TOKEN_FILE" ]; then
    log "creating credential placeholder: $CREDENTIAL_TOKEN_FILE"
    printf '%s\n' 'REPLACE_ME' >"$CREDENTIAL_TOKEN_FILE"
    chmod 600 "$CREDENTIAL_TOKEN_FILE"
  else
    log "credential exists: $CREDENTIAL_TOKEN_FILE"
  fi
}

enable_timer() {
  log "enabling timer"
  systemctl daemon-reload
  systemctl enable --now "${SERVICE_NAME}.timer"
  systemctl --no-pager --full status "${SERVICE_NAME}.timer" || true
}

print_next_steps() {
  cat <<MSG
[setup] next steps:
  1) set credentials:
     - sudoedit ${CREDENTIAL_ACCOUNT_FILE}
     - sudoedit ${CREDENTIAL_TOKEN_FILE}
  2) run first deploy manually:
     sudo systemctl start ${SERVICE_NAME}.service
  3) check logs:
     sudo journalctl -u ${SERVICE_NAME}.service -n 200 --no-pager
MSG
}

main() {
  require_root
  ensure_user
  clone_or_update_repo
  copy_scripts_from_repo
  write_credentials
  enable_timer
  print_next_steps
  log "done"
}

main "$@"
