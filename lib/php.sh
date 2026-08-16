#!/usr/bin/env bash

cmd_php() {
  local sub=${1:-}; shift || true
  case "$sub" in list) (($# == 0)) || die "php list accepts no arguments." "$EXIT_INVALID_ARGUMENT"; php_list ;; set) php_set "$@" ;; health) php_health "$@" ;; *) die "Usage: serverctl php <list|set|health>" "$EXIT_INVALID_ARGUMENT" ;; esac
}

php_health() {
  local domain=${1:-} record version pool socket memory opcache failures=0
  (($# == 1)) && [[ -n "$domain" ]] || die "Usage: serverctl php health DOMAIN" "$EXIT_INVALID_ARGUMENT"
  validate_site_name "$domain" || die "Invalid domain or IP address." "$EXIT_VALIDATION"; website_exists "$domain" || die "Website not found." "$EXIT_VALIDATION"
  record=$(website_record_path "$domain"); version=$(record_get "$record" PHP_VERSION); pool="$(php_pool_dir "$version")/$domain.conf"; socket=$(php_socket_path "$domain")
  printf 'PHP health: %s\nVersion: %s\nPool: %s\nSocket: %s\n' "$domain" "$version" "$pool" "$socket"
  if service_is_active "php$version-fpm" || [[ "$SERVERCTL_TEST_MODE" == 1 ]]; then ok 'PHP-FPM service running'; else error 'PHP-FPM service stopped'; ((++failures)); fi
  [[ -f "$pool" ]] && ok 'Pool configuration exists' || { error 'Pool configuration missing'; ((++failures)); }
  [[ -S "$socket" || "$SERVERCTL_TEST_MODE" == 1 ]] && ok 'Pool socket exists' || { error 'Pool socket missing'; ((++failures)); }
  if has_command "php$version"; then
    memory=$("php$version" -r 'echo ini_get("memory_limit");' 2>/dev/null || printf unknown)
    opcache=$("php$version" -r 'echo ini_get("opcache.enable");' 2>/dev/null || printf unknown)
    printf 'Memory limit: %s\nOPcache: %s\n' "$memory" "${opcache:-0}"
  fi
  ((failures == 0))
}

php_list() {
  local version marker state
  for version in $ALLOWED_PHP_VERSIONS; do
    marker=' '; [[ "$version" == "$DEFAULT_PHP_VERSION" ]] && marker='*'
    state=not-installed
    [[ -x "/usr/sbin/php-fpm$version" || -x "/usr/bin/php-fpm$version" || "$SERVERCTL_TEST_MODE" == 1 ]] && state=installed
    printf 'PHP %-4s %s %s\n' "$version" "$marker" "$state"
  done
}

php_set() {
  require_root
  local domain=${1:-} new_version=${2:-}
  (($# == 2)) && [[ -n "$domain" && -n "$new_version" ]] || die "Usage: serverctl php set DOMAIN VERSION" "$EXIT_INVALID_ARGUMENT"
  validate_site_name "$domain" || die "Invalid domain or IP address." "$EXIT_VALIDATION"
  validate_php_version "$new_version" || die "Unsupported PHP version." "$EXIT_VALIDATION"
  website_exists "$domain" || die "Website not found." "$EXIT_VALIDATION"
  [[ "$SERVERCTL_TEST_MODE" == 1 || -x "/usr/sbin/php-fpm$new_version" || -x "/usr/bin/php-fpm$new_version" ]] || die "PHP $new_version FPM is not installed." "$EXIT_SYSTEM"
  confirm "Change $domain to PHP $new_version?" || die "Cancelled." "$EXIT_GENERAL"
  with_lock website _php_set_locked "$domain" "$new_version"
}

_php_set_locked() {
  local domain=$1 new_version=$2 record old_version user ssl old_pool new_pool nginx_file
  local csp upload_limit rate_burst static_cache
  record=$(website_record_path "$domain"); old_version=$(record_get "$record" PHP_VERSION); user=$(record_get "$record" USER); ssl=$(record_get "$record" SSL); csp=$(record_get "$record" CSP || true)
  upload_limit=$(record_get "$record" UPLOAD_LIMIT || printf 32m); rate_burst=$(record_get "$record" RATE_BURST || printf 40); static_cache=$(record_get "$record" STATIC_CACHE || printf off)
  [[ "$old_version" != "$new_version" ]] || { ok "$domain already uses PHP $new_version."; return; }
  old_pool="$(php_pool_dir "$old_version")/$domain.conf"; new_pool="$(php_pool_dir "$new_version")/$domain.conf"; nginx_file="$(nginx_available_dir)/$domain.conf"
  ROLLBACK_FILES=(); backup_config_file "$old_pool"; backup_config_file "$nginx_file"
  render_php_pool "$domain" "$new_version" "$user"; render_nginx_site "$domain" "$new_version" "$ssl" "$csp" "$upload_limit" "$rate_burst" "$static_cache"
  if ! validate_php_fpm "$new_version" || ! validate_nginx; then
    rm -f -- "$new_pool"; rollback_configs; die "Validation failed; configuration restored." "$EXIT_VALIDATION"
  fi
  rm -f -- "$old_pool"
  if ! run_cmd systemctl reload "php$new_version-fpm" || ! run_cmd systemctl reload nginx; then
    rm -f -- "$new_pool"; rollback_configs
    run_cmd systemctl reload "php$old_version-fpm" || true; run_cmd systemctl reload nginx || true
    die "Service reload failed; configuration restored." "$EXIT_SYSTEM"
  fi
  run_cmd systemctl reload "php$old_version-fpm" || true
  update_record_value "$record" PHP_VERSION "$new_version"; commit_configs
  ok "$domain now uses PHP $new_version."
}
