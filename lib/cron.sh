#!/usr/bin/env bash

# Cron is deliberately implemented as a data-driven manager.  User supplied
# values are validated before they are written to a cron file; Run Now and
# the Dashboard only ever execute a command looked up by numeric job ID.

CRON_OUTPUT_LIMIT_BYTES=${CRON_OUTPUT_LIMIT_BYTES:-1048576}
CRON_TIMEOUT_SECONDS=${CRON_TIMEOUT_SECONDS:-300}
CRON_EXECUTABLE=${CRON_EXECUTABLE:-$(root_path /usr/local/libexec/serverctl-cron-run)}

cron_jobs_dir() { printf '%s/cron/jobs' "$STATE_DIR"; }
cron_record_path() { printf '%s/%s.conf' "$(cron_jobs_dir)" "$1"; }
cron_config_dir() { printf '%s' "$(root_path /etc/cron.d)"; }
cron_website_config_path() { printf '%s/serverctl-websites' "$(cron_config_dir)"; }
cron_log_dir() { printf '%s/cron' "$LOG_DIR"; }
cron_log_path() { printf '%s/cron-%s.log' "$(cron_log_dir)" "$1"; }
cron_backup_dir() { printf '%s/cron' "$BACKUP_DIR"; }
cron_lock_path() { printf '%s/cron-job-%s.lock' "$STATE_DIR/locks" "$1"; }
cron_config_lock_path() { printf '%s/cron-config.lock' "$STATE_DIR/locks"; }

cron_valid_id() { [[ "${1:-}" =~ ^[1-9][0-9]{0,8}$ ]]; }

