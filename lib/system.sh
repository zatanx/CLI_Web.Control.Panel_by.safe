#!/usr/bin/env bash

cmd_status() {
  local argument
  for argument in "$@"; do [[ "$argument" == --watch ]] || die "Unknown status argument: $argument" "$EXIT_INVALID_ARGUMENT"; done
  if has_flag --watch "$@"; then
    while true; do clear; status_once; sleep 5; done
  else status_once; fi
}

status_once() {
  local uptime_text load memory_total memory_used disk_total disk_used cpu network_rx network_tx
  uptime_text=$(uptime -p 2>/dev/null || true); load=$(awk '{print $1, $2, $3}' /proc/loadavg 2>/dev/null || printf unknown)
  memory_total=$(awk '/MemTotal/ {print $2*1024}' /proc/meminfo 2>/dev/null || printf 0); memory_used=$(free -b 2>/dev/null | awk '/Mem:/ {print $3}' || printf 0)
  read -r disk_total disk_used < <(df -B1 --output=size,used / 2>/dev/null | tail -1 || printf '0 0')
  cpu=$(cpu_usage); read -r network_rx network_tx < <(network_bytes)
  printf 'Server     %s\nOS         %s\nUptime     %s\nCPU        %s%%\nLoad       %s\nRAM        %s / %s\nDisk       %s / %s\nNetwork    RX %s / TX %s\n' \
    "$(hostname -f 2>/dev/null || hostname)" "$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-unknown}")" "$uptime_text" "$cpu" "$load" \
    "$(human_bytes "$memory_used")" "$(human_bytes "$memory_total")" "$(human_bytes "$disk_used")" "$(human_bytes "$disk_total")" "$(human_bytes "$network_rx")" "$(human_bytes "$network_tx")"
  printf '\n%-18s %s\n' SERVICE STATUS
  print_service nginx nginx
  local version; for version in $ALLOWED_PHP_VERSIONS; do [[ -e "/etc/php/$version/fpm" ]] && print_service "PHP $version FPM" "php$version-fpm"; done
  print_service MariaDB mariadb; print_service Fail2Ban fail2ban
  if ufw status 2>/dev/null | grep -q 'Status: active'; then printf '%-18s %s\n' UFW RUNNING; else printf '%-18s %s\n' UFW STOPPED; fi
  if aa-status --enabled >/dev/null 2>&1; then printf '%-18s %s\n' AppArmor ENABLED; else printf '%-18s %s\n' AppArmor DISABLED; fi
}

cpu_usage() {
  local cpu user nice system idle iowait irq softirq steal guest guest_nice total1 idle1 total2 idle2 delta_total delta_idle
  read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
  total1=$((user + nice + system + idle + iowait + irq + softirq + steal)); idle1=$((idle + iowait))
  sleep 0.1
  read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
  total2=$((user + nice + system + idle + iowait + irq + softirq + steal)); idle2=$((idle + iowait))
  delta_total=$((total2 - total1)); delta_idle=$((idle2 - idle1))
  if ((delta_total > 0)); then printf '%d' "$((100 * (delta_total - delta_idle) / delta_total))"; else printf 0; fi
}

