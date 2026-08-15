#!/usr/bin/env bash

NGINX_BACKUP_DIR="$BACKUP_DIR/nginx"
NGINX_GLOBAL_STATE="$(root_path /etc/serverctl/nginx-global.conf)"

cmd_nginx() {
  NGINX_BACKUP_DIR="$BACKUP_DIR/nginx"
  local sub=${1:-status}; shift || true
  case "$sub" in
    status) (($# == 0)) || die "nginx status accepts no arguments." "$EXIT_INVALID_ARGUMENT"; nginx_status ;;
    test) (($# == 0)) || die "nginx test accepts no arguments." "$EXIT_INVALID_ARGUMENT"; nginx_test ;;
    reload) (($# == 0)) || die "nginx reload accepts no arguments." "$EXIT_INVALID_ARGUMENT"; nginx_reload ;;
    restart) (($# == 0)) || die "nginx restart accepts no arguments." "$EXIT_INVALID_ARGUMENT"; nginx_restart ;;
    stop) (($# == 0)) || die "nginx stop accepts no arguments." "$EXIT_INVALID_ARGUMENT"; nginx_stop ;;
    start) (($# == 0)) || die "nginx start accepts no arguments." "$EXIT_INVALID_ARGUMENT"; nginx_start ;;
    config) nginx_view_config "$@" ;;
    global) nginx_global "$@" ;;
    website) nginx_website "$@" ;;
    security) (($# == 0)) || die "nginx security accepts no arguments." "$EXIT_INVALID_ARGUMENT"; nginx_security_audit ;;
    access-log) nginx_log access "$@" ;;
    error-log) nginx_log error "$@" ;;
    backup) (($# == 0)) || die "nginx backup accepts no arguments." "$EXIT_INVALID_ARGUMENT"; nginx_backup_config ;;
    backup-list) (($# == 0)) || die "nginx backup-list accepts no arguments." "$EXIT_INVALID_ARGUMENT"; nginx_backup_list ;;
    restore) nginx_restore_config "$@" ;;
    history) (($# == 0)) || die "nginx history accepts no arguments." "$EXIT_INVALID_ARGUMENT"; nginx_history ;;
    *) die "Usage: serverctl nginx <status|test|reload|restart|stop|start|config|global|website|security|access-log|error-log|backup|backup-list|restore|history>" "$EXIT_INVALID_ARGUMENT" ;;
  esac
}

nginx_status() {
  local state version pid workers connections active_since config_status http=NOT_LISTENING https=NOT_LISTENING http2=disabled http3=disabled
  state=$(systemctl is-active nginx 2>/dev/null || true); state=${state:-inactive}
  version=$(nginx -v 2>&1 | sed 's#nginx version: nginx/##' || printf unknown)
  pid=$(systemctl show nginx -p MainPID --value 2>/dev/null || printf 0)
  workers=$(pgrep -fc 'nginx: worker process' 2>/dev/null || printf 0)
  connections=$(ss -Htn state established '( sport = :80 or sport = :443 )' 2>/dev/null | wc -l)
  active_since=$(systemctl show nginx -p ActiveEnterTimestamp --value 2>/dev/null || printf unknown)
  if nginx -t >/dev/null 2>&1; then config_status=VALID; else config_status=INVALID; fi
  ss -Hln sport = :80 2>/dev/null | grep -q . && http=LISTENING
  ss -Hln sport = :443 2>/dev/null | grep -q . && https=LISTENING
  nginx -T 2>/dev/null | grep -Eq 'listen[^;]*443[^;]*http2|http2[[:space:]]+on' && http2=enabled
  nginx -T 2>/dev/null | grep -Eq 'listen[^;]*443[^;]*quic|http3[[:space:]]+on' && http3=enabled
  printf 'NGINX STATUS\n============\nService Status      : %s\nVersion             : %s\nPID                 : %s\nWorker Processes    : %s\nActive Connections  : %s\nActive Since        : %s\nConfiguration       : %s\nHTTP                : %s\nHTTPS               : %s\nHTTP/2              : %s\nHTTP/3              : %s\n' \
    "$state" "$version" "$pid" "$workers" "$connections" "$active_since" "$config_status" "$http" "$https" "$http2" "$http3"
  [[ "$state" == active && "$config_status" == VALID ]]
}

nginx_test() {
  if nginx -t; then ok 'Nginx configuration is valid.'; else error 'Nginx configuration is invalid. Reload/restart was blocked.'; return "$EXIT_VALIDATION"; fi
}

nginx_backup_stamp() { date '+%Y-%m-%d_%H%M%S_%N'; }

nginx_backup_config() {
  require_root
  local source destination temporary
  source=$(root_path /etc/nginx); [[ -d "$source" ]] || die "Nginx configuration directory is missing." "$EXIT_SYSTEM"
  mkdir -p -- "$NGINX_BACKUP_DIR"; destination="$NGINX_BACKUP_DIR/$(nginx_backup_stamp)"; temporary=$(mktemp -d "$NGINX_BACKUP_DIR/.backup.XXXXXX")
  cp -a -- "$source" "$temporary/nginx"
  (cd "$temporary" && find nginx -type l -printf '%p -> %l\n' | sort > SYMLINKS && find nginx -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS && sha256sum SYMLINKS >> SHA256SUMS)
  atomic_write "$temporary/metadata" 0600 root root <<EOF
DATE=$(timestamp)
USER=${SUDO_USER:-${USER:-unknown}}
SOURCE_IP=$(client_ip)
NGINX_VERSION=$(nginx -v 2>&1 | sed 's#nginx version: nginx/##')
EOF
  mv -- "$temporary" "$destination"; chmod -R go-rwx "$destination"; LAST_NGINX_BACKUP=$destination
  find "$NGINX_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name '20??-??-??_*' -mtime "+$BACKUP_RETENTION" -print -exec rm -rf -- {} +
  audit_event 'nginx backup configuration' SUCCESS "backup=$(basename "$destination")"
  ok "Nginx configuration backup created: $destination"
}

nginx_backup_list() {
  printf '%-36s %-22s %s\n' BACKUP CREATED SIZE
  local directory
  shopt -s nullglob
  for directory in "$NGINX_BACKUP_DIR"/20*; do
    [[ -d "$directory/nginx" ]] || continue
    printf '%-36s %-22s %s\n' "$(basename "$directory")" "$(date -r "$directory" '+%Y-%m-%d %H:%M:%S')" "$(du -sh "$directory" | awk '{print $1}')"
  done
  shopt -u nullglob
}

validate_nginx_backup_name() { [[ "$1" =~ ^20[0-9]{2}-[01][0-9]-[0-3][0-9]_[0-2][0-9][0-5][0-9][0-5][0-9]_[0-9]+$ ]]; }

nginx_restore_config() {
  require_root
  local name=${1:-} selected current current_name nginx_dir
  (($# == 1)) || die "Usage: serverctl nginx restore BACKUP_NAME" "$EXIT_INVALID_ARGUMENT"
  validate_nginx_backup_name "$name" || die "Invalid Nginx backup name." "$EXIT_VALIDATION"
  selected="$NGINX_BACKUP_DIR/$name"; [[ -d "$selected/nginx" && -f "$selected/SHA256SUMS" ]] || die "Nginx backup not found or incomplete." "$EXIT_VALIDATION"
  (cd "$selected" && sha256sum -c SHA256SUMS >/dev/null && find nginx -type l -printf '%p -> %l\n' | sort | cmp -s - SYMLINKS) || die "Nginx backup checksum or symlink verification failed." "$EXIT_VALIDATION"
  nginx_validate_backup_symlinks "$selected/SYMLINKS"
  confirm "Restore Nginx configuration backup $name?" "$name" || die 'Cancelled.' "$EXIT_GENERAL"
  nginx_backup_config; current=$LAST_NGINX_BACKUP; current_name=$(basename "$current"); nginx_dir=$(root_path /etc/nginx)
  rsync -a --delete -- "$selected/nginx/" "$nginx_dir/"
  if ! nginx -t; then
    rsync -a --delete -- "$current/nginx/" "$nginx_dir/"
    nginx -t >/dev/null 2>&1 || true
    audit_event "nginx restore $name" FAILED 'validation failed; current configuration restored'
    die "Selected backup is invalid; current configuration was restored from $current_name." "$EXIT_VALIDATION"
  fi
  if ! run_cmd systemctl reload nginx || ! service_is_active nginx; then
    rsync -a --delete -- "$current/nginx/" "$nginx_dir/"; nginx -t && run_cmd systemctl reload nginx || true
    die "Nginx reload failed; current configuration was restored." "$EXIT_SYSTEM"
  fi
  audit_event "nginx restore $name" SUCCESS "rollback=$current_name"; ok "Nginx configuration restored and health check passed."
}

nginx_validate_backup_symlinks() {
  local manifest=$1 line target
  while IFS= read -r line; do
    target=${line#* -> }
    [[ "$target" != *'/../'* && "$target" != ../../* ]] || die "Unsafe symlink in Nginx backup: $target" "$EXIT_VALIDATION"
    case "$target" in
      /etc/nginx/*|/usr/share/nginx/modules*|../sites-available/*|../snippets/*) ;;
      *) [[ "$target" != /* && "$target" != *..* ]] || die "Unexpected symlink in Nginx backup: $target" "$EXIT_VALIDATION" ;;
    esac
  done < "$manifest"
}

nginx_reload() {
  require_root; nginx_backup_config; nginx_test
  run_cmd systemctl reload nginx
  service_is_active nginx || die "Nginx did not remain active after reload." "$EXIT_SYSTEM"
  nginx_test; ok 'Nginx reloaded and health check passed.'
}

nginx_restart() {
  require_root; nginx_test
  warn 'Restarting Nginx may temporarily interrupt connections.'
  confirm 'Continue with Nginx restart?' || die 'Cancelled.' "$EXIT_GENERAL"
  nginx_backup_config; run_cmd systemctl restart nginx
  nginx_post_service_check; ok 'Nginx restarted successfully.'
}

nginx_stop() {
  require_root; warn 'Stopping Nginx will make every website unavailable.'
  confirm 'Continue with Nginx stop?' || die 'Cancelled.' "$EXIT_GENERAL"
  run_cmd systemctl stop nginx; service_is_active nginx && die 'Nginx is still running.' "$EXIT_SYSTEM" || true; ok 'Nginx stopped.'
}

nginx_start() { require_root; nginx_test; run_cmd systemctl start nginx; nginx_post_service_check; ok 'Nginx started successfully.'; }

nginx_post_service_check() {
  service_is_active nginx || die 'Nginx service is not active.' "$EXIT_SYSTEM"
  nginx -t >/dev/null 2>&1 || die 'Nginx configuration failed after service action.' "$EXIT_VALIDATION"
  ss -Hln sport = :80 2>/dev/null | grep -q . || warn 'Port 80 is not listening.'
  if find "$STATE_DIR/websites" -type f -name '*.conf' -exec grep -l '^SSL=yes$' {} + 2>/dev/null | grep -q .; then ss -Hln sport = :443 2>/dev/null | grep -q . || warn 'Port 443 is not listening.'; fi
}

nginx_view_config() {
  local type=${1:-}; (($# == 1)) || die "Usage: serverctl nginx config <main|available|enabled|snippets|included>" "$EXIT_INVALID_ARGUMENT"
  case "$type" in
    main) sed -n '1,500p' "$(root_path /etc/nginx/nginx.conf)" ;;
    available) find "$(nginx_available_dir)" -maxdepth 1 -type f -printf '%f\n' | sort ;;
    enabled) find "$(nginx_enabled_dir)" -maxdepth 1 \( -type f -o -type l \) -printf '%f -> %l\n' | sort ;;
    snippets) find "$(root_path /etc/nginx/snippets)" -maxdepth 1 -type f -printf '%f\n' | sort ;;
    included) nginx -T ;;
    *) die 'Unknown Nginx configuration view.' "$EXIT_INVALID_ARGUMENT" ;;
  esac
}

nginx_global() {
  local action=${1:-show}; shift || true
  case "$action" in show) (($# == 0)) || die 'nginx global show accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; nginx_global_show ;; set) nginx_global_set "$@" ;; *) die 'Usage: serverctl nginx global <show|set KEY VALUE>' "$EXIT_INVALID_ARGUMENT" ;; esac
}

nginx_global_show() {
  printf 'NGINX GLOBAL SETTINGS\n=====================\n'
  nginx -T 2>/dev/null | grep -E '^[[:space:]]*(worker_processes|worker_connections|keepalive_timeout|client_max_body_size|gzip|client_body_timeout|client_header_timeout|send_timeout|server_tokens)[[:space:]]' | sed 's/^[[:space:]]*//'
  printf 'HTTP/2: '; nginx -T 2>/dev/null | grep -Eq 'listen[^;]*http2|http2 on' && printf 'enabled\n' || printf 'disabled\n'
  printf 'HTTP/3: '; nginx -T 2>/dev/null | grep -Eq 'listen[^;]*quic|http3 on' && printf 'enabled\n' || printf 'disabled\n'
}

nginx_global_set() {
  require_root
  local key=${1:-} value=${2:-}; (($# == 2)) || die 'Usage: serverctl nginx global set KEY VALUE' "$EXIT_INVALID_ARGUMENT"
  case "$key" in
    worker_processes) [[ "$value" == auto || "$value" =~ ^([1-9]|[1-5][0-9]|6[0-4])$ ]] || die 'worker_processes must be auto or 1-64.' "$EXIT_VALIDATION"; nginx_main_setting "$key" "$value"; return ;;
    worker_connections) [[ "$value" =~ ^[0-9]+$ ]] && ((10#$value >= 128 && 10#$value <= 65535)) || die 'worker_connections must be 128-65535.' "$EXIT_VALIDATION"; nginx_main_setting "$key" "$value"; return ;;
    keepalive_timeout|client_body_timeout|client_header_timeout|send_timeout) [[ "$value" =~ ^([1-9]|[1-9][0-9]|[12][0-9][0-9]|300)$ ]] || die 'Timeout must be 1-300 seconds.' "$EXIT_VALIDATION"; value="${value}s" ;;
    client_max_body_size) [[ "$value" =~ ^([1-9][0-9]{0,3})([kKmMgG])$ ]] || die 'Body size must look like 32m (1-9999 k/m/g).' "$EXIT_VALIDATION" ;;
    gzip) [[ "$value" == on || "$value" == off ]] || die 'gzip must be on or off.' "$EXIT_VALIDATION" ;;
    *) die 'Allowed global settings: worker_processes, worker_connections, keepalive_timeout, client_body_timeout, client_header_timeout, send_timeout, client_max_body_size, gzip.' "$EXIT_VALIDATION" ;;
  esac
  nginx_update_global_state "$key" "$value"
}

nginx_main_setting() {
  local key=$1 value=$2 file candidate
  file=$(root_path /etc/nginx/nginx.conf); candidate=$(mktemp); cp -- "$file" "$candidate"
  grep -Eq "^[[:space:]]*$key[[:space:]]+" "$candidate" || { rm -f -- "$candidate"; die "$key directive was not found in nginx.conf." "$EXIT_VALIDATION"; }
  sed -i -E "s#^([[:space:]]*)$key[[:space:]]+[^;]+;#\\1$key $value;#" "$candidate"
  nginx_apply_candidate "$candidate" "$file" "nginx global set $key=$value"; rm -f -- "$candidate"
}

nginx_update_global_state() {
  local key=$1 value=$2 state_tmp candidate tuning
  mkdir -p -- "$(dirname "$NGINX_GLOBAL_STATE")"; state_tmp=$(mktemp "$(dirname "$NGINX_GLOBAL_STATE")/.nginx-global.XXXXXX")
  if [[ -f "$NGINX_GLOBAL_STATE" ]]; then awk -F= -v key="$key" '$1 != key {print}' "$NGINX_GLOBAL_STATE" > "$state_tmp"; fi
  printf '%s=%s\n' "$key" "$value" >> "$state_tmp"; chmod 0640 "$state_tmp"
  candidate=$(mktemp); tuning=$(root_path /etc/nginx/conf.d/serverctl-tuning.conf)
  nginx_render_tuning "$state_tmp" > "$candidate"
  nginx_apply_candidate "$candidate" "$tuning" "nginx global set $key=$value"
  mv -f -- "$state_tmp" "$NGINX_GLOBAL_STATE"; chmod 0640 "$NGINX_GLOBAL_STATE"; rm -f -- "$candidate"
}

nginx_render_tuning() {
  local state=$1 key value keepalive=75s body=32m gzip=on body_timeout=60s header_timeout=60s send_timeout=60s
  while IFS='=' read -r key value; do case "$key" in keepalive_timeout) keepalive=$value ;; client_max_body_size) body=$value ;; gzip) gzip=$value ;; client_body_timeout) body_timeout=$value ;; client_header_timeout) header_timeout=$value ;; send_timeout) send_timeout=$value ;; esac; done < "$state"
  printf '# Managed by serverctl.\nkeepalive_timeout %s;\nclient_max_body_size %s;\ngzip %s;\nclient_body_timeout %s;\nclient_header_timeout %s;\nsend_timeout %s;\n' "$keepalive" "$body" "$gzip" "$body_timeout" "$header_timeout" "$send_timeout"
}