cron_validate_field() {
  local value=${1:-} minimum=${2:-0} maximum=${3:-0} part base step start end number
  [[ "$value" =~ ^[-0-9,/*]+$ ]] || return 1
  IFS=',' read -r -a parts <<< "$value"
  ((${#parts[@]} > 0)) || return 1
  for part in "${parts[@]}"; do
    [[ -n "$part" ]] || return 1
    step=1
    base=$part
    if [[ "$part" == */* ]]; then
      base=${part%%/*}; step=${part##*/}
      [[ "$base" != */* && "$step" =~ ^[0-9]+$ && $((10#$step)) -ge 1 && $((10#$step)) -le 1000 ]] || return 1
    fi
    if [[ "$base" == '*' ]]; then
      continue
    elif [[ "$base" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start=${BASH_REMATCH[1]}; end=${BASH_REMATCH[2]}
      [[ $((10#$start)) -le $((10#$end)) && $((10#$start)) -ge $minimum && $((10#$end)) -le $maximum ]] || return 1
    elif [[ "$base" =~ ^[0-9]+$ ]]; then
      number=$base
      [[ $((10#$number)) -ge $minimum && $((10#$number)) -le $maximum ]] || return 1
    else
      return 1
    fi
  done
}

cron_validate_expression() {
  local expression=${1:-} field
  [[ -n "$expression" && "$expression" != *$'\n'* && "$expression" != *$'\r'* ]] || return 1
  read -r -a fields <<< "$expression"
  ((${#fields[@]} == 5)) || return 1
  cron_validate_field "${fields[0]}" 0 59 || return 1
  cron_validate_field "${fields[1]}" 0 23 || return 1
  cron_validate_field "${fields[2]}" 1 31 || return 1
  cron_validate_field "${fields[3]}" 1 12 || return 1
  cron_validate_field "${fields[4]}" 0 7 || return 1
  for field in "${fields[@]}"; do [[ "$field" != *' '* && "$field" != *$'\t'* ]] || return 1; done
}

cron_validate_user() {
  local user=${1:-}
  [[ "$user" =~ ^[a-z_][a-z0-9_-]{0,31}\$?$ ]] || return 1
  [[ "$SERVERCTL_TEST_MODE" == 1 ]] && return 0
  getent passwd "$user" >/dev/null 2>&1
}

cron_validate_description() {
  local description=${1:-}
  ((${#description} <= 200)) || return 1
  [[ "$description" != *$'\n'* && "$description" != *$'\r'* && "$description" != *$'\t'* && "$description" =~ ^[[:print:]]*$ ]]
}

cron_allowed_executable() {
  local executable=${1:-}
  [[ "$executable" =~ ^/usr/bin/php([0-9]+(\.[0-9]+)?)?$ ]] && return 0
  [[ "$executable" =~ ^/usr/bin/python3(\.[0-9]+)?$ ]] && return 0
  [[ "$executable" == /usr/bin/curl || "$executable" == /usr/bin/wget || "$executable" == /usr/bin/perl || "$executable" == /usr/bin/ruby ]] && return 0
  return 1
}

cron_validate_command() {
  local command=${1:-} executable token
  [[ -n "$command" && ${#command} -le 4096 ]] || return 1
  [[ "$command" != *$'\n'* && "$command" != *$'\r'* && "$command" != *'..'* && "$command" != *'//' ]] || return 1
  # This character allow-list intentionally excludes shell syntax, quoting,
  # expansion, globbing and redirection.  Commands are later executed as an
  # argv array, never through a shell interpreter.
  [[ "$command" =~ ^[-A-Za-z0-9_./:@%+=,?~]+([[:space:]]+[-A-Za-z0-9_./:@%+=,?~]+)*$ ]] || return 1
  read -r -a command_parts <<< "$command"
  ((${#command_parts[@]} > 0)) || return 1
  executable=${command_parts[0]}
  [[ "$executable" == /* ]] || return 1
  cron_allowed_executable "$executable" || return 1
  if [[ "$SERVERCTL_TEST_MODE" != 1 && ! -x "$executable" ]]; then return 1; fi
  for token in "${command_parts[@]}"; do [[ "$token" != *'..'* ]] || return 1; done
}

cron_validate_type() { [[ "${1:-}" == system || "${1:-}" == website ]]; }
cron_validate_enabled() { [[ "${1:-}" == yes || "${1:-}" == no ]]; }

# Shared validation entry point used by both CLI and Dashboard adapters.
validate_cron_job() {
  local user=${1:-} schedule=${2:-} command=${3:-} description=${4:-} enabled=${5:-yes} type=${6:-system}
  cron_validate_user "$user" || return 1
  cron_validate_expression "$schedule" || return 1
  cron_validate_command "$command" || return 1
  cron_validate_description "$description" || return 1
  cron_validate_enabled "$enabled" || return 1
  cron_validate_type "$type" || return 1
  if [[ "$type" == website && "$user" == root ]]; then return 1; fi
}

cron_split_schedule() {
  local schedule=$1
  read -r CRON_MINUTE CRON_HOUR CRON_DAY CRON_MONTH CRON_WEEKDAY <<< "$schedule"
}

cron_json_string() {
  local value=${1:-}
  value=${value//\\/\\\\}; value=${value//\"/\\\"}
  value=${value//$'\r'/\\r}; value=${value//$'\n'/\\n}; value=${value//$'\t'/\\t}
  printf '"%s"' "$value"
}

cron_json_number() { [[ "${1:-}" =~ ^-?[0-9]+$ ]] && printf '%s' "$1" || printf '0'; }

cron_job_files() {
  local directory
  directory=$(cron_jobs_dir)
  [[ -d "$directory" ]] || return 0
  find "$directory" -maxdepth 1 -type f -name '[1-9]*.conf' -print 2>/dev/null | sort -V
}

cron_next_run() {
  local schedule=${1:-} current target day_epoch day_offset day_value month_value weekday_value date_value candidate hour minute
  cron_validate_expression "$schedule" || { printf '—'; return 0; }
  current=$(date +%s)
  target=$((current - current % 60 + 60))
  cron_split_schedule "$schedule"
  day_epoch=$(date -d "$(date '+%Y-%m-%d') 00:00" +%s 2>/dev/null || printf 0)
  # Iterate over calendar days and only the matching hour/minute fields. This
  # avoids spawning `date` once per minute when the Dashboard refreshes.
  for ((day_offset=0; day_offset<=366; day_offset++)); do
    date_value=$(date -d "@$day_epoch" '+%Y-%m-%d %d %m %w' 2>/dev/null || true)
    read -r date_value day_value month_value weekday_value <<< "$date_value"
    [[ "$day_value" =~ ^[0-9]+$ && "$month_value" =~ ^[0-9]+$ && "$weekday_value" =~ ^[0-9]+$ ]] || break
    day_value=$((10#$day_value)); month_value=$((10#$month_value)); weekday_value=$((10#$weekday_value))
    if cron_field_matches "$CRON_DAY" "$day_value" 1 31 && cron_field_matches "$CRON_MONTH" "$month_value" 1 12 && cron_field_matches "$CRON_WEEKDAY" "$weekday_value" 0 7; then
      for ((hour=0; hour<=23; hour++)); do
        cron_field_matches "$CRON_HOUR" "$hour" 0 23 || continue
        for ((minute=0; minute<=59; minute++)); do
          cron_field_matches "$CRON_MINUTE" "$minute" 0 59 || continue
          candidate=$((day_epoch + hour * 3600 + minute * 60))
          if ((candidate >= target)); then date -d "@$candidate" '+%Y-%m-%d %H:%M' 2>/dev/null; return 0; fi
        done
      done
    fi
    day_epoch=$((day_epoch + 86400))
  done
  printf '—'
}

cron_token_matches() {
  local token=$1 value=$2 minimum=$3 maximum=$4 base step start end
  step=1; base=$token
  if [[ "$token" == */* ]]; then base=${token%%/*}; step=${token##*/}; fi
  if [[ "$base" == '*' ]]; then start=$minimum; end=$maximum
  elif [[ "$base" =~ ^([0-9]+)-([0-9]+)$ ]]; then start=${BASH_REMATCH[1]}; end=${BASH_REMATCH[2]}
  elif [[ "$base" =~ ^[0-9]+$ ]]; then start=$base; end=$base
  else return 1; fi
  ((value >= 10#$start && value <= 10#$end && (value - 10#$start) % 10#$step == 0))
}

cron_field_matches() {
  local expression=$1 value=$2 minimum=$3 maximum=$4 token
  IFS=',' read -r -a tokens <<< "$expression"
  for token in "${tokens[@]}"; do
    cron_token_matches "$token" "$value" "$minimum" "$maximum" && return 0
    [[ "$minimum" == 0 && "$maximum" == 7 && "$value" == 0 ]] && cron_token_matches "$token" 7 "$minimum" "$maximum" && return 0
  done
  return 1
}

cron_validate_record() {
  local record=$1 user schedule command description enabled type id
  [[ -f "$record" ]] || return 1
  id=$(record_get "$record" ID || true)
  [[ "$(basename -- "$record")" == "$id.conf" ]] || return 1
  user=$(record_get "$record" USER || true); schedule=$(record_get "$record" SCHEDULE || true)
  command=$(record_get "$record" COMMAND || true); description=$(record_get "$record" DESCRIPTION || true)
  enabled=$(record_get "$record" ENABLED || true); type=$(record_get "$record" TYPE || true)
  validate_cron_job "$user" "$schedule" "$command" "$description" "$enabled" "$type"
}

cron_prepare_job_files() {
  local id=$1 user=$2
  mkdir -p -- "$(cron_log_dir)" "$(dirname "$(cron_lock_path "$id")")"
  chmod 0755 "$(cron_log_dir)" 2>/dev/null || true
  touch -- "$(cron_log_path "$id")" "$(cron_lock_path "$id")"
  chmod 0600 "$(cron_log_path "$id")" 2>/dev/null || true
  chmod 0666 "$(cron_lock_path "$id")" 2>/dev/null || true
  if [[ "$SERVERCTL_TEST_MODE" != 1 ]]; then
    chown "$user:" "$(cron_log_path "$id")" 2>/dev/null || true
    chown root:root "$(cron_lock_path "$id")" 2>/dev/null || true
  fi
}

cron_write_record() {
  local record=$1 id=$2 user=$3 schedule=$4 command=$5 description=$6 enabled=$7 type=$8 website=${9:-} created=${10:-} last_run=${11:-} last_exit=${12:--} last_status=${13:-NEVER}
  cron_split_schedule "$schedule"
  atomic_write "$record" 0644 root root <<EOF
ID=$id
TYPE=$type
USER=$user
SCHEDULE=$schedule
MINUTE=$CRON_MINUTE
HOUR=$CRON_HOUR
DAY=$CRON_DAY
MONTH=$CRON_MONTH
WEEKDAY=$CRON_WEEKDAY
COMMAND=$command
DESCRIPTION=$description
ENABLED=$enabled
WEBSITE=$website
CREATED_AT=${created:-$(timestamp)}
UPDATED_AT=$(timestamp)
LAST_RUN=$last_run
LAST_EXIT_CODE=$last_exit
LAST_STATUS=$last_status
EOF
}

cron_next_id() {
  local record id max=0
  while IFS= read -r record; do
    id=$(record_get "$record" ID || true)
    [[ "$id" =~ ^[0-9]+$ ]] && ((id > max)) && max=$id
  done < <(cron_job_files)
  printf '%s' "$((max + 1))"
}

cron_render_line() {
  local record=$1 id user schedule
  id=$(record_get "$record" ID); user=$(record_get "$record" USER); schedule=$(record_get "$record" SCHEDULE)
  printf '%s %s %s %s >> %s 2>&1 # serverctl-managed\n' "$schedule" "$user" "$CRON_EXECUTABLE" "$id" "$(cron_log_path "$id")"
}

cron_render_all() {
  local record id type enabled website_lines='' system_file
  local config_dir; config_dir=$(cron_config_dir)
  mkdir -p -- "$config_dir"
  chmod 0755 "$config_dir" 2>/dev/null || true
  shopt -s nullglob
  for system_file in "$config_dir"/serverctl-cron-*; do rm -f -- "$system_file"; done
  rm -f -- "$(cron_website_config_path)"
  shopt -u nullglob
  while IFS= read -r record; do
    cron_validate_record "$record" || die "Invalid Cron record: $(basename "$record")" "$EXIT_VALIDATION"
    id=$(record_get "$record" ID); type=$(record_get "$record" TYPE); enabled=$(record_get "$record" ENABLED)
    cron_prepare_job_files "$id" "$(record_get "$record" USER)"
    [[ "$enabled" == yes ]] || continue
    if [[ "$type" == website ]]; then
      website_lines+="$(cron_render_line "$record")"$'\n'
    else
      system_file="$config_dir/serverctl-cron-$id"
      atomic_write "$system_file" 0644 root root <<EOF
# Managed by serverctl. Do not edit this file; use serverctl cron.
$(cron_render_line "$record")
EOF
    fi
  done < <(cron_job_files)
  if [[ -n "$website_lines" ]]; then
    atomic_write "$(cron_website_config_path)" 0644 root root <<EOF
# Managed by serverctl. Do not edit this file; use serverctl cron website.
$website_lines
EOF
  fi
  if [[ "$SERVERCTL_TEST_MODE" != 1 ]]; then
    local service; service=$(cron_service_name)
    [[ -n "$service" ]] && systemctl reload "$service" >/dev/null 2>&1 || true
  fi
}

cron_backup_configuration() {
  require_root
  local destination file
  destination="$(cron_backup_dir)/$(date '+%Y%m%d-%H%M%S-%N')"
  mkdir -p -- "$destination/jobs" "$destination/cron.d"
  [[ -d "$(cron_jobs_dir)" ]] && cp -a -- "$(cron_jobs_dir)/." "$destination/jobs/"
  shopt -s nullglob
  for file in "$(cron_config_dir)"/serverctl-cron-* "$(cron_website_config_path)"; do [[ -e "$file" ]] && cp -a -- "$file" "$destination/cron.d/"; done
  shopt -u nullglob
  atomic_write "$destination/metadata" 0600 root root <<EOF
DATE=$(timestamp)
USER=${SUDO_USER:-${USER:-unknown}}
SOURCE_IP=$(client_ip)
EOF
  chmod -R go-rwx -- "$destination"
  find "$(cron_backup_dir)" -mindepth 1 -maxdepth 1 -type d -mtime "+$BACKUP_RETENTION" -exec rm -rf -- {} + 2>/dev/null || true
  LAST_CRON_BACKUP=$destination
}

cron_reload_service() {
  [[ "$SERVERCTL_TEST_MODE" == 1 ]] && return 0
  local service; service=$(cron_service_name)
  [[ -n "$service" ]] && systemctl reload "$service" >/dev/null 2>&1 || true
}

cron_lock_acquire() {
  local id=$1 fd
  mkdir -p -- "$(dirname "$(cron_lock_path "$id")")"
  touch -- "$(cron_lock_path "$id")"
  if has_command flock; then
    exec {fd}>>"$(cron_lock_path "$id")"
    if ! flock -n "$fd"; then return 1; fi
    CRON_LOCK_FD=$fd
  fi
  return 0
}

cron_lock_release() {
  local fd=${CRON_LOCK_FD:-}
  [[ -n "$fd" ]] || return 0
  flock -u "$fd" 2>/dev/null || true
  exec {fd}>&-
  CRON_LOCK_FD=''
}

cron_limit_output() {
  local file=$1 size temporary
  size=$(wc -c < "$file" 2>/dev/null || printf 0)
  [[ "$size" =~ ^[0-9]+$ && "$size" -gt "$CRON_OUTPUT_LIMIT_BYTES" ]] || return 0
  temporary=$(mktemp "$(dirname "$file")/.output.XXXXXX")
  head -c "$CRON_OUTPUT_LIMIT_BYTES" -- "$file" > "$temporary"
  printf '\n[OUTPUT TRUNCATED]\n' >> "$temporary"
  mv -f -- "$temporary" "$file"
}

cron_execute_command() {
  local user=$1 command=$2 stdout_file=$3 stderr_file=$4 rc=0 home=/tmp
  local -a parts runner
  read -r -a parts <<< "$command"
  if [[ "$user" == root ]]; then home=/root
  elif [[ "$SERVERCTL_TEST_MODE" != 1 ]]; then home=$(getent passwd "$user" | cut -d: -f6); home=${home:-/}
  fi
  runner=(/usr/bin/env -i "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" "HOME=$home" "USER=$user" "LOGNAME=$user")
  if has_command timeout; then runner=(/usr/bin/timeout --signal=TERM --kill-after=10s "$CRON_TIMEOUT_SECONDS" "${runner[@]}"); fi
  if [[ "$SERVERCTL_TEST_MODE" != 1 && ${EUID:-$(id -u)} -eq 0 && "$user" != root ]]; then
    runner=(/usr/sbin/runuser -u "$user" -- "${runner[@]}")
  fi
  if [[ "$SERVERCTL_TEST_MODE" == 1 ]]; then
    printf '[serverctl test mode] command execution skipped.\n' > "$stdout_file"
    : > "$stderr_file"
    printf '0'
    return 0
  fi
  if "${runner[@]}" "${parts[@]}" >"$stdout_file" 2>"$stderr_file"; then rc=0; else rc=$?; fi
  printf '%s' "$rc"
}

cron_log_run() {
  local id=$1 status=$2 exit_code=$3 start=$4 end=$5 stdout_file=$6 stderr_file=$7 log
  log=$(cron_log_path "$id")
  {
    printf '\n=== CRON RUN %s ===\nStart Time: %s\nEnd Time: %s\nStatus: %s\nExit Code: %s\n' "$id" "$start" "$end" "$status" "$exit_code"
    printf '%s\n' 'Output:'; cat -- "$stdout_file"
    printf '%s\n' 'Error:'; cat -- "$stderr_file"
  } >> "$log"
}

cron_run_common() {
  local record=$1 scheduled=${2:-no} id user command start end rc status tempdir
  local stdout_file stderr_file
  id=$(record_get "$record" ID); user=$(record_get "$record" USER); command=$(record_get "$record" COMMAND)
  if [[ "$scheduled" == yes && "$SERVERCTL_TEST_MODE" != 1 ]]; then
    [[ "$(id -un)" == "$user" ]] || { printf 'Cron user mismatch.\n' >&2; return "$EXIT_PERMISSION"; }
  fi
  if ! cron_lock_acquire "$id"; then
    printf 'SKIPPED\n'
    [[ -f "$(cron_log_path "$id")" ]] && printf '\n=== CRON RUN %s ===\nStatus: SKIPPED\nReason: Job is already running.\n' "$id" >> "$(cron_log_path "$id")" || true
    return 0
  fi
  tempdir=$(mktemp -d "/tmp/serverctl-cron-$id.XXXXXX")
  stdout_file="$tempdir/output"; stderr_file="$tempdir/error"; : > "$stdout_file"; : > "$stderr_file"
  start=$(timestamp)
  rc=$(cron_execute_command "$user" "$command" "$stdout_file" "$stderr_file")
  end=$(timestamp)
  cron_limit_output "$stdout_file"; cron_limit_output "$stderr_file"
  if [[ "$rc" == 124 || "$rc" == 137 || "$rc" == 143 ]]; then status=TIMEOUT
  elif [[ "$rc" == 0 ]]; then status=SUCCESS
  else status=FAILED; fi
  if [[ "$scheduled" != yes ]]; then cron_log_run "$id" "$status" "$rc" "$start" "$end" "$stdout_file" "$stderr_file"; fi
  printf '%s\n' "$status"
  if [[ "$scheduled" != yes ]]; then
    update_record_value "$record" LAST_RUN "$end"
    update_record_value "$record" LAST_EXIT_CODE "$rc"
    update_record_value "$record" LAST_STATUS "$status"
    chmod 0644 "$record" 2>/dev/null || true
    [[ "$SERVERCTL_TEST_MODE" == 1 ]] || chown root:root "$record" 2>/dev/null || true
    audit_event CRON_RUN "$status" "cron_id=$id exit_code=$rc"
  else
    printf 'Exit Code: %s\n' "$rc"
    printf 'Output:\n'; cat -- "$stdout_file"
    printf 'Error:\n'; cat -- "$stderr_file"
  fi
  rm -rf -- "$tempdir"
  cron_lock_release
  [[ "$rc" == 0 ]] && return 0
  return "$EXIT_SYSTEM"
}

run_cron_job() {
  require_root
  local id=${1:-} record
  cron_valid_id "$id" || die 'Invalid Cron job ID.' "$EXIT_VALIDATION"
  record=$(cron_record_path "$id"); [[ -f "$record" ]] || die 'Cron job not found.' "$EXIT_VALIDATION"
  cron_validate_record "$record" || die 'Cron job configuration is invalid.' "$EXIT_VALIDATION"
  printf 'Running...\n'
  cron_run_common "$record" no
}

cron_scheduled_run() {
  local id=${1:-} record
  cron_valid_id "$id" || { printf 'Invalid Cron job ID.\n' >&2; return "$EXIT_VALIDATION"; }
  record=$(cron_record_path "$id"); [[ -f "$record" ]] || { printf 'Cron job not found.\n' >&2; return "$EXIT_VALIDATION"; }
  [[ "$(record_get "$record" ENABLED || true)" == yes ]] || { printf 'DISABLED\n'; return 0; }
  cron_validate_record "$record" || { printf 'Invalid Cron job configuration.\n' >&2; return "$EXIT_VALIDATION"; }
  cron_run_common "$record" yes
}

cron_job_json() {
  local record=$1 id user schedule command description enabled type website last_run last_exit last_status next
  id=$(record_get "$record" ID); user=$(record_get "$record" USER); schedule=$(record_get "$record" SCHEDULE)
  command=$(record_get "$record" COMMAND); description=$(record_get "$record" DESCRIPTION || true); enabled=$(record_get "$record" ENABLED)
  type=$(record_get "$record" TYPE); website=$(record_get "$record" WEBSITE || true); last_run=$(record_get "$record" LAST_RUN || true)
  last_exit=$(record_get "$record" LAST_EXIT_CODE || printf -- -); last_status=$(record_get "$record" LAST_STATUS || printf NEVER); next=$(cron_next_run "$schedule")
  printf '{"id":%s,"user":%s,"schedule":%s,"command":%s,"description":%s,"status":%s,"enabled":%s,"type":%s,"website":%s,"last_run":%s,"last_exit_code":%s,"last_status":%s,"next_run":%s}' \
    "$(cron_json_number "$id")" "$(cron_json_string "$user")" "$(cron_json_string "$schedule")" "$(cron_json_string "$command")" "$(cron_json_string "$description")" \
    "$(cron_json_string "$([[ "$enabled" == yes ]] && printf ENABLED || printf DISABLED)")" "$(cron_json_string "$enabled")" "$(cron_json_string "$type")" "$(cron_json_string "$website")" \
    "$(cron_json_string "$last_run")" "$(cron_json_string "$last_exit")" "$(cron_json_string "$last_status")" "$(cron_json_string "$next")"
}

cron_jobs_json() {
  local record first=1 total=0 enabled=0 disabled=0 failed=0
  printf '{"jobs":['
  while IFS= read -r record; do
    ((first)) || printf ','; first=0; cron_job_json "$record"
    total=$((total + 1)); [[ "$(record_get "$record" ENABLED || true)" == yes ]] && enabled=$((enabled + 1)) || disabled=$((disabled + 1))
    [[ "$(record_get "$record" LAST_STATUS || true)" == FAILED || "$(record_get "$record" LAST_STATUS || true)" == TIMEOUT ]] && failed=$((failed + 1))
  done < <(cron_job_files)
  printf '],"summary":{"total":%s,"enabled":%s,"disabled":%s,"failed_recently":%s}}\n' "$total" "$enabled" "$disabled" "$failed"
}

get_cron_jobs() {
  local record id user schedule enabled last_run next
  printf '%-4s %-16s %-18s %-9s %-19s %-19s\n' ID USER SCHEDULE STATUS 'LAST RUN' 'NEXT RUN'
  printf '%s\n' '--------------------------------------------------------------------------------'
  while IFS= read -r record; do
    id=$(record_get "$record" ID); user=$(record_get "$record" USER); schedule=$(record_get "$record" SCHEDULE); enabled=$(record_get "$record" ENABLED)
    last_run=$(record_get "$record" LAST_RUN || printf -- '-'); next=$(cron_next_run "$schedule")
    printf '%-4s %-16s %-18s %-9s %-19s %-19s\n' "$id" "$user" "$schedule" "$([[ "$enabled" == yes ]] && printf ENABLED || printf DISABLED)" "$last_run" "$next"
  done < <(cron_job_files)
}

get_cron_logs() {
  local id=${1:-} lines=${2:-100} file
  cron_valid_id "$id" || return 1
  [[ "$lines" =~ ^(50|100|500)$ ]] || return 1
  file=$(cron_log_path "$id")
  [[ -f "$file" ]] || { printf 'No log entries.\n'; return 0; }
  tail -n "$lines" -- "$file"
}

cron_service_name() {
  [[ -n "${CRON_SERVICE_OVERRIDE:-}" ]] && { printf '%s' "$CRON_SERVICE_OVERRIDE"; return; }
  if service_is_active cron || { [[ "$SERVERCTL_TEST_MODE" != 1 ]] && systemctl list-unit-files cron.service 2>/dev/null | grep -q '^cron.service'; }; then printf cron
  elif service_is_active crond || { [[ "$SERVERCTL_TEST_MODE" != 1 ]] && systemctl list-unit-files crond.service 2>/dev/null | grep -q '^crond.service'; }; then printf crond
  else printf ''; fi
}

get_cron_status() {
  local service state enabled
  service=$(cron_service_name); state=STOPPED; enabled=NO
  if [[ -n "$service" ]]; then
    service_is_active "$service" && state=RUNNING
    [[ "$SERVERCTL_TEST_MODE" == 1 || "$(systemctl is-enabled "$service" 2>/dev/null || true)" == enabled ]] && enabled=YES
  fi
  printf 'Cron Service : %s\nEnabled      : %s\n' "$state" "$enabled"
}

cron_status_json() {
  local service state enabled
  service=$(cron_service_name); state=stopped; enabled=no
  if [[ -n "$service" ]]; then service_is_active "$service" && state=running; [[ "$SERVERCTL_TEST_MODE" == 1 || "$(systemctl is-enabled "$service" 2>/dev/null || true)" == enabled ]] && enabled=yes; fi
  printf '{"service":%s,"state":%s,"enabled":%s}\n' "$(cron_json_string "${service:-unknown}")" "$(cron_json_string "$state")" "$(cron_json_string "$enabled")"
}

cron_add_job_locked() {
  local user=$1 schedule=$2 command=$3 description=$4 enabled=$5 type=$6 website=${7:-} id record
  id=$(cron_next_id); record=$(cron_record_path "$id")
  mkdir -p -- "$(cron_jobs_dir)"
  cron_write_record "$record" "$id" "$user" "$schedule" "$command" "$description" "$enabled" "$type" "$website"
  cron_prepare_job_files "$id" "$user"; cron_render_all; cron_reload_service
  audit_event CRON_CREATE SUCCESS "cron_id=$id type=$type user=$user"
  printf 'Cron job created: %s\n' "$id"
}

add_cron_job() {
  local user=${1:-} schedule=${2:-} command=${3:-} description=${4:-} enabled=${5:-yes} type=${6:-system} website=${7:-}
  validate_cron_job "$user" "$schedule" "$command" "$description" "$enabled" "$type" || die 'Invalid Cron job input.' "$EXIT_VALIDATION"
  [[ "$type" != website || -n "$website" ]] || die 'Website Cron requires a website.' "$EXIT_VALIDATION"
  [[ "$type" != website ]] || cron_validate_website_command "$command" "$website" || die 'Website Cron command must target the selected website.' "$EXIT_VALIDATION"
  [[ "$type" != website || "$user" == "$(record_get "$(website_record_path "$website")" USER || printf www-data)" ]] || die 'Website Cron must run as the website owner.' "$EXIT_VALIDATION"
  if [[ "$type" == system && "$user" == root ]]; then
    warn 'WARNING: This cron job will execute with root privileges.'
    confirm 'Continue?' || die 'Cancelled.' "$EXIT_GENERAL"
  fi
  require_root; cron_backup_configuration
  with_lock cron-config cron_add_job_locked "$user" "$schedule" "$command" "$description" "$enabled" "$type" "$website"
}

cron_update_job_locked() {
  local id=$1 user=$2 schedule=$3 command=$4 description=$5 enabled=$6 type=$7 website=${8:-} record
  record=$(cron_record_path "$id")
  cron_write_record "$record" "$id" "$user" "$schedule" "$command" "$description" "$enabled" "$type" "$website" \
    "$(record_get "$record" CREATED_AT || true)" "$(record_get "$record" LAST_RUN || true)" "$(record_get "$record" LAST_EXIT_CODE || printf -- -)" "$(record_get "$record" LAST_STATUS || printf NEVER)"
  cron_prepare_job_files "$id" "$user"; cron_render_all; cron_reload_service
  audit_event CRON_UPDATE SUCCESS "cron_id=$id"
  printf 'Cron job updated: %s\n' "$id"
}

update_cron_job() {
  local id=$1 user=$2 schedule=$3 command=$4 description=$5 enabled=$6 type=${7:-system} website=${8:-} record old_user old_schedule old_command old_description old_enabled
  cron_valid_id "$id" || die 'Invalid Cron job ID.' "$EXIT_VALIDATION"
  record=$(cron_record_path "$id"); [[ -f "$record" ]] || die 'Cron job not found.' "$EXIT_VALIDATION"
  old_user=$(record_get "$record" USER || true); old_schedule=$(record_get "$record" SCHEDULE || true); old_command=$(record_get "$record" COMMAND || true); old_description=$(record_get "$record" DESCRIPTION || true); old_enabled=$(record_get "$record" ENABLED || true)
  validate_cron_job "$user" "$schedule" "$command" "$description" "$enabled" "$type" || die 'Invalid Cron job input.' "$EXIT_VALIDATION"
  [[ "$type" != website || -n "$website" ]] || die 'Website Cron requires a website.' "$EXIT_VALIDATION"
  [[ "$type" != website ]] || cron_validate_website_command "$command" "$website" || die 'Website Cron command must target the selected website.' "$EXIT_VALIDATION"
  [[ "$type" != website || "$user" == "$(record_get "$(website_record_path "$website")" USER || printf www-data)" ]] || die 'Website Cron must run as the website owner.' "$EXIT_VALIDATION"
  if [[ "$type" == system && "$user" == root ]]; then
    warn 'WARNING: This cron job will execute with root privileges.'
    confirm 'Continue?' || die 'Cancelled.' "$EXIT_GENERAL"
  fi
  printf '\nCron Job %s diff:\n- User       : %s\n+ User       : %s\n- Schedule   : %s\n+ Schedule   : %s\n- Command    : %s\n+ Command    : %s\n- Description: %s\n+ Description: %s\n- Status     : %s\n+ Status     : %s\n' "$id" "$old_user" "$user" "$old_schedule" "$schedule" "$old_command" "$command" "$old_description" "$description" "$old_enabled" "$enabled"
  confirm 'Apply these changes?' || die 'Cancelled.' "$EXIT_GENERAL"
  require_root; cron_backup_configuration
  with_lock cron-config cron_update_job_locked "$id" "$user" "$schedule" "$command" "$description" "$enabled" "$type" "$website"
}

cron_set_enabled_locked() {
  local id=$1 enabled=$2 record user schedule command description type website
  record=$(cron_record_path "$id"); user=$(record_get "$record" USER); schedule=$(record_get "$record" SCHEDULE); command=$(record_get "$record" COMMAND); description=$(record_get "$record" DESCRIPTION || true); type=$(record_get "$record" TYPE); website=$(record_get "$record" WEBSITE || true)
  update_record_value "$record" ENABLED "$enabled"; update_record_value "$record" UPDATED_AT "$(timestamp)"; chmod 0644 "$record" 2>/dev/null || true; [[ "$SERVERCTL_TEST_MODE" == 1 ]] || chown root:root "$record" 2>/dev/null || true; cron_render_all; cron_reload_service
  audit_event "$([[ "$enabled" == yes ]] && printf CRON_ENABLE || printf CRON_DISABLE)" SUCCESS "cron_id=$id"
  printf 'Cron job %s: %s\n' "$([[ "$enabled" == yes ]] && printf enabled || printf disabled)" "$id"
}

enable_cron_job() {
  local id=${1:-} record; cron_valid_id "$id" || die 'Invalid Cron job ID.' "$EXIT_VALIDATION"; record=$(cron_record_path "$id"); [[ -f "$record" ]] || die 'Cron job not found.' "$EXIT_VALIDATION"; require_root; with_lock cron-config cron_set_enabled_locked "$id" yes
}

disable_cron_job() {
  local id=${1:-} record; cron_valid_id "$id" || die 'Invalid Cron job ID.' "$EXIT_VALIDATION"; record=$(cron_record_path "$id"); [[ -f "$record" ]] || die 'Cron job not found.' "$EXIT_VALIDATION"; require_root; with_lock cron-config cron_set_enabled_locked "$id" no
}

cron_delete_job_locked() {
  local id=$1 record; record=$(cron_record_path "$id"); rm -f -- "$record" "$(cron_config_dir)/serverctl-cron-$id"; cron_render_all; cron_reload_service; rm -f -- "$(cron_log_path "$id")" "$(cron_lock_path "$id")"; audit_event CRON_DELETE SUCCESS "cron_id=$id"; printf 'Cron job deleted: %s\n' "$id"
}

delete_cron_job() {
  local id=${1:-} record; cron_valid_id "$id" || die 'Invalid Cron job ID.' "$EXIT_VALIDATION"; record=$(cron_record_path "$id"); [[ -f "$record" ]] || die 'Cron job not found.' "$EXIT_VALIDATION"; require_root; confirm 'WARNING: This cron job will be permanently removed. Delete?' || die 'Cancelled.' "$EXIT_GENERAL"; cron_backup_configuration; with_lock cron-config cron_delete_job_locked "$id"
}

cron_build_website_command() {
  local website=$1 script=$2 record docroot php_version php_path script_path website_user
  validate_site_name "$website" || return 1; record=$(website_record_path "$website"); [[ -f "$record" ]] || return 1
  [[ "$script" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$ && "$script" != *'..'* ]] || return 1
  docroot=$(record_get "$record" DOCUMENT_ROOT || printf '%s/%s/public' "$WEB_ROOT" "$website"); [[ "$docroot" == "$WEB_ROOT/"* && "$docroot" != *'..'* ]] || return 1
  script_path="$docroot/$script"; [[ "$SERVERCTL_TEST_MODE" == 1 || -f "$script_path" ]] || return 1
  php_version=$(record_get "$record" PHP_VERSION || printf '%s' "$DEFAULT_PHP_VERSION"); php_path="/usr/bin/php$php_version"
  [[ "$SERVERCTL_TEST_MODE" == 1 || -x "$php_path" ]] || php_path=/usr/bin/php
  [[ "$SERVERCTL_TEST_MODE" == 1 || -x "$php_path" ]] || return 1
  cron_allowed_executable "$php_path" || return 1
  website_user=$(record_get "$record" USER || printf www-data); [[ "$website_user" != root ]] || return 1
  printf '%s %s' "$php_path" "$script_path"
}

cron_validate_website_command() {
  local command=$1 website=$2 record docroot expected user
  validate_site_name "$website" || return 1
  record=$(website_record_path "$website"); [[ -f "$record" ]] || return 1
  docroot=$(record_get "$record" DOCUMENT_ROOT || printf '%s/%s/public' "$WEB_ROOT" "$website")
  expected="$docroot/"
  read -r -a command_parts <<< "$command"
  ((${#command_parts[@]} == 2)) || return 1
  [[ "${command_parts[1]}" == "$expected"* && "${command_parts[1]}" != *'..'* ]] || return 1
  user=$(record_get "$record" USER || printf www-data)
  [[ "$user" != root ]] || return 1
}

add_cron_website_job() {
  local website=$1 schedule=$2 script=$3 description=${4:-} enabled=${5:-yes} command user
  command=$(cron_build_website_command "$website" "$script") || die 'Invalid website Cron configuration or script.' "$EXIT_VALIDATION"
  user=$(record_get "$(website_record_path "$website")" USER || printf www-data)
  add_cron_job "$user" "$schedule" "$command" "$description" "$enabled" website "$website"
}

update_cron_website_job() {
  local id=$1 website=$2 schedule=$3 script=$4 description=${5:-} enabled=${6:-yes} record command user
  cron_valid_id "$id" || die 'Invalid Cron job ID.' "$EXIT_VALIDATION"; record=$(cron_record_path "$id"); [[ -f "$record" && "$(record_get "$record" TYPE)" == website ]] || die 'Website Cron job not found.' "$EXIT_VALIDATION"
  command=$(cron_build_website_command "$website" "$script") || die 'Invalid website Cron configuration or script.' "$EXIT_VALIDATION"; user=$(record_get "$(website_record_path "$website")" USER || printf www-data)
  update_cron_job "$id" "$user" "$schedule" "$command" "$description" "$enabled" website "$website"
}

cron_system_view() {
  local directory file; directory=$(cron_config_dir)
  printf 'SYSTEM CRON\n===========\n\n/etc/crontab\n-----------\n'; [[ -f "$(root_path /etc/crontab)" ]] && sed -n '1,240p' "$(root_path /etc/crontab)" || printf 'Unavailable\n'
  printf '\nFiles in /etc/cron.d\n--------------------\n'; shopt -s nullglob; for file in "$directory"/*; do if [[ -f "$file" ]]; then printf '\n### %s\n' "$(basename "$file")"; sed -n '1,240p' "$file"; fi; done; shopt -u nullglob
  for directory in "$(root_path /etc/cron.hourly)" "$(root_path /etc/cron.daily)" "$(root_path /etc/cron.weekly)" "$(root_path /etc/cron.monthly)"; do
    printf '\n%s\n%s\n' "$directory" '--------------------'; shopt -s nullglob; for file in "$directory"/*; do [[ -f "$file" ]] && printf '%s\n' "$(basename "$file")"; done; shopt -u nullglob
  done
  printf '\nSystem Cron is read-only here. Add managed jobs with: serverctl cron add\n'
}

cron_cli_add() {
  local user='' schedule='' command='' description='' enabled=yes type=system website=''
  while (($#)); do
    case "$1" in
      --user) (($# >= 2)) || die '--user requires a value.' "$EXIT_INVALID_ARGUMENT"; user=$2; shift 2;;
      --schedule) (($# >= 2)) || die '--schedule requires a value.' "$EXIT_INVALID_ARGUMENT"; schedule=$2; shift 2;;
      --command) (($# >= 2)) || die '--command requires a value.' "$EXIT_INVALID_ARGUMENT"; command=$2; shift 2;;
      --description) (($# >= 2)) || die '--description requires a value.' "$EXIT_INVALID_ARGUMENT"; description=$2; shift 2;;
      --disabled) enabled=no; shift;;
      --enabled) enabled=yes; shift;;
      --type) (($# >= 2)) || die '--type requires system or website.' "$EXIT_INVALID_ARGUMENT"; type=$2; shift 2;;
      --website) (($# >= 2)) || die '--website requires a domain.' "$EXIT_INVALID_ARGUMENT"; website=$2; shift 2;;
      *) die "Unknown cron add argument: $1" "$EXIT_INVALID_ARGUMENT";;
    esac
  done
  [[ "$type" == system && -z "$user" ]] && user=root
  [[ -n "$user" && -n "$schedule" && -n "$command" ]] || die 'Cron add requires --user, --schedule, and --command.' "$EXIT_INVALID_ARGUMENT"
  add_cron_job "$user" "$schedule" "$command" "$description" "$enabled" "$type" "$website"
}

cron_cli_edit() {
  local id=${1:-} record user schedule command description enabled type website value
  [[ -n "$id" ]] || die 'Cron job ID is required.' "$EXIT_INVALID_ARGUMENT"; shift || true
  cron_valid_id "$id" || die 'Invalid Cron job ID.' "$EXIT_VALIDATION"; record=$(cron_record_path "$id"); [[ -f "$record" ]] || die 'Cron job not found.' "$EXIT_VALIDATION"
  user=$(record_get "$record" USER); schedule=$(record_get "$record" SCHEDULE); command=$(record_get "$record" COMMAND); description=$(record_get "$record" DESCRIPTION || true); enabled=$(record_get "$record" ENABLED); type=$(record_get "$record" TYPE); website=$(record_get "$record" WEBSITE || true)
  while (($#)); do
    case "$1" in
      --user|--schedule|--command|--description|--website) (($# >= 2)) || die "$1 requires a value." "$EXIT_INVALID_ARGUMENT"; value=$2; case "$1" in --user) user=$value;; --schedule) schedule=$value;; --command) command=$value;; --description) description=$value;; --website) website=$value;; esac; shift 2;;
      --disabled) enabled=no; shift;; --enabled) enabled=yes; shift;;
      *) die "Unknown cron edit argument: $1" "$EXIT_INVALID_ARGUMENT";;
    esac
  done
  update_cron_job "$id" "$user" "$schedule" "$command" "$description" "$enabled" "$type" "$website"
}

cmd_cron() {
  local sub=${1:-}; shift || true
  case "$sub" in
    list)
      if (($# == 0)); then require_root; get_cron_jobs
      elif (($# == 1)) && [[ "$1" == --json ]]; then require_root; cron_jobs_json
      else die 'Usage: serverctl cron list [--json].' "$EXIT_INVALID_ARGUMENT"; fi
      ;;
    add) require_root; cron_cli_add "$@";;
    edit) require_root; cron_cli_edit "$@";;
    enable) (($# == 1)) || die 'cron enable requires an ID.' "$EXIT_INVALID_ARGUMENT"; enable_cron_job "$1";;
    disable) (($# == 1)) || die 'cron disable requires an ID.' "$EXIT_INVALID_ARGUMENT"; disable_cron_job "$1";;
    run|run-now) (($# == 1)) || die 'cron run requires an ID.' "$EXIT_INVALID_ARGUMENT"; run_cron_job "$1";;
    delete) (($# == 1)) || die 'cron delete requires an ID.' "$EXIT_INVALID_ARGUMENT"; delete_cron_job "$1";;
    logs) require_root; (($# >= 1 && $# <= 2)) || die 'Usage: serverctl cron logs ID [50|100|500].' "$EXIT_INVALID_ARGUMENT"; get_cron_logs "$1" "${2:-100}" || die 'Invalid Cron log request.' "$EXIT_VALIDATION";;
    validate) (($# == 1)) || die 'cron validate requires a five-field expression.' "$EXIT_INVALID_ARGUMENT"; if cron_validate_expression "$1"; then printf '[OK] Valid cron expression.\n'; else error 'Invalid cron expression.'; return "$EXIT_VALIDATION"; fi;;
    status) (($# == 0)) || die 'cron status accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; require_root; get_cron_status;;
    system) (($# == 0)) || die 'cron system accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; require_root; cron_system_view;;
    website)
      local website_sub=${1:-}; shift || true
      case "$website_sub" in
        add) (($# >= 1)) || die 'cron website add requires a domain.' "$EXIT_INVALID_ARGUMENT"; local domain=$1 schedule='' script='' description='' enabled=yes; shift; while (($#)); do case "$1" in --schedule) schedule=$2; shift 2;; --script) script=$2; shift 2;; --description) description=$2; shift 2;; --disabled) enabled=no; shift;; --enabled) enabled=yes; shift;; *) die "Unknown website cron argument: $1" "$EXIT_INVALID_ARGUMENT";; esac; done; [[ -n "$schedule" && -n "$script" ]] || die 'Website Cron requires --schedule and --script.' "$EXIT_INVALID_ARGUMENT"; require_root; add_cron_website_job "$domain" "$schedule" "$script" "$description" "$enabled";;
        list) require_root; get_cron_jobs;;
        *) die 'Usage: serverctl cron website <add|list>.' "$EXIT_INVALID_ARGUMENT";;
      esac;;
    restore) (($# == 1)) || die 'cron restore requires a backup name.' "$EXIT_INVALID_ARGUMENT"; require_root; cron_restore_configuration "$1";;
    _run-scheduled) (($# == 1)) || return "$EXIT_INVALID_ARGUMENT"; cron_scheduled_run "$1";;
    *) die 'Usage: serverctl cron <list|add|edit|enable|disable|run|delete|logs|validate|status|system|website|restore>.' "$EXIT_INVALID_ARGUMENT";;
  esac
}

cron_restore_configuration() {
  local name=${1:-} source record
  safe_basename "$name" || die 'Invalid Cron backup name.' "$EXIT_VALIDATION"
  source="$(cron_backup_dir)/$name"; [[ -d "$source/jobs" ]] || die 'Cron backup not found.' "$EXIT_VALIDATION"
  confirm 'Restore Cron configuration? Existing Cron jobs will be replaced.' || die 'Cancelled.' "$EXIT_GENERAL"
  cron_backup_configuration
  while IFS= read -r record; do cron_validate_record "$record" || die 'Cron backup validation failed.' "$EXIT_VALIDATION"; done < <(find "$source/jobs" -maxdepth 1 -type f -name '[1-9]*.conf' -print)
  mkdir -p -- "$(cron_jobs_dir)"; find "$(cron_jobs_dir)" -maxdepth 1 -type f -name '[1-9]*.conf' -delete
  cp -a -- "$source/jobs/." "$(cron_jobs_dir)/"; cron_render_all; cron_reload_service; audit_event CRON_RESTORE SUCCESS "backup=$name"; ok 'Cron configuration restored and verified.'
}
