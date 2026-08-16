#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
export SERVERCTL_ROOT=$TEST_ROOT SERVERCTL_TEST_MODE=1 SERVERCTL_ASSUME_YES=1 SERVERCTL_COLOR=never

for library in common validators registry render website php ssl database backup sftp security nginx system dashboard menu; do
  # shellcheck source=/dev/null
  source "$PROJECT_DIR/lib/$library.sh"
done
init_runtime

passed=0 failed=0
pass() { printf 'ok - %s\n' "$1"; ((passed+=1)); }
fail_test() { printf 'not ok - %s\n' "$1" >&2; ((failed+=1)); }
assert_true() { local name=$1; shift; if "$@"; then pass "$name"; else fail_test "$name"; fi; }
assert_false() { local name=$1; shift; if "$@"; then fail_test "$name"; else pass "$name"; fi; }
assert_file_contains() { local name=$1 file=$2 pattern=$3; if grep -Eq "$pattern" "$file"; then pass "$name"; else fail_test "$name"; fi; }

[[ "$SERVERCTL_VERSION" == 1.1.7 && "$SERVERCTL_RELEASE_DATE" == 2026-08-16 ]] && pass 'serverctl version metadata is defined' || fail_test 'serverctl version metadata is defined'
assert_file_contains 'Dashboard Fail2Ban read access is sudoers allow-listed' "$PROJECT_DIR/etc/sudoers.d/serverctl" 'dashboard fail2ban'
assert_true 'valid apex domain' validate_domain example.com
assert_true 'valid subdomain' validate_domain erp.company.co.th
assert_true 'accepts localhost site name' validate_site_name localhost
assert_true 'accepts IPv4 site name' validate_site_name 192.168.1.50
assert_false 'rejects IPv4 as public domain' validate_domain 192.168.1.50
assert_true 'recognizes private site name' is_local_site 192.168.1.50
assert_true 'accepts local dashboard IP' dashboard_validate_name 192.168.1.50
assert_false 'rejects separate dashboard IP hostname' dashboard_validate_name dashboard.192.168.1.50
assert_true 'accepts bot protection key value' dashboard_validate_bot_value site_key_123
assert_false 'rejects bot protection newline' dashboard_validate_bot_value $'bad\nvalue'
assert_false 'rejects bot protection config delimiter' dashboard_validate_bot_value 'bad=value'
assert_file_contains 'Fail2Ban dashboard filter catches failed logins' "$PROJECT_DIR/etc/fail2ban/filter.d/serverctl-dashboard-login.conf" 'LOGIN.*FAILED'
assert_file_contains 'Fail2Ban dashboard jail is enabled' "$PROJECT_DIR/etc/fail2ban/jail.d/serverctl.local" 'serverctl-dashboard-login'
dashboard_render_nginx 192.168.1.50 /run/php/php8.3-fpm.sock '' yes 8088
assert_file_contains 'local dashboard listens on port 8088' "$DASHBOARD_NGINX_AVAILABLE" 'listen 8088;'
dashboard_render_nginx example.com /run/php/php8.3-fpm.sock /etc/letsencrypt/live/example.com no 8088
assert_file_contains 'domain dashboard listens on TLS port 8088' "$DASHBOARD_NGINX_AVAILABLE" 'listen 8088 ssl http2;'
assert_false 'rejects command substitution domain' validate_domain 'x$(id).com'
assert_false 'rejects traversal domain' validate_domain '../example.com'
assert_false 'rejects leading hyphen label' validate_domain '-bad.example.com'
assert_true 'valid database name' validate_db_name ERP_2026
assert_false 'rejects SQL syntax in database name' validate_db_name 'erp`; DROP DATABASE mysql;'
assert_true 'valid IPv4' validate_ip 192.0.2.10
assert_false 'rejects invalid IPv4' validate_ip 999.0.2.10
assert_true 'accepts valid IPv4 CIDR' validate_cidr 192.0.2.0/24
assert_false 'rejects invalid CIDR prefix' validate_cidr 192.0.2.0/99
assert_false 'rejects traversal in remote backup target' validate_remote_backup_target '/mnt/backups/../../var/www'
assert_true 'valid PHP version' validate_php_version 8.3
assert_false 'rejects unsupported PHP version' validate_php_version 9.0
assert_true 'valid Nginx backup name' validate_nginx_backup_name 2026-08-14_140000_123456789
assert_false 'rejects traversal Nginx backup name' validate_nginx_backup_name '../../etc/nginx'
[[ "$(redact_command dashboard install --password-hash '$2y$hash')" == 'dashboard install [REDACTED] [REDACTED]' ]] && pass 'Dashboard password hashes are redacted from audit actions' || fail_test 'Dashboard password hashes are redacted from audit actions'

