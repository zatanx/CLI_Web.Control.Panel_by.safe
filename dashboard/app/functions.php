<?php
declare(strict_types=1);

require_once __DIR__ . '/csrf.php';

function dashboard_command(string $operation, array $arguments = [], bool $assume_yes = false): array
{
    $read_operations = ['snapshot', 'websites', 'fail2ban', 'cron', 'cron-status'];
    if (!in_array($operation, $read_operations, true) && $operation !== 'logs' && $operation !== 'cron-logs' && $operation !== 'action') {
        throw new RuntimeException('Dashboard operation is not allowed.');
    }
    if ($operation === 'logs') {
        if (count($arguments) !== 3 || !in_array($arguments[0], ['nginx-access', 'nginx-error', 'system', 'security', 'audit'], true)) {
            throw new RuntimeException('Invalid log request.');
        }
        if (!in_array((string) $arguments[1], ['50', '100', '500'], true)) {
            throw new RuntimeException('Invalid log limit.');
        }
        if (strlen((string) $arguments[2]) > 200 || preg_match('/[\r\n]/', (string) $arguments[2])) {
            throw new RuntimeException('Invalid log search.');
        }
    }
    if ($operation === 'cron-logs') {
        if (count($arguments) !== 2 || !preg_match('/^[1-9][0-9]{0,8}$/', (string) $arguments[0]) || !in_array((string) $arguments[1], ['50', '100', '500'], true)) {
            throw new RuntimeException('Invalid Cron log request.');
        }
    }
    if ($operation === 'action') {
        $action = $arguments[0] ?? '';
        $allowed = [
            'nginx-reload' => 0,
            'nginx-restart' => 0,
            'firewall-reload' => 0,
            'backup-all' => 0,
            'update-check' => 0,
            'fail2ban-unban' => 1,
            'backup-restore' => 1,
            'website-remove' => 1,
            'database-remove' => 1,
            'bot-protection-set' => 4,
            'cron-add-website' => 5,
            'cron-edit-website' => 6,
            'cron-enable' => 1,
            'cron-disable' => 1,
            'cron-run' => 1,
            'cron-delete' => 1,
        ];
        if (!array_key_exists($action, $allowed) || count($arguments) - 1 !== $allowed[$action]) {
            throw new RuntimeException('Invalid dashboard action.');
        }
        if ($action === 'fail2ban-unban' && !filter_var($arguments[1], FILTER_VALIDATE_IP)) {
            throw new RuntimeException('Invalid IP address.');
        }
        if ($action === 'website-remove' && !preg_match('/^([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/i', $arguments[1])) {
            throw new RuntimeException('Invalid domain.');
        }
        if ($action === 'database-remove' && !preg_match('/^[A-Za-z][A-Za-z0-9_]{0,47}$/', $arguments[1])) {
            throw new RuntimeException('Invalid database name.');
        }
        if ($action === 'backup-restore' && !preg_match('/^serverctl-[A-Za-z0-9_.-]+\.tar\.gz(?:\.gpg)?$/', $arguments[1])) {
            throw new RuntimeException('Invalid backup name.');
        }
        if ($action === 'bot-protection-set') {
            $provider = (string) ($arguments[1] ?? '');
            $site_key = (string) ($arguments[2] ?? '');
            $secret_flag = (string) ($arguments[3] ?? '');
            $secret = (string) ($arguments[4] ?? '');
            if (!in_array($provider, ['none', 'recaptcha_v3', 'turnstile'], true) || $secret_flag !== '--secret') {
                throw new RuntimeException('Invalid bot-protection provider.');
            }
            if (strlen($site_key) > 512 || strlen($secret) > 512 || preg_match('/[\r\n=]/', $site_key . $secret)) {
                throw new RuntimeException('Invalid bot-protection key.');
            }
            if ($provider === 'none') {
                if ($site_key !== '' || $secret !== '') {
                    throw new RuntimeException('Disabled bot protection must not include keys.');
                }
            } elseif ($site_key === '' || $secret === '') {
                throw new RuntimeException('A site key and secret are required.');
            }
        }
        if (in_array($action, ['cron-enable', 'cron-disable', 'cron-run', 'cron-delete'], true)) {
            if (!preg_match('/^[1-9][0-9]{0,8}$/', (string) $arguments[1])) {
                throw new RuntimeException('Invalid Cron job ID.');
            }
        }
        if ($action === 'cron-add-website' || $action === 'cron-edit-website') {
            $offset = $action === 'cron-add-website' ? 1 : 2;
            $website = (string) ($arguments[$offset] ?? '');
            $schedule = (string) ($arguments[$offset + 1] ?? '');
            $script = (string) ($arguments[$offset + 2] ?? '');
            $description = (string) ($arguments[$offset + 3] ?? '');
            $enabled = (string) ($arguments[$offset + 4] ?? '');
            if (!preg_match('/^([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/i', $website)) {
                throw new RuntimeException('Invalid website.');
            }
            if (strlen($schedule) > 100 || preg_match('/[\r\n]/', $schedule) || !preg_match('/^[0-9*\/, -]+$/', $schedule)) {
                throw new RuntimeException('Invalid Cron schedule.');
            }
            if (!preg_match('/^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/', $script)) {
                throw new RuntimeException('Invalid Cron script.');
            }
            if (strlen($description) > 200 || preg_match('/[\r\n\t]/', $description)) {
                throw new RuntimeException('Invalid Cron description.');
            }
            if (!in_array($enabled, ['yes', 'no'], true)) {
                throw new RuntimeException('Invalid Cron status.');
            }
        }
    }

    $command = ['/usr/bin/sudo', '-n', dashboard_cli()];
    if ($assume_yes) {
        $command[] = '--yes';
    }
    $command[] = 'dashboard';
    $command[] = $operation;
    foreach ($arguments as $argument) {
        $command[] = (string) $argument;
    }

    $descriptors = [1 => ['pipe', 'w'], 2 => ['pipe', 'w']];
    $process = proc_open($command, $descriptors, $pipes);
    if (!is_resource($process)) {
        throw new RuntimeException('Unable to start server manager.');
    }
    $stdout = stream_get_contents($pipes[1]);
    $stderr = stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    $exit_code = proc_close($process);
    return ['code' => $exit_code, 'stdout' => (string) $stdout, 'stderr' => (string) $stderr];
}

