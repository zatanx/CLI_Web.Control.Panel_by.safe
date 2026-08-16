#!/usr/bin/env bash

SFTP_CONFIG_FILE="$(root_path /etc/ssh/sshd_config.d/59-serverctl-sftp.conf)"

cmd_sftp() {
  local sub=${1:-}; shift || true
  case "$sub" in
    list) (($# == 0)) || die 'sftp list accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; sftp_list ;;
    password) sftp_password "$@" ;;
    enable) sftp_enable "$@" ;;
    disable) sftp_disable "$@" ;;
    *) die 'Usage: serverctl sftp <list|password|enable|disable>' "$EXIT_INVALID_ARGUMENT" ;;
  esac
}

sftp_generate_password() {
  if has_command openssl; then
    openssl rand -base64 32 | tr -d '/+=' | cut -c1-32
  else
    LC_ALL=C tr -dc 'A-Za-z0-9_@#%-' < /dev/urandom | head -c 32
  fi
}

sftp_set_password() {
  local user=$1 password=$2
  [[ "$SERVERCTL_TEST_MODE" == 1 ]] && return 0
  printf '%s:%s\n' "$user" "$password" | chpasswd
}

sftp_prepare_site() {
  local user=$1 site_root=$2
  [[ "$SERVERCTL_TEST_MODE" == 1 ]] && return 0
  [[ -d "$site_root" && -d "$site_root/public" ]] || return 1
  chown root:root "$site_root"
  chmod 0755 "$site_root"
  chown "$user:www-data" "$site_root/public"
  chmod 0750 "$site_root/public"
}

sftp_restore_site_permissions() {
  local user=$1 site_root=$2
  [[ "$SERVERCTL_TEST_MODE" == 1 ]] && return 0
  [[ -d "$site_root" && -d "$site_root/public" ]] || return 1
  chown "$user:$user" "$site_root"
  chmod 0750 "$site_root"
  chown "$user:www-data" "$site_root/public"
  chmod 0750 "$site_root/public"
}

sftp_render_entry() {
  local user=$1 site_root=$2
  cat <<EOF

Match User $user
    ChrootDirectory $site_root
    ForceCommand internal-sftp -d /public -u 0027
    PasswordAuthentication yes
    PubkeyAuthentication yes
    PermitTTY no
    AllowTcpForwarding no
    X11Forwarding no
    PermitTunnel no
EOF
}

