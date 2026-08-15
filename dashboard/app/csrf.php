<?php
declare(strict_types=1);

require_once __DIR__ . '/auth.php';

function dashboard_csrf_token(): string
{
    dashboard_session_start();
    if (!isset($_SESSION['csrf_token']) || !is_string($_SESSION['csrf_token'])) {
        $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf_token'];
}

function dashboard_verify_csrf(): void
{
    dashboard_session_start();
    $provided = (string) ($_POST['csrf_token'] ?? $_SERVER['HTTP_X_CSRF_TOKEN'] ?? '');
    $stored = (string) ($_SESSION['csrf_token'] ?? '');
    if ($stored === '' || $provided === '' || !hash_equals($stored, $provided)) {
        dashboard_json_response(['status' => 'error', 'message' => 'Invalid CSRF token.'], 419);
    }
}
