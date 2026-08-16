#!/usr/bin/env bash
set -Eeuo pipefail
umask 027
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
CDPATH=; export CDPATH

readonly INSTALL_LOG=/var/log/serverctl/install.log
readonly SERVERCTL_VERSION=1.1.6 SERVERCTL_RELEASE_DATE=2026-08-16
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROFILE=minimal
DEFAULT_PHP=8.3
ENABLE_PHP_PPA=0
ASSUME_YES=0
CUSTOM_PHP_VERSIONS=""
WITH_AUDIT=0

usage() {
  cat <<'EOF'
Usage: sudo bash install.sh [options]
  --profile minimal|standard|custom  Installation profile (default: minimal)
  --php 8.2|8.3|8.4           Default PHP version (default: 8.3)
  --php-versions LIST          Custom comma-separated PHP versions
  --with-audit                 Add Lynis and rkhunter to a custom profile
  --enable-php-ppa             Permit the maintained Ondrej PHP PPA
  --yes                        Non-interactive confirmation

Ubuntu 22.04 needs --enable-php-ppa for supported PHP 8.2-8.4 packages.
Ubuntu 24.04 can install PHP 8.3 from the official repository; PHP 8.2/8.4
and the standard multi-PHP profile need --enable-php-ppa.
EOF
}