sftp_render_config() {
  local extra_domain=${1:-} extra_user=${2:-} extra_root=${3:-} skip_domain=${4:-}
  local file domain user enabled
  printf '# Managed by serverctl. SFTP-only website accounts.\n'
  shopt -s nullglob
  for file in "$STATE_DIR"/websites/*.conf; do
    domain=$(record_get "$file" DOMAIN); [[ "$domain" == "$skip_domain" ]] && continue
    enabled=$(record_get "$file" SFTP_ENABLED || printf no); [[ "$enabled" == yes ]] || continue
    user=$(record_get "$file" USER)
    sftp_render_entry "$user" "$WEB_ROOT/$domain"
  done
  shopt -u nullglob
  if [[ -n "$extra_domain" && "$extra_domain" != "$skip_domain" ]]; then
    sftp_render_entry "$extra_user" "$extra_root"
  fi
  printf '\nMatch all\n'
}

sftp_apply_config() {
  local extra_domain=${1:-} extra_user=${2:-} extra_root=${3:-} skip_domain=${4:-}
  local candidate had_config=0
  [[ -e "$SFTP_CONFIG_FILE" || -L "$SFTP_CONFIG_FILE" ]] && had_config=1
  candidate=$(mktemp "$STATE_DIR/.sftp-config.XXXXXX")
  sftp_render_config "$extra_domain" "$extra_user" "$extra_root" "$skip_domain" > "$candidate"
  ROLLBACK_FILES=()
  backup_config_file "$SFTP_CONFIG_FILE"
  atomic_write "$SFTP_CONFIG_FILE" 0644 root root < "$candidate"
  rm -f -- "$candidate"
  if [[ "$SERVERCTL_TEST_MODE" != 1 ]]; then
    if ! sshd -t; then
      rollback_configs; ((had_config)) || rm -f -- "$SFTP_CONFIG_FILE"; return 1
    fi
    if ! run_cmd systemctl reload ssh; then
      rollback_configs; ((had_config)) || rm -f -- "$SFTP_CONFIG_FILE"; return 1
    fi
  fi
  commit_configs
}

sftp_list() {
  require_root
  printf '%-32s %-24s %-8s %s\n' WEBSITE USER ENABLED ROOT
  local file domain user enabled
  shopt -s nullglob
  for file in "$STATE_DIR"/websites/*.conf; do
    domain=$(record_get "$file" DOMAIN); user=$(record_get "$file" USER); enabled=$(record_get "$file" SFTP_ENABLED || printf no)
    printf '%-32s %-24s %-8s %s\n' "$domain" "$user" "$enabled" "$WEB_ROOT/$domain"
  done
  shopt -u nullglob
}

sftp_password() {
  require_root
  local domain=${1:-} record user password enabled
  (($# == 1)) || die 'Usage: serverctl sftp password DOMAIN' "$EXIT_INVALID_ARGUMENT"
  validate_site_name "$domain" || die 'Invalid domain or IP address.' "$EXIT_VALIDATION"
  website_exists "$domain" || die 'Website not found.' "$EXIT_VALIDATION"
  record=$(website_record_path "$domain"); user=$(record_get "$record" USER); enabled=$(record_get "$record" SFTP_ENABLED || printf no)
  [[ "$enabled" == yes ]] || die "SFTP is disabled for $domain. Enable it first." "$EXIT_VALIDATION"
  password=$(sftp_generate_password); sftp_set_password "$user" "$password" || die 'Unable to set the SFTP password.' "$EXIT_SYSTEM"
  ok "SFTP password reset for $domain."
  printf 'SFTP User: %s\nPassword:  %s\nHost:      %s\nPort:      22\nPath:      /public\n' "$user" "$password" "$domain"
}

sftp_enable() {
  require_root
  local domain=${1:-} record user password old_enabled
  (($# == 1)) || die 'Usage: serverctl sftp enable DOMAIN' "$EXIT_INVALID_ARGUMENT"
  validate_site_name "$domain" || die 'Invalid domain or IP address.' "$EXIT_VALIDATION"
  website_exists "$domain" || die 'Website not found.' "$EXIT_VALIDATION"
  record=$(website_record_path "$domain"); user=$(record_get "$record" USER); old_enabled=$(record_get "$record" SFTP_ENABLED || printf no)
  password=$(sftp_generate_password)
  sftp_prepare_site "$user" "$WEB_ROOT/$domain" || die 'Unable to prepare the website root for SFTP.' "$EXIT_SYSTEM"
  sftp_set_password "$user" "$password" || die 'Unable to set the SFTP password.' "$EXIT_SYSTEM"
  update_record_value "$record" SFTP_ENABLED yes
  if ! sftp_apply_config; then
    update_record_value "$record" SFTP_ENABLED "$old_enabled"
    sftp_restore_site_permissions "$user" "$WEB_ROOT/$domain" || true
    die 'Unable to validate or reload SSH SFTP configuration.' "$EXIT_VALIDATION"
  fi
  ok "SFTP enabled for $domain."
  printf 'SFTP User: %s\nPassword:  %s\nHost:      %s\nPort:      22\nPath:      /public\n' "$user" "$password" "$domain"
}

sftp_disable() {
  require_root
  local domain=${1:-} record user old_enabled
  (($# == 1)) || die 'Usage: serverctl sftp disable DOMAIN' "$EXIT_INVALID_ARGUMENT"
  validate_site_name "$domain" || die 'Invalid domain or IP address.' "$EXIT_VALIDATION"
  website_exists "$domain" || die 'Website not found.' "$EXIT_VALIDATION"
  record=$(website_record_path "$domain"); user=$(record_get "$record" USER); old_enabled=$(record_get "$record" SFTP_ENABLED || printf no)
  update_record_value "$record" SFTP_ENABLED no
  if ! sftp_apply_config; then
    update_record_value "$record" SFTP_ENABLED "$old_enabled"
    die 'Unable to validate or reload SSH SFTP configuration.' "$EXIT_VALIDATION"
  fi
  passwd -l "$user" >/dev/null 2>&1 || true
  sftp_restore_site_permissions "$user" "$WEB_ROOT/$domain" || true
  ok "SFTP disabled for $domain."
}
