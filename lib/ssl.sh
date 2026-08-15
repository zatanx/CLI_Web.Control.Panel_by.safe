#!/usr/bin/env bash

cmd_ssl() {
  local sub=${1:-}; shift || true
  case "$sub" in enable) ssl_enable "$@" ;; status) ssl_status "$@" ;; health) ssl_health "$@" ;; *) die "Usage: serverctl ssl <enable|status|health>" "$EXIT_INVALID_ARGUMENT" ;; esac
}

ssl_health() {
  local domain=${1:-} cert chain issuer_chain expiry failures=0 redirect
  (($# == 1)) && [[ -n "$domain" ]] || die "Usage: serverctl ssl health DOMAIN" "$EXIT_INVALID_ARGUMENT"
  validate_domain "$domain" || die "Invalid domain." "$EXIT_VALIDATION"; website_exists "$domain" || die "Website not found." "$EXIT_VALIDATION"
  cert="$(root_path /etc/letsencrypt/live)/$domain/cert.pem"; chain="$(root_path /etc/letsencrypt/live)/$domain/fullchain.pem"; issuer_chain="$(root_path /etc/letsencrypt/live)/$domain/chain.pem"
  [[ -s "$cert" && -s "$chain" ]] || die "Certificate files are missing." "$EXIT_VALIDATION"
  openssl x509 -in "$cert" -noout -subject -issuer -startdate -enddate -fingerprint -sha256
  if openssl verify -CApath /etc/ssl/certs -untrusted "$issuer_chain" "$cert" >/dev/null 2>&1; then ok 'Certificate chain verifies'; else error 'Certificate chain verification failed'; ((++failures)); fi
  expiry=$(openssl x509 -in "$cert" -checkend $((30 * 86400)) -noout 2>/dev/null && printf ok || printf soon)
  [[ "$expiry" == ok ]] && ok 'Certificate valid for more than 30 days' || { warn 'Certificate expires within 30 days'; ((++failures)); }
  if curl -fsSIL --max-time 10 "https://$domain" >/dev/null; then ok 'HTTPS responds'; else error 'HTTPS request failed'; ((++failures)); fi
  redirect=$(curl -sSI --max-time 10 "http://$domain" 2>/dev/null | awk 'tolower($1)=="location:" {print $2}' | tr -d '\r' || true)
  [[ "$redirect" == https://* ]] && ok 'HTTP redirects to HTTPS' || { warn 'HTTP redirect was not observed'; ((++failures)); }
  ((failures == 0))
}

ssl_enable() {
  require_root
  local domain=${1:-} email=""
  [[ -n "$domain" ]] || die "Domain is required." "$EXIT_INVALID_ARGUMENT"
  shift || true; domain=${domain,,}
  while (($#)); do
    case "$1" in --email) (($# >= 2)) || die "--email requires an address." "$EXIT_INVALID_ARGUMENT"; email=$2; shift 2 ;; *) die "Unknown SSL argument: $1" "$EXIT_INVALID_ARGUMENT" ;; esac
  done
  validate_domain "$domain" || die "Invalid domain." "$EXIT_VALIDATION"
  website_exists "$domain" || die "Website not found." "$EXIT_VALIDATION"
  [[ -z "$email" ]] || validate_email "$email" || die "Invalid email address." "$EXIT_VALIDATION"
  [[ "$(record_get "$(website_record_path "$domain")" SSL)" != yes ]] || { ok "SSL is already enabled for $domain."; return; }
  if [[ "$SERVERCTL_TEST_MODE" != 1 ]]; then
    getent ahosts "$domain" >/dev/null 2>&1 || die "DNS does not resolve for $domain." "$EXIT_VALIDATION"
    has_command certbot || die "Certbot is not installed." "$EXIT_SYSTEM"
  fi
  confirm "Request a Let's Encrypt certificate for $domain?" || die "Cancelled." "$EXIT_GENERAL"
  with_lock ssl _ssl_enable_locked "$domain" "$email"
}

_ssl_enable_locked() {
  local domain=$1 email=$2 record php user nginx_file cert_args csp upload_limit rate_burst static_cache
  record=$(website_record_path "$domain"); php=$(record_get "$record" PHP_VERSION); user=$(record_get "$record" USER); csp=$(record_get "$record" CSP || true); nginx_file="$(nginx_available_dir)/$domain.conf"
  upload_limit=$(record_get "$record" UPLOAD_LIMIT || printf 32m); rate_burst=$(record_get "$record" RATE_BURST || printf 40); static_cache=$(record_get "$record" STATIC_CACHE || printf off)
  cert_args=(certonly --webroot -w "$WEB_ROOT/$domain/public" -d "$domain" --non-interactive --agree-tos --no-eff-email)
  if [[ -n "$email" ]]; then cert_args+=(--email "$email"); else cert_args+=(--register-unsafely-without-email); fi
  run_cmd certbot "${cert_args[@]}"
  if [[ "$SERVERCTL_TEST_MODE" != 1 && ! -s "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
    die "Certificate was not created." "$EXIT_SYSTEM"
  fi
  ROLLBACK_FILES=(); backup_config_file "$nginx_file"; render_nginx_site "$domain" "$php" yes "$csp" "$upload_limit" "$rate_burst" "$static_cache"
  if ! validate_nginx; then rollback_configs; die "Nginx rejected the TLS configuration; restored previous config." "$EXIT_VALIDATION"; fi
  run_cmd systemctl reload nginx
  update_record_value "$record" SSL yes; commit_configs
  ok "HTTPS enabled: https://$domain"
}

ssl_status() {
  local requested=${1:-} file domain ssl cert expiry days
  (($# <= 1)) || die "ssl status accepts at most one domain." "$EXIT_INVALID_ARGUMENT"
  [[ -z "$requested" ]] || validate_domain "$requested" || die "Invalid domain." "$EXIT_VALIDATION"
  printf '%-32s %-8s %-24s %s\n' DOMAIN ENABLED EXPIRES DAYS_LEFT
  shopt -s nullglob
  for file in "$STATE_DIR"/websites/*.conf; do
    domain=$(record_get "$file" DOMAIN); [[ -z "$requested" || "$domain" == "$requested" ]] || continue
    ssl=$(record_get "$file" SSL); cert="$(root_path /etc/letsencrypt/live)/$domain/cert.pem"; expiry=-; days=-
    if [[ "$ssl" == yes && -s "$cert" ]] && has_command openssl; then
      expiry=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2-)
      if [[ -n "$expiry" ]]; then days=$(( ($(date -d "$expiry" +%s) - $(date +%s)) / 86400 )); fi
    fi
    printf '%-32s %-8s %-24s %s\n' "$domain" "$ssl" "$expiry" "$days"
    [[ "$days" == - || "$days" -gt 30 ]] || warn "$domain certificate expires in $days days."
  done
  shopt -u nullglob
}
