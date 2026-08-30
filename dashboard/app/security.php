<?php
declare(strict_types=1);

function h(mixed $value): string
{
    return htmlspecialchars((string) $value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function dashboard_security_headers(): void
{
    if (headers_sent()) {
        return;
    }
    header('X-Content-Type-Options: nosniff');
    header('X-Frame-Options: DENY');
    header('Referrer-Policy: no-referrer');
    header('Permissions-Policy: camera=(), microphone=(), geolocation=()');
    $script_sources = "'self'";
    $connect_sources = "'self'";
    $frame_sources = "'self'";
    $image_sources = "'self' data:";
    if (function_exists('dashboard_bot_login_enabled') && dashboard_bot_login_enabled()) {
        $provider = dashboard_bot_provider();
        if ($provider === 'recaptcha_v3') {
            $script_sources .= ' https://www.google.com/recaptcha/ https://www.gstatic.com/recaptcha/';
            $connect_sources .= ' https://www.google.com/recaptcha/';
            $frame_sources .= ' https://www.google.com/recaptcha/';
            $image_sources .= ' https://www.google.com/recaptcha/ https://www.gstatic.com/recaptcha/';
        } elseif ($provider === 'turnstile') {
            $script_sources .= ' https://challenges.cloudflare.com';
            $connect_sources .= ' https://challenges.cloudflare.com';
            $frame_sources .= ' https://challenges.cloudflare.com';
        }
    }
    header(sprintf(
        "Content-Security-Policy: default-src 'self'; style-src 'self'; script-src %s; connect-src %s; frame-src %s; img-src %s; frame-ancestors 'none'; base-uri 'self'; form-action 'self'",
        $script_sources,
        $connect_sources,
        $frame_sources,
        $image_sources
    ));
    if (!dashboard_is_local_mode() && dashboard_request_is_https()) {
        header('Strict-Transport-Security: max-age=31536000');
    }
    header('Cache-Control: no-store');
}

function dashboard_json_response(array $payload, int $status = 200): never
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE);
    exit;
}

function dashboard_client_ip(): string
{
    $ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
    return filter_var($ip, FILTER_VALIDATE_IP) ? $ip : 'unknown';
}

function dashboard_audit(string $action, string $result, string $target = ''): void
{
    $target = preg_replace('/[\r\n\t]+/', ' ', $target) ?? '';
    $target = substr($target, 0, 200);
    $line = sprintf(
        "%s\t%s\t%s\t%s\t%s\n",
        date('c'),
        (string) (dashboard_config('DASHBOARD_USER', 'unknown')),
        dashboard_client_ip(),
        substr(preg_replace('/[\r\n\t]+/', ' ', $action) ?? '', 0, 100),
        substr(preg_replace('/[\r\n\t]+/', ' ', $result) ?? '', 0, 40) . ($target !== '' ? "\t$target" : '')
    );
    $directory = dashboard_state_dir();
    if (is_dir($directory) && is_writable($directory)) {
        @file_put_contents($directory . '/audit.log', $line, FILE_APPEND | LOCK_EX);
    }
}

function dashboard_require_https(): void
{
    if (dashboard_is_local_mode()) {
        return;
    }
    if (!dashboard_request_is_https()) {
        http_response_code(400);
        exit('HTTPS is required.');
    }
}
