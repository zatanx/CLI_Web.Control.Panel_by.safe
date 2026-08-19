#!/usr/bin/env bash

nginx_available_dir() { root_path /etc/nginx/sites-available; }
nginx_enabled_dir() { root_path /etc/nginx/sites-enabled; }
php_pool_dir() { root_path "/etc/php/$1/fpm/pool.d"; }
php_socket_dir() { root_path /run/php/serverctl; }
php_socket_path() { root_path "/run/php/serverctl/$1.sock"; }
nginx_access_path() { root_path "/etc/nginx/snippets/serverctl-access-$1.conf"; }

prepare_php_socket_dir() {
  local directory
  directory=$(php_socket_dir)
  mkdir -p -- "$directory"
  if [[ "$SERVERCTL_TEST_MODE" != 1 ]]; then
    # serverctl runs with umask 077, but Nginx must traverse this directory
    # to connect to the per-site PHP-FPM sockets inside it.
    chown root:root "$directory"
    chmod 0755 "$directory"
  fi
}

render_php_pool() {
  local domain=$1 version=$2 user=$3 destination
  destination="$(php_pool_dir "$version")/$domain.conf"
  atomic_write "$destination" 0640 root root <<EOF
; Managed by serverctl. Manual changes may be overwritten.
[$domain]
user = $user
group = $user
listen = $(php_socket_path "$domain")
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = ondemand
pm.max_children = 8
pm.process_idle_timeout = 10s
pm.max_requests = 500
request_terminate_timeout = 120s
catch_workers_output = yes
php_admin_flag[display_errors] = off
php_admin_flag[log_errors] = on
php_admin_flag[expose_php] = off
php_admin_flag[allow_url_include] = off
php_admin_flag[session.cookie_httponly] = on
php_admin_flag[session.cookie_secure] = on
php_admin_flag[session.use_strict_mode] = on
php_admin_value[error_log] = $WEB_ROOT/$domain/logs/php-error.log
php_admin_value[open_basedir] = $WEB_ROOT/$domain:/tmp:/usr/share/php
php_admin_value[upload_tmp_dir] = $WEB_ROOT/$domain/tmp
php_admin_value[session.save_path] = $WEB_ROOT/$domain/tmp
EOF
}

render_nginx_site() {
  local domain=$1 version=$2 ssl=$3 csp=${4:-"default-src 'self'; object-src 'none'; frame-ancestors 'self'; base-uri 'self'"}
  local upload_limit=${5:-32m} rate_burst=${6:-40} static_cache=${7:-off} destination=${8:-"$(nginx_available_dir)/$domain.conf"} cert_root static_block="" access_file
  if [[ "$static_cache" == on ]]; then static_block='    location ~* \.(jpg|jpeg|png|gif|svg|css|js|woff2)$ { expires 7d; add_header Cache-Control "public, immutable"; }'; fi
  cert_root="$(root_path /etc/letsencrypt/live)/$domain"
  access_file=$(nginx_access_path "$domain")
  if [[ "$ssl" == yes ]]; then
    atomic_write "$destination" 0644 root root <<EOF
# Managed by serverctl. Manual changes may be overwritten.
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    location ^~ /.well-known/acme-challenge/ { root $WEB_ROOT/$domain/public; allow all; }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain;
    root $WEB_ROOT/$domain/public;
    index index.php index.html;
    autoindex off;
    disable_symlinks if_not_owner from=\$document_root;
    if (\$host != \$server_name) { return 444; }

    ssl_certificate $cert_root/fullchain.pem;
    ssl_certificate_key $cert_root/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_timeout 1d;
    ssl_session_cache shared:serverctl_tls:10m;
    ssl_session_tickets off;

    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
    add_header Content-Security-Policy "$csp" always;
    add_header Strict-Transport-Security "max-age=31536000" always;

    client_max_body_size $upload_limit;
    access_log $WEB_ROOT/$domain/logs/access.log;
    error_log $WEB_ROOT/$domain/logs/error.log warn;
    include $access_file;

$static_block
    location / {
        limit_req zone=serverctl_per_ip burst=$rate_burst nodelay;
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location ~* ^/(uploads?|files?)/.*\.php$ { deny all; }
    location ~ (^|/)\. { deny all; access_log off; log_not_found off; }
    location ~* /(\.env|\.gitignore|config\.php|composer\.(json|lock))$ { deny all; }
    location ~* \.(sql|log)$ { deny all; }
    location ~ \.php$ {
        try_files \$uri =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_pass unix:$(php_socket_path "$domain");
    }
}
EOF
  else
    atomic_write "$destination" 0644 root root <<EOF
# Managed by serverctl. Manual changes may be overwritten.
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    root $WEB_ROOT/$domain/public;
    index index.php index.html;
    autoindex off;
    disable_symlinks if_not_owner from=\$document_root;

    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
    add_header Content-Security-Policy "$csp" always;

    client_max_body_size $upload_limit;
    access_log $WEB_ROOT/$domain/logs/access.log;
    error_log $WEB_ROOT/$domain/logs/error.log warn;
    include $access_file;
    location ^~ /.well-known/acme-challenge/ { allow all; }
$static_block
    location / {
        limit_req zone=serverctl_per_ip burst=$rate_burst nodelay;
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location ~* ^/(uploads?|files?)/.*\.php$ { deny all; }
    location ~ (^|/)\. { deny all; access_log off; log_not_found off; }
    location ~* /(\.env|\.gitignore|config\.php|composer\.(json|lock))$ { deny all; }
    location ~* \.(sql|log)$ { deny all; }
    location ~ \.php$ {
        try_files \$uri =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_pass unix:$(php_socket_path "$domain");
    }
}
EOF
  fi
}

validate_nginx() { [[ "$SERVERCTL_TEST_MODE" == 1 ]] || nginx -t; }
validate_php_fpm() { local version=$1; [[ "$SERVERCTL_TEST_MODE" == 1 ]] || "php-fpm$version" -t; }

reload_web_stack() {
  local version=$1
  validate_php_fpm "$version" || return "$EXIT_VALIDATION"
  validate_nginx || return "$EXIT_VALIDATION"
  run_cmd systemctl reload "php$version-fpm"
  run_cmd systemctl reload nginx
}
