#!/usr/bin/env bash

menu_header() {
  clear 2>/dev/null || true
  printf '%s\n' '========================================' 'WEB SERVER MANAGER' '=================='
  printf 'Server : %s\nOS     : %s\nIP     : %s\n\n' "$(hostname 2>/dev/null)" "$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-unknown}")" "$(hostname -I 2>/dev/null | awk '{print $1}')"
}

menu_pause() { printf '\nPress Enter to continue...'; read -r _; }
menu_exec() { "$REAL_SELF" "$@" || true; }

interactive_menu() {
  local choice
  while true; do
    menu_header
    cat <<'EOF'
1.  Add Website
2.  Remove Website
3.  Enable SSL
4.  Database Management
5.  PHP Version
6.  Backup
7.  View Logs
8.  Security Status
9.  Server Status
10. Firewall
11. Fail2Ban
12. System Update
13. Nginx
14. SFTP Users
15. Exit
========================================
EOF
    printf 'Select option: '; read -r choice
    case "$choice" in
      1) menu_add_website ;;
      2) menu_remove_website ;;
      3) menu_enable_ssl ;;
      4) menu_database ;;
      5) menu_php ;;
      6) menu_backup ;;
      7) menu_logs ;;
      8) security_status || true; menu_pause ;;
      9) status_once; menu_pause ;;
      10) menu_firewall ;;
      11) fail2ban-client status || true; menu_pause ;;
      12) menu_system_update ;;
      13) menu_nginx ;;
      14) menu_sftp ;;
      15) return 0 ;;
      *) warn 'Invalid option.'; sleep 1 ;;
    esac
  done
}

menu_system_update() {
  local choice
  while true; do
    printf '\n========================================\n          SYSTEM UPDATE\n========================================\n\n  1. Update serverctl from GitHub\n  2. Check for Ubuntu Updates\n  3. Security Updates\n  4. Install Ubuntu Updates\n  5. Update History\n  6. System Health Check\n  7. Reboot Required Status\n\n  0. Back\n========================================\nSelect option: '
    read -r choice
    case "$choice" in
      1) menu_exec update serverctl; menu_pause ;;
      2) menu_exec update check; menu_pause ;;
      3) menu_exec update security; menu_pause ;;
      4) menu_exec update all; menu_pause ;;
      5) menu_exec update history; menu_pause ;;
      6) menu_exec update health; menu_pause ;;
      7) menu_exec update reboot-status; menu_pause ;;
      0) return ;;
      *) warn 'Invalid option.' ;;
    esac
  done
}

menu_nginx() {
  local choice state version config
  while true; do
    state=$(systemctl is-active nginx 2>/dev/null || true); state=${state:-inactive}; version=$(nginx -v 2>&1 | sed 's#nginx version: nginx/##' || printf unknown)
    if nginx -t >/dev/null 2>&1; then config=VALID; else config=INVALID; fi
    printf '\n========================================\n              NGINX\n========================================\n\nStatus      : %s\nVersion     : %s\nConfig      : %s\n\n----------------------------------------\n\n  1. Nginx Status\n  2. Test Configuration\n  3. Reload Nginx\n  4. Restart Nginx\n  5. Stop Nginx\n  6. Start Nginx\n  7. View Configuration\n  8. Global Settings\n  9. Website Configuration\n 10. Security Settings\n 11. Access Log\n 12. Error Log\n 13. Backup Configuration\n 14. Restore Configuration\n 15. Configuration History\n 16. Manual Edit Configuration\n\n  0. Back\n\n========================================\nSelect option: ' "$state" "$version" "$config"
    read -r choice
    case "$choice" in
      1) menu_exec nginx status; menu_pause ;;
      2) menu_exec nginx test; menu_pause ;;
      3) menu_exec nginx reload; menu_pause ;;
      4) menu_exec nginx restart; menu_pause ;;
      5) menu_exec nginx stop; menu_pause ;;
      6) menu_exec nginx start; menu_pause ;;
      7) menu_nginx_view ;;
      8) menu_nginx_global ;;
      9) menu_nginx_website ;;
      10) menu_exec nginx security; menu_pause ;;
      11) menu_nginx_log access ;;
      12) menu_nginx_log error ;;
      13) menu_exec nginx backup; menu_pause ;;
      14) menu_nginx_restore ;;
      15) menu_exec nginx history; menu_pause ;;
      16) menu_nginx_manual_edit ;;
      0) return ;;
      *) warn 'Invalid option.' ;;
    esac
  done
}

