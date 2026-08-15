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
  printf '%s %s' "${total:-0}" "${security:-0}"
}

dashboard_snapshot() {
  require_root
  local hostname_value os kernel uptime_value load cpu memory_total memory_available ram disk reboot
  local websites=0 https=0 expiring=0 updates security_updates security_output security_score
  local version php_state
  hostname_value=$(hostname -f 2>/dev/null || hostname 2>/dev/null || printf unknown)
  os=$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-unknown}")
  kernel=$(uname -r 2>/dev/null || printf unknown)
  uptime_value=$(uptime -p 2>/dev/null || printf unknown)
  load=$(awk '{print $1}' /proc/loadavg 2>/dev/null || printf 0)
  cpu=$(cpu_usage 2>/dev/null || printf 0)
  memory_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || printf 0)
  memory_available=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || printf 0)
  if [[ "$memory_total" =~ ^[0-9]+$ && "$memory_total" -gt 0 ]]; then ram=$((100 * (memory_total - memory_available) / memory_total)); else ram=0; fi
  disk=$(df -P / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}' || printf 0)
  [[ "$disk" =~ ^[0-9]+$ ]] || disk=0
  [[ -f "$(root_path /var/run/reboot-required)" ]] && reboot=yes || reboot=no
  read -r updates security_updates < <(dashboard_update_counts)
  security_output=$(security_status 2>/dev/null || true)
  security_score=$(sed -n 's/^Security Score: \([0-9][0-9]*\) \/ 100$/\1/p' <<< "$security_output" | head -1)
  security_score=${security_score:-0}

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
  printf '"cpu":%s,"ram":%s,"disk":%s},' "$(dashboard_json_number "$cpu")" "$(dashboard_json_number "$ram")" "$(dashboard_json_number "$disk")"
  printf '"services":{"nginx":%s,"php_fpm":%s,"mariadb":%s,"fail2ban":%s,"firewall":%s},' \
    "$(dashboard_json_string "$(dashboard_service_state nginx)")" "$(dashboard_json_string "$php_state")" \
    "$(dashboard_json_string "$(dashboard_service_state mariadb)")" "$(dashboard_json_string "$(dashboard_service_state fail2ban)")" \
    "$(dashboard_json_string "$(ufw status 2>/dev/null | grep -q 'Status: active' && printf running || printf stopped)")"
  printf '"websites":{"total":%s,"https":%s,"ssl_expiring":%s},' "$(dashboard_json_number "$websites")" "$(dashboard_json_number "$https")" "$(dashboard_json_number "$expiring")"
  printf '"updates":{"available":%s,"security":%s,"reboot_required":%s},' "$(dashboard_json_number "$updates")" "$(dashboard_json_number "$security_updates")" "$(dashboard_json_string "$reboot")"
  printf '"security":{"score":%s},"php":{"default_version":%s}}}\n' \
    "$(dashboard_json_number "$security_score")" "$(dashboard_json_string "$version")"
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

