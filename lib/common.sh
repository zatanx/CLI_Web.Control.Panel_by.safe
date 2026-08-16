#!/usr/bin/env bash

readonly EXIT_GENERAL=1 EXIT_INVALID_ARGUMENT=2 EXIT_PERMISSION=3 EXIT_VALIDATION=4 EXIT_SYSTEM=5
SERVERCTL_VERSION="${SERVERCTL_VERSION:-1.0.5}"
SERVERCTL_RELEASE_DATE="${SERVERCTL_RELEASE_DATE:-2026-08-16}"
SERVERCTL_ROOT="${SERVERCTL_ROOT:-}"
SERVERCTL_TEST_MODE="${SERVERCTL_TEST_MODE:-0}"
SERVERCTL_ASSUME_YES="${SERVERCTL_ASSUME_YES:-0}"
SERVERCTL_COLOR="${SERVERCTL_COLOR:-auto}"
PARSED_ARGS=()
ROLLBACK_FILES=()

root_path() {
  local path=$1
  if [[ -n "$SERVERCTL_ROOT" ]]; then printf '%s%s' "${SERVERCTL_ROOT%/}" "$path"; else printf '%s' "$path"; fi
}

CONFIG_FILE="${SERVERCTL_CONFIG_FILE:-$(root_path /etc/serverctl/serverctl.conf)}"
STATE_DIR="$(root_path /var/lib/serverctl)"
LOG_DIR="$(root_path /var/log/serverctl)"
BACKUP_DIR="$(root_path /var/backups/serverctl)"
WEB_ROOT="$(root_path /var/www)"
SERVERCTL_LOG_FILE="$LOG_DIR/serverctl.log"
AUDIT_LOG="$LOG_DIR/audit.log"
DEFAULT_PHP_VERSION=8.3
BACKUP_RETENTION=30
SSH_PORT=22
TIMEZONE=Asia/Bangkok
ALLOWED_PHP_VERSIONS="8.2 8.3 8.4"
REMOTE_BACKUP_TARGET=""
SERVERCTL_SOURCE_DIR="${SERVERCTL_SOURCE_DIR:-}"

supports_color() { [[ "$SERVERCTL_COLOR" == always ]] || [[ "$SERVERCTL_COLOR" == auto && -t 1 && "${TERM:-dumb}" != dumb ]]; }
color() { local code=$1; shift; if supports_color; then printf '\033[%sm%s\033[0m' "$code" "$*"; else printf '%s' "$*"; fi; }
info() { printf '%s %s\n' "$(color '1;34' '[ INFO ]')" "$*"; }
ok() { printf '%s %s\n' "$(color '1;32' '[ OK ]')" "$*"; }
warn() { printf '%s %s\n' "$(color '1;33' '[ WARNING ]')" "$*" >&2; }
error() { printf '%s %s\n' "$(color '1;31' '[ ERROR ]')" "$*" >&2; }
serverctl_version() {
  printf 'serverctl version %s\n' "$SERVERCTL_VERSION"
}
die() {
  local message=$1 rc=${2:-$EXIT_GENERAL}
  error "$message"
  audit_event "${SERVERCTL_AUDIT_ACTION:-unknown}" FAILED "exit=$rc"
  exit "$rc"
}

parse_global_options() {
  PARSED_ARGS=()
  while (($#)); do
    case "$1" in
      --no-color) SERVERCTL_COLOR=never ;;
      --yes|-y) SERVERCTL_ASSUME_YES=1 ;;
      *) PARSED_ARGS+=("$1") ;;
    esac
    shift
  done
}

