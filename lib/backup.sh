#!/usr/bin/env bash

cmd_backup() {
  local sub=${1:-}; shift || true
  case "$sub" in
    create) backup_create "$@" ;;
    list) (($# == 0)) || die "backup list accepts no arguments." "$EXIT_INVALID_ARGUMENT"; backup_list ;;
    verify) backup_verify "$@" ;;
    encrypt) backup_encrypt "$@" ;;
    restore) backup_restore "$@" ;;
    delete) backup_delete "$@" ;;
    sync) (($# == 0)) || die "backup sync accepts no arguments." "$EXIT_INVALID_ARGUMENT"; backup_sync ;;
    *) die "Usage: serverctl backup <create|list|verify|encrypt|restore|delete|sync>" "$EXIT_INVALID_ARGUMENT" ;;
  esac
}

backup_timestamp() { date '+%Y%m%d-%H%M%S-%N'; }

backup_create() {
  require_root
  local kind="" target="" encrypt=0
  (($#)) || kind=all
  while (($#)); do
    case "$1" in
      --all) [[ -z "$kind" ]] || die "Select only one backup scope." "$EXIT_INVALID_ARGUMENT"; kind=all; shift ;;
      --website|--database)
        [[ -z "$kind" ]] || die "Select only one backup scope." "$EXIT_INVALID_ARGUMENT"
        (($# >= 2)) || die "$1 requires a name." "$EXIT_INVALID_ARGUMENT"
        kind=${1#--}; target=$2; shift 2 ;;
      --encrypt) encrypt=1; shift ;;
      *) die "Unknown backup create argument: $1" "$EXIT_INVALID_ARGUMENT" ;;
    esac
  done
  case "$kind" in all) backup_create_all ;; website) backup_create_website "$target" ;; database) backup_create_database "$target" ;; *) die "Use --all, --website DOMAIN, or --database NAME." "$EXIT_INVALID_ARGUMENT" ;; esac
  if ((encrypt)); then backup_encrypt "$(basename "$LAST_BACKUP")"; fi
}

backup_create_website() {
  local domain=$1 archive manifest stage
  validate_site_name "$domain" || die "Invalid domain or IP address." "$EXIT_VALIDATION"
  website_exists "$domain" || die "Website not found." "$EXIT_VALIDATION"
  archive="$BACKUP_DIR/serverctl-website-$domain-$(backup_timestamp).tar.gz"
  stage=$(mktemp -d "$BACKUP_DIR/.stage.XXXXXX")
  mkdir -p "$stage/files" "$stage/config"
  [[ -d "$WEB_ROOT/$domain" ]] || { rm -rf -- "$stage"; die "Website files are missing." "$EXIT_SYSTEM"; }
  cp -a -- "$WEB_ROOT/$domain" "$stage/files/"
  cp -a -- "$(website_record_path "$domain")" "$stage/config/record.conf"
  [[ -f "$(nginx_available_dir)/$domain.conf" ]] && cp -a -- "$(nginx_available_dir)/$domain.conf" "$stage/config/nginx.conf"
  [[ -f "$(php_pool_dir "$(record_get "$(website_record_path "$domain")" PHP_VERSION)")/$domain.conf" ]] && cp -a -- "$(php_pool_dir "$(record_get "$(website_record_path "$domain")" PHP_VERSION)")/$domain.conf" "$stage/config/php-fpm.conf"
  [[ -f "$(nginx_access_path "$domain")" ]] && cp -a -- "$(nginx_access_path "$domain")" "$stage/config/access.conf"
  finalize_backup "$stage" "$archive"
  LAST_BACKUP=$archive
  ok "Website backup created: $archive"
}

backup_create_database() {
  local database=$1 archive stage
  validate_db_name "$database" || die "Invalid database name." "$EXIT_VALIDATION"
  database_exists "$database" || die "Database not found." "$EXIT_VALIDATION"
  if [[ "$SERVERCTL_TEST_MODE" != 1 ]]; then
    if database_exists_in_mariadb "$database"; then :; else
      local verify_rc=$?
      ((verify_rc == 1)) && die "Database does not exist in MariaDB." "$EXIT_VALIDATION"
      die "Unable to verify MariaDB database state." "$EXIT_SYSTEM"
    fi
  fi
  archive="$BACKUP_DIR/serverctl-database-$database-$(backup_timestamp).tar.gz"
  stage=$(mktemp -d "$BACKUP_DIR/.stage.XXXXXX")
  if [[ "$SERVERCTL_TEST_MODE" == 1 ]]; then printf '%s\n' '-- test dump' > "$stage/database.sql"; else mariadb-dump --single-transaction --routines --triggers -- "$database" > "$stage/database.sql"; fi
  cp -a -- "$(database_record_path "$database")" "$stage/record.conf"
  finalize_backup "$stage" "$archive"
  LAST_BACKUP=$archive
  ok "Database backup created: $archive"
}

