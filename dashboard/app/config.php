<?php
declare(strict_types=1);

const DASHBOARD_APP_ROOT = __DIR__;
const DASHBOARD_ROOT = __DIR__ . '/..';
const DASHBOARD_PUBLIC_ROOT = DASHBOARD_ROOT . '/public';
const SERVERCTL_VERSION = '1.0.3';
const SERVERCTL_RELEASE_DATE = '2026-08-16';

$dashboard_config_file = getenv('SERVERCTL_DASHBOARD_CONFIG') ?: '/etc/serverctl/dashboard.conf';
$dashboard_config = [];
if (is_readable($dashboard_config_file)) {
    foreach (file($dashboard_config_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        if ($line === '' || str_starts_with(ltrim($line), '#')) {
            continue;
        }
        [$key, $value] = array_pad(explode('=', $line, 2), 2, '');
        if (preg_match('/^[A-Z][A-Z0-9_]*$/', $key)) {
            $dashboard_config[$key] = $value;
        }
    }
}

date_default_timezone_set('Asia/Bangkok');

function dashboard_config(string $key, mixed $default = null): mixed
{
    global $dashboard_config;
    return array_key_exists($key, $dashboard_config) ? $dashboard_config[$key] : $default;
}

function dashboard_is_configured(): bool
{
    return dashboard_config('DASHBOARD_ENABLED', '0') === '1'
        && dashboard_config('DASHBOARD_USER') !== null
        && dashboard_config('DASHBOARD_PASSWORD_HASH') !== null
        && dashboard_config('DASHBOARD_PASSWORD_HASH') !== '';
}

function dashboard_is_local_mode(): bool
{
    return strtolower((string) dashboard_config('DASHBOARD_LOCAL_ONLY', 'no')) === 'yes';
}

function dashboard_request_is_https(): bool
{
    return isset($_SERVER['HTTPS']) && strtolower((string) $_SERVER['HTTPS']) !== '' && strtolower((string) $_SERVER['HTTPS']) !== 'off';
}

function dashboard_state_dir(): string
{
    return '/var/lib/serverctl/dashboard';
}

function dashboard_cli(): string
{
    return getenv('SERVERCTL_DASHBOARD_CLI') ?: '/usr/local/bin/serverctl';
}