menu_nginx_manual_edit() {
  local choice domain file
  printf '\n========================================\n        MANUAL NGINX EDITOR\n========================================\n\n  1. Main Configuration (nginx.conf)\n  2. Website Configuration\n  3. conf.d Configuration\n  4. Snippet Configuration\n\n  0. Back\n========================================\nSelect option: '
  read -r choice
  case "$choice" in
    1) menu_exec nginx edit main ;;
    2) website_list; printf '\nWebsite: '; read -r domain; [[ -n "$domain" ]] && menu_exec nginx edit website "$domain" ;;
    3) printf 'conf.d filename (.conf): '; read -r file; [[ -n "$file" ]] && menu_exec nginx edit conf.d "$file" ;;
    4) printf 'Snippet filename (.conf): '; read -r file; [[ -n "$file" ]] && menu_exec nginx edit snippets "$file" ;;
    *) return ;;
  esac
  menu_pause
}

menu_nginx_view() {
  local choice type
  printf '\n1. Main Configuration\n2. Sites Available\n3. Sites Enabled\n4. Snippets\n5. Included Configuration\n0. Back\nSelect: '; read -r choice
  case "$choice" in 1) type=main ;; 2) type=available ;; 3) type=enabled ;; 4) type=snippets ;; 5) type=included ;; *) return ;; esac
  menu_exec nginx config "$type"; menu_pause
}

menu_nginx_global() {
  local choice key value
  printf '\n========================================\n        NGINX GLOBAL SETTINGS\n========================================\n\n  1. Worker Processes (view)\n  2. Worker Connections (view)\n  3. Keepalive Timeout\n  4. Client Max Body Size\n  5. Gzip\n  6. Brotli (view)\n  7. HTTP/2 (view)\n  8. HTTP/3 (view)\n  9. Access Log (view)\n 10. Error Log (view)\n 11. Security Headers (audit)\n 12. Request Timeout\n 13. Custom Configuration (view only)\n\n  0. Back\n========================================\nSelect: '; read -r choice
  case "$choice" in
    1) key=worker_processes; printf 'auto or workers (1-64): '; read -r value; menu_exec nginx global set "$key" "$value" ;;
    2) key=worker_connections; printf 'Connections per worker (128-65535): '; read -r value; menu_exec nginx global set "$key" "$value" ;;
    6|7|8|13) menu_exec nginx global show ;;
    3) key=keepalive_timeout; printf 'Seconds (1-300): '; read -r value; menu_exec nginx global set "$key" "$value" ;;
    4) key=client_max_body_size; printf 'Size (example 32m): '; read -r value; menu_exec nginx global set "$key" "$value" ;;
    5) key=gzip; printf 'on/off: '; read -r value; menu_exec nginx global set "$key" "$value" ;;
    9) menu_exec nginx access-log global 100 ;;
    10) menu_exec nginx error-log global 100 ;;
    11) menu_exec nginx security ;;
    12) key=client_body_timeout; printf 'Seconds (1-300): '; read -r value; menu_exec nginx global set "$key" "$value" ;;
    *) return ;;
  esac
  menu_pause
}

