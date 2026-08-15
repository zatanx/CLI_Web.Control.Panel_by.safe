#!/usr/bin/env bash

cmd_database() {
  local sub=${1:-}; shift || true
  case "$sub" in list) (($# == 0)) || die "database list accepts no arguments." "$EXIT_INVALID_ARGUMENT"; database_list ;; create) database_create "$@" ;; remove) database_remove "$@" ;; health) database_health "$@" ;; *) die "Usage: serverctl database <list|create|remove|health>" "$EXIT_INVALID_ARGUMENT" ;; esac
}

database_health() {
  local database=${1:-} query
  (($# <= 1)) || die "database health accepts at most one database name." "$EXIT_INVALID_ARGUMENT"
  service_is_active mariadb || die "MariaDB is not running." "$EXIT_SYSTEM"
  if [[ -n "$database" ]]; then validate_db_name "$database" || die "Invalid database name." "$EXIT_VALIDATION"; database_exists "$database" || die "Database not found." "$EXIT_VALIDATION"; fi
  query="SELECT VARIABLE_NAME, VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME IN ('THREADS_CONNECTED','SLOW_QUERIES');"
  mariadb --protocol=socket --batch --skip-column-names -e "$query"
  if [[ -n "$database" ]]; then
    mariadb --protocol=socket --batch --skip-column-names -e "SELECT TABLE_SCHEMA, ROUND(SUM(DATA_LENGTH+INDEX_LENGTH)/1024/1024,2) AS SIZE_MB FROM information_schema.TABLES WHERE TABLE_SCHEMA='$database' GROUP BY TABLE_SCHEMA;"
  else
    mariadb --protocol=socket --batch --skip-column-names -e "SELECT ROUND(SUM(DATA_LENGTH+INDEX_LENGTH)/1024/1024,2) AS TOTAL_MB FROM information_schema.TABLES;"
  fi
  df -h "$(root_path /var/lib/mysql)" | tail -1
}

database_list() {
  printf '%-32s %-32s %s\n' DATABASE USER CREATED_AT
  local file
  shopt -s nullglob
  for file in "$STATE_DIR"/databases/*.conf; do
    printf '%-32s %-32s %s\n' "$(record_get "$file" DATABASE)" "$(record_get "$file" USER)" "$(record_get "$file" CREATED_AT)"
  done
  shopt -u nullglob
}

database_create() {
  require_root
  local database=${1:-} db_user password sql_file
  (($# == 1)) && [[ -n "$database" ]] || die "Database name is required and no extra arguments are allowed." "$EXIT_INVALID_ARGUMENT"
  validate_db_name "$database" || die "Database name must start with a letter and contain only letters, numbers, or underscore (max 48)." "$EXIT_VALIDATION"
  database_exists "$database" && die "Database already exists in serverctl." "$EXIT_VALIDATION"
  confirm "Create database $database and a restricted user?" || die "Cancelled." "$EXIT_GENERAL"
  db_user="u_${database,,}"; db_user=${db_user:0:32}
  password=$(generate_password)
  sql_file=$(mktemp "$STATE_DIR/.database.XXXXXX.sql"); chmod 0600 "$sql_file"
  printf "CREATE DATABASE \`%s\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\nCREATE USER '%s'@'localhost' IDENTIFIED BY '%s';\nGRANT ALL PRIVILEGES ON \`%s\`.* TO '%s'@'localhost';\nFLUSH PRIVILEGES;\n" "$database" "$db_user" "$password" "$database" "$db_user" > "$sql_file"
  if ! mariadb_execute_file "$sql_file"; then rm -f -- "$sql_file"; die "MariaDB rejected the create request." "$EXIT_SYSTEM"; fi
  rm -f -- "$sql_file"
  save_database_record "$database" "$db_user"
  audit_event "database create $database" SUCCESS
  ok "Database created. Save these credentials now; the password is not stored by serverctl."
  printf 'Database: %s\nUser:     %s\nPassword: %s\nHost:     localhost\n' "$database" "$db_user" "$password"
}

database_remove() {
  require_root
  local database=${1:-} no_backup=0; [[ -n "$database" ]] || die "Database name is required." "$EXIT_INVALID_ARGUMENT"; shift || true
  while (($#)); do case "$1" in --no-backup) no_backup=1 ;; *) die "Unknown database remove argument: $1" "$EXIT_INVALID_ARGUMENT" ;; esac; shift; done
  validate_db_name "$database" || die "Invalid database name." "$EXIT_VALIDATION"
  database_exists "$database" || die "Database not found." "$EXIT_VALIDATION"
  local record db_user sql_file
  record=$(database_record_path "$database"); db_user=$(record_get "$record" USER)
  [[ "$db_user" =~ ^u_[a-z0-9_]{1,30}$ ]] || die "Invalid database user metadata." "$EXIT_VALIDATION"
  if ((no_backup == 0)); then backup_create_database "$database"; fi
  confirm "Permanently drop database $database?" "$database" || die "Cancelled." "$EXIT_GENERAL"
  sql_file=$(mktemp "$STATE_DIR/.database.XXXXXX.sql"); chmod 0600 "$sql_file"
  printf "DROP DATABASE IF EXISTS \`%s\`;\nDROP USER IF EXISTS '%s'@'localhost';\nFLUSH PRIVILEGES;\n" "$database" "$db_user" > "$sql_file"
  mariadb_execute_file "$sql_file" || { rm -f -- "$sql_file"; die "MariaDB rejected the drop request." "$EXIT_SYSTEM"; }
  rm -f -- "$sql_file" "$record"; ok "Database removed: $database"
}

generate_password() {
  if has_command openssl; then openssl rand -base64 32 | tr -d '/+=' | cut -c1-32
  else LC_ALL=C tr -dc 'A-Za-z0-9_@#%-' < /dev/urandom | head -c 32; fi
}

mariadb_execute_file() {
  local sql_file=$1
  log_message INFO "run: mariadb < [REDACTED_SQL_FILE]"
  [[ "$SERVERCTL_TEST_MODE" == 1 ]] && return 0
  mariadb --protocol=socket < "$sql_file"
}
