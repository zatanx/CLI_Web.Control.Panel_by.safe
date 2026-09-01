#!/usr/bin/env bash

# Dashboard commands are deliberately small adapters around the existing
# serverctl functions.  The web application only calls the JSON/read-only
# endpoints and the explicitly whitelisted actions below.
DASHBOARD_INSTALL_ROOT="$(root_path /opt/serverctl/dashboard)"
DASHBOARD_CONFIG_FILE="$(root_path /etc/serverctl/dashboard.conf)"
DASHBOARD_NGINX_AVAILABLE="$(root_path /etc/nginx/sites-available/serverctl-dashboard.conf)"
DASHBOARD_NGINX_ENABLED="$(root_path /etc/nginx/sites-enabled/serverctl-dashboard.conf)"
DASHBOARD_STATE_DIR="$(root_path /var/lib/serverctl/dashboard)"

dashboard_json_string() {
  local value=${1:-}
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\r'/\\r}
  value=${value//$'\n'/\\n}
  value=${value//$'\t'/\\t}
  printf '"%s"' "$value"
}

dashboard_json_number() {
  [[ "${1:-}" =~ ^-?[0-9]+$ ]] && printf '%s' "$1" || printf '0'
}

dashboard_config_set_bot_values() {
  local provider=${1:-} site_key=${2:-} secret=${3:-} temporary line
  local found_provider=0 found_site_key=0 found_secret=0
  [[ -f "$DASHBOARD_CONFIG_FILE" ]] || die 'Dashboard configuration is not present.' "$EXIT_VALIDATION"
  temporary=$(mktemp "$(dirname "$DASHBOARD_CONFIG_FILE")/.dashboard-config.XXXXXX")
  while IFS= read -r line; do
    case "$line" in
      DASHBOARD_BOT_PROVIDER=*) printf 'DASHBOARD_BOT_PROVIDER=%s\n' "$provider" >> "$temporary"; found_provider=1 ;;
      DASHBOARD_BOT_SITE_KEY=*) printf 'DASHBOARD_BOT_SITE_KEY=%s\n' "$site_key" >> "$temporary"; found_site_key=1 ;;
      DASHBOARD_BOT_SECRET=*) printf 'DASHBOARD_BOT_SECRET=%s\n' "$secret" >> "$temporary"; found_secret=1 ;;
      *) printf '%s\n' "$line" >> "$temporary" ;;
    esac
  done < "$DASHBOARD_CONFIG_FILE"
  ((found_provider)) || printf 'DASHBOARD_BOT_PROVIDER=%s\n' "$provider" >> "$temporary"
  ((found_site_key)) || printf 'DASHBOARD_BOT_SITE_KEY=%s\n' "$site_key" >> "$temporary"
  ((found_secret)) || printf 'DASHBOARD_BOT_SECRET=%s\n' "$secret" >> "$temporary"
  chmod 0640 "$temporary"
  if [[ "$SERVERCTL_TEST_MODE" != 1 ]]; then chown root:www-data "$temporary"; fi
  mv -f -- "$temporary" "$DASHBOARD_CONFIG_FILE"
}

