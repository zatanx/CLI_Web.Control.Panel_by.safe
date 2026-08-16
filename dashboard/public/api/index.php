<?php
declare(strict_types=1);

require_once dirname(__DIR__, 2) . '/app/functions.php';

dashboard_security_headers();
dashboard_require_login(true);

$resource = (string) ($_GET['resource'] ?? 'snapshot');

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    try {
        if ($resource === 'snapshot') {
            dashboard_json_response(dashboard_json_command('snapshot'));
        }
        if ($resource === 'websites') {
            dashboard_json_response(dashboard_json_command('websites'));
        }
        if ($resource === 'events') {
            dashboard_json_response(['status' => 'success', 'data' => dashboard_recent_events()]);
        }
        if ($resource === 'logs') {
            $type = (string) ($_GET['type'] ?? 'nginx-error');
            $limit = (string) ($_GET['limit'] ?? '100');
            $search = (string) ($_GET['search'] ?? '');
            $result = dashboard_command('logs', [$type, $limit, $search]);
            if ($result['code'] !== 0) {
                throw new RuntimeException('Log data is currently unavailable.');
            }
            $lines = array_values(array_filter(explode("\n", $result['stdout']), static fn (string $line): bool => $line !== ''));
            dashboard_json_response(['status' => 'success', 'data' => $lines]);
        }
        dashboard_json_response(['status' => 'error', 'message' => 'Unknown dashboard resource.'], 404);
    } catch (Throwable $exception) {
        dashboard_json_response(['status' => 'error', 'message' => $exception->getMessage()], 503);
    }
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    dashboard_json_response(['status' => 'error', 'message' => 'Method not allowed.'], 405);
}

dashboard_require_admin(true);
dashboard_verify_csrf();

if (dashboard_config('DASHBOARD_READ_ONLY', '0') === '1') {
    dashboard_json_response(['status' => 'error', 'message' => 'Dashboard is in read-only mode.'], 403);
}

$action = (string) ($_POST['action'] ?? '');
$target = (string) ($_POST['target'] ?? '');
$provider = (string) ($_POST['provider'] ?? '');
$site_key = (string) ($_POST['site_key'] ?? '');
$secret = (string) ($_POST['secret'] ?? '');
$requires_confirmation = in_array($action, [
    'nginx-restart', 'firewall-reload', 'backup-all', 'update-check',
    'fail2ban-unban', 'backup-restore', 'website-remove', 'database-remove', 'bot-protection-set',
], true);
if ($requires_confirmation && (string) ($_POST['confirmed'] ?? '') !== '1') {
    dashboard_json_response(['status' => 'error', 'message' => 'Confirmation is required for this action.'], 409);
}

$arguments = $action === 'bot-protection-set'
    ? [$action, $provider, $site_key, '--secret', $secret]
    : ($target === '' ? [$action] : [$action, $target]);
try {
    $result = dashboard_command('action', $arguments, true);
    $success = $result['code'] === 0;
    dashboard_audit($action, $success ? 'SUCCESS' : 'FAILED', $target);
    if (!$success) {
        dashboard_json_response(['status' => 'error', 'message' => 'The requested action failed.', 'output' => trim($result['stderr'])], 422);
    }
    dashboard_json_response(['status' => 'success', 'message' => 'Action completed.', 'output' => trim($result['stdout'])]);
} catch (Throwable $exception) {
    dashboard_audit($action, 'REJECTED', $target);
    dashboard_json_response(['status' => 'error', 'message' => $exception->getMessage()], 422);
}