menu_nginx_website() {
  local domain choice value
  website_list; printf '\nDomain (blank to return): '; read -r domain; [[ -n "$domain" ]] || return
  printf '\n1. View Config\n2. Edit Config (safe settings)\n3. Force HTTPS\n4. Security Headers / CSP\n5. Upload Limit\n6. Access Rules\n7. Rate Limit\n8. Static Cache\n9. Custom Rules\n10. Test Config\n0. Back\nSelect: '; read -r choice
  case "$choice" in
    1|2) menu_exec nginx website view "$domain" ;;
    3) menu_exec ssl enable "$domain" ;;
    4) printf 'CSP policy: '; read -r value; menu_exec website csp "$domain" "$value" ;;
    5) printf 'Upload limit (example 32m): '; read -r value; menu_exec nginx website set "$domain" upload-limit "$value" ;;
    6) menu_nginx_access "$domain" ;;
    9) warn 'Arbitrary Nginx directives are intentionally not accepted. Use a reviewed root maintenance workflow.' ;;
    7) printf 'Burst (1-100): '; read -r value; menu_exec nginx website set "$domain" rate-limit "$value" ;;
    8) printf 'Static cache on/off: '; read -r value; menu_exec nginx website set "$domain" static-cache "$value" ;;
    10) menu_exec nginx test ;;
    *) return ;;
  esac
  menu_pause
}

menu_nginx_access() {
  local domain=$1 choice action cidr
  printf '\n1. List Rules\n2. Allow-only IP/CIDR\n3. Deny IP/CIDR\n4. Clear Rules\n0. Back\nSelect: '; read -r choice
  case "$choice" in
    1) menu_exec nginx website access "$domain" list ;;
    2) action=allow; printf 'IP/CIDR: '; read -r cidr; menu_exec nginx website access "$domain" "$action" "$cidr" ;;
    3) action=deny; printf 'IP/CIDR: '; read -r cidr; menu_exec nginx website access "$domain" "$action" "$cidr" ;;
    4) menu_exec nginx website access "$domain" clear ;;
    *) return ;;
  esac
}

menu_nginx_log() {
  local type=$1 scope choice lines search
  printf '\n1. Last 50\n2. Last 100\n3. Last 500\n4. Live\n5. Search\n0. Back\nSelect: '; read -r choice
  case "$choice" in 1) lines=50 ;; 2) lines=100 ;; 3) lines=500 ;; 4) lines=100 ;; 5) lines=100 ;; *) return ;; esac
  printf 'Domain or global [global]: '; read -r scope; scope=${scope:-global}
  if [[ "$choice" == 4 ]]; then menu_exec nginx "$type-log" "$scope" --lines "$lines" --follow
  elif [[ "$choice" == 5 ]]; then printf 'Search text: '; read -r search; menu_exec nginx "$type-log" "$scope" --lines "$lines" --search "$search"
  else menu_exec nginx "$type-log" "$scope" --lines "$lines"; fi
  menu_pause
}

menu_nginx_restore() {
  local name
  menu_exec nginx backup-list; printf '\nBackup name (blank to return): '; read -r name; [[ -n "$name" ]] || return
  menu_exec nginx restore "$name"; menu_pause
}

menu_add_website() { local domain php; printf 'Domain: '; read -r domain; printf 'PHP version [%s]: ' "$DEFAULT_PHP_VERSION"; read -r php; php=${php:-$DEFAULT_PHP_VERSION}; menu_exec website add "$domain" --php "$php"; menu_pause; }
menu_remove_website() { local domain; website_list; printf '\nDomain to remove: '; read -r domain; menu_exec website remove "$domain"; menu_pause; }
menu_enable_ssl() { local domain email; printf 'Domain: '; read -r domain; printf 'Let\x27s Encrypt email (optional): '; read -r email; if [[ -n "$email" ]]; then menu_exec ssl enable "$domain" --email "$email"; else menu_exec ssl enable "$domain"; fi; menu_pause; }