user_a=$(website_user example.com); user_b=$(website_user example.com); user_c=$(website_user example.net)
[[ "$user_a" == "$user_b" && "$user_a" != "$user_c" && ${#user_a} -le 32 ]] && pass 'website users are stable and collision-resistant' || fail_test 'website users are stable and collision-resistant'

website_add example.com --php 8.3
record=$(website_record_path example.com)
assert_true 'website registry created' test -f "$record"
assert_file_contains 'website SFTP account enabled' "$record" '^SFTP_ENABLED=yes$'
assert_file_contains 'SFTP uses internal subsystem' "$(root_path /etc/ssh/sshd_config.d/59-serverctl-sftp.conf)" 'ForceCommand internal-sftp'
assert_true 'website public directory created' test -d "$WEB_ROOT/example.com/public"
assert_file_contains 'Nginx blocks hidden files' "$(nginx_available_dir)/example.com.conf" 'location ~ \(\^\|/\)\\\.'
assert_file_contains 'Nginx blocks PHP below uploads' "$(nginx_available_dir)/example.com.conf" 'uploads'
assert_file_contains 'Nginx enables per-IP rate limiting' "$(nginx_available_dir)/example.com.conf" 'limit_req zone=serverctl_per_ip'
assert_file_contains 'Nginx blocks cross-owner symlink escape' "$(nginx_available_dir)/example.com.conf" 'disable_symlinks if_not_owner'
assert_file_contains 'Nginx includes protected site access rules' "$(nginx_available_dir)/example.com.conf" 'serverctl-access-example.com.conf'
assert_true 'default site access rule validates' validate_nginx_access_file "$(nginx_access_path example.com)"
printf 'allow 192.0.2.0/24;\nroot /etc;\n' > "$TEST_ROOT/bad-access.conf"
assert_false 'site access validator rejects arbitrary Nginx directives' validate_nginx_access_file "$TEST_ROOT/bad-access.conf"
deny_line=$(grep -n 'uploads' "$(nginx_available_dir)/example.com.conf" | head -1 | cut -d: -f1)
php_line=$(grep -n 'location ~ \\.php' "$(nginx_available_dir)/example.com.conf" | head -1 | cut -d: -f1)
((deny_line < php_line)) && pass 'Nginx deny regex precedes generic PHP handler' || fail_test 'Nginx deny regex precedes generic PHP handler'
assert_file_contains 'PHP pool uses isolated user' "$(php_pool_dir 8.3)/example.com.conf" "user = $user_a"
assert_file_contains 'PHP pool uses Unix socket' "$(php_pool_dir 8.3)/example.com.conf" 'listen = .*/run/php/serverctl/example.com.sock'
website_csp example.com "default-src 'self'; img-src 'self' data:"
assert_file_contains 'per-site CSP is rendered' "$(nginx_available_dir)/example.com.conf" "img-src 'self' data:"
assert_false 'CSP rejects Nginx quote injection' validate_csp $'default-src self";\nroot /etc;'

php_set example.com 8.4
[[ "$(record_get "$record" PHP_VERSION)" == 8.4 ]] && pass 'PHP version switch updates registry' || fail_test 'PHP version switch updates registry'
assert_true 'new PHP pool created' test -f "$(php_pool_dir 8.4)/example.com.conf"
assert_false 'old PHP pool removed' test -e "$(php_pool_dir 8.3)/example.com.conf"
assert_file_contains 'PHP switch preserves per-site CSP' "$(nginx_available_dir)/example.com.conf" "img-src 'self' data:"

backup_create_website example.com
backup_name=$(basename "$LAST_BACKUP")
assert_true 'website backup archive created' test -s "$LAST_BACKUP"
backup_verify "$backup_name"
pass 'website backup checksum verification'

database_create ERP_2026 >/dev/null
assert_true 'database registry created without password' test -f "$(database_record_path ERP_2026)"
assert_false 'database registry does not store password' grep -qi password "$(database_record_path ERP_2026)"
backup_create_database ERP_2026 >/dev/null
database_backup=$(basename "$LAST_BACKUP")
database_remove ERP_2026 --no-backup >/dev/null
assert_false 'database removal deletes registry' test -e "$(database_record_path ERP_2026)"
backup_restore "$database_backup" >/dev/null
assert_true 'database restore recreates registry' test -f "$(database_record_path ERP_2026)"

website_remove example.com --no-backup
assert_false 'website removal deletes registry' test -e "$record"
assert_false 'website removal deletes only site root' test -e "$WEB_ROOT/example.com"
backup_restore "$backup_name" >/dev/null
assert_true 'website restore recreates registry' test -f "$record"
assert_true 'website restore regenerates Nginx config' test -f "$(nginx_available_dir)/example.com.conf"
assert_file_contains 'website restore preserves validated CSP' "$(nginx_available_dir)/example.com.conf" "img-src 'self' data:"

global_state="$TEST_ROOT/nginx-global-test.conf"
printf 'keepalive_timeout=30s\nclient_max_body_size=64m\ngzip=off\n' > "$global_state"
nginx_render_tuning "$global_state" > "$TEST_ROOT/tuning.conf"
assert_file_contains 'Nginx global renderer applies timeout' "$TEST_ROOT/tuning.conf" 'keepalive_timeout 30s;'
assert_file_contains 'Nginx global renderer applies body limit' "$TEST_ROOT/tuning.conf" 'client_max_body_size 64m;'
render_nginx_site example.com 8.4 no "default-src 'self'" 64m 25 on "$TEST_ROOT/site-candidate.conf"
assert_file_contains 'Nginx site renderer persists upload limit' "$TEST_ROOT/site-candidate.conf" 'client_max_body_size 64m;'
assert_file_contains 'Nginx site renderer persists rate burst' "$TEST_ROOT/site-candidate.conf" 'burst=25 nodelay'
assert_file_contains 'Nginx site renderer supports static cache' "$TEST_ROOT/site-candidate.conf" 'expires 7d'

nginx() { if [[ "${1:-}" == -v ]]; then printf '%s\n' 'nginx version: nginx/1.24.0' >&2; else return 0; fi; }
nginx_backup_config >/dev/null
assert_true 'Nginx configuration backup is created' test -d "$LAST_NGINX_BACKUP/nginx"
assert_true 'Nginx backup contains checksum manifest' test -s "$LAST_NGINX_BACKUP/SHA256SUMS"
assert_true 'Nginx backup records symlink manifest' test -f "$LAST_NGINX_BACKUP/SYMLINKS"

apt-get() {
  cat <<'EOF'
Inst openssl [3.0.0] (3.0.1 Ubuntu:24.04-security [amd64])
Inst curl [8.0.0] (8.1.0 Ubuntu:24.04-updates [amd64])
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
EOF
}
update_collect
[[ "$UPDATE_TOTAL" == 2 && "$UPDATE_SECURITY" == 1 && "$UPDATE_REMOVED" == 0 ]] && pass 'APT simulation separates security and normal updates' || fail_test 'APT simulation separates security and normal updates'

dashboard_snapshot_output=$(dashboard_snapshot)
[[ "$dashboard_snapshot_output" == '{"status":"success","data":{'* ]] && pass 'Dashboard snapshot returns structured JSON' || fail_test 'Dashboard snapshot returns structured JSON'
dashboard_websites_output=$(dashboard_websites)
[[ "$dashboard_websites_output" == '{"status":"success","data":['* ]] && pass 'Dashboard website endpoint returns structured JSON' || fail_test 'Dashboard website endpoint returns structured JSON'
dashboard_fail2ban_output=$(dashboard_fail2ban)
[[ "$dashboard_fail2ban_output" == '{"status":"success","data":{"service":'* ]] && pass 'Dashboard Fail2Ban endpoint returns structured JSON' || fail_test 'Dashboard Fail2Ban endpoint returns structured JSON'
if dashboard_action not-allowed >/dev/null 2>&1; then
  fail_test 'Dashboard action dispatcher rejects unlisted actions'
else
  pass 'Dashboard action dispatcher rejects unlisted actions'
fi

if SERVERCTL_LIB_DIR="$PROJECT_DIR/lib" bash "$PROJECT_DIR/bin/serverctl" --yes website add cli.example.com --php 8.3 >/dev/null; then pass 'CLI entry-point accepts global --yes'; else fail_test 'CLI entry-point accepts global --yes'; fi
if SERVERCTL_LIB_DIR="$PROJECT_DIR/lib" bash "$PROJECT_DIR/bin/serverctl" unknown-command >/dev/null 2>&1; then
  fail_test 'CLI unknown command returns exit code 2'
else
  rc=$?; [[ "$rc" == 2 ]] && pass 'CLI unknown command returns exit code 2' || fail_test 'CLI unknown command returns exit code 2'
fi
if SERVERCTL_LIB_DIR="$PROJECT_DIR/lib" bash "$PROJECT_DIR/bin/serverctl" --yes website add rejected.example.com --bogus >/dev/null 2>&1; then
  fail_test 'CLI rejects unknown mutation arguments'
else
  rc=$?; [[ "$rc" == 2 && ! -e "$(website_record_path rejected.example.com)" ]] && pass 'CLI rejects unknown mutation arguments' || fail_test 'CLI rejects unknown mutation arguments'
fi

printf '\n%d passed, %d failed\n' "$passed" "$failed"
((failed == 0))