network_bytes() {
  local interface rx=0 tx=0 value
  for interface in /sys/class/net/*; do
    [[ "$(basename "$interface")" == lo ]] && continue
    read -r value < "$interface/statistics/rx_bytes"; rx=$((rx + value))
    read -r value < "$interface/statistics/tx_bytes"; tx=$((tx + value))
  done
  printf '%s %s\n' "$rx" "$tx"
}

print_service() { if service_is_active "$2"; then printf '%-18s %s\n' "$1" RUNNING; else printf '%-18s %s\n' "$1" STOPPED; fi; }

cmd_health() {
  local failures=0 warnings=0 usage memory_total memory_available memory_usage version
  printf 'Server health\n'
  health_service nginx nginx "$failures"; failures=$HEALTH_FAILURES
  health_service MariaDB mariadb "$failures"; failures=$HEALTH_FAILURES
  health_service Fail2Ban fail2ban "$failures"; failures=$HEALTH_FAILURES
  for version in $ALLOWED_PHP_VERSIONS; do
    if [[ -d "/etc/php/$version/fpm" ]]; then health_service "PHP $version FPM" "php$version-fpm" "$failures"; failures=$HEALTH_FAILURES; fi
  done
  if ufw status 2>/dev/null | grep -q 'Status: active'; then ok 'Firewall active'; else error 'Firewall inactive'; ((++failures)); fi
  if aa-status --enabled >/dev/null 2>&1; then ok 'AppArmor enabled'; else error 'AppArmor disabled'; ((++failures)); fi
  usage=$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
  if ((usage >= 90)); then error "Disk usage critical: $usage%"; ((++failures)); elif ((usage >= 80)); then warn "Disk usage high: $usage%"; ((++warnings)); else ok "Disk usage: $usage%"; fi
  memory_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo); memory_available=$(awk '/MemAvailable/ {print $2}' /proc/meminfo); memory_usage=$((100 * (memory_total - memory_available) / memory_total))
  if ((memory_usage >= 95)); then error "RAM usage critical: $memory_usage%"; ((++failures)); elif ((memory_usage >= 85)); then warn "RAM usage high: $memory_usage%"; ((++warnings)); else ok "RAM usage: $memory_usage%"; fi
  if ((failures)); then printf 'CRITICAL (%d failures, %d warnings)\n' "$failures" "$warnings"; return 1
  elif ((warnings)); then printf 'WARNING (%d warnings)\n' "$warnings"; return 0
  else printf 'OK\n'; fi
}

health_service() {
  local label=$1 service=$2 failures=${3:-0}
  if service_is_active "$service"; then ok "$label running"; else error "$label stopped"; ((++failures)); fi
  HEALTH_FAILURES=$failures
}

cmd_logs() {
  local type=${1:-}; [[ -n "$type" ]] || die "Log type is required." "$EXIT_INVALID_ARGUMENT"; shift || true
  local lines=100 file follow=0 search=""
  lines=$(extract_flag_value --lines "$@" 2>/dev/null || printf 100)
  [[ "$lines" =~ ^(50|100|500)$ ]] || die "--lines must be 50, 100, or 500." "$EXIT_VALIDATION"
  has_flag --follow "$@" && follow=1
  search=$(extract_flag_value --search "$@" 2>/dev/null || true)
  [[ "$search" != *$'\n'* && "$search" != *$'\r'* && ${#search} -le 200 ]] || die "Invalid log search text." "$EXIT_VALIDATION"
  case "$type" in
    nginx) file=/var/log/nginx/error.log ;;
    php) file=$(find /var/log/php* -maxdepth 1 -type f -name '*fpm*.log' 2>/dev/null | head -1) ;;
    mariadb) file=/var/log/mysql/error.log ;;
    fail2ban) file=/var/log/fail2ban.log ;;
    firewall) file=/var/log/ufw.log ;;
    system) file=/var/log/syslog ;;
    serverctl) file=$SERVERCTL_LOG_FILE ;;
    *) die "Unknown log type." "$EXIT_INVALID_ARGUMENT" ;;
  esac
  [[ -n "$file" && -f "$file" ]] || die "Log file is unavailable." "$EXIT_SYSTEM"
  if [[ -n "$search" ]]; then grep -F -- "$search" "$file" | tail -n "$lines" || true
  elif ((follow)); then tail -n "$lines" -f -- "$file"; else tail -n "$lines" -- "$file"; fi
}

cmd_firewall() {
  local sub=${1:-}; shift || true
  case "$sub" in
    status|list) ufw status numbered ;;
    reload) require_root; backup_ufw; run_cmd ufw reload; ok 'Firewall reloaded.' ;;
    add) firewall_add "$@" ;;
    remove) firewall_remove "$@" ;;
    *) die "Usage: serverctl firewall <status|list|add|remove|reload>" "$EXIT_INVALID_ARGUMENT" ;;
  esac
}

backup_ufw() { local target="$BACKUP_DIR/config-ufw-$(backup_timestamp).tar.gz"; [[ -d /etc/ufw ]] && tar -C /etc -czf "$target" ufw; }

firewall_add() {
  require_root
  local port=${1:-} protocol=${2:-tcp} source=${3:-any}
  (($# >= 1 && $# <= 3)) || die "Usage: serverctl firewall add PORT [tcp|udp] [SOURCE]" "$EXIT_INVALID_ARGUMENT"
  validate_port "$port" || die "Invalid port." "$EXIT_VALIDATION"; validate_protocol "$protocol" || die "Protocol must be tcp or udp." "$EXIT_VALIDATION"
  if [[ "$source" == any || "$source" == 0.0.0.0/0 || "$source" == ::/0 ]]; then
    warn "This rule is open to the internet."; confirm "Allow $port/$protocol from everywhere?" || die "Cancelled." "$EXIT_GENERAL"
    source=any
  else validate_cidr "$source" || die "Invalid source IP/CIDR." "$EXIT_VALIDATION"; confirm "Allow $port/$protocol from $source?" || die "Cancelled." "$EXIT_GENERAL"; fi
  backup_ufw
  if [[ "$source" == any ]]; then run_cmd ufw allow "$port/$protocol"; else run_cmd ufw allow from "$source" to any port "$port" proto "$protocol"; fi
  ok 'Firewall rule added.'
}

firewall_remove() {
  require_root
  local number=${1:-}; [[ "$number" =~ ^[0-9]+$ ]] || die "Provide a numbered UFW rule." "$EXIT_VALIDATION"
  (($# == 1)) || die "firewall remove accepts one rule number." "$EXIT_INVALID_ARGUMENT"
  ufw status numbered; confirm "Delete UFW rule $number?" || die "Cancelled." "$EXIT_GENERAL"
  backup_ufw; run_cmd ufw --force delete "$number"; ok 'Firewall rule removed.'
}

cmd_fail2ban() {
  local sub=${1:-}; shift || true
  case "$sub" in
    status) fail2ban-client status ;;
    list) fail2ban_list ;;
    ban|unban) fail2ban_ip "$sub" "$@" ;;
    *) die "Usage: serverctl fail2ban <status|list|ban|unban>" "$EXIT_INVALID_ARGUMENT" ;;
  esac
}

fail2ban_list() {
  local jail
  for jail in $(fail2ban-client status 2>/dev/null | sed -n 's/.*Jail list:[[:space:]]*//p' | tr ',' ' '); do fail2ban-client status "$jail"; done
}

