#!/usr/bin/env bash

cmd_security() {
  local sub=${1:-status}; shift || true
  case "$sub" in
    status) security_status ;;
    scan) security_scan ;;
    ports) security_ports ;;
    permissions) security_permissions ;;
    php-scan) security_php_scan ;;
    suid) security_suid ;;
    services) security_services ;;
    updates) security_updates ;;
    audit) security_audit ;;
    ssh) security_ssh ;;
    *) die "Usage: serverctl security <status|scan|ports|permissions|php-scan|suid|services|updates|audit|ssh>" "$EXIT_INVALID_ARGUMENT" ;;
  esac
}

security_check() {
  local label=$1 weight=$2 check_function=$3
  if "$check_function" >/dev/null 2>&1; then printf '%-24s %s\n' "$label" "$(color '1;32' '[ OK ]')"; SECURITY_SCORE=$((SECURITY_SCORE + weight))
  else printf '%-24s %s\n' "$label" "$(color '1;31' '[ CRITICAL ]')"; SECURITY_CRITICAL=$((SECURITY_CRITICAL + 1)); fi
}

check_firewall() { ufw status | grep -q 'Status: active'; }
check_apparmor() { aa-status --enabled; }
check_ssh_root() { sshd -T | grep -qi '^permitrootlogin no$'; }
check_ssh_keys() { sshd -T | grep -qi '^pubkeyauthentication yes$'; }
check_fail2ban() { systemctl is-active --quiet fail2ban; }
check_php_hardening() { grep -Rqs '^display_errors[[:space:]]*=[[:space:]]*Off' "$(root_path /etc/php)"/*/fpm/conf.d/99-serverctl-security.ini; }
check_mariadb_local() {
  local endpoint found=0
  while IFS= read -r endpoint; do
    found=1
    [[ "$endpoint" == 127.0.0.1:3306 || "$endpoint" == '[::1]:3306' ]] || return 1
  done < <(ss -H -lnt 2>/dev/null | awk '$4 ~ /:3306$/ {print $4}')
  ((found))
}
check_ssl() {
  local file found=0
  shopt -s nullglob
  for file in "$STATE_DIR"/websites/*.conf; do found=1; [[ "$(record_get "$file" SSL)" == yes ]] || { shopt -u nullglob; return 1; }; done
  shopt -u nullglob
  ((found == 0)) || return 0
}
check_updates() { [[ ! -s /var/lib/update-notifier/updates-available ]]; }
check_permissions() { [[ -z "$(find "$WEB_ROOT" -xdev -perm -0002 -print -quit 2>/dev/null)" ]]; }

security_status() {
  SECURITY_SCORE=0 SECURITY_CRITICAL=0
  printf 'SECURITY STATUS\n===============\n'
  security_check Firewall 20 check_firewall
  security_check AppArmor 15 check_apparmor
  security_check 'SSH Root Login' 10 check_ssh_root
  security_check 'SSH Authentication' 5 check_ssh_keys
  security_check Fail2Ban 10 check_fail2ban
  security_check 'PHP hardening' 10 check_php_hardening
  security_check 'MariaDB localhost' 10 check_mariadb_local
  security_check SSL 10 check_ssl
  security_check Updates 5 check_updates
  security_check Permissions 5 check_permissions
  printf '\nSecurity Score: %d / 100\n' "$SECURITY_SCORE"
  if ((SECURITY_SCORE >= 90)); then printf 'Rating: Excellent\n'; elif ((SECURITY_SCORE >= 75)); then printf 'Rating: Good\n'; elif ((SECURITY_SCORE >= 60)); then printf 'Rating: Warning\n'; else printf 'Rating: Critical\n'; fi
  ((SECURITY_CRITICAL == 0))
}

security_scan() {
  security_status || true
  printf '\nOPEN PORTS\n'; security_ports
  printf '\nFILE PERMISSIONS\n'; security_permissions
  printf '\nSUSPICIOUS PHP\n'; security_php_scan
  printf '\nSUID FILES\n'; security_suid
  printf '\nPACKAGE UPDATES\n'; security_updates
  printf '\nENABLED SERVICES\n'; security_services
  printf '\nSSL EXPIRY\n'; ssl_status
  has_command lynis && { printf '\nLYNIS\n'; lynis audit system --quick; } || warn 'Lynis is not installed (optional).'
}

security_ports() {
  local allowed=" $SSH_PORT 80 443 " line port
  printf '%-8s %-8s %-24s %s\n' PORT PROTO ADDRESS PROCESS
  while IFS= read -r line; do
    port=$(awk '{address=$5; sub(/^.*:/,"",address); print address}' <<< "$line")
    printf '%s\n' "$line"
    [[ "$port" =~ ^[0-9]+$ && "$allowed" == *" $port "* ]] || warn "Unexpected listening endpoint: $line"
  done < <(ss -H -lntup 2>/dev/null)
}

security_permissions() {
  [[ -d "$WEB_ROOT" ]] || { warn "$WEB_ROOT does not exist."; return; }
  local found=0 path
  while IFS= read -r -d '' path; do printf 'WARNING world-writable: %s\n' "$path"; found=1; done < <(find "$WEB_ROOT" -xdev -perm -0002 -print0 2>/dev/null)
  local record domain expected
  shopt -s nullglob
  for record in "$STATE_DIR"/websites/*.conf; do
    domain=$(record_get "$record" DOMAIN); expected=$(record_get "$record" USER)
    while IFS= read -r -d '' path; do printf 'WARNING unexpected owner (expected %s or www-data): %s\n' "$expected" "$path"; found=1; done < <(find "$WEB_ROOT/$domain" -xdev ! -user "$expected" ! -user www-data -print0 2>/dev/null)
  done
  shopt -u nullglob
  ((found)) || ok 'No world-writable website files found.'
}

security_suid() {
  local path found=0
  while IFS= read -r -d '' path; do
    found=1
    if dpkg-query -S "$path" >/dev/null 2>&1; then printf 'PACKAGED %s\n' "$path"; else warn "Unowned SUID file: $path"; fi
  done < <(find /usr /bin /sbin -xdev -type f -perm -4000 -print0 2>/dev/null)
  ((found)) || ok 'No SUID files found.'
}

security_updates() {
  local updates
  updates=$(apt-get -s upgrade 2>/dev/null | awk '/^Inst / {print $2}' || true)
  if [[ -n "$updates" ]]; then printf '%s\n' "$updates"; warn 'Package updates are available.'; else ok 'No pending package upgrades found.'; fi
  [[ -f /var/run/reboot-required ]] && warn 'Reboot required.' || true
}

security_services() {
  local service
  while IFS= read -r service; do
    case "$service" in
      apparmor.service|cron.service|dbus.service|fail2ban.service|getty@.service|mariadb.service|networkd-dispatcher.service|nginx.service|php*-fpm.service|rsyslog.service|ssh.service|sshd.service|systemd-*.service|unattended-upgrades.service|ufw.service) printf 'EXPECTED %s\n' "$service" ;;
      *) warn "Review enabled service: $service" ;;
    esac
  done < <(systemctl list-unit-files --type=service --state=enabled --no-legend 2>/dev/null | awk '{print $1}')
}

security_php_scan() {
  [[ -d "$WEB_ROOT" ]] || { warn "$WEB_ROOT does not exist."; return; }
  local output
  output=$(grep -RInE --include='*.php' '(eval[[:space:]]*\(|base64_decode[[:space:]]*\(|shell_exec[[:space:]]*\(|system[[:space:]]*\(|passthru[[:space:]]*\(|assert[[:space:]]*\()' "$WEB_ROOT" 2>/dev/null || true)
  if [[ -n "$output" ]]; then printf '%s\n' "$output"; warn 'Matches are indicators only; nothing was deleted.'; return 1; else ok 'No suspicious PHP patterns found.'; fi
}

security_audit() { if has_command lynis; then require_root; lynis audit system --quick; else die 'Lynis is not installed. Install the optional audit package first.' "$EXIT_SYSTEM"; fi; }

security_ssh() {
  local action=${1:-status}; shift || true
  if [[ "$action" == harden ]]; then security_ssh_harden "$@"; return; fi
  [[ "$action" == status ]] || die "Usage: serverctl security ssh [status|harden [--disable-password]]" "$EXIT_INVALID_ARGUMENT"
  printf 'Effective SSH settings\n'
  sshd -T 2>/dev/null | grep -E '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|allowusers) ' || die 'Unable to read sshd configuration.' "$EXIT_SYSTEM"
  printf '\nUse `serverctl security ssh harden` after verifying a second key-based session.\n'
}

security_ssh_harden() {
  require_root
  local admin=${SUDO_USER:-} admin_home="" target disable_password=no
  [[ -n "$admin" && "$admin" != root ]] || die "Run serverctl through sudo from the non-root SSH admin account." "$EXIT_PERMISSION"
  [[ -n "${SSH_CONNECTION:-}" ]] || die "SSH hardening is allowed only from an active SSH session." "$EXIT_PERMISSION"
  admin_home=$(getent passwd "$admin" 2>/dev/null | cut -d: -f6 || true)
  [[ -n "$admin_home" && -s "$admin_home/.ssh/authorized_keys" ]] || die "No authorized_keys file was found for $admin." "$EXIT_VALIDATION"
  has_flag --disable-password "$@" && disable_password=yes
  warn "Keep this SSH session open and test a second key-based login immediately after applying."
  confirm "Harden SSH for admin $admin?" "$admin" || die "Cancelled." "$EXIT_GENERAL"
  target="$(root_path /etc/ssh/sshd_config.d/60-serverctl.conf)"; ROLLBACK_FILES=(); backup_config_file "$target"
  if [[ "$disable_password" == yes ]]; then
    atomic_write "$target" 0644 root root <<'EOF'
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
  else
    atomic_write "$target" 0644 root root <<'EOF'
PermitRootLogin no
PubkeyAuthentication yes
EOF
  fi
  if [[ "$SERVERCTL_TEST_MODE" != 1 ]] && ! sshd -t; then rollback_configs; die "sshd rejected the configuration; restored previous settings." "$EXIT_VALIDATION"; fi
  if ! run_cmd systemctl reload ssh; then rollback_configs; run_cmd systemctl reload ssh || true; die "SSH reload failed; restored previous settings." "$EXIT_SYSTEM"; fi
  commit_configs; ok "SSH hardened. Test a second key-based session before closing this one."
}