load_config() {
  [[ -f "$CONFIG_FILE" ]] || return 0
  local key value
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^[A-Z_]+$ ]] || continue
    value=${value%$'\r'}
    case "$key" in
      DEFAULT_PHP_VERSION) validate_php_version "$value" && DEFAULT_PHP_VERSION=$value ;;
      BACKUP_RETENTION) [[ "$value" =~ ^(7|14|30|90)$ ]] && BACKUP_RETENTION=$value ;;
      BACKUP_PATH) validate_backup_path "$value" && BACKUP_DIR=$(root_path "$value") ;;
      WEB_ROOT) [[ "$value" == /var/www || "$value" == /srv/www ]] && WEB_ROOT=$(root_path "$value") ;;
      SSH_PORT) [[ "$value" =~ ^[0-9]+$ ]] && ((value >= 1 && value <= 65535)) && SSH_PORT=$value ;;
      TIMEZONE) [[ "$value" =~ ^[A-Za-z_+-]+(/[A-Za-z0-9_+-]+)+$ ]] && TIMEZONE=$value ;;
      ALLOWED_PHP_VERSIONS) [[ "$value" =~ ^[0-9.\ ]+$ ]] && ALLOWED_PHP_VERSIONS=$value ;;
      REMOTE_BACKUP_TARGET) validate_remote_backup_target "$value" && REMOTE_BACKUP_TARGET=$value ;;
      SERVERCTL_SOURCE_DIR) [[ "$value" == /* ]] && SERVERCTL_SOURCE_DIR=$value ;;
    esac
  done < "$CONFIG_FILE"
}

init_runtime() {
  mkdir -p -- "$STATE_DIR/websites" "$STATE_DIR/databases" "$STATE_DIR/locks" "$LOG_DIR" "$BACKUP_DIR"
  if [[ -d "$STATE_DIR/dashboard" ]]; then chmod 0751 "$STATE_DIR" 2>/dev/null || true; else chmod 0750 "$STATE_DIR" 2>/dev/null || true; fi
  chmod 0750 "$LOG_DIR" "$BACKUP_DIR" 2>/dev/null || true
  touch "$SERVERCTL_LOG_FILE" "$AUDIT_LOG"
  chmod 0640 "$SERVERCTL_LOG_FILE" "$AUDIT_LOG" 2>/dev/null || true
}

require_root() {
  if [[ "$SERVERCTL_TEST_MODE" != 1 && ${EUID:-$(id -u)} -ne 0 ]]; then
    die "This operation requires root. Run with sudo." "$EXIT_PERMISSION"
  fi
}

timestamp() { date '+%Y-%m-%dT%H:%M:%S%z'; }
log_message() { printf '%s [%s] %s\n' "$(timestamp)" "$1" "$2" >> "$SERVERCTL_LOG_FILE"; }

client_ip() {
  local connection=${SSH_CONNECTION:-} ip
  ip=${connection%% *}
  if [[ -z "$ip" || "$ip" == "$connection" ]]; then ip=local; fi
  printf '%s' "$ip"
}

audit_event() {
  local action=${1:-unknown} result=${2:-UNKNOWN} detail=${3:-}
  action=$(printf '%s' "$action" | tr '\n\r\t' '   ' | sed -E 's/(password|token|secret|key)=[^ ]+/\1=[REDACTED]/Ig')
  detail=$(printf '%s' "$detail" | tr '\n\r\t' '   ' | sed -E 's/(password|token|secret|key)=[^ ]+/\1=[REDACTED]/Ig')
  [[ -d "$LOG_DIR" ]] || return 0
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(timestamp)" "${SUDO_USER:-${USER:-unknown}}" "$(client_ip)" "$action" "$result" "$detail" >> "$AUDIT_LOG"
}

redact_command() {
  local item output="" redact_next=0
  for item in "$@"; do
    if ((redact_next)); then item='[REDACTED]'; redact_next=0
    else
      case "$item" in
        --password-hash|--password|--token|--secret|--private-key) item='[REDACTED]'; redact_next=1 ;;
        *password*|*token*|*secret*|*key*) item='[REDACTED]' ;;
      esac
    fi
    output+="${output:+ }$item"
  done
  printf '%s' "$output"
}

confirm() {
  local prompt=$1 expected=${2:-}
  [[ "$SERVERCTL_ASSUME_YES" == 1 ]] && return 0
  [[ -t 0 ]] || { warn "Confirmation required; use --yes for automation."; return 1; }
  local answer
  if [[ -n "$expected" ]]; then
    printf '%s Type %s to confirm: ' "$prompt" "$expected"
    read -r answer
    [[ "$answer" == "$expected" ]]
  else
    printf '%s [y/N]: ' "$prompt"
    read -r answer
    [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
  fi
}

has_command() { command -v "$1" >/dev/null 2>&1; }
run_cmd() {
  log_message INFO "run: $(redact_command "$@")"
  if [[ "$SERVERCTL_TEST_MODE" == 1 ]]; then return 0; fi
  "$@"
}

service_is_active() { systemctl is-active --quiet "$1" 2>/dev/null; }
with_lock() {
  local name=$1; shift
  if has_command flock; then
    local lock_file="$STATE_DIR/locks/$name.lock" fd
    exec {fd}>"$lock_file"
    flock -n "$fd" || die "Another $name operation is in progress." "$EXIT_SYSTEM"
    "$@"
    local rc=$?
    flock -u "$fd"
    exec {fd}>&-
    return "$rc"
  fi
  "$@"
}

backup_config_file() {
  local file=$1
  [[ -e "$file" || -L "$file" ]] || return 0
  local snapshot="$file.serverctl.$(date +%s).bak"
  cp -a -- "$file" "$snapshot"
  ROLLBACK_FILES+=("$file|$snapshot")
}

rollback_configs() {
  local pair original snapshot
  for pair in "${ROLLBACK_FILES[@]}"; do
    original=${pair%%|*}; snapshot=${pair#*|}
    cp -a -- "$snapshot" "$original" || true
    rm -f -- "$snapshot"
  done
  ROLLBACK_FILES=()
}

commit_configs() {
  local pair snapshot
  for pair in "${ROLLBACK_FILES[@]}"; do snapshot=${pair#*|}; rm -f -- "$snapshot"; done
  ROLLBACK_FILES=()
}

atomic_write() {
  local destination=$1 mode=${2:-0640} owner=${3:-root} group=${4:-root}
  local directory temporary
  directory=$(dirname -- "$destination")
  mkdir -p -- "$directory"
  temporary=$(mktemp "$directory/.serverctl.XXXXXX")
  cat > "$temporary"
  chmod "$mode" "$temporary"
  if [[ "$SERVERCTL_TEST_MODE" != 1 ]]; then chown "$owner:$group" "$temporary"; fi
  mv -f -- "$temporary" "$destination"
}

human_bytes() {
  local bytes=${1:-0} units=(B KB MB GB TB) index=0
  while ((bytes >= 1024 && index < 4)); do bytes=$((bytes / 1024)); ((index+=1)); done
  printf '%s %s' "$bytes" "${units[$index]}"
}

extract_flag_value() {
  local flag=$1; shift
  while (($#)); do
    if [[ "$1" == "$flag" ]]; then (($# >= 2)) || return 2; printf '%s' "$2"; return 0; fi
    shift
  done
  return 1
}

has_flag() { local wanted=$1; shift; local item; for item in "$@"; do [[ "$item" == "$wanted" ]] && return 0; done; return 1; }
