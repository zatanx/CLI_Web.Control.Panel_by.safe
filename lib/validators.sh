#!/usr/bin/env bash

validate_domain() {
  local domain=${1,,}
  ((${#domain} <= 253)) || return 1
  [[ "$domain" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] || return 1
  [[ "$domain" != *..* ]]
}

validate_site_name() {
  local site=${1,,}
  [[ "$site" == localhost ]] && return 0
  if [[ "$site" != *:* ]] && validate_ip "$site"; then return 0; fi
  validate_domain "$site"
}

validate_web_folder() {
  local folder=${1:-}
  [[ -z "$folder" || "$folder" == . ]] && return 0
  [[ "$folder" != /* && "$folder" != */ && "$folder" != *'..'* ]] || return 1
  [[ "$folder" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*$ ]]
}

web_document_root() {
  local domain=$1 folder=${2:-} base
  base="$WEB_ROOT/$domain/public"
  [[ -z "$folder" || "$folder" == . ]] && printf '%s' "$base" || printf '%s/%s' "$base" "$folder"
}

is_local_site() {
  local site=${1,,} first second
  [[ "$site" == localhost ]] && return 0
  [[ "$site" != *:* ]] && validate_ip "$site" || return 1
  IFS=. read -r first second _ <<< "$site"
  ((first == 10)) && return 0
  ((first == 127)) && return 0
  ((first == 192 && second == 168)) && return 0
  ((first == 172 && second >= 16 && second <= 31))
}

validate_php_version() { [[ " $ALLOWED_PHP_VERSIONS " == *" $1 "* && "$1" =~ ^[0-9]+\.[0-9]+$ ]]; }
validate_db_name() { [[ "$1" =~ ^[A-Za-z][A-Za-z0-9_]{0,47}$ ]]; }
validate_backup_name() { [[ "$1" =~ ^serverctl-[A-Za-z0-9_.-]+\.(tar\.gz|tar\.gz\.gpg)$ ]] && [[ "$1" != *..* ]]; }
validate_email() { [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}$ ]]; }

validate_ip() {
  local ip=$1 part
  if [[ "$ip" == *:* ]]; then [[ "$ip" =~ ^[0-9A-Fa-f:]+$ ]] && [[ "$ip" == *:* ]]; return; fi
  IFS=. read -r -a parts <<< "$ip"
  ((${#parts[@]} == 4)) || return 1
  for part in "${parts[@]}"; do [[ "$part" =~ ^[0-9]{1,3}$ ]] && ((10#$part <= 255)) || return 1; done
}

validate_port() { [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535)); }
validate_protocol() { [[ "$1" == tcp || "$1" == udp ]]; }

validate_cidr() {
  local cidr=$1 address prefix
  [[ "$cidr" == */* ]] || { validate_ip "$cidr"; return; }
  address=${cidr%/*}; prefix=${cidr##*/}
  validate_ip "$address" || return 1
  [[ "$prefix" =~ ^[0-9]+$ ]] || return 1
  if [[ "$address" == *:* ]]; then ((10#$prefix <= 128)); else ((10#$prefix <= 32)); fi
}

validate_remote_backup_target() {
  local target=$1
  [[ "$target" != *$'\n'* && "$target" != *$'\r'* && "$target" != *'/../'* && "$target" != */.. && "$target" != *'//'* ]] || return 1
  [[ "$target" =~ ^[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:/[A-Za-z0-9._/~/-]+$ || "$target" =~ ^/(mnt|media|srv)/[A-Za-z0-9._/-]+$ ]]
}

validate_backup_path() {
  [[ "$1" != *'/../'* && "$1" != */.. && "$1" != *'//'* ]] || return 1
  [[ "$1" == /var/backups/serverctl || "$1" =~ ^/(mnt|media)/[A-Za-z0-9._/-]+$ || "$1" =~ ^/srv/backups/[A-Za-z0-9._/-]+$ ]]
}

validate_csp() {
  local policy=$1
  ((${#policy} >= 1 && ${#policy} <= 1024)) || return 1
  [[ "$policy" =~ ^[[:print:]]+$ && "$policy" != *$'\n'* && "$policy" != *$'\r'* && "$policy" != *'"'* && "$policy" != *'\\'* ]]
}

validate_nginx_access_file() {
  local file=$1 line value
  [[ -f "$file" ]] || return 1
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == '# Managed by serverctl.'* || "$line" == '# serverctl-access-mode: '* ]] && continue
    if [[ "$line" =~ ^(allow|deny)[[:space:]]+([^;]+)\;$ ]]; then value=${BASH_REMATCH[2]}; [[ "$value" == all ]] || validate_cidr "$value" || return 1
    else return 1; fi
  done < "$file"
}

safe_basename() {
  local value=$1
  [[ "$value" == "$(basename -- "$value")" && "$value" != . && "$value" != .. ]]
}

website_user() {
  local domain=$1 label digest
  label=${domain%%.*}; label=${label//[^a-z0-9]/_}; label=${label:0:16}
  if has_command sha256sum; then digest=$(printf '%s' "$domain" | sha256sum | cut -c1-6); else digest=$(printf '%s' "$domain" | cksum | cut -d' ' -f1 | cut -c1-6); fi
  printf 'web_%s_%s' "$label" "$digest"
}

assert_safe_web_path() {
  local path=$1 normalized_root=${WEB_ROOT%/}
  [[ "$path" == "$normalized_root/"* && "$path" != *'/../'* && "$path" != *'/./'* ]] || die "Unsafe web path: $path" "$EXIT_VALIDATION"
}