dashboard_validate_bot_value() {
  local value=${1:-}
  [[ ${#value} -le 512 && "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *'='* ]]
}

dashboard_bot_protection_set() {
  require_root
  local provider=${1:-} site_key=${2:-} secret=${3:-} had_nginx=0
  (($# == 3)) || die 'Usage: dashboard bot-protection set PROVIDER SITE_KEY --secret SECRET' "$EXIT_INVALID_ARGUMENT"
  [[ "$provider" == none || "$provider" == recaptcha_v3 || "$provider" == turnstile ]] || die 'Provider must be none, recaptcha_v3, or turnstile.' "$EXIT_VALIDATION"
  dashboard_validate_bot_value "$site_key" || die 'Invalid bot-protection site key.' "$EXIT_VALIDATION"
  dashboard_validate_bot_value "$secret" || die 'Invalid bot-protection secret.' "$EXIT_VALIDATION"
  if [[ "$provider" == none ]]; then
    site_key=''; secret=''
  else
    [[ -n "$site_key" && -n "$secret" ]] || die 'A site key and secret are required when bot protection is enabled.' "$EXIT_VALIDATION"
  fi
  [[ -e "$DASHBOARD_NGINX_AVAILABLE" ]] && had_nginx=1
  ROLLBACK_FILES=()
  backup_config_file "$DASHBOARD_CONFIG_FILE"
  backup_config_file "$DASHBOARD_NGINX_AVAILABLE"
  dashboard_config_set_bot_values "$provider" "$site_key" "$secret"
  local domain local_mode dashboard_port cert_root
  domain=$(record_get "$DASHBOARD_CONFIG_FILE" DASHBOARD_DOMAIN || true)
  local_mode=$(record_get "$DASHBOARD_CONFIG_FILE" DASHBOARD_LOCAL_ONLY || printf no)
  dashboard_port=$(record_get "$DASHBOARD_CONFIG_FILE" DASHBOARD_PORT || printf 8088)
  if [[ "$local_mode" == yes ]]; then cert_root=''; else cert_root="$(root_path /etc/letsencrypt/live)/$domain"; fi
  dashboard_render_nginx "$domain" "/run/php/php${DEFAULT_PHP_VERSION}-fpm.sock" "$cert_root" "$local_mode" "$dashboard_port"
  if ! validate_nginx; then
    rollback_configs
    ((had_nginx)) || rm -f -- "$DASHBOARD_NGINX_AVAILABLE"
    die 'Nginx rejected the Dashboard bot-protection configuration; previous settings restored.' "$EXIT_VALIDATION"
  fi
  if ! run_cmd systemctl reload nginx; then
    rollback_configs
    ((had_nginx)) || rm -f -- "$DASHBOARD_NGINX_AVAILABLE"
    validate_nginx && run_cmd systemctl reload nginx || true
    die 'Unable to reload Nginx; previous Dashboard bot-protection settings restored.' "$EXIT_SYSTEM"
  fi
  commit_configs
  audit_event 'dashboard bot protection set' SUCCESS "provider=$provider"
  ok "Dashboard bot protection: $provider"
}

dashboard_bot_protection() {
  local sub=${1:-status} configured_secret
  shift || true
  case "$sub" in
    status)
      (($# == 0)) || die 'dashboard bot-protection status accepts no arguments.' "$EXIT_INVALID_ARGUMENT"
      configured_secret=$(record_get "$DASHBOARD_CONFIG_FILE" DASHBOARD_BOT_SECRET || printf '')
      printf 'BOT PROTECTION\n================\nProvider       : %s\nSite key       : %s\nSecret         : %s\n' \
        "$(record_get "$DASHBOARD_CONFIG_FILE" DASHBOARD_BOT_PROVIDER || printf none)" \
        "$(record_get "$DASHBOARD_CONFIG_FILE" DASHBOARD_BOT_SITE_KEY || printf '')" \
        "$([[ -n "$configured_secret" ]] && printf configured || printf not-configured)"
      ;;
    set) (($# == 4 && "$3" == --secret)) || die 'Usage: dashboard bot-protection set PROVIDER SITE_KEY --secret SECRET' "$EXIT_INVALID_ARGUMENT"; dashboard_bot_protection_set "$1" "$2" "$4" ;;
    *) die 'Usage: dashboard bot-protection <status|set PROVIDER SITE_KEY --secret SECRET>' "$EXIT_INVALID_ARGUMENT" ;;
  esac
}

dashboard_service_state() {
  if service_is_active "$1"; then printf 'running'; else printf 'stopped'; fi
}

dashboard_ssl_days() {
  local record=$1 domain ssl cert expiry
  domain=$(record_get "$record" DOMAIN || true)
  ssl=$(record_get "$record" SSL || true)
  cert="$(root_path /etc/letsencrypt/live)/$domain/cert.pem"
  if ! [[ "$ssl" == yes && -s "$cert" ]] || ! has_command openssl; then printf ''; return; fi
  expiry=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2- || true)
  [[ -n "$expiry" ]] || { printf ''; return; }
  date -d "$expiry" +%s 2>/dev/null | awk -v now="$(date +%s)" '{printf "%d", ($1-now)/86400}'
}

dashboard_update_counts() {
  local simulation total security
  simulation=$(apt-get -s upgrade 2>/dev/null || true)
  total=$(grep -c '^Inst ' <<< "$simulation" || true)
  security=$(grep '^Inst ' <<< "$simulation" | grep -Eci 'security|UbuntuESMApps|UbuntuESMInfra' || true)
  printf '%s %s\n' "${total:-0}" "${security:-0}"
}

dashboard_snapshot() {
  require_root
  local hostname_value os kernel uptime_value load cpu memory_total memory_available memory_used ram disk disk_total_bytes disk_used_bytes reboot
  local websites=0 https=0 expiring=0 updates security_updates security_output security_score
  local bot_provider bot_site_key bot_secret bot_enabled bot_secret_configured
  local version php_state
  hostname_value=$(hostname -f 2>/dev/null || hostname 2>/dev/null || printf unknown)
  os=$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-unknown}")
  kernel=$(uname -r 2>/dev/null || printf unknown)
  uptime_value=$(uptime -p 2>/dev/null || printf unknown)
  load=$(awk '{print $1}' /proc/loadavg 2>/dev/null || printf 0)
  cpu=$(cpu_usage 2>/dev/null || printf 0)
  memory_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || printf 0)
  memory_available=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || printf 0)
  memory_used=0
  if [[ "$memory_total" =~ ^[0-9]+$ && "$memory_available" =~ ^[0-9]+$ && "$memory_total" -gt 0 ]]; then
    memory_used=$((memory_total - memory_available)); ((memory_used < 0)) && memory_used=0
    ram=$((100 * memory_used / memory_total))
  else
    ram=0
  fi
  read -r disk_total_bytes disk_used_bytes disk < <(df -P -B1 / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $2, $3, $5}' || printf '0 0 0')
  [[ "$disk_total_bytes" =~ ^[0-9]+$ ]] || disk_total_bytes=0
  [[ "$disk_used_bytes" =~ ^[0-9]+$ ]] || disk_used_bytes=0
  [[ "$disk" =~ ^[0-9]+$ ]] || disk=0
  [[ -f "$(root_path /var/run/reboot-required)" ]] && reboot=yes || reboot=no
  read -r updates security_updates < <(dashboard_update_counts)
  security_output=$(security_status 2>/dev/null || true)
  security_score=$(sed -n 's/^Security Score: \([0-9][0-9]*\) \/ 100$/\1/p' <<< "$security_output" | head -1)
  security_score=${security_score:-0}
  bot_provider=$(record_get "$DASHBOARD_CONFIG_FILE" DASHBOARD_BOT_PROVIDER || printf none)
  bot_site_key=$(record_get "$DASHBOARD_CONFIG_FILE" DASHBOARD_BOT_SITE_KEY || printf '')
  bot_secret=$(record_get "$DASHBOARD_CONFIG_FILE" DASHBOARD_BOT_SECRET || printf '')
  [[ "$bot_provider" != none && -n "$bot_secret" ]] && bot_enabled=yes || bot_enabled=no
  [[ -n "$bot_secret" ]] && bot_secret_configured=yes || bot_secret_configured=no

  local record domain ssl days
  shopt -s nullglob
  for record in "$STATE_DIR"/websites/*.conf; do
    websites=$((websites + 1)); domain=$(record_get "$record" DOMAIN || true); ssl=$(record_get "$record" SSL || true)
    [[ "$ssl" == yes ]] && https=$((https + 1))
    days=$(dashboard_ssl_days "$record")
    [[ "$days" =~ ^-?[0-9]+$ && "$days" -le 30 ]] && expiring=$((expiring + 1))
  done
  shopt -u nullglob

  version=$DEFAULT_PHP_VERSION
  php_state=$(dashboard_service_state "php$version-fpm")
  printf '{"status":"success","data":{'
  printf '"server":{"hostname":%s,"os":%s,"kernel":%s,"uptime":%s,"load":%s,' \
    "$(dashboard_json_string "$hostname_value")" "$(dashboard_json_string "$os")" "$(dashboard_json_string "$kernel")" "$(dashboard_json_string "$uptime_value")" "$(dashboard_json_string "$load")"
  printf '"cpu":%s,"ram":%s,"disk":%s,"ram_used_kb":%s,"ram_total_kb":%s,"disk_used_bytes":%s,"disk_total_bytes":%s},' \
    "$(dashboard_json_number "$cpu")" "$(dashboard_json_number "$ram")" "$(dashboard_json_number "$disk")" \
    "$(dashboard_json_number "$memory_used")" "$(dashboard_json_number "$memory_total")" \
    "$(dashboard_json_number "$disk_used_bytes")" "$(dashboard_json_number "$disk_total_bytes")"
  printf '"services":{"nginx":%s,"php_fpm":%s,"mariadb":%s,"firewall":%s},' \
    "$(dashboard_json_string "$(dashboard_service_state nginx)")" "$(dashboard_json_string "$php_state")" \
    "$(dashboard_json_string "$(dashboard_service_state mariadb)")" \
    "$(dashboard_json_string "$(ufw status 2>/dev/null | grep -q 'Status: active' && printf running || printf stopped)")"
  printf '"websites":{"total":%s,"https":%s,"ssl_expiring":%s},' "$(dashboard_json_number "$websites")" "$(dashboard_json_number "$https")" "$(dashboard_json_number "$expiring")"
  printf '"updates":{"available":%s,"security":%s,"reboot_required":%s},' "$(dashboard_json_number "$updates")" "$(dashboard_json_number "$security_updates")" "$(dashboard_json_string "$reboot")"
  printf '"security":{"score":%s},"php":{"default_version":%s},"bot_protection":{"provider":%s,"enabled":%s,"site_key":%s,"secret_configured":%s}}}\n' \
    "$(dashboard_json_number "$security_score")" "$(dashboard_json_string "$version")" \
    "$(dashboard_json_string "$bot_provider")" "$(dashboard_json_string "$bot_enabled")" \
    "$(dashboard_json_string "$bot_site_key")" "$(dashboard_json_string "$bot_secret_configured")"
}

dashboard_websites() {
  require_root
  local record domain status ssl php root days first=1
  printf '{"status":"success","data":['
  shopt -s nullglob
  for record in "$STATE_DIR"/websites/*.conf; do
    domain=$(record_get "$record" DOMAIN || true); status=$(record_get "$record" STATUS || printf unknown)
    ssl=$(record_get "$record" SSL || printf no); php=$(record_get "$record" PHP_VERSION || printf unknown)
    root=$(record_get "$record" DOCUMENT_ROOT || printf '') ; days=$(dashboard_ssl_days "$record")
    ((first)) || printf ','; first=0
    printf '{"domain":%s,"status":%s,"https":%s,"php_version":%s,"document_root":%s,"ssl_days":%s}' \
      "$(dashboard_json_string "$domain")" "$(dashboard_json_string "$status")" "$(dashboard_json_string "$ssl")" \
      "$(dashboard_json_string "$php")" "$(dashboard_json_string "$root")" "$(dashboard_json_number "${days:--1}")"
  done
  shopt -u nullglob
  printf ']}\n'
}

dashboard_backups() {
  require_root
  local file name size created first=1
  printf '{"status":"success","data":['
  shopt -s nullglob
  for file in "$BACKUP_DIR"/serverctl-*.tar.gz "$BACKUP_DIR"/serverctl-*.tar.gz.gpg; do
    name=$(basename "$file")
    validate_backup_name "$name" || continue
    size=$(stat -c %s -- "$file" 2>/dev/null || printf 0)
    created=$(date -r "$file" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf unknown)
    ((first)) || printf ','
    first=0
    printf '{"name":%s,"size":%s,"created":%s}' \
      "$(dashboard_json_string "$name")" "$(dashboard_json_number "$size")" "$(dashboard_json_string "$created")"
  done
  shopt -u nullglob
  printf ']}\n'
}

dashboard_cron() {
  require_root
  printf '{"status":"success","data":%s}\n' "$(cron_jobs_json)"
}

dashboard_cron_status() {
  require_root
  printf '{"status":"success","data":%s}\n' "$(cron_status_json)"
}

dashboard_cron_logs() {
  require_root
  local id=${1:-} lines=${2:-100} file line first=1
  cron_valid_id "$id" || die 'Invalid Cron job ID.' "$EXIT_VALIDATION"
  [[ "$lines" =~ ^(50|100|500)$ ]] || die 'Invalid Cron log limit.' "$EXIT_VALIDATION"
  file=$(cron_log_path "$id")
  printf '{"status":"success","data":['
  if [[ -f "$file" ]]; then
    while IFS= read -r line; do
      ((first)) || printf ','; first=0; cron_json_string "$line"
    done < <(tail -n "$lines" -- "$file")
  fi
  printf ']}\n'
}

dashboard_logs() {
  require_root
  local type=${1:-} lines=${2:-100} search=${3:-} file
  [[ "$lines" =~ ^(50|100|500)$ ]] || die 'Dashboard log limit must be 50, 100, or 500.' "$EXIT_VALIDATION"
  [[ "$search" != *$'\n'* && "$search" != *$'\r'* && ${#search} -le 200 ]] || die 'Invalid dashboard log search.' "$EXIT_VALIDATION"
  case "$type" in
    nginx-access) file=$(root_path /var/log/nginx/access.log) ;;
    nginx-error) file=$(root_path /var/log/nginx/error.log) ;;
    system) file=$(root_path /var/log/syslog) ;;
    audit) file=$AUDIT_LOG ;;
    login) file="$DASHBOARD_STATE_DIR/audit.log"; search=$'\tLOGIN\t' ;;
    *) die 'Unknown dashboard log type.' "$EXIT_INVALID_ARGUMENT" ;;
  esac
  [[ -f "$file" ]] || die 'Requested log file is unavailable.' "$EXIT_SYSTEM"
  if [[ -n "$search" ]]; then grep -F -- "$search" "$file" | tail -n "$lines" || true
  else tail -n "$lines" -- "$file"; fi
}

dashboard_action() {
  require_root
  local action=${1:-}; shift || true
  case "$action" in
    nginx-reload) (($# == 0)) || die 'nginx-reload accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; nginx_reload ;;
    nginx-restart) (($# == 0)) || die 'nginx-restart accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; nginx_restart ;;
    firewall-reload) (($# == 0)) || die 'firewall-reload accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; cmd_firewall reload ;;
    backup-all) (($# == 0)) || die 'backup-all accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; backup_create_all ;;
    backup-restore) (($# == 1)) || die 'backup-restore requires one archive name.' "$EXIT_INVALID_ARGUMENT"; backup_restore "$1" ;;
    backup-delete) (($# == 1)) || die 'backup-delete requires one archive name.' "$EXIT_INVALID_ARGUMENT"; backup_delete "$1" ;;
    website-remove) (($# == 1)) || die 'website-remove requires one domain.' "$EXIT_INVALID_ARGUMENT"; website_remove "$1" ;;
    database-remove) (($# == 1)) || die 'database-remove requires one database name.' "$EXIT_INVALID_ARGUMENT"; database_remove "$1" ;;
    update-check) (($# == 0)) || die 'update-check accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; update_check ;;
    bot-protection-set) [[ "$#" -eq 4 && "${3:-}" == --secret ]] || die 'bot-protection-set requires PROVIDER SITE_KEY --secret SECRET.' "$EXIT_INVALID_ARGUMENT"; dashboard_bot_protection_set "${1:-}" "${2:-}" "${4:-}" ;;
    cron-add-website) (($# == 5)) || die 'cron-add-website requires WEBSITE SCHEDULE SCRIPT DESCRIPTION ENABLED.' "$EXIT_INVALID_ARGUMENT"; add_cron_website_job "$1" "$2" "$3" "$4" "$5" ;;
    cron-edit-website) (($# == 6)) || die 'cron-edit-website requires ID WEBSITE SCHEDULE SCRIPT DESCRIPTION ENABLED.' "$EXIT_INVALID_ARGUMENT"; update_cron_website_job "$1" "$2" "$3" "$4" "$5" "$6" ;;
    cron-enable) (($# == 1)) || die 'cron-enable requires one ID.' "$EXIT_INVALID_ARGUMENT"; enable_cron_job "$1" ;;
    cron-disable) (($# == 1)) || die 'cron-disable requires one ID.' "$EXIT_INVALID_ARGUMENT"; disable_cron_job "$1" ;;
    cron-run) (($# == 1)) || die 'cron-run requires one ID.' "$EXIT_INVALID_ARGUMENT"; run_cron_job "$1" ;;
    cron-delete) (($# == 1)) || die 'cron-delete requires one ID.' "$EXIT_INVALID_ARGUMENT"; delete_cron_job "$1" ;;
    *) die 'Unknown or disallowed dashboard action.' "$EXIT_INVALID_ARGUMENT" ;;
  esac
}

dashboard_status() {
  printf 'DASHBOARD STATUS\n=================\n'
  if [[ -d "$DASHBOARD_INSTALL_ROOT/public" ]]; then printf 'Files       : INSTALLED\n'; else printf 'Files       : NOT INSTALLED\n'; fi
  if [[ -f "$DASHBOARD_CONFIG_FILE" ]]; then printf 'Configuration: PRESENT\n'; else printf 'Configuration: NOT CONFIGURED\n'; fi
  if [[ -L "$DASHBOARD_NGINX_ENABLED" || -f "$DASHBOARD_NGINX_ENABLED" ]]; then printf 'Nginx       : ENABLED\n'; else printf 'Nginx       : DISABLED\n'; fi
}

dashboard_validate_name() {
  validate_site_name "${1,,}"
}

dashboard_is_local_name() {
  is_local_site "${1,,}"
}

dashboard_render_nginx() {
  local domain=$1 php_socket=$2 cert_root=$3 local_mode=${4:-no} local_port=${5:-8088}
  if [[ "$local_mode" == yes ]]; then
    atomic_write "$DASHBOARD_NGINX_AVAILABLE" 0644 root root <<EOF
# Managed by serverctl. Manual changes may be overwritten.
server {
    listen $local_port;
    listen [::]:$local_port;
    server_name $domain;
    root $DASHBOARD_INSTALL_ROOT/public;
    index index.php;
    autoindex off;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
    add_header Content-Security-Policy "default-src 'self'; style-src 'self'; script-src 'self' https://www.google.com/recaptcha/ https://www.gstatic.com/recaptcha/ https://challenges.cloudflare.com; connect-src 'self' https://www.google.com/recaptcha/ https://challenges.cloudflare.com; frame-src 'self' https://www.google.com/recaptcha/ https://challenges.cloudflare.com; img-src 'self' data: https://www.google.com/recaptcha/ https://www.gstatic.com/recaptcha/; frame-ancestors 'none'; base-uri 'self'" always;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location /api/ { try_files \$uri =404; }
    location ~ ^/(app|views|config) { deny all; }
    location ~ \.php$ {
        try_files \$uri =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_pass unix:$php_socket;
    }
}
EOF
    return 0
  fi
  atomic_write "$DASHBOARD_NGINX_AVAILABLE" 0644 root root <<EOF
# Managed by serverctl. Manual changes may be overwritten.
server {
    listen $local_port ssl http2;
    listen [::]:$local_port ssl http2;
    server_name $domain;
    root $DASHBOARD_INSTALL_ROOT/public;
    index index.php;
    autoindex off;
    ssl_certificate $cert_root/fullchain.pem;
    ssl_certificate_key $cert_root/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_tickets off;
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
    add_header Content-Security-Policy "default-src 'self'; style-src 'self'; script-src 'self' https://www.google.com/recaptcha/ https://www.gstatic.com/recaptcha/ https://challenges.cloudflare.com; connect-src 'self' https://www.google.com/recaptcha/ https://challenges.cloudflare.com; frame-src 'self' https://www.google.com/recaptcha/ https://challenges.cloudflare.com; img-src 'self' data: https://www.google.com/recaptcha/ https://www.gstatic.com/recaptcha/; frame-ancestors 'none'; base-uri 'self'" always;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location /api/ { try_files \$uri =404; }
    location ~ ^/(app|views|config) { deny all; }
    location ~ \.php$ {
        try_files \$uri =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTPS on;
        fastcgi_pass unix:$php_socket;
    }
}
EOF
}

dashboard_install() {
  require_root
  local domain=${1:-} dashboard_user=admin user_supplied=0 requested_user='' password_hash='' password readback php_socket cert_root local_mode=no dashboard_ssl=yes dashboard_port=8088
  [[ -n "$domain" ]] || die 'Usage: serverctl dashboard install DOMAIN [--user USER] [--password-hash HASH]' "$EXIT_INVALID_ARGUMENT"
  shift || true; domain=${domain,,}; dashboard_validate_name "$domain" || die 'Invalid dashboard site name. Use localhost, an IPv4 address, or a DNS domain.' "$EXIT_VALIDATION"
  while (($#)); do
    case "$1" in
      --user) (($# >= 2)) || die '--user requires a value.' "$EXIT_INVALID_ARGUMENT"; dashboard_user=$2; user_supplied=1; shift 2 ;;
      --password-hash) (($# >= 2)) || die '--password-hash requires a value.' "$EXIT_INVALID_ARGUMENT"; password_hash=$2; shift 2 ;;
      *) die "Unknown dashboard install argument: $1" "$EXIT_INVALID_ARGUMENT" ;;
    esac
  done
  if ((user_supplied == 0)) && [[ "$SERVERCTL_TEST_MODE" != 1 && -t 0 ]]; then
    printf 'Dashboard username [%s]: ' "$dashboard_user"
    read -r requested_user || true
    [[ -n "$requested_user" ]] && dashboard_user=$requested_user
  fi
  [[ "$dashboard_user" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die 'Invalid dashboard username.' "$EXIT_VALIDATION"
  [[ -d "$DASHBOARD_INSTALL_ROOT/public" ]] || die 'Dashboard files are not installed.' "$EXIT_SYSTEM"
  run_cmd chmod o+x "$DASHBOARD_INSTALL_ROOT"
  if dashboard_is_local_name "$domain"; then
    local_mode=yes; dashboard_ssl=no; dashboard_port=8088; cert_root=''
  else
    cert_root="$(root_path /etc/letsencrypt/live)/$domain"
    [[ -s "$cert_root/fullchain.pem" && -s "$cert_root/privkey.pem" ]] || die "Dashboard requires an existing HTTPS certificate at $cert_root." "$EXIT_VALIDATION"
  fi
  if [[ -z "$password_hash" ]]; then
    has_command php || die 'PHP CLI is required to create a dashboard password hash.' "$EXIT_SYSTEM"
    printf 'Dashboard password: '; read -r -s password; printf '\nConfirm password: '; read -r -s readback; printf '\n'
    [[ -n "$password" && "$password" == "$readback" ]] || die 'Passwords do not match.' "$EXIT_VALIDATION"
    password_hash=$(printf '%s' "$password" | php -r '$p=stream_get_contents(STDIN); echo password_hash($p, PASSWORD_DEFAULT);')
    unset password readback
  fi
  [[ "$password_hash" =~ ^\$2[ayb]?\$|^\$argon2 ]] || die 'Password hash must be produced by password_hash().' "$EXIT_VALIDATION"
  mkdir -p -- "$DASHBOARD_STATE_DIR"
  touch "$DASHBOARD_STATE_DIR/audit.log"
  if [[ "$SERVERCTL_TEST_MODE" != 1 ]]; then chown www-data:www-data "$DASHBOARD_STATE_DIR"; chmod 0750 "$DASHBOARD_STATE_DIR"; fi
  if [[ "$SERVERCTL_TEST_MODE" != 1 ]]; then chown www-data:www-data "$DASHBOARD_STATE_DIR/audit.log"; chmod 0640 "$DASHBOARD_STATE_DIR/audit.log"; fi
  atomic_write "$DASHBOARD_CONFIG_FILE" 0640 root www-data <<EOF
DASHBOARD_DOMAIN=$domain
DASHBOARD_PATH=/
DASHBOARD_USER=$dashboard_user
DASHBOARD_PASSWORD_HASH=$password_hash
DASHBOARD_READ_ONLY=0
DASHBOARD_BOT_PROVIDER=none
DASHBOARD_BOT_SITE_KEY=
DASHBOARD_BOT_SECRET=
DASHBOARD_BOT_RECAPTCHA_THRESHOLD=0.5
DASHBOARD_ENABLED=1
DASHBOARD_LOCAL_ONLY=$local_mode
DASHBOARD_SSL=$dashboard_ssl
DASHBOARD_PORT=$dashboard_port
EOF
  dashboard_render_nginx "$domain" "/run/php/php${DEFAULT_PHP_VERSION}-fpm.sock" "$cert_root" "$local_mode" "$dashboard_port"
  ln -sfn "$DASHBOARD_NGINX_AVAILABLE" "$DASHBOARD_NGINX_ENABLED"
  validate_nginx || { rm -f -- "$DASHBOARD_NGINX_ENABLED"; die 'Nginx rejected the dashboard configuration.' "$EXIT_VALIDATION"; }
  run_cmd systemctl reload nginx
  audit_event 'dashboard install' SUCCESS "domain=$domain"
  if [[ "$local_mode" == yes ]]; then
    ok "Dashboard enabled: http://$domain:$dashboard_port/"
  else
    ok "Dashboard enabled: https://$domain:$dashboard_port/"
  fi
  if ufw status 2>/dev/null | grep -q 'Status: active'; then
    warn "Dashboard listens on TCP $dashboard_port. Allow it as needed with: serverctl firewall add $dashboard_port tcp SOURCE_CIDR"
  fi
}

dashboard_uninstall() {
  require_root
  (($# == 0)) || die 'dashboard uninstall accepts no arguments.' "$EXIT_INVALID_ARGUMENT"
  [[ -f "$DASHBOARD_CONFIG_FILE" ]] || die 'Dashboard is not configured.' "$EXIT_VALIDATION"
  local domain; domain=$(record_get "$DASHBOARD_CONFIG_FILE" DASHBOARD_DOMAIN || sed -n 's/^DASHBOARD_DOMAIN=//p' "$DASHBOARD_CONFIG_FILE")
  confirm "Remove the Dashboard and its Nginx site?" "$domain" || die 'Cancelled.' "$EXIT_GENERAL"
  rm -f -- "$DASHBOARD_NGINX_ENABLED" "$DASHBOARD_NGINX_AVAILABLE" "$DASHBOARD_CONFIG_FILE"
  rm -rf -- "$DASHBOARD_INSTALL_ROOT" "$DASHBOARD_STATE_DIR"
  run_cmd systemctl reload nginx || true
  audit_event 'dashboard uninstall' SUCCESS "domain=$domain"
  ok 'Dashboard removed. Existing websites and server services were not changed.'
}

cmd_dashboard() {
  local sub=${1:-status}; shift || true
  case "$sub" in
    status) (($# == 0)) || die 'dashboard status accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; dashboard_status ;;
    snapshot) (($# == 0)) || die 'dashboard snapshot accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; dashboard_snapshot ;;
    websites) (($# == 0)) || die 'dashboard websites accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; dashboard_websites ;;
    backups) (($# == 0)) || die 'dashboard backups accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; dashboard_backups ;;
    cron) (($# == 0)) || die 'dashboard cron accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; dashboard_cron ;;
    cron-status) (($# == 0)) || die 'dashboard cron-status accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; dashboard_cron_status ;;
    cron-logs) (($# == 2)) || die 'dashboard cron-logs requires ID and line limit.' "$EXIT_INVALID_ARGUMENT"; dashboard_cron_logs "$@" ;;
    logs) dashboard_logs "$@" ;;
    action) dashboard_action "$@" ;;
    bot-protection) dashboard_bot_protection "$@" ;;
    install) dashboard_install "$@" ;;
    uninstall) dashboard_uninstall "$@" ;;
    *) die 'Usage: serverctl dashboard <status|snapshot|websites|backups|cron|cron-status|cron-logs|bot-protection|logs|action|install|uninstall>' "$EXIT_INVALID_ARGUMENT" ;;
  esac
}
