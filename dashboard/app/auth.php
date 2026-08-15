<?php
declare(strict_types=1);

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/security.php';

function dashboard_session_start(): void
{
    if (session_status() === PHP_SESSION_ACTIVE) {
        return;
    }
    ini_set('session.use_strict_mode', '1');
    ini_set('session.use_only_cookies', '1');
    session_name('serverctl_dashboard');
    session_set_cookie_params([
        'lifetime' => 0,
        'path' => '/',
        'secure' => true,
        'httponly' => true,
        'samesite' => 'Strict',
    ]);
    session_start();
}

function dashboard_rate_file(): string
{
    return dashboard_state_dir() . '/login-rate.json';
}

function dashboard_rate_data(): array
{
    $file = dashboard_rate_file();
    if (!is_readable($file)) {
        return [];
    }
    $data = json_decode((string) file_get_contents($file), true);
    return is_array($data) ? $data : [];
}

function dashboard_save_rate_data(array $data): void
{
    $directory = dashboard_state_dir();
    if (!is_dir($directory)) {
        return;
    }
    @file_put_contents(dashboard_rate_file(), json_encode($data), LOCK_EX);
    @chmod(dashboard_rate_file(), 0640);
}

function dashboard_login_allowed(string $ip): bool
{
    $data = dashboard_rate_data();
    $now = time();
    $entry = $data[$ip] ?? ['attempts' => [], 'locked_until' => 0];
    return (int) ($entry['locked_until'] ?? 0) <= $now;
}

function dashboard_record_login_failure(string $ip): void
{
    $data = dashboard_rate_data();
    $now = time();
    $entry = $data[$ip] ?? ['attempts' => [], 'locked_until' => 0];
    $attempts = array_values(array_filter((array) ($entry['attempts'] ?? []), static fn ($item): bool => (int) $item > $now - 900));
    $attempts[] = $now;
    $data[$ip] = [
        'attempts' => $attempts,
        'locked_until' => count($attempts) >= 5 ? $now + 900 : 0,
    ];
    dashboard_save_rate_data($data);
}

function dashboard_record_login_success(string $ip): void
{
    $data = dashboard_rate_data();
    unset($data[$ip]);
    dashboard_save_rate_data($data);
}

function dashboard_login(string $username, string $password): bool
{
    dashboard_session_start();
    $ip = dashboard_client_ip();
    if (!dashboard_is_configured() || !dashboard_login_allowed($ip)) {
        dashboard_audit('LOGIN', 'BLOCKED', $username);
        return false;
    }
    $configured_user = (string) dashboard_config('DASHBOARD_USER', '');
    $hash = (string) dashboard_config('DASHBOARD_PASSWORD_HASH', '');
    if (!hash_equals($configured_user, $username) || !password_verify($password, $hash)) {
        dashboard_record_login_failure($ip);
        dashboard_audit('LOGIN', 'FAILED', $username);
        return false;
    }
    session_regenerate_id(true);
    $_SESSION['user'] = $configured_user;
    $_SESSION['role'] = 'admin';
    $_SESSION['last_activity'] = time();
    dashboard_record_login_success($ip);
    dashboard_audit('LOGIN', 'SUCCESS');
    return true;
}

function dashboard_logged_in(): bool
{
    dashboard_session_start();
    if (!isset($_SESSION['user'], $_SESSION['last_activity'])) {
        return false;
    }
    $timeout = max(300, min(7200, (int) dashboard_config('DASHBOARD_SESSION_TIMEOUT', '1800')));
    if ((int) $_SESSION['last_activity'] + $timeout < time()) {
        dashboard_logout();
        return false;
    }
    $_SESSION['last_activity'] = time();
    return true;
}

function dashboard_require_login(bool $json = false): void
{
    dashboard_require_https();
    if (dashboard_logged_in()) {
        return;
    }
    if ($json) {
        dashboard_json_response(['status' => 'error', 'message' => 'Authentication required.'], 401);
    }
    header('Location: login.php');
    exit;
}

function dashboard_require_admin(bool $json = false): void
{
    dashboard_require_login($json);
    if (($_SESSION['role'] ?? '') !== 'admin') {
        if ($json) {
            dashboard_json_response(['status' => 'error', 'message' => 'Administrator permission required.'], 403);
        }
        http_response_code(403);
        exit('Administrator permission required.');
    }
}

function dashboard_logout(): void
{
    dashboard_session_start();
    $_SESSION = [];
    if (ini_get('session.use_cookies')) {
        $params = session_get_cookie_params();
        setcookie(session_name(), '', time() - 42000, $params['path'], $params['domain'] ?? '', true, true);
    }
    session_destroy();
}