nginx_apply_candidate() {
  local candidate=$1 destination=$2 action=$3 stage stage_file diff_output
  nginx_backup_config
  stage=$(mktemp -d "$STATE_DIR/.nginx-test.XXXXXX"); mkdir -p "$stage/nginx"; cp -a -- "$(root_path /etc/nginx)/." "$stage/nginx/"
  local link target
  while IFS= read -r -d '' link; do target=$(readlink "$link"); if [[ "$target" == /etc/nginx/* ]]; then ln -sfn "$stage/nginx/${target#/etc/nginx/}" "$link"; fi; done < <(find "$stage/nginx" -type l -print0)
  stage_file="$stage/nginx/${destination#$(root_path /etc/nginx)/}"; mkdir -p -- "$(dirname "$stage_file")"; cp -- "$candidate" "$stage_file"
  find "$stage/nginx" -type f -name '*.conf' -exec sed -i "s#/etc/nginx/#$stage/nginx/#g" {} +
  nginx -t -p "$stage/nginx/" -c "$stage/nginx/nginx.conf" || { rm -rf -- "$stage"; die 'Candidate Nginx configuration is invalid; nothing was applied.' "$EXIT_VALIDATION"; }
  diff_output=$(diff -u -- "$destination" "$candidate" 2>/dev/null || true); printf '%s\n' "${diff_output:-[new configuration file]}"
  confirm 'Apply this validated Nginx configuration change?' || { rm -rf -- "$stage"; die 'Cancelled.' "$EXIT_GENERAL"; }
  backup_config_file "$destination"; atomic_write "$destination" 0644 root root < "$candidate"
  if ! nginx -t || ! run_cmd systemctl reload nginx; then rollback_configs; nginx -t && run_cmd systemctl reload nginx || true; rm -rf -- "$stage"; die 'Apply failed; previous Nginx configuration restored.' "$EXIT_SYSTEM"; fi
  commit_configs; rm -rf -- "$stage"; nginx_post_service_check; audit_event "$action" SUCCESS; ok 'Nginx change applied and health check passed.'
}

nginx_website() {
  local action=${1:-list}; shift || true domain key value file
  case "$action" in
    list) (($# == 0)) || die 'nginx website list accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; website_list ;;
    view) domain=${1:-}; (($# == 1)) && validate_domain "$domain" || die 'Usage: serverctl nginx website view DOMAIN' "$EXIT_INVALID_ARGUMENT"; website_exists "$domain" || die 'Website not found.' "$EXIT_VALIDATION"; sed -n '1,500p' "$(nginx_available_dir)/$domain.conf" ;;
    set)
      domain=${1:-}; key=${2:-}; value=${3:-}; (($# == 3)) || die 'Usage: serverctl nginx website set DOMAIN <upload-limit|rate-limit|static-cache> VALUE' "$EXIT_INVALID_ARGUMENT"
      validate_domain "$domain" || die 'Invalid domain.' "$EXIT_VALIDATION"; website_exists "$domain" || die 'Website not found.' "$EXIT_VALIDATION"
      nginx_website_setting "$domain" "$key" "$value" ;;
    access) nginx_website_access "$@" ;;
    *) die 'Usage: serverctl nginx website <list|view|set|access>' "$EXIT_INVALID_ARGUMENT" ;;
  esac
}

nginx_website_access() {
  require_root
  local domain=${1:-} action=${2:-list} cidr=${3:-} file candidate current_mode=open
  validate_domain "$domain" || die 'Invalid domain.' "$EXIT_VALIDATION"; website_exists "$domain" || die 'Website not found.' "$EXIT_VALIDATION"
  file=$(nginx_access_path "$domain")
  if [[ ! -f "$file" ]]; then atomic_write "$file" 0644 root root <<'EOF'
# Managed by serverctl.
# serverctl-access-mode: open
allow all;
EOF
  fi
  case "$action" in
    list) (($# == 2)) || die 'Usage: serverctl nginx website access DOMAIN list' "$EXIT_INVALID_ARGUMENT"; cat -- "$file"; return ;;
    clear) (($# == 2)) || die 'Usage: serverctl nginx website access DOMAIN clear' "$EXIT_INVALID_ARGUMENT"; candidate=$(mktemp); printf '# Managed by serverctl.\n# serverctl-access-mode: open\nallow all;\n' > "$candidate" ;;
    allow|deny)
      (($# == 3)) || die 'Usage: serverctl nginx website access DOMAIN allow|deny CIDR' "$EXIT_INVALID_ARGUMENT"
      validate_cidr "$cidr" || die 'Invalid access-rule IP/CIDR.' "$EXIT_VALIDATION"
      current_mode=$(sed -n 's/^# serverctl-access-mode: //p' "$file" | head -1); current_mode=${current_mode:-open}
      if [[ "$current_mode" != open && "$current_mode" != "$action" ]]; then warn "Changing access mode from $current_mode to $action clears existing rules."; confirm 'Continue changing the website access mode?' || die 'Cancelled.' "$EXIT_GENERAL"; fi
      candidate=$(mktemp); printf '# Managed by serverctl.\n# serverctl-access-mode: %s\n' "$action" > "$candidate"
      if [[ "$current_mode" == "$action" ]]; then grep -E "^$action[[:space:]]+" "$file" | grep -v '[[:space:]]all;' >> "$candidate" || true; fi
      grep -Fqx "$action $cidr;" "$candidate" || printf '%s %s;\n' "$action" "$cidr" >> "$candidate"
      if [[ "$action" == allow ]]; then printf 'deny all;\n' >> "$candidate"; else printf 'allow all;\n' >> "$candidate"; fi ;;
    *) die 'Access action must be list, allow, deny, or clear.' "$EXIT_INVALID_ARGUMENT" ;;
  esac
  validate_nginx_access_file "$candidate" || { rm -f -- "$candidate"; die 'Generated access rule file failed validation.' "$EXIT_VALIDATION"; }
  nginx_apply_candidate "$candidate" "$file" "nginx website $domain access $action ${cidr:-all}"; rm -f -- "$candidate"
}

nginx_website_setting() {
  local domain=$1 key=$2 value=$3 file candidate record php ssl csp upload_limit rate_burst static_cache record_key
  file="$(nginx_available_dir)/$domain.conf"; candidate=$(mktemp); record=$(website_record_path "$domain")
  php=$(record_get "$record" PHP_VERSION); ssl=$(record_get "$record" SSL); csp=$(record_get "$record" CSP || true)
  upload_limit=$(record_get "$record" UPLOAD_LIMIT || printf 32m); rate_burst=$(record_get "$record" RATE_BURST || printf 40); static_cache=$(record_get "$record" STATIC_CACHE || printf off)
  case "$key" in
    upload-limit) [[ "$value" =~ ^[1-9][0-9]{0,3}[kKmMgG]$ ]] || die 'Upload limit must look like 32m.' "$EXIT_VALIDATION"; upload_limit=$value; record_key=UPLOAD_LIMIT ;;
    rate-limit) [[ "$value" =~ ^([1-9]|[1-9][0-9]|100)$ ]] || die 'Rate burst must be 1-100.' "$EXIT_VALIDATION"; rate_burst=$value; record_key=RATE_BURST ;;
    static-cache) [[ "$value" == on || "$value" == off ]] || die 'static-cache must be on or off.' "$EXIT_VALIDATION"; static_cache=$value; record_key=STATIC_CACHE ;;
    *) rm -f -- "$candidate"; die 'Allowed website settings: upload-limit, rate-limit, static-cache.' "$EXIT_VALIDATION" ;;
  esac
  render_nginx_site "$domain" "$php" "$ssl" "$csp" "$upload_limit" "$rate_burst" "$static_cache" "$candidate"
  nginx_apply_candidate "$candidate" "$file" "nginx website $domain set $key=$value"
  update_record_value "$record" "$record_key" "$value"; rm -f -- "$candidate"
}

nginx_security_audit() {
  local config; config=$(nginx -T 2>&1) || { printf '%s\n' "$config"; return "$EXIT_VALIDATION"; }
  nginx_security_line 'Hide Nginx Version' "$config" 'server_tokens off'
  nginx_security_line 'Block Hidden Files' "$config" 'location ~ (^|/)\\\.'
  nginx_security_line 'Disable Directory Listing' "$config" 'autoindex off'
  nginx_security_line 'Block PHP in Uploads' "$config" 'uploads?.*\\.php'
  nginx_security_line 'Request Limits' "$config" 'limit_req zone=serverctl_per_ip'
  nginx_security_line 'Default Server' "$config" 'listen 80 default_server'
}

nginx_security_line() { local label=$1 config=$2 pattern=$3; if grep -Eq "$pattern" <<< "$config"; then printf '%-28s [ OK ]\n' "$label"; else printf '%-28s [ WARNING ]\n' "$label"; fi; }

nginx_log() {
  local type=$1; shift; local domain=global lines=100 file follow=0 search=""
  if (($#)) && [[ "$1" != --* && ! "$1" =~ ^(50|100|500)$ ]]; then domain=$1; shift; fi
  while (($#)); do
    case "$1" in
      --lines) (($# >= 2)) || die '--lines requires 50, 100, or 500.' "$EXIT_INVALID_ARGUMENT"; lines=$2; shift 2 ;;
      --follow) follow=1; shift ;;
      --search) (($# >= 2)) || die '--search requires text.' "$EXIT_INVALID_ARGUMENT"; search=$2; shift 2 ;;
      50|100|500) lines=$1; shift ;;
      *) die "Unknown Nginx log argument: $1" "$EXIT_INVALID_ARGUMENT" ;;
    esac
  done
  [[ "$lines" =~ ^(50|100|500)$ ]] || die 'Log lines must be 50, 100, or 500.' "$EXIT_VALIDATION"
  [[ ${#search} -le 200 && "$search" != *$'\n'* && "$search" != *$'\r'* ]] || die 'Invalid log search text.' "$EXIT_VALIDATION"
  if [[ -n "$domain" && "$domain" != global ]]; then validate_domain "$domain" || die 'Invalid domain.' "$EXIT_VALIDATION"; website_exists "$domain" || die 'Website not found.' "$EXIT_VALIDATION"; file="$WEB_ROOT/$domain/logs/$type.log"
  elif [[ "$type" == access ]]; then file=/var/log/nginx/access.log; else file=/var/log/nginx/error.log; fi
  [[ -f "$file" ]] || die "Log file not found: $file" "$EXIT_SYSTEM"
  if [[ -n "$search" ]]; then grep -F -- "$search" "$file" | tail -n "$lines" || true
  elif ((follow)); then tail -n "$lines" -f -- "$file"; else tail -n "$lines" -- "$file"; fi
}

nginx_history() { [[ -f "$AUDIT_LOG" ]] && awk -F '\t' 'tolower($4) ~ /nginx/ {printf "%s\t%s\t%s\t%s\t%s\n",$1,$2,$3,$4,$5}' "$AUDIT_LOG" | tail -100; }