while (($#)); do
  case "$1" in
    --profile) [[ $# -ge 2 ]] || { usage; exit 2; }; PROFILE=$2; shift ;;
    --php) [[ $# -ge 2 ]] || { usage; exit 2; }; DEFAULT_PHP=$2; shift ;;
    --php-versions) [[ $# -ge 2 ]] || { usage; exit 2; }; CUSTOM_PHP_VERSIONS=$2; shift ;;
    --with-audit) WITH_AUDIT=1 ;;
    --enable-php-ppa) ENABLE_PHP_PPA=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage; exit 2 ;;
  esac
  shift
done

[[ "$PROFILE" == minimal || "$PROFILE" == standard || "$PROFILE" == custom ]] || { printf 'Invalid profile.\n' >&2; exit 2; }
[[ "$DEFAULT_PHP" =~ ^8\.[234]$ ]] || { printf 'PHP must be 8.2, 8.3, or 8.4.\n' >&2; exit 2; }
PHP_VERSIONS=("$DEFAULT_PHP")
if [[ "$PROFILE" == standard ]]; then
  PHP_VERSIONS=(8.2 8.3 8.4); WITH_AUDIT=1
elif [[ "$PROFILE" == custom && -n "$CUSTOM_PHP_VERSIONS" ]]; then
  IFS=, read -r -a PHP_VERSIONS <<< "$CUSTOM_PHP_VERSIONS"
  found_default=0
  for version in "${PHP_VERSIONS[@]}"; do [[ "$version" =~ ^8\.[234]$ ]] || { printf 'Invalid custom PHP version: %s\n' "$version" >&2; exit 2; }; [[ "$version" == "$DEFAULT_PHP" ]] && found_default=1; done
  ((found_default)) || { printf 'The default PHP version must be included in --php-versions.\n' >&2; exit 2; }
fi
[[ ${EUID:-$(id -u)} -eq 0 ]] || { printf 'Run this installer as root: sudo bash install.sh\n' >&2; exit 3; }

mkdir -p /var/log/serverctl
touch "$INSTALL_LOG"; chmod 0600 "$INSTALL_LOG"
exec > >(tee -a "$INSTALL_LOG") 2>&1

fail() { printf '[ ERROR ] %s\n' "$1" >&2; exit "${2:-1}"; }
ok() { printf '[ OK ] %s\n' "$1"; }
info() { printf '[ INFO ] %s\n' "$1"; }
confirm() { [[ "$ASSUME_YES" == 1 ]] && return; local answer; printf '%s [y/N]: ' "$1"; read -r answer; [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]; }
on_error() { local rc=$?; printf '[ ERROR ] Installation stopped at line %s (exit %s). See %s\n' "$1" "$rc" "$INSTALL_LOG" >&2; exit "$rc"; }
trap 'on_error $LINENO' ERR

preflight() {
  [[ -r /etc/os-release ]] || fail 'Cannot identify operating system.' 4
  # shellcheck source=/dev/null
  source /etc/os-release
  [[ "${ID:-}" == ubuntu ]] || fail 'Only Ubuntu Server is supported.' 4
  [[ "${VERSION_ID:-}" == 22.04 || "${VERSION_ID:-}" == 24.04 ]] || fail 'Only Ubuntu 22.04 and 24.04 LTS are supported.' 4
  local architecture memory_mb disk_mb cpu_count
  architecture=$(dpkg --print-architecture)
  [[ "$architecture" == amd64 || "$architecture" == arm64 ]] || fail "Unsupported architecture: $architecture" 4
  memory_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo); ((memory_mb >= 1024)) || fail 'At least 1 GB RAM is required.' 4
  disk_mb=$(df -Pm / | awk 'NR==2 {print $4}'); ((disk_mb >= 5120)) || fail 'At least 5 GB free disk space is required.' 4
  cpu_count=$(nproc); ((cpu_count >= 1)) || fail 'At least one CPU is required.' 4
  getent hosts archive.ubuntu.com >/dev/null 2>&1 || fail 'DNS connectivity check failed.' 4
  if command -v curl >/dev/null 2>&1; then curl -fsSI --max-time 10 https://archive.ubuntu.com/ubuntu/ >/dev/null || fail 'HTTPS/internet connectivity check failed.' 4
  elif command -v wget >/dev/null 2>&1; then wget -q --spider --timeout=10 https://archive.ubuntu.com/ubuntu/ || fail 'HTTPS/internet connectivity check failed.' 4
  else timeout 10 bash -c 'exec 3<>/dev/tcp/archive.ubuntu.com/443' || fail 'TCP/internet connectivity check failed.' 4; fi
  if [[ -d /etc/nginx/sites-enabled ]] && find /etc/nginx/sites-enabled -mindepth 1 -maxdepth 1 ! -name default ! -name serverctl-default.conf -print -quit | grep -q .; then
    fail 'Existing Nginx sites were detected. Install serverctl on a clean server or migrate them first.' 4
  fi
  if [[ "$VERSION_ID" == 22.04 && "$ENABLE_PHP_PPA" != 1 ]]; then
    if [[ "$ASSUME_YES" == 0 ]] && confirm 'Ubuntu 22.04 needs the external ppa:ondrej/php repository. Authorize it?'; then ENABLE_PHP_PPA=1
    else fail 'Ubuntu 22.04 requires --enable-php-ppa for PHP 8.2-8.4.' 4; fi
  fi
  local needs_ppa=0 version
  for version in "${PHP_VERSIONS[@]}"; do [[ "$version" != 8.3 ]] && needs_ppa=1; done
  if [[ "$VERSION_ID" == 24.04 && "$needs_ppa" == 1 && "$ENABLE_PHP_PPA" != 1 ]]; then
    if [[ "$ASSUME_YES" == 0 ]] && confirm 'This PHP selection needs the external ppa:ondrej/php repository. Authorize it?'; then ENABLE_PHP_PPA=1
    else fail 'This PHP selection needs --enable-php-ppa on Ubuntu 24.04.' 4; fi
  fi
  ok "Preflight: Ubuntu $VERSION_ID, $architecture, ${memory_mb} MB RAM, ${disk_mb} MB free, $cpu_count CPU(s)"
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl gnupg nginx mariadb-server certbot ufw fail2ban apparmor apparmor-utils unattended-upgrades logrotate openssl rsync acl psmisc
  if [[ "$ENABLE_PHP_PPA" == 1 ]]; then
    apt-get install -y --no-install-recommends software-properties-common
    add-apt-repository -y ppa:ondrej/php
    apt-get update
  fi
  local version packages=()
  for version in "${PHP_VERSIONS[@]}"; do
    packages+=("php$version-fpm" "php$version-cli" "php$version-mysql" "php$version-mbstring" "php$version-curl" "php$version-zip" "php$version-gd" "php$version-xml" "php$version-intl" "php$version-bcmath" "php$version-opcache")
  done
  apt-get install -y --no-install-recommends "${packages[@]}"
  [[ "$WITH_AUDIT" == 1 ]] && apt-get install -y --no-install-recommends lynis rkhunter
  ok 'Packages installed.'
}

install_serverctl() {
  install -d -m 0751 /opt/serverctl
  install -d -m 0750 /opt/serverctl/bin /opt/serverctl/lib /etc/serverctl /var/lib/serverctl/{websites,databases,locks,dashboard} /var/log/serverctl /var/backups/serverctl
  install -d -m 0755 -o root -g root /opt/serverctl/dashboard
  install -m 0755 "$SCRIPT_DIR/bin/serverctl" /opt/serverctl/bin/serverctl
  install -m 0644 "$SCRIPT_DIR"/lib/*.sh /opt/serverctl/lib/
  install -d -m 0750 -o root -g www-data /opt/serverctl/dashboard/app /opt/serverctl/dashboard/views
  install -d -m 0755 -o root -g root /opt/serverctl/dashboard/public /opt/serverctl/dashboard/public/assets /opt/serverctl/dashboard/public/assets/css /opt/serverctl/dashboard/public/assets/js /opt/serverctl/dashboard/public/api
  [[ -d "$SCRIPT_DIR/dashboard/app" ]] || fail 'Dashboard app directory is missing from installer source.'
  find "$SCRIPT_DIR/dashboard/app" -type f -exec install -m 0640 -o root -g www-data {} /opt/serverctl/dashboard/app/ \;
  if [[ -d "$SCRIPT_DIR/dashboard/views" ]]; then
    find "$SCRIPT_DIR/dashboard/views" -type f -exec install -m 0640 -o root -g www-data {} /opt/serverctl/dashboard/views/ \;
  fi
  find "$SCRIPT_DIR/dashboard/public" -maxdepth 1 -type f -exec install -m 0644 -o root -g root {} /opt/serverctl/dashboard/public/ \;
  find "$SCRIPT_DIR/dashboard/public/api" -type f -exec install -m 0644 -o root -g root {} /opt/serverctl/dashboard/public/api/ \;
  find "$SCRIPT_DIR/dashboard/public/assets/css" -type f -exec install -m 0644 -o root -g root {} /opt/serverctl/dashboard/public/assets/css/ \;
  find "$SCRIPT_DIR/dashboard/public/assets/js" -type f -exec install -m 0644 -o root -g root {} /opt/serverctl/dashboard/public/assets/js/ \;
  ln -sfn /opt/serverctl/bin/serverctl /usr/local/bin/serverctl
  install -m 0640 "$SCRIPT_DIR/config/serverctl.conf" /etc/serverctl/serverctl.conf
  sed -i "s/^DEFAULT_PHP_VERSION=.*/DEFAULT_PHP_VERSION=$DEFAULT_PHP/" /etc/serverctl/serverctl.conf
  timedatectl set-timezone Asia/Bangkok
  install -d -m 0755 /etc/fail2ban/jail.d /etc/fail2ban/filter.d /etc/logrotate.d /etc/systemd/system /etc/letsencrypt/renewal-hooks/deploy /etc/nginx/conf.d /etc/nginx/sites-available /etc/nginx/sites-enabled
  install -m 0644 "$SCRIPT_DIR/etc/fail2ban/jail.d/serverctl.local" /etc/fail2ban/jail.d/serverctl.local
  install -m 0644 "$SCRIPT_DIR/etc/fail2ban/filter.d/serverctl-dashboard-login.conf" /etc/fail2ban/filter.d/serverctl-dashboard-login.conf
  install -m 0644 "$SCRIPT_DIR/etc/logrotate.d/serverctl" /etc/logrotate.d/serverctl
  install -m 0644 "$SCRIPT_DIR/etc/logrotate.d/serverctl-web" /etc/logrotate.d/serverctl-web
  install -m 0644 "$SCRIPT_DIR/etc/logrotate.d/serverctl-dashboard" /etc/logrotate.d/serverctl-dashboard
  install -m 0644 "$SCRIPT_DIR/etc/nginx/conf.d/serverctl-security.conf" /etc/nginx/conf.d/serverctl-security.conf
  install -m 0644 "$SCRIPT_DIR/etc/nginx/sites-available/serverctl-default.conf" /etc/nginx/sites-available/serverctl-default.conf
  rm -f /etc/nginx/sites-enabled/default
  ln -sfn /etc/nginx/sites-available/serverctl-default.conf /etc/nginx/sites-enabled/serverctl-default.conf
  install -m 0644 "$SCRIPT_DIR"/etc/systemd/system/*.service "$SCRIPT_DIR"/etc/systemd/system/*.timer /etc/systemd/system/
  install -m 0755 "$SCRIPT_DIR/etc/letsencrypt/renewal-hooks/deploy/serverctl-reload-nginx" /etc/letsencrypt/renewal-hooks/deploy/serverctl-reload-nginx
  touch /var/log/serverctl/serverctl.log /var/log/serverctl/audit.log
  chown -R root:root /opt/serverctl /etc/serverctl /var/lib/serverctl /var/backups/serverctl
  chown root:www-data /opt/serverctl/dashboard/app /opt/serverctl/dashboard/views
  find /opt/serverctl/dashboard/app /opt/serverctl/dashboard/views -type f -exec chown root:www-data {} \;
  chmod 0750 /opt/serverctl/dashboard/app /opt/serverctl/dashboard/views
  touch /var/lib/serverctl/dashboard/audit.log
  chown www-data:www-data /var/lib/serverctl/dashboard
  chown www-data:www-data /var/lib/serverctl/dashboard/audit.log
  chmod 0750 /var/lib/serverctl/dashboard
  chmod 0640 /var/lib/serverctl/dashboard/audit.log
  chmod 0751 /opt/serverctl
  chmod 0751 /etc/serverctl
  chmod 0751 /var/lib/serverctl
  chmod 0750 /var/backups/serverctl /var/log/serverctl
  chmod 0640 /var/log/serverctl/*.log
  ok 'serverctl files installed.'
}

configure_php_security() {
  local version
  for version in "${PHP_VERSIONS[@]}"; do
    install -d -m 0755 "/etc/php/$version/fpm/conf.d"
    cat > "/etc/php/$version/fpm/conf.d/99-serverctl-security.ini" <<'EOF'
display_errors = Off
log_errors = On
expose_php = Off
allow_url_include = Off
session.cookie_httponly = On
session.cookie_secure = On
session.use_strict_mode = On
cgi.fix_pathinfo = 0
EOF
    chmod 0644 "/etc/php/$version/fpm/conf.d/99-serverctl-security.ini"
  done
  ok 'PHP production security defaults configured.'
}

secure_mariadb() {
  install -d -m 0755 /etc/mysql/mariadb.conf.d
  install -m 0644 /dev/null /etc/mysql/mariadb.conf.d/99-serverctl-security.cnf
  printf '[mysqld]\nbind-address = 127.0.0.1\nskip-name-resolve\nlocal-infile = 0\n' > /etc/mysql/mariadb.conf.d/99-serverctl-security.cnf
  mariadb --protocol=socket <<'SQL'
DELETE FROM mysql.global_priv WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db LIKE 'test\\_%';
DELETE FROM mysql.global_priv WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
FLUSH PRIVILEGES;
SQL
  systemctl restart mariadb
  ok 'MariaDB restricted to localhost and anonymous/test accounts removed.'
}

configure_firewall() {
  local ssh_port
  ssh_port=$(sshd -T 2>/dev/null | awk '/^port / && !port {port=$2} END {if (port) print port}'); ssh_port=${ssh_port:-22}
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow "$ssh_port/tcp" comment SSH
  ufw allow 80/tcp comment HTTP
  ufw allow 443/tcp comment HTTPS
  ufw --force enable
  sed -i "s/^SSH_PORT=.*/SSH_PORT=$ssh_port/" /etc/serverctl/serverctl.conf
  ok "UFW enabled (SSH $ssh_port, HTTP 80, HTTPS 443)."
}

configure_ssh_safely() {
  local admin=${SUDO_USER:-} admin_home=""
  if [[ -n "$admin" ]]; then admin_home=$(getent passwd "$admin" 2>/dev/null | cut -d: -f6 || true); fi
  if [[ -n "$admin" && "$admin" != root && -n "$admin_home" && -s "$admin_home/.ssh/authorized_keys" ]]; then
    install -d -m 0755 /etc/ssh/sshd_config.d
    printf 'PermitRootLogin no\nPubkeyAuthentication yes\n' > /etc/ssh/sshd_config.d/60-serverctl.conf
    sshd -t && systemctl reload ssh
    ok 'Root SSH login disabled; password login unchanged to prevent lockout.'
  else
    info 'SSH root setting was not changed because a sudo user with authorized_keys was not verified.'
  fi
}

configure_admin_group() {
  local admin=${SUDO_USER:-}
  groupadd -f serverctl-admin
  if [[ -n "$admin" && "$admin" != root ]]; then usermod -aG serverctl-admin "$admin"; fi
  install -m 0440 "$SCRIPT_DIR/etc/sudoers.d/serverctl" /etc/sudoers.d/serverctl
  visudo -cf /etc/sudoers.d/serverctl >/dev/null
}

enable_services() {
  local version
  systemctl enable --now nginx mariadb fail2ban apparmor
  for version in "${PHP_VERSIONS[@]}"; do systemctl enable --now "php$version-fpm"; done
  dpkg-reconfigure -f noninteractive unattended-upgrades
  systemctl daemon-reload
  systemctl enable --now certbot.timer serverctl-backup.timer serverctl-security-scan.timer
  nginx -t
  for version in "${PHP_VERSIONS[@]}"; do "php-fpm$version" -t; done
  systemctl is-active --quiet nginx mariadb fail2ban apparmor
  aa-status --enabled
  ok 'Services enabled and configuration validation passed.'
}

summary() {
  cat <<EOF

========================================
SERVERCTL INSTALLATION COMPLETE
========================================
Profile      : $PROFILE
Version      : v$SERVERCTL_VERSION
Default PHP  : $DEFAULT_PHP
PHP versions : ${PHP_VERSIONS[*]}
Management   : SSH + sudo serverctl
  Web panel    : Dashboard source installed (not enabled)
Firewall     : $(ufw status | sed -n 's/Status: //p')
Install log  : $INSTALL_LOG

Next steps:
  1. Open a second SSH key session before disabling password authentication.
  2. Run: sudo serverctl health
  3. Run: sudo serverctl security status
  4. Configure an off-server backup copy (NAS/SFTP/rsync).
  5. Enable Dashboard after issuing an HTTPS certificate:
     sudo serverctl dashboard install example.com
========================================
EOF
}

preflight
cat <<EOF
serverctl will install the $PROFILE profile with PHP $DEFAULT_PHP.
It will configure Nginx, MariaDB, UFW, Fail2Ban, AppArmor and automatic updates.
EOF
confirm 'Continue installation?' || exit 1
install_packages
install_serverctl
configure_php_security
secure_mariadb
configure_firewall
configure_ssh_safely
configure_admin_group
enable_services
/usr/local/bin/serverctl health
/usr/local/bin/serverctl security status || true
summary
