#!/usr/bin/env bash

website_record_path() { printf '%s/websites/%s.conf' "$STATE_DIR" "$1"; }
database_record_path() { printf '%s/databases/%s.conf' "$STATE_DIR" "$1"; }
website_exists() { [[ -f "$(website_record_path "$1")" ]]; }
database_exists() { [[ -f "$(database_record_path "$1")" ]]; }

record_get() {
  local file=$1 wanted=$2 key value
  [[ -f "$file" ]] || return 1
  while IFS='=' read -r key value; do
    if [[ "$key" == "$wanted" ]]; then printf '%s' "$value"; return 0; fi
  done < "$file"
  return 1
}

save_website_record() {
  local domain=$1 php=$2 user=$3 ssl=${4:-no} status=${5:-online} sftp_enabled=${6:-no} document_root
  document_root=${7:-$WEB_ROOT/$domain/public}
  atomic_write "$(website_record_path "$domain")" 0640 root root <<EOF
DOMAIN=$domain
PHP_VERSION=$php
USER=$user
SSL=$ssl
STATUS=$status
DOCUMENT_ROOT=$document_root
CSP=default-src 'self'; object-src 'none'; frame-ancestors 'self'; base-uri 'self'
UPLOAD_LIMIT=32m
RATE_BURST=40
STATIC_CACHE=off
SFTP_ENABLED=$sftp_enabled
CREATED_AT=$(timestamp)
EOF
}

update_record_value() {
  local file=$1 wanted=$2 new_value=$3 temporary key value found=0
  temporary=$(mktemp "$(dirname "$file")/.record.XXXXXX")
  while IFS='=' read -r key value; do
    if [[ "$key" == "$wanted" ]]; then printf '%s=%s\n' "$key" "$new_value" >> "$temporary"; found=1
    else printf '%s=%s\n' "$key" "$value" >> "$temporary"; fi
  done < "$file"
  ((found)) || printf '%s=%s\n' "$wanted" "$new_value" >> "$temporary"
  chmod 0640 "$temporary"; mv -f -- "$temporary" "$file"
}

save_database_record() {
  local database=$1 user=$2
  atomic_write "$(database_record_path "$database")" 0640 root root <<EOF
DATABASE=$database
USER=$user
CREATED_AT=$(timestamp)
EOF
}