dashboard_logs() {
  require_root
  local type=${1:-} lines=${2:-100} search=${3:-} file
  [[ "$lines" =~ ^(50|100|500)$ ]] || die 'Dashboard log limit must be 50, 100, or 500.' "$EXIT_VALIDATION"
  [[ "$search" != *$'\n'* && "$search" != *$'\r'* && ${#search} -le 200 ]] || die 'Invalid dashboard log search.' "$EXIT_VALIDATION"
  case "$type" in
    nginx-access) file=$(root_path /var/log/nginx/access.log) ;;
    nginx-error) file=$(root_path /var/log/nginx/error.log) ;;
    system) file=$(root_path /var/log/syslog) ;;
    security) file=$(root_path /var/log/fail2ban.log) ;;
    audit) file=$AUDIT_LOG ;;
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
    fail2ban-unban) (($# == 1)) || die 'fail2ban-unban requires one IP address.' "$EXIT_INVALID_ARGUMENT"; fail2ban_ip unban "$1" ;;
    backup-all) (($# == 0)) || die 'backup-all accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; backup_create_all ;;
    backup-restore) (($# == 1)) || die 'backup-restore requires one archive name.' "$EXIT_INVALID_ARGUMENT"; backup_restore "$1" ;;
    website-remove) (($# == 1)) || die 'website-remove requires one domain.' "$EXIT_INVALID_ARGUMENT"; website_remove "$1" ;;
    database-remove) (($# == 1)) || die 'database-remove requires one database name.' "$EXIT_INVALID_ARGUMENT"; database_remove "$1" ;;
    update-check) (($# == 0)) || die 'update-check accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; update_check ;;
    *) die 'Unknown or disallowed dashboard action.' "$EXIT_INVALID_ARGUMENT" ;;
  esac
}

dashboard_status() {
  printf 'DASHBOARD STATUS\n=================\n'
  if [[ -d "$DASHBOARD_INSTALL_ROOT/public" ]]; then printf 'Files       : INSTALLED\n'; else printf 'Files       : NOT INSTALLED\n'; fi
  if [[ -f "$DASHBOARD_CONFIG_FILE" ]]; then printf 'Configuration: PRESENT\n'; else printf 'Configuration: NOT CONFIGURED\n'; fi
  if [[ -L "$DASHBOARD_NGINX_ENABLED" || -f "$DASHBOARD_NGINX_ENABLED" ]]; then printf 'Nginx       : ENABLED\n'; else printf 'Nginx       : DISABLED\n'; fi
}

dashboard_render_nginx() {
  local domain=$1 php_socket=$2 cert_root=$3
  atomic_write "$DASHBOARD_NGINX_AVAILABLE" 0644 root root <<EOF
# Managed by serverctl. Manual changes may be overwritten.
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    location ^~ /.well-known/acme-challenge/ { root $DASHBOARD_INSTALL_ROOT/public; allow all; }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
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
    add_header Content-Security-Policy "default-src 'self'; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'" always;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ^~ /api/ { try_files \$uri =404; }
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
  local domain=${1:-} dashboard_user=admin password_hash='' password readback php_socket cert_root
  [[ -n "$domain" ]] || die 'Usage: serverctl dashboard install DOMAIN [--user USER] [--password-hash HASH]' "$EXIT_INVALID_ARGUMENT"
  shift || true; validate_domain "$domain" || die 'Invalid dashboard domain.' "$EXIT_VALIDATION"
  while (($#)); do
    case "$1" in
      --user) (($# >= 2)) || die '--user requires a value.' "$EXIT_INVALID_ARGUMENT"; dashboard_user=$2; shift 2 ;;
      --password-hash) (($# >= 2)) || die '--password-hash requires a value.' "$EXIT_INVALID_ARGUMENT"; password_hash=$2; shift 2 ;;
      *) die "Unknown dashboard install argument: $1" "$EXIT_INVALID_ARGUMENT" ;;
    esac
  done
  [[ "$dashboard_user" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die 'Invalid dashboard username.' "$EXIT_VALIDATION"
  [[ -d "$DASHBOARD_INSTALL_ROOT/public" ]] || die 'Dashboard files are not installed.' "$EXIT_SYSTEM"
  cert_root="$(root_path /etc/letsencrypt/live)/$domain"
  [[ -s "$cert_root/fullchain.pem" && -s "$cert_root/privkey.pem" ]] || die "Dashboard requires an existing HTTPS certificate at $cert_root." "$EXIT_VALIDATION"
  if [[ -z "$password_hash" ]]; then
    has_command php || die 'PHP CLI is required to create a dashboard password hash.' "$EXIT_SYSTEM"
    printf 'Dashboard password: '; read -r -s password; printf '\nConfirm password: '; read -r -s readback; printf '\n'
    [[ -n "$password" && "$password" == "$readback" ]] || die 'Passwords do not match.' "$EXIT_VALIDATION"
    password_hash=$(printf '%s' "$password" | php -r '$p=stream_get_contents(STDIN); echo password_hash($p, PASSWORD_DEFAULT);')
    unset password readback
  fi
  [[ "$password_hash" =~ ^\$2[ayb]?\$|^\$argon2 ]] || die 'Password hash must be produced by password_hash().' "$EXIT_VALIDATION"
  mkdir -p -- "$DASHBOARD_STATE_DIR"
  if [[ "$SERVERCTL_TEST_MODE" != 1 ]]; then chown www-data:www-data "$DASHBOARD_STATE_DIR"; chmod 0750 "$DASHBOARD_STATE_DIR"; fi
  atomic_write "$DASHBOARD_CONFIG_FILE" 0640 root www-data <<EOF
DASHBOARD_DOMAIN=$domain
DASHBOARD_PATH=/
DASHBOARD_USER=$dashboard_user
DASHBOARD_PASSWORD_HASH=$password_hash
DASHBOARD_READ_ONLY=0
DASHBOARD_ENABLED=1
EOF
  dashboard_render_nginx "$domain" "/run/php/php${DEFAULT_PHP_VERSION}-fpm.sock" "$cert_root"
  ln -sfn "$DASHBOARD_NGINX_AVAILABLE" "$DASHBOARD_NGINX_ENABLED"
  validate_nginx || { rm -f -- "$DASHBOARD_NGINX_ENABLED"; die 'Nginx rejected the dashboard configuration.' "$EXIT_VALIDATION"; }
  run_cmd systemctl reload nginx
  audit_event 'dashboard install' SUCCESS "domain=$domain"
  ok "Dashboard enabled: https://$domain/"
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
    logs) dashboard_logs "$@" ;;
    action) dashboard_action "$@" ;;
    install) dashboard_install "$@" ;;
    uninstall) dashboard_uninstall "$@" ;;
    *) die 'Usage: serverctl dashboard <status|snapshot|websites|logs|action|install|uninstall>' "$EXIT_INVALID_ARGUMENT" ;;
  esac
}