function dashboard_json_command(string $operation): array
{
    $result = dashboard_command($operation);
    if ($result['code'] !== 0) {
        $detail = trim((string) $result['stderr']);
        $detail = preg_replace('/\s+/', ' ', $detail) ?: '';
        $detail = substr($detail, 0, 1000);
        error_log(sprintf('[serverctl-dashboard] %s failed with exit code %d: %s', $operation, $result['code'], $detail));
        $message = 'Server status is currently unavailable.';
        if ($detail !== '') {
            $message .= sprintf(' serverctl error: %s', $detail);
        }
        throw new RuntimeException($message);
    }
    $decoded = json_decode($result['stdout'], true);
    if (!is_array($decoded)) {
        error_log(sprintf('[serverctl-dashboard] %s returned invalid JSON: %s', $operation, substr(trim($result['stdout']), 0, 1000)));
        throw new RuntimeException('Server manager returned invalid data.');
    }
    return $decoded;
}

function dashboard_recent_events(int $limit = 12): array
{
    $file = dashboard_state_dir() . '/audit.log';
    if (!is_readable($file)) {
        return [];
    }
    $lines = array_slice(file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [], -max(1, min(50, $limit)));
    $events = [];
    foreach ($lines as $line) {
        $parts = explode("\t", $line, 5);
        $events[] = [
            'time' => $parts[0] ?? '',
            'user' => $parts[1] ?? '',
            'ip' => $parts[2] ?? '',
            'action' => $parts[3] ?? '',
            'result' => $parts[4] ?? '',
        ];
    }
    return array_reverse($events);
}