backup_create_all() {
  local archive stage file domain database
  archive="$BACKUP_DIR/serverctl-all-$(backup_timestamp).tar.gz"; stage=$(mktemp -d "$BACKUP_DIR/.stage.XXXXXX")
  mkdir -p "$stage/websites" "$stage/databases" "$stage/config"
  cp -a -- "$STATE_DIR" "$stage/config/state"
  for file in "$(root_path /etc/serverctl)" "$(root_path /etc/nginx)" "$(root_path /etc/php)" "$(root_path /etc/fail2ban)" "$(root_path /etc/ufw)"; do [[ -e "$file" ]] && cp -a -- "$file" "$stage/config/"; done
  if [[ -d "$(root_path /etc/cron.d)" ]]; then
    mkdir -p "$stage/config/cron.d"
    shopt -s nullglob
    for file in "$(root_path /etc/cron.d)"/serverctl-cron-* "$(root_path /etc/cron.d)/serverctl-websites"; do [[ -e "$file" ]] && cp -a -- "$file" "$stage/config/cron.d/"; done
    shopt -u nullglob
  fi
  shopt -s nullglob
  for file in "$STATE_DIR"/websites/*.conf; do
    domain=$(record_get "$file" DOMAIN)
    [[ -d "$WEB_ROOT/$domain" ]] || { rm -rf -- "$stage"; die "Registered website files are missing: $domain" "$EXIT_SYSTEM"; }
    cp -a -- "$WEB_ROOT/$domain" "$stage/websites/"
  done
  for file in "$STATE_DIR"/databases/*.conf; do database=$(record_get "$file" DATABASE); if [[ "$SERVERCTL_TEST_MODE" == 1 ]]; then printf '%s\n' '-- test dump' > "$stage/databases/$database.sql"; else mariadb-dump --single-transaction --routines --triggers -- "$database" > "$stage/databases/$database.sql"; fi; done
  shopt -u nullglob
  finalize_backup "$stage" "$archive"
  LAST_BACKUP=$archive
  prune_backups
  ok "Full backup created: $archive"
}

create_manifest() {
  local directory=$1
  (cd "$directory" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
}

finalize_backup() {
  local stage=$1 archive=$2 partial="$archive.partial.$$"
  if ! create_manifest "$stage"; then rm -rf -- "$stage"; die "Unable to create backup checksum manifest." "$EXIT_SYSTEM"; fi
  if ! tar -C "$stage" -czf "$partial" . || ! tar -tzf "$partial" >/dev/null; then
    rm -f -- "$partial"; rm -rf -- "$stage"; die "Backup archive creation or integrity check failed." "$EXIT_SYSTEM"
  fi
  chmod 0600 "$partial"; mv -f -- "$partial" "$archive"; rm -rf -- "$stage"
}

backup_list() {
  printf '%-64s %-12s %s\n' BACKUP SIZE CREATED
  local file
  shopt -s nullglob
  for file in "$BACKUP_DIR"/serverctl-*.tar.gz "$BACKUP_DIR"/serverctl-*.tar.gz.gpg; do
    printf '%-64s %-12s %s\n' "$(basename "$file")" "$(human_bytes "$(stat -c %s "$file")")" "$(date -r "$file" '+%Y-%m-%d %H:%M')"
  done
  shopt -u nullglob
}

resolve_backup() {
  local name=$1
  safe_basename "$name" || die "Unsafe backup name." "$EXIT_VALIDATION"
  validate_backup_name "$name" || die "Invalid backup filename." "$EXIT_VALIDATION"
  local path="$BACKUP_DIR/$name"
  [[ -f "$path" ]] || die "Backup not found: $name" "$EXIT_VALIDATION"
  printf '%s' "$path"
}

backup_verify() {
  local name=${1:-}; [[ -n "$name" ]] || die "Backup filename is required." "$EXIT_INVALID_ARGUMENT"
  (($# == 1)) || die "backup verify accepts exactly one filename." "$EXIT_INVALID_ARGUMENT"
  resolve_backup "$name" >/dev/null
  local temporary; temporary=$(mktemp -d "$BACKUP_DIR/.verify.XXXXXX")
  extract_verified_backup "$name" "$temporary"
  rm -rf -- "$temporary"; ok "Backup verified: $name"
}

extract_verified_backup() {
  local name=$1 destination=$2 archive plain cleanup=0
  [[ "$destination" == "$BACKUP_DIR/".* ]] || die "Unsafe extraction directory." "$EXIT_VALIDATION"
  archive=$(resolve_backup "$name"); plain=$archive
  if [[ "$archive" == *.gpg ]]; then
    has_command gpg || die "GnuPG is required for encrypted backups." "$EXIT_SYSTEM"
    plain=$(mktemp "$BACKUP_DIR/.decrypt.XXXXXX.tar.gz"); chmod 0600 "$plain"; cleanup=1
    if ! gpg --quiet --output "$plain" --decrypt "$archive"; then rm -f -- "$plain"; rm -rf -- "$destination"; die "Backup decryption failed." "$EXIT_VALIDATION"; fi
  fi
  safe_archive_members "$plain" || { ((cleanup)) && rm -f -- "$plain"; rm -rf -- "$destination"; die "Archive contains an unsafe path." "$EXIT_VALIDATION"; }
  tar -tzf "$plain" >/dev/null || { ((cleanup)) && rm -f -- "$plain"; rm -rf -- "$destination"; die "Archive integrity check failed." "$EXIT_VALIDATION"; }
  tar --no-same-owner --no-same-permissions -xzf "$plain" -C "$destination"
  ((cleanup)) && rm -f -- "$plain"
  (cd "$destination" && sha256sum -c SHA256SUMS >/dev/null) || { rm -rf -- "$destination"; die "File checksum verification failed." "$EXIT_VALIDATION"; }
}

safe_archive_members() {
  local archive=$1 member
  while IFS= read -r member; do
    [[ "$member" != /* && "$member" != ../* && "$member" != *'/../'* && "$member" != *'/..' ]] || return 1
  done < <(tar -tzf "$archive")
}

backup_encrypt() {
  require_root
  local name=${1:-} archive encrypted
  [[ -n "$name" ]] || die "Backup filename is required." "$EXIT_INVALID_ARGUMENT"
  (($# == 1)) || die "backup encrypt accepts exactly one filename." "$EXIT_INVALID_ARGUMENT"
  archive=$(resolve_backup "$name"); [[ "$archive" != *.gpg ]] || die "Backup is already encrypted." "$EXIT_VALIDATION"
  has_command gpg || die "GnuPG is required for AES-256 backup encryption." "$EXIT_SYSTEM"
  [[ -t 0 ]] || die "Encryption requires an interactive terminal so the passphrase is never exposed as an argument." "$EXIT_PERMISSION"
  encrypted="$archive.gpg"
  gpg --symmetric --cipher-algo AES256 --output "$encrypted" "$archive"
  [[ -s "$encrypted" ]] || die "Encrypted backup was not created." "$EXIT_SYSTEM"
  chmod 0600 "$encrypted"; rm -f -- "$archive"; LAST_BACKUP=$encrypted
  ok "Encrypted backup created: $encrypted (original removed)."
}

backup_restore() {
  require_root
  local name=${1:-}; [[ -n "$name" ]] || die "Backup filename is required." "$EXIT_INVALID_ARGUMENT"
  (($# == 1)) || die "backup restore accepts exactly one filename." "$EXIT_INVALID_ARGUMENT"
  local stage; resolve_backup "$name" >/dev/null
  confirm "Restore $name? Existing data may be replaced." "$name" || die "Cancelled." "$EXIT_GENERAL"
  stage=$(mktemp -d "$BACKUP_DIR/.restore.XXXXXX"); extract_verified_backup "$name" "$stage"
  if [[ -f "$stage/database.sql" && -f "$stage/record.conf" ]]; then
    restore_database_stage "$stage"
  elif [[ -f "$stage/config/record.conf" ]]; then
    restore_website_stage "$stage"
  else
    rm -rf -- "$stage"; die "Full restore is intentionally not automatic. Restore components from the verified archive during a maintenance window." "$EXIT_INVALID_ARGUMENT"
  fi
  rm -rf -- "$stage"; ok "Restore completed."
}

restore_database_stage() {
  local stage=$1 database db_user password sql_file
  database=$(record_get "$stage/record.conf" DATABASE); validate_db_name "$database" || die "Invalid database metadata in backup." "$EXIT_VALIDATION"
  database_exists "$database" && backup_create_database "$database"
  db_user="u_${database,,}"; db_user=${db_user:0:32}; password=$(generate_password)
  sql_file=$(mktemp "$STATE_DIR/.restore-db.XXXXXX.sql"); chmod 0600 "$sql_file"
  printf "DROP DATABASE IF EXISTS \`%s\`;\nCREATE DATABASE \`%s\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\nDROP USER IF EXISTS '%s'@'localhost';\nCREATE USER '%s'@'localhost' IDENTIFIED BY '%s';\nGRANT ALL PRIVILEGES ON \`%s\`.* TO '%s'@'localhost';\nFLUSH PRIVILEGES;\n" "$database" "$database" "$db_user" "$db_user" "$password" "$database" "$db_user" > "$sql_file"
  mariadb_execute_file "$sql_file" || { rm -f -- "$sql_file"; die "Unable to recreate database." "$EXIT_SYSTEM"; }
  rm -f -- "$sql_file"
  if [[ "$SERVERCTL_TEST_MODE" != 1 ]]; then mariadb --protocol=socket "$database" < "$stage/database.sql"; fi
  save_database_record "$database" "$db_user"
  ok "Database restored. Save the new credentials now; the password is not stored."
  printf 'Database: %s\nUser:     %s\nPassword: %s\nHost:     localhost\n' "$database" "$db_user" "$password"
}

restore_website_stage() {
  local stage=$1 record domain php user site_root csp upload_limit rate_burst static_cache
  record="$stage/config/record.conf"; domain=$(record_get "$record" DOMAIN); php=$(record_get "$record" PHP_VERSION); csp=$(record_get "$record" CSP || true)
  upload_limit=$(record_get "$record" UPLOAD_LIMIT || printf 32m); rate_burst=$(record_get "$record" RATE_BURST || printf 40); static_cache=$(record_get "$record" STATIC_CACHE || printf off)
  validate_site_name "$domain" || die "Invalid website metadata in backup." "$EXIT_VALIDATION"
  validate_php_version "$php" || die "Unsupported PHP metadata in backup." "$EXIT_VALIDATION"
  validate_csp "$csp" || csp="default-src 'self'; object-src 'none'; frame-ancestors 'self'; base-uri 'self'"
  [[ "$upload_limit" =~ ^[1-9][0-9]{0,3}[kKmMgG]$ ]] || upload_limit=32m; [[ "$rate_burst" =~ ^([1-9]|[1-9][0-9]|100)$ ]] || rate_burst=40; [[ "$static_cache" == on || "$static_cache" == off ]] || static_cache=off
  [[ -d "$stage/files/$domain" ]] || die "Website payload is missing." "$EXIT_VALIDATION"
  website_exists "$domain" && backup_create_website "$domain"
  user=$(website_user "$domain"); site_root="$WEB_ROOT/$domain"; assert_safe_web_path "$site_root"
  if [[ "$SERVERCTL_TEST_MODE" != 1 ]]; then getent passwd "$user" >/dev/null || run_cmd useradd --system --home-dir "$site_root" --shell /usr/sbin/nologin --user-group "$user"; fi
  rm -rf -- "$site_root"; mkdir -p -- "$WEB_ROOT"; cp -a -- "$stage/files/$domain" "$WEB_ROOT/"
  mkdir -p -- "$site_root/public" "$site_root/logs" "$site_root/tmp"
  prepare_php_socket_dir || die "Unable to prepare the PHP-FPM socket directory." "$EXIT_SYSTEM"
  mkdir -p -- "$(dirname "$(nginx_access_path "$domain")")"
  if [[ -f "$stage/config/access.conf" ]] && validate_nginx_access_file "$stage/config/access.conf"; then cp -- "$stage/config/access.conf" "$(nginx_access_path "$domain")"; chmod 0644 "$(nginx_access_path "$domain")"
  else atomic_write "$(nginx_access_path "$domain")" 0644 root root <<'EOF'
# Managed by serverctl. Open access.
allow all;
EOF
  fi
  touch "$site_root/logs/access.log" "$site_root/logs/error.log" "$site_root/logs/php-error.log"
  if [[ "$SERVERCTL_TEST_MODE" != 1 ]]; then
    chown -R "$user:$user" "$site_root"; chown "$user:www-data" "$site_root" "$site_root/public"; chown "root:$user" "$site_root/logs"
    chown "www-data:adm" "$site_root/logs/access.log" "$site_root/logs/error.log"; chown "$user:$user" "$site_root/logs/php-error.log"
    sftp_repair_content_permissions "$site_root/public"
    chmod 0750 "$site_root" "$site_root/logs" "$site_root/tmp"; chmod 2750 "$site_root/public"; chmod 0640 "$site_root/logs/"*.log
  fi
  render_php_pool "$domain" "$php" "$user"; render_nginx_site "$domain" "$php" no "$csp" "$upload_limit" "$rate_burst" "$static_cache"
  mkdir -p -- "$(nginx_enabled_dir)"; ln -sfn "$(nginx_available_dir)/$domain.conf" "$(nginx_enabled_dir)/$domain.conf"
  reload_web_stack "$php" || die "Restored files, but generated web configuration failed validation." "$EXIT_VALIDATION"
  save_website_record "$domain" "$php" "$user" no online; update_record_value "$(website_record_path "$domain")" CSP "$csp"
  update_record_value "$(website_record_path "$domain")" UPLOAD_LIMIT "$upload_limit"; update_record_value "$(website_record_path "$domain")" RATE_BURST "$rate_burst"; update_record_value "$(website_record_path "$domain")" STATIC_CACHE "$static_cache"
  if is_local_site "$domain"; then warn "Local/LAN website restored over HTTP."; else warn "Website restored over HTTP. Re-enable SSL after verifying DNS and certificate state."; fi
}

backup_delete() {
  require_root
  local name=${1:-}; [[ -n "$name" ]] || die "Backup filename is required." "$EXIT_INVALID_ARGUMENT"
  (($# == 1)) || die "backup delete accepts exactly one filename." "$EXIT_INVALID_ARGUMENT"
  local archive; archive=$(resolve_backup "$name"); confirm "Delete backup $name?" "$name" || die "Cancelled." "$EXIT_GENERAL"
  rm -f -- "$archive"; ok "Backup deleted: $name"
}

backup_sync() {
  require_root
  [[ -n "$REMOTE_BACKUP_TARGET" ]] || die "REMOTE_BACKUP_TARGET is not configured." "$EXIT_VALIDATION"
  validate_remote_backup_target "$REMOTE_BACKUP_TARGET" || die "Unsafe remote backup target." "$EXIT_VALIDATION"
  has_command rsync || die "rsync is not installed." "$EXIT_SYSTEM"
  run_cmd rsync -a --partial --chmod=F600,D700 -- "$BACKUP_DIR/" "$REMOTE_BACKUP_TARGET/"
  ok "Backups synchronized to the configured remote target."
}

backup_create_update_config() {
  require_root
  local directory stage source
  directory="$BACKUP_DIR/system-update/$(date '+%Y-%m-%d_%H%M%S_%N')"; mkdir -p -- "$BACKUP_DIR/system-update"; stage=$(mktemp -d "$BACKUP_DIR/system-update/.stage.XXXXXX")
  mkdir -p "$stage/config"
  for source in "$(root_path /etc/nginx)" "$(root_path /etc/php)" "$(root_path /etc/mysql)" "$(root_path /etc/serverctl)"; do [[ -d "$source" ]] && cp -a -- "$source" "$stage/config/"; done
  [[ -d "$STATE_DIR" ]] && cp -a -- "$STATE_DIR" "$stage/serverctl-state"
  if [[ "$SERVERCTL_TEST_MODE" == 1 ]]; then printf 'test-package 1.0\n' > "$stage/packages.txt"; else dpkg-query -W -f='${binary:Package}\t${Version}\n' > "$stage/packages.txt"; fi
  atomic_write "$stage/metadata" 0600 root root <<EOF
DATE=$(timestamp)
USER=${SUDO_USER:-${USER:-unknown}}
SOURCE_IP=$(client_ip)
UBUNTU=$(source /etc/os-release 2>/dev/null; printf '%s' "${VERSION_ID:-unknown}")
KERNEL=$(uname -r)
EOF
  create_manifest "$stage"; mv -- "$stage" "$directory"; chmod -R go-rwx "$directory"; LAST_UPDATE_BACKUP=$directory
  find "$BACKUP_DIR/system-update" -mindepth 1 -maxdepth 1 -type d -name '20??-??-??_*' -mtime "+$BACKUP_RETENTION" -print -exec rm -rf -- {} +
  audit_event 'system update configuration backup' SUCCESS "backup=$(basename "$directory")"; ok "Pre-update configuration backup: $directory"
}

prune_backups() { find "$BACKUP_DIR" -maxdepth 1 -type f \( -name 'serverctl-*.tar.gz' -o -name 'serverctl-*.tar.gz.gpg' \) -mtime "+$BACKUP_RETENTION" -print -delete; }
