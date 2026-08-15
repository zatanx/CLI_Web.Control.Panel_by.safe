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
    header("Content-Security-Policy: default-src 'self'; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'");
    header('Strict-Transport-Security: max-age=31536000');
    header('Cache-Control: no-store');
}

function dashboard_json_response(array $payload, int $status = 200): never
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
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
    if (($_SERVER['HTTPS'] ?? '') === '' || strtolower((string) $_SERVER['HTTPS']) === 'off') {
        http_response_code(400);
        exit('HTTPS is required.');
    }
}