menu_sftp() {
  local choice domain
  while true; do
    printf '\n========================================\n           SFTP USERS\n========================================\n\n  1. List SFTP Users\n  2. Reset Password\n  3. Enable SFTP\n  4. Disable SFTP\n\n  0. Back\n========================================\nSelect option: '
    read -r choice
    case "$choice" in
      1) menu_exec sftp list; menu_pause ;;
      2) printf 'Website: '; read -r domain; [[ -n "$domain" ]] && menu_exec sftp password "$domain"; menu_pause ;;
      3) printf 'Website: '; read -r domain; [[ -n "$domain" ]] && menu_exec sftp enable "$domain"; menu_pause ;;
      4) printf 'Website: '; read -r domain; [[ -n "$domain" ]] && menu_exec sftp disable "$domain"; menu_pause ;;
      0) return ;;
      *) warn 'Invalid option.' ;;
    esac
  done
}

menu_database() {
  local choice database
  while true; do
    printf '\n========================================\n        DATABASE MANAGEMENT\n========================================\n\n  1. List Databases\n  2. Create Database\n  3. Remove Database\n  4. Database Health\n\n  0. Back\n========================================\nSelect option: '
    read -r choice
    case "$choice" in
      1) menu_exec database list; menu_pause ;;
      2) printf 'Database name: '; read -r database; [[ -n "$database" ]] && menu_exec database create "$database"; menu_pause ;;
      3) database_list; printf '\nDatabase to remove (blank to return): '; read -r database; [[ -n "$database" ]] || continue; menu_exec database remove "$database"; menu_pause ;;
      4) printf 'Database name (blank for server health): '; read -r database; if [[ -n "$database" ]]; then menu_exec database health "$database"; else menu_exec database health; fi; menu_pause ;;
      0) return ;;
      *) warn 'Invalid option.' ;;
    esac
  done
}

menu_php() {
  local choice domain version
  php_list; printf '\n1. Change website PHP\n2. Back\nSelect: '; read -r choice
  [[ "$choice" == 1 ]] || return 0
  printf 'Domain: '; read -r domain; printf 'PHP version: '; read -r version; menu_exec php set "$domain" "$version"; menu_pause
}

menu_backup() {
  local choice value
  printf '1. Backup Website\n2. Backup Database\n3. Backup Everything\n4. List Backups\n5. Back\nSelect: '; read -r choice
  case "$choice" in
    1) printf 'Domain: '; read -r value; menu_exec backup create --website "$value" ;;
    2) printf 'Database: '; read -r value; menu_exec backup create --database "$value" ;;
    3) menu_exec backup create --all ;;
    4) backup_list ;;
    *) return ;;
  esac
  menu_pause
}

menu_logs() {
  local choice type
  printf '1. Nginx Error\n2. PHP-FPM\n3. MariaDB\n4. Fail2Ban\n5. Firewall\n6. System\n7. Serverctl\n8. Back\nSelect: '; read -r choice
  case "$choice" in 1) type=nginx ;; 2) type=php ;; 3) type=mariadb ;; 4) type=fail2ban ;; 5) type=firewall ;; 6) type=system ;; 7) type=serverctl ;; *) return ;; esac
  menu_exec logs "$type" --lines 100; menu_pause
}

menu_firewall() {
  local choice port protocol source number
  printf '1. Add Rule\n2. Remove Rule\n3. List Rules\n4. Reload Firewall\n5. Back\nSelect: '; read -r choice
  case "$choice" in
    1) printf 'Port: '; read -r port; printf 'Protocol [tcp]: '; read -r protocol; printf 'Source IP/CIDR [any]: '; read -r source; menu_exec firewall add "$port" "${protocol:-tcp}" "${source:-any}" ;;
    2) ufw status numbered; printf 'Rule number: '; read -r number; menu_exec firewall remove "$number" ;;
    3) ufw status numbered ;;
    4) menu_exec firewall reload ;;
    *) return ;;
  esac
  menu_pause
}
