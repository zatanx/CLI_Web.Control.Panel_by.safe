#!/usr/bin/env bash

cmd_website() {
  local sub=${1:-}; shift || true
  case "$sub" in
    list) (($# == 0)) || die "website list accepts no arguments." "$EXIT_INVALID_ARGUMENT"; website_list ;;
    add) website_add "$@" ;;
    remove) website_remove "$@" ;;
    health) website_health "$@" ;;
    csp) website_csp "$@" ;;
    *) die "Usage: serverctl website <list|add|remove|health|csp>" "$EXIT_INVALID_ARGUMENT" ;;
  esac
}

website_list() {
  printf '%-32s %-8s %-8s %-10s %-24s %s\n' DOMAIN PHP SSL STATUS USER DOCUMENT_ROOT
  local file domain php ssl status user root
  shopt -s nullglob
  for file in "$STATE_DIR"/websites/*.conf; do
    domain=$(record_get "$file" DOMAIN); php=$(record_get "$file" PHP_VERSION)
    ssl=$(record_get "$file" SSL); status=$(record_get "$file" STATUS)
    user=$(record_get "$file" USER); root=$(record_get "$file" DOCUMENT_ROOT)
    printf '%-32s %-8s %-8s %-10s %-24s %s\n' "$domain" "$php" "$ssl" "$status" "$user" "$root"
  done
  shopt -u nullglob
}

website_add() {
  require_root
  local domain=${1:-} php=$DEFAULT_PHP_VERSION user site_root
  [[ -n "$domain" ]] || die "Domain is required." "$EXIT_INVALID_ARGUMENT"
  shift || true
  while (($#)); do
    case "$1" in
      --php) (($# >= 2)) || die "--php requires a version." "$EXIT_INVALID_ARGUMENT"; php=$2; shift 2 ;;
      *) die "Unknown website add argument: $1" "$EXIT_INVALID_ARGUMENT" ;;
    esac
  done
  domain=${domain,,}
  validate_site_name "$domain" || die "Invalid domain or IP address: $domain" "$EXIT_VALIDATION"
  validate_php_version "$php" || die "Unsupported PHP version: $php" "$EXIT_VALIDATION"
  website_exists "$domain" && die "Website already exists: $domain" "$EXIT_VALIDATION"
  [[ "$SERVERCTL_TEST_MODE" == 1 || -x "/usr/sbin/php-fpm$php" || -x "/usr/bin/php-fpm$php" ]] || die "PHP $php FPM is not installed." "$EXIT_SYSTEM"
  user=$(website_user "$domain")
  site_root="$WEB_ROOT/$domain"
  assert_safe_web_path "$site_root"
  [[ ! -e "$site_root" && ! -e "$(nginx_available_dir)/$domain.conf" && ! -e "$(php_pool_dir "$php")/$domain.conf" ]] || die "Unmanaged files or configuration already exist for $domain; refusing to overwrite them." "$EXIT_VALIDATION"
  if [[ "$SERVERCTL_TEST_MODE" != 1 ]] && getent passwd "$user" >/dev/null; then die "Linux user $user already exists without a serverctl website record." "$EXIT_VALIDATION"; fi
  with_lock website _website_add_locked "$domain" "$php" "$user" "$site_root"
}

_website_add_locked() {
  local domain=$1 php=$2 user=$3 site_root=$4 pool site_config link sftp_password
  pool="$(php_pool_dir "$php")/$domain.conf"; site_config="$(nginx_available_dir)/$domain.conf"; link="$(nginx_enabled_dir)/$domain.conf"
  info "Creating isolated website $domain ($user, PHP $php)..."
  if [[ "$SERVERCTL_TEST_MODE" != 1 ]]; then
    getent passwd "$user" >/dev/null || run_cmd useradd --system --home-dir "$site_root" --create-home --shell /usr/sbin/nologin --user-group "$user"
  fi
  mkdir -p -- "$site_root/public" "$site_root/logs" "$site_root/tmp" "$(dirname "$(php_socket_path "$domain")")"
  mkdir -p -- "$(dirname "$(nginx_access_path "$domain")")"
  atomic_write "$(nginx_access_path "$domain")" 0644 root root <<'EOF'
# Managed by serverctl. Open access.
allow all;
EOF
  touch "$site_root/logs/access.log" "$site_root/logs/error.log" "$site_root/logs/php-error.log"
  if [[ "$SERVERCTL_TEST_MODE" != 1 ]]; then
    chown -R "$user:$user" "$site_root"
    chown "$user:www-data" "$site_root" "$site_root/public"
    chown "root:$user" "$site_root/logs"; chown "www-data:adm" "$site_root/logs/access.log" "$site_root/logs/error.log"; chown "$user:$user" "$site_root/logs/php-error.log"
    chmod 0750 "$site_root" "$site_root/public" "$site_root/logs" "$site_root/tmp"; chmod 0640 "$site_root/logs/"*.log
  fi
  sftp_password=$(sftp_generate_password)
  if ! sftp_prepare_site "$user" "$site_root" || ! sftp_set_password "$user" "$sftp_password" || ! sftp_apply_config "$domain" "$user" "$site_root"; then
    rm -f -- "$link" "$site_config" "$pool" "$(nginx_access_path "$domain")"
    rm -rf -- "$site_root"
    [[ "$SERVERCTL_TEST_MODE" == 1 ]] || userdel "$user" 2>/dev/null || true
    die "SFTP configuration failed; website creation rolled back." "$EXIT_SYSTEM"
  fi
  if [[ ! -e "$site_root/public/index.html" ]]; then
    atomic_write "$site_root/public/index.html" 0640 "$user" www-data <<EOF
<!doctype html><html lang="en"><meta charset="utf-8"><title>$domain</title><h1>$domain is ready</h1></html>
EOF
  fi
  render_php_pool "$domain" "$php" "$user"
  render_nginx_site "$domain" "$php" no
  mkdir -p -- "$(nginx_enabled_dir)"
  [[ -L "$link" ]] || ln -s "$site_config" "$link"
  if ! reload_web_stack "$php"; then
    sftp_apply_config "" "" "" "$domain" || true
    rm -f -- "$link" "$site_config" "$pool" "$(nginx_access_path "$domain")"
    rm -rf -- "$site_root"
    [[ "$SERVERCTL_TEST_MODE" == 1 ]] || userdel "$user" 2>/dev/null || true
    die "Validation failed; website configuration rolled back." "$EXIT_VALIDATION"
  fi
  save_website_record "$domain" "$php" "$user" no online yes
  ok "Website created: http://$domain ($site_root/public)"
  printf 'SFTP User: %s\nPassword:  %s\nHost:      %s\nPort:      22\nPath:      /public\n' "$user" "$sftp_password" "$domain"
}

website_remove() {
  require_root
  local domain=${1:-} no_backup=0
  [[ -n "$domain" ]] || die "Domain is required." "$EXIT_INVALID_ARGUMENT"
  shift || true; domain=${domain,,}
  while (($#)); do case "$1" in --no-backup) no_backup=1 ;; *) die "Unknown website remove argument: $1" "$EXIT_INVALID_ARGUMENT" ;; esac; shift; done
  validate_site_name "$domain" || die "Invalid domain or IP address." "$EXIT_VALIDATION"
  website_exists "$domain" || die "Website not found: $domain" "$EXIT_VALIDATION"
  local record php user ssl site_root
  record=$(website_record_path "$domain"); php=$(record_get "$record" PHP_VERSION); user=$(record_get "$record" USER); ssl=$(record_get "$record" SSL); site_root="$WEB_ROOT/$domain"
  printf 'Domain: %s\nUser: %s\nFiles: %s\nSSL: %s\n' "$domain" "$user" "$site_root" "$ssl"
  if ((no_backup == 0)); then backup_create_website "$domain"; fi
  confirm "Permanently remove this website?" "$domain" || die "Cancelled." "$EXIT_GENERAL"
  with_lock website _website_remove_locked "$domain" "$php" "$user" "$site_root"
}

remove_website_user() {
  local user=$1 attempt group_members
  [[ "$SERVERCTL_TEST_MODE" == 1 ]] && return 0
  getent passwd "$user" >/dev/null 2>&1 || return 0

  if ! userdel "$user" 2>/dev/null; then
    if has_command pkill; then
      pkill -TERM -u "$user" 2>/dev/null || true
      for attempt in 1 2 3 4 5; do
        pgrep -u "$user" >/dev/null 2>&1 || break
        sleep 1
      done
      if pgrep -u "$user" >/dev/null 2>&1; then
        pkill -KILL -u "$user" 2>/dev/null || true
      fi
    fi
    userdel "$user" 2>/dev/null || true
  fi

  if getent passwd "$user" >/dev/null 2>&1; then
    warn "Linux user $user could not be removed. Remove it after stopping its remaining processes."
    return 1
  fi
  if getent group "$user" >/dev/null 2>&1; then
    group_members=$(getent group "$user" | cut -d: -f4)
    [[ -n "$group_members" ]] || groupdel "$user" 2>/dev/null || true
  fi
  return 0
}

_website_remove_locked() {
  local domain=$1 php=$2 user=$3 site_root=$4 enabled_file enabled_target="" enabled_snapshot=""
  assert_safe_web_path "$site_root"
  enabled_file="$(nginx_enabled_dir)/$domain.conf"
  if [[ -L "$enabled_file" ]]; then
    enabled_target=$(readlink -- "$enabled_file")
  elif [[ -e "$enabled_file" ]]; then
    enabled_snapshot=$(mktemp "$STATE_DIR/.website-remove.XXXXXX")
    rm -f -- "$enabled_snapshot"
    cp -a -- "$enabled_file" "$enabled_snapshot"
  fi
  ROLLBACK_FILES=()
  backup_config_file "$(nginx_available_dir)/$domain.conf"
  backup_config_file "$(php_pool_dir "$php")/$domain.conf"
  backup_config_file "$(nginx_access_path "$domain")"
  rm -f -- "$enabled_file" "$(nginx_available_dir)/$domain.conf" "$(php_pool_dir "$php")/$domain.conf" "$(nginx_access_path "$domain")"
  if ! validate_nginx; then
    rollback_configs
    if [[ -n "$enabled_target" ]]; then ln -sfn -- "$enabled_target" "$enabled_file"; elif [[ -n "$enabled_snapshot" ]]; then cp -a -- "$enabled_snapshot" "$enabled_file"; fi
    rm -f -- "$enabled_snapshot"
    error "Nginx validation failed after removal; configuration restored."
    return "$EXIT_VALIDATION"
  fi
  rm -f -- "$enabled_snapshot"
  run_cmd systemctl reload nginx; run_cmd systemctl reload "php$php-fpm"
  commit_configs
  sftp_apply_config "" "" "" "$domain" || warn "Website removed, but the SFTP SSH configuration could not be reloaded."
  remove_website_user "$user" || true
  rm -rf -- "$site_root"
  rm -f -- "$(website_record_path "$domain")"
  ok "Website removed: $domain"
}

website_csp() {
  require_root
  local domain=${1:-} policy=${2:-}
  (($# == 2)) && [[ -n "$domain" && -n "$policy" ]] || die "Usage: serverctl website csp DOMAIN 'POLICY'" "$EXIT_INVALID_ARGUMENT"
  validate_site_name "$domain" || die "Invalid domain or IP address." "$EXIT_VALIDATION"
  validate_csp "$policy" || die "CSP must be 1-1024 printable characters and cannot contain double quotes, backslashes, or newlines." "$EXIT_VALIDATION"
  website_exists "$domain" || die "Website not found." "$EXIT_VALIDATION"
  confirm "Replace the Content-Security-Policy for $domain?" || die "Cancelled." "$EXIT_GENERAL"
  local record php ssl nginx_file upload_limit rate_burst static_cache
  record=$(website_record_path "$domain"); php=$(record_get "$record" PHP_VERSION); ssl=$(record_get "$record" SSL); nginx_file="$(nginx_available_dir)/$domain.conf"
  upload_limit=$(record_get "$record" UPLOAD_LIMIT || printf 32m); rate_burst=$(record_get "$record" RATE_BURST || printf 40); static_cache=$(record_get "$record" STATIC_CACHE || printf off)
  ROLLBACK_FILES=(); backup_config_file "$nginx_file"; render_nginx_site "$domain" "$php" "$ssl" "$policy" "$upload_limit" "$rate_burst" "$static_cache"
  if ! validate_nginx; then rollback_configs; die "Nginx rejected the CSP; configuration restored." "$EXIT_VALIDATION"; fi
  run_cmd systemctl reload nginx; update_record_value "$record" CSP "$policy"; commit_configs
  ok "CSP updated for $domain."
}

website_health() {
  local domain=${1:-}; (($# == 1)) || die "Domain is required and no extra arguments are allowed." "$EXIT_INVALID_ARGUMENT"
  validate_site_name "$domain" || die "Invalid domain or IP address." "$EXIT_VALIDATION"
  website_exists "$domain" || die "Website not found." "$EXIT_VALIDATION"
  local file php socket failures=0
  file=$(website_record_path "$domain"); php=$(record_get "$file" PHP_VERSION); socket=$(php_socket_path "$domain")
  printf 'Website health: %s\n' "$domain"
  if getent ahosts "$domain" >/dev/null 2>&1; then ok "DNS resolves"; else warn "DNS does not resolve"; ((++failures)); fi
  if [[ -S "$socket" || "$SERVERCTL_TEST_MODE" == 1 ]]; then ok "PHP-FPM socket exists (PHP $php)"; else warn "PHP-FPM socket missing"; ((++failures)); fi
  if curl -fsSIL --max-time 8 "http://$domain" >/dev/null 2>&1; then ok "HTTP responds"; else warn "HTTP check failed"; ((++failures)); fi
  if [[ "$(record_get "$file" SSL)" == yes ]]; then
    if curl -fsSIL --max-time 8 "https://$domain" >/dev/null 2>&1; then ok "HTTPS responds"; else warn "HTTPS check failed"; ((++failures)); fi
  fi
  ((failures == 0))
}