fail2ban_ip() {
  require_root
  local action=$1 ip=${2:-}; validate_ip "$ip" || die "Invalid IP address." "$EXIT_VALIDATION"
  (($# == 2)) || die "Fail2Ban ban/unban accepts one IP address." "$EXIT_INVALID_ARGUMENT"
  confirm "$action $ip in the sshd jail?" || die "Cancelled." "$EXIT_GENERAL"
  if [[ "$action" == ban ]]; then run_cmd fail2ban-client set sshd banip "$ip"; else run_cmd fail2ban-client set sshd unbanip "$ip"; fi
  ok "Fail2Ban $action completed for $ip."
}

cmd_update() {
  local sub=${1:-}; shift || true
  case "$sub" in
    serverctl) (($# == 0)) || die 'update serverctl accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; with_lock serverctl-code-update serverctl_update_source ;;
    check) (($# == 0)) || die 'update check accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; update_check ;;
    security) (($# == 0)) || die 'update security accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; update_install security ;;
    all) (($# == 0)) || die 'update all accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; update_install all ;;
    history) (($# == 0)) || die 'update history accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; update_history ;;
    health) (($# == 0)) || die 'update health accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; apt_lock_check; update_precheck ;;
    reboot-status) (($# == 0)) || die 'update reboot-status accepts no arguments.' "$EXIT_INVALID_ARGUMENT"; update_reboot_status ;;
    *) die "Usage: serverctl update <serverctl|check|security|all|history|health|reboot-status>" "$EXIT_INVALID_ARGUMENT" ;;
  esac
}

SERVERCTL_REPOSITORY_NAME="CLI_Web.Control.Panel_by.safe"

serverctl_source_dir() {
  local candidate current git_root
  if [[ -n "$SERVERCTL_SOURCE_DIR" ]]; then
    git_root=$(git -C "$SERVERCTL_SOURCE_DIR" rev-parse --show-toplevel 2>/dev/null || true)
    [[ -n "$git_root" ]] || die "Configured serverctl source directory is not a Git repository: $SERVERCTL_SOURCE_DIR" "$EXIT_VALIDATION"
    printf '%s' "$SERVERCTL_SOURCE_DIR"
    return 0
  fi

  current=$(pwd -P 2>/dev/null || true)
  git_root=$(git -C "$current" rev-parse --show-toplevel 2>/dev/null || true)
  if [[ "$(basename -- "$git_root")" == "$SERVERCTL_REPOSITORY_NAME" ]]; then
    printf '%s' "$git_root"
    return 0
  fi

  candidate=$(find /home /root -maxdepth 3 -type d -name "$SERVERCTL_REPOSITORY_NAME" -print -quit 2>/dev/null || true)
  if [[ -n "$candidate" ]] && git -C "$candidate" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s' "$(git -C "$candidate" rev-parse --show-toplevel)"
    return 0
  fi

  die "Could not find $SERVERCTL_REPOSITORY_NAME. Set SERVERCTL_SOURCE_DIR in /etc/serverctl/serverctl.conf." "$EXIT_VALIDATION"
}

serverctl_update_source() {
  require_root
  has_command git || die 'Git is required to update serverctl from GitHub.' "$EXIT_SYSTEM"

  local source_dir remote branch old_revision new_revision file dashboard_dir sudoers_file
  source_dir=$(serverctl_source_dir)
  [[ -f "$source_dir/bin/serverctl" && -d "$source_dir/lib" ]] || die "Invalid serverctl source directory: $source_dir" "$EXIT_VALIDATION"

  branch=$(git -C "$source_dir" symbolic-ref --short HEAD 2>/dev/null || true)
  [[ "$branch" == main ]] || die "serverctl source must be on the main branch (current: ${branch:-detached})." "$EXIT_VALIDATION"
  remote=$(git -C "$source_dir" remote get-url origin 2>/dev/null || true)
  [[ -n "$remote" ]] || die "serverctl source has no Git origin remote." "$EXIT_VALIDATION"
  [[ -z "$(git -C "$source_dir" status --porcelain)" ]] || die "Local changes exist in $source_dir. Commit or back them up before updating." "$EXIT_SYSTEM"

  old_revision=$(git -C "$source_dir" rev-parse HEAD)
  info "Updating serverctl from $remote"
  run_cmd git -C "$source_dir" pull --ff-only origin main
  new_revision=$(git -C "$source_dir" rev-parse HEAD)

  run_cmd bash -n "$source_dir/bin/serverctl"
  for file in "$source_dir"/lib/*.sh; do
    [[ -f "$file" ]] || continue
    run_cmd bash -n "$file"
  done

  run_cmd install -d -m 0755 "$(root_path /opt/serverctl/bin)" "$(root_path /opt/serverctl/lib)"
  run_cmd install -m 0755 "$source_dir/bin/serverctl" "$(root_path /opt/serverctl/bin/serverctl)"
  run_cmd install -m 0644 "$source_dir"/lib/*.sh "$(root_path /opt/serverctl/lib)/"
  if [[ -f "$source_dir/etc/sudoers.d/serverctl" ]]; then
    sudoers_file="$(root_path /etc/sudoers.d/serverctl)"
    run_cmd visudo -cf "$source_dir/etc/sudoers.d/serverctl"
    run_cmd install -d -m 0755 "$(dirname "$sudoers_file")"
    run_cmd install -m 0440 "$source_dir/etc/sudoers.d/serverctl" "$sudoers_file"
  fi
  if [[ -d "$source_dir/dashboard" ]]; then
    dashboard_dir="$(root_path /opt/serverctl/dashboard)"
    run_cmd install -d -m 0755 -o root -g root "$dashboard_dir"
    run_cmd cp -a -- "$source_dir/dashboard/." "$dashboard_dir/"
    run_cmd chown -R root:root "$dashboard_dir"
    run_cmd find "$dashboard_dir" -type d -path "$dashboard_dir/public*" -exec chmod 0755 {} +
    run_cmd find "$dashboard_dir" -type f -path "$dashboard_dir/public/*" -exec chmod 0644 {} +
    for file in "$dashboard_dir/app" "$dashboard_dir/views"; do
      [[ -d "$file" ]] || continue
      run_cmd chown root:www-data "$file"
      run_cmd chmod 0750 "$file"
      run_cmd find "$file" -type f -exec chown root:www-data {} +
      run_cmd find "$file" -type f -exec chmod 0640 {} +
    done
  fi

  if [[ "$old_revision" == "$new_revision" ]]; then
    ok "serverctl is already up to date (${new_revision:0:12})."
  else
    ok "serverctl updated to ${new_revision:0:12}."
  fi
}

UPDATE_HISTORY_FILE="${UPDATE_HISTORY_FILE:-$LOG_DIR/update-history.log}"
UPDATE_TOTAL=0 UPDATE_SECURITY=0 UPDATE_NEW=0 UPDATE_REMOVED=0 UPDATE_IMPORTANT="" APT_SIM_OUTPUT=""

apt_lock_check() {
  local lock
  if pgrep -af '(^|/)(unattended-upgrade|unattended-upgr)([[:space:]]|$)' >/dev/null 2>&1; then die 'Automatic update is currently running. Please wait.' "$EXIT_SYSTEM"; fi
  if has_command fuser; then
    for lock in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock /var/lib/apt/lists/lock; do
      if fuser "$lock" >/dev/null 2>&1; then die "Another package manager holds $lock. Update was not started." "$EXIT_SYSTEM"; fi
    done
  elif pgrep -x apt >/dev/null 2>&1 || pgrep -x apt-get >/dev/null 2>&1 || pgrep -x dpkg >/dev/null 2>&1; then
    die 'Another package manager process is running.' "$EXIT_SYSTEM"
  fi
}

update_collect() {
  APT_SIM_OUTPUT=$(apt-get -s upgrade 2>&1) || { printf '%s\n' "$APT_SIM_OUTPUT"; die 'APT simulation failed.' "$EXIT_SYSTEM"; }
  UPDATE_TOTAL=$(grep -c '^Inst ' <<< "$APT_SIM_OUTPUT" || true)
  UPDATE_SECURITY=$(grep '^Inst ' <<< "$APT_SIM_OUTPUT" | grep -Eci 'security|UbuntuESMApps|UbuntuESMInfra' || true)
  UPDATE_NEW=$(sed -nE 's/.* ([0-9]+) newly installed.*/\1/p' <<< "$APT_SIM_OUTPUT" | tail -1); UPDATE_NEW=${UPDATE_NEW:-0}
  UPDATE_REMOVED=$(sed -nE 's/.* ([0-9]+) to remove.*/\1/p' <<< "$APT_SIM_OUTPUT" | tail -1); UPDATE_REMOVED=${UPDATE_REMOVED:-0}
  UPDATE_IMPORTANT=$(grep '^Inst ' <<< "$APT_SIM_OUTPUT" | awk '{print $2}' | grep -Ei '^(nginx|openssl|libssl|php|php[0-9]|mariadb|systemd|linux-image|linux-headers)' || true)
}

update_print_packages() {
  local mode=${1:-all}
  printf '\n%-34s %-28s %s\n' Package Current New
  printf '%s\n' '------------------------------------------------------------------------------------------'
  awk -v mode="$mode" '
    /^Inst / {
      security=(tolower($0) ~ /security|ubuntuesmapps|ubuntuesminfra/)
      if (mode=="security" && !security) next
      pkg=$2; old="-"; new="-"
      if (match($0,/\[[^]]+\]/)) old=substr($0,RSTART+1,RLENGTH-2)
      rest=substr($0,index($0,")")+1)
      if (match($0,/\([^ )]+/)) new=substr($0,RSTART+1,RLENGTH-1)
      printf "%-34s %-28s %s%s\n",pkg,old,new,(security?" [security]":"")
    }' <<< "$APT_SIM_OUTPUT"
}

update_summary() {
  local mode=${1:-all} displayed=$UPDATE_TOTAL; [[ "$mode" == security ]] && displayed=$UPDATE_SECURITY
  printf '\n========================================\n         UPDATE SUMMARY\n========================================\nPackages to Update : %s\nSecurity Updates   : %s\nNew Packages       : %s\nRemoved Packages   : %s\n' "$displayed" "$UPDATE_SECURITY" "$UPDATE_NEW" "$UPDATE_REMOVED"
  if [[ -n "$UPDATE_IMPORTANT" ]]; then printf '\nImportant Packages:\n%s\n' "$UPDATE_IMPORTANT"; warn 'Core web-server packages are included in this update.'; fi
  printf '========================================\n'
}

update_check() {
  require_root; apt_lock_check
  info 'Refreshing Ubuntu package indexes only; no packages will be installed.'
  run_cmd apt-get update
  update_collect
  printf '\n========================================\n         AVAILABLE UPDATES\n========================================\n'
  update_print_packages all
  printf '\nSecurity Updates : %s\nOther Updates    : %s\n========================================\n' "$UPDATE_SECURITY" "$((UPDATE_TOTAL - UPDATE_SECURITY))"
  update_reboot_status
}

update_check_line() { local label=$1 status=$2; printf '%-20s : %s\n' "$label" "$status"; }

update_precheck() {
  local failures=0 warnings=0 version mount available_kb memory_available load_limit load_int php_version record domain ssl
  printf '\n========================================\n          PRE-UPDATE CHECK\n========================================\n'
  version=$(source /etc/os-release 2>/dev/null; printf '%s' "${VERSION_ID:-unknown}")
  if [[ "$version" == 22.04 || "$version" == 24.04 ]]; then update_check_line Ubuntu PASS; else update_check_line Ubuntu CRITICAL; ((++failures)); fi
  if apt-get check >/dev/null 2>&1; then update_check_line APT PASS; else update_check_line APT CRITICAL; ((++failures)); fi
  for mount in / /var /var/log /var/lib; do
    available_kb=$(df -Pk "$mount" | awk 'NR==2 {print $4}')
    if ((available_kb < 262144)); then update_check_line "Disk $mount" CRITICAL; ((++failures)); elif ((available_kb < 524288)); then update_check_line "Disk $mount" WARNING; ((++warnings)); else update_check_line "Disk $mount" PASS; fi
  done
  memory_available=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
  if ((memory_available < 131072)); then update_check_line Memory CRITICAL; ((++failures)); elif ((memory_available < 262144)); then update_check_line Memory WARNING; ((++warnings)); else update_check_line Memory PASS; fi
  load_limit=$(( $(nproc) * 2 )); load_int=$(awk '{printf "%d",$1}' /proc/loadavg)
  if ((load_int > load_limit)); then update_check_line 'CPU Load' WARNING; ((++warnings)); else update_check_line 'CPU Load' PASS; fi
  if service_is_active nginx; then update_check_line Nginx PASS; else update_check_line Nginx CRITICAL; ((++failures)); fi
  if nginx -t >/dev/null 2>&1; then update_check_line 'Nginx Config' PASS; else update_check_line 'Nginx Config' CRITICAL; ((++failures)); fi
  local php_fail=0 php_found=0
  for php_version in $ALLOWED_PHP_VERSIONS; do if [[ -d "/etc/php/$php_version/fpm" ]]; then php_found=1; service_is_active "php$php_version-fpm" || php_fail=1; fi; done
  if ((php_found && php_fail == 0)); then update_check_line PHP-FPM PASS; else update_check_line PHP-FPM CRITICAL; ((++failures)); fi
  if service_is_active mariadb && mariadb --protocol=socket -Nse 'SELECT 1' >/dev/null 2>&1; then update_check_line MariaDB PASS; else update_check_line MariaDB CRITICAL; ((++failures)); fi
  local ssl_fail=0 website_fail=0 url
  shopt -s nullglob
  for record in "$STATE_DIR"/websites/*.conf; do
    domain=$(record_get "$record" DOMAIN); ssl=$(record_get "$record" SSL); url="http://$domain"
    if [[ "$ssl" == yes ]]; then
      url="https://$domain"; openssl x509 -checkend $((3*86400)) -noout -in "$(root_path /etc/letsencrypt/live)/$domain/cert.pem" >/dev/null 2>&1 || ssl_fail=1
    fi
    curl -fsSIL --max-time 5 "$url" >/dev/null 2>&1 || website_fail=1
  done
  shopt -u nullglob
  if ((ssl_fail)); then update_check_line SSL CRITICAL; ((++failures)); else update_check_line SSL PASS; fi
  if ((website_fail)); then update_check_line Websites WARNING; ((++warnings)); else update_check_line Websites PASS; fi
  printf '========================================\n'
  UPDATE_PRECHECK_FAILURES=$failures; UPDATE_PRECHECK_WARNINGS=$warnings
  if ((failures)); then error 'System is not ready for update.'; return "$EXIT_VALIDATION"; fi
  ((warnings)) && warn "Pre-update check completed with $warnings warning(s)." || ok 'Pre-update check passed.'
}

update_install() {
  require_root
  local mode=$1 result=SUCCESS update_log start_time package_count
  apt_lock_check; run_cmd apt-get update; update_collect
  if [[ "$mode" == security && "$UPDATE_SECURITY" == 0 ]]; then ok 'No security updates are available.'; return; fi
  if ((UPDATE_TOTAL == 0)); then ok 'No package updates are available.'; return; fi
  update_precheck || die 'Critical pre-update check failed; no packages were installed.' "$EXIT_VALIDATION"
  backup_create_update_config
  update_print_packages "$mode"; update_summary "$mode"
  ((UPDATE_REMOVED == 0)) || die 'APT proposes removing packages; automatic update was blocked for administrator review.' "$EXIT_VALIDATION"
  if [[ "$mode" == security ]]; then confirm 'Install the listed security updates?' || die 'Cancelled.' "$EXIT_GENERAL"; else confirm 'Install all current-release updates (no distribution upgrade)?' || die 'Cancelled.' "$EXIT_GENERAL"; fi
  mkdir -p "$LOG_DIR"; update_log="$LOG_DIR/update-$(date '+%Y%m%d-%H%M%S').log"; start_time=$(date +%s)
  info 'APT is updating packages. Do not stop this process.'
  set +e
  if [[ "$mode" == security ]]; then unattended-upgrade -v 2>&1 | tee -a "$update_log"; update_rc=${PIPESTATUS[0]}
  else DEBIAN_FRONTEND=readline apt-get -y upgrade 2>&1 | tee -a "$update_log"; update_rc=${PIPESTATUS[0]}; fi
  set -e
  if ((update_rc != 0)); then
    update_write_history "$mode" FAILED "$UPDATE_TOTAL" "$UPDATE_SECURITY" "$update_log"
    error "APT returned exit $update_rc. Configuration backup was preserved at $LAST_UPDATE_BACKUP. Review $update_log"; return "$EXIT_SYSTEM"
  fi
  if update_post_check; then result=SUCCESS; else result=WARNING; fi
  if grep -Eqi 'configuration file.*(modified|conflict)|conffile.*prompt|dpkg: error processing' "$update_log"; then
    warn 'A package configuration message requires administrator review. No force-overwrite action was taken.'; result=WARNING
  fi
  package_count=$(awk -v start="$start_time" '$1" "$2 >= strftime("%Y-%m-%d %H:%M:%S",start) && $3=="upgrade" {count++} END {print count+0}' /var/log/dpkg.log 2>/dev/null || printf "$UPDATE_TOTAL")
  update_write_history "$mode" "$result" "$package_count" "$UPDATE_SECURITY" "$update_log"
  printf '\n========================================\n       UPDATE COMPLETED%s\n========================================\nPackages Updated : %s\nSecurity Updates  : %s\nResult            : %s\nReboot Required   : %s\n========================================\n' "$([[ "$result" == WARNING ]] && printf ' WITH WARNING')" "$package_count" "$UPDATE_SECURITY" "$result" "$([[ -f /var/run/reboot-required ]] && printf YES || printf NO)"
  [[ "$result" == SUCCESS ]] || { warn "Do not remove backup $LAST_UPDATE_BACKUP. Administrator review is required; packages were not downgraded automatically."; return "$EXIT_SYSTEM"; }
}

update_post_check() {
  local failures=0 version record domain ssl url has_ssl=0 disk_usage memory_total memory_available memory_usage
  printf '\nPOST-UPDATE CHECK\n=================\n'
  if service_is_active nginx; then update_check_line Nginx PASS; else update_check_line Nginx CRITICAL; ((++failures)); fi
  if nginx -t >/dev/null 2>&1; then update_check_line 'Nginx Config' PASS; else update_check_line 'Nginx Config' CRITICAL; ((++failures)); fi
  for version in $ALLOWED_PHP_VERSIONS; do if [[ -d "/etc/php/$version/fpm" ]] && ! service_is_active "php$version-fpm"; then update_check_line "PHP $version" CRITICAL; ((++failures)); fi; done
  if service_is_active mariadb && mariadb --protocol=socket -Nse 'SELECT 1' >/dev/null 2>&1; then update_check_line MariaDB PASS; else update_check_line MariaDB CRITICAL; ((++failures)); fi
  ss -Hln sport = :80 2>/dev/null | grep -q . && update_check_line 'Port 80' PASS || { update_check_line 'Port 80' CRITICAL; ((++failures)); }
  shopt -s nullglob
  for record in "$STATE_DIR"/websites/*.conf; do domain=$(record_get "$record" DOMAIN); ssl=$(record_get "$record" SSL); url="http://$domain"; if [[ "$ssl" == yes ]]; then url="https://$domain"; has_ssl=1; fi; if curl -fsSIL --max-time 8 "$url" >/dev/null 2>&1; then printf '%-32s PASS\n' "$domain"; else printf '%-32s WARNING\n' "$domain"; ((++failures)); fi; done
  shopt -u nullglob
  if ((has_ssl)); then ss -Hln sport = :443 2>/dev/null | grep -q . && update_check_line 'Port 443' PASS || { update_check_line 'Port 443' CRITICAL; ((++failures)); }; else update_check_line 'Port 443' 'N/A'; fi
  disk_usage=$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}'); ((disk_usage < 95)) && update_check_line Disk PASS || { update_check_line Disk CRITICAL; ((++failures)); }
  memory_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo); memory_available=$(awk '/MemAvailable/ {print $2}' /proc/meminfo); memory_usage=$((100 * (memory_total-memory_available) / memory_total))
  ((memory_usage < 95)) && update_check_line Memory PASS || { update_check_line Memory CRITICAL; ((++failures)); }
  ((failures == 0))
}

update_write_history() {
  local action=$1 result=$2 packages=$3 security=$4 log_file=$5 ubuntu
  ubuntu=$(source /etc/os-release 2>/dev/null; printf '%s' "${VERSION_ID:-unknown}")
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(timestamp)" "${SUDO_USER:-${USER:-unknown}}" "$(client_ip)" "$ubuntu" "$(uname -r)" "$action" "$packages" "$security" "$result:$log_file" >> "$UPDATE_HISTORY_FILE"
  chmod 0640 "$UPDATE_HISTORY_FILE"; audit_event "system update $action" "$result" "packages=$packages security=$security"
}

update_history() {
  printf '%-25s %-14s %-16s %-8s %-20s %-10s %-9s %-9s %s\n' DATE USER SOURCE UBUNTU KERNEL ACTION PACKAGES SECURITY RESULT
  [[ -f "$UPDATE_HISTORY_FILE" ]] && tail -100 "$UPDATE_HISTORY_FILE" || ok 'No update history recorded yet.'
}

update_reboot_status() {
  printf '\n========================================\n        REBOOT STATUS\n========================================\nCurrent Kernel   : %s\nInstalled Kernel: %s\n' "$(uname -r)" "$(dpkg-query -W -f='${Version}\n' 'linux-image-*' 2>/dev/null | sort -V | tail -1 || printf unknown)"
  if [[ -f /var/run/reboot-required ]]; then printf 'Reboot Required : YES\nReason:\n'; sed -n '1,20p' /var/run/reboot-required.pkgs 2>/dev/null || printf 'Kernel or core library update detected.\n'; warn 'Reboot later during a planned maintenance window; serverctl will not reboot automatically.'
  else printf 'Reboot Required : NO\n'; fi
  printf '========================================\n'
}
