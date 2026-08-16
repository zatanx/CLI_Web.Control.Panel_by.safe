<?php
declare(strict_types=1);

const DASHBOARD_APP_ROOT = __DIR__;
const DASHBOARD_ROOT = __DIR__ . '/..';
const DASHBOARD_PUBLIC_ROOT = DASHBOARD_ROOT . '/public';
const SERVERCTL_VERSION = '1.1.10';
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

function dashboard_request_host(): string
{
    $host = strtolower(trim((string) ($_SERVER['HTTP_HOST'] ?? '')));
    if ($host === '') {
        return '';
    }
    if (str_starts_with($host, '[')) {
        $end = strpos($host, ']');
        $host = $end === false ? $host : substr($host, 1, $end - 1);
    } else {
        $host = preg_replace('/:\\d+$/', '', $host) ?? $host;
    }
    return rtrim($host, '.');
}

function dashboard_request_is_local_host(): bool
{
    $host = dashboard_request_host();
    if ($host === 'localhost' || str_ends_with($host, '.localhost')) {
        return true;
    }
    if (filter_var($host, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) !== false) {
        $address = ip2long($host);
        return $address !== false && (
            ($address >= ip2long('10.0.0.0') && $address <= ip2long('10.255.255.255'))
            || ($address >= ip2long('172.16.0.0') && $address <= ip2long('172.31.255.255'))
            || ($address >= ip2long('192.168.0.0') && $address <= ip2long('192.168.255.255'))
            || ($address >= ip2long('127.0.0.0') && $address <= ip2long('127.255.255.255'))
            || ($address >= ip2long('169.254.0.0') && $address <= ip2long('169.254.255.255'))
        );
    }
    if (filter_var($host, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6) !== false) {
        $packed = inet_pton($host);
        if ($packed === false) {
            return false;
        }
        $first = ord($packed[0]);
        $second = ord($packed[1]);
        return $host === '::1' || (($first & 0xfe) === 0xfc) || ($first === 0xfe && ($second & 0xc0) === 0x80);
    }
    return false;
}

function dashboard_state_dir(): string
{
    return '/var/lib/serverctl/dashboard';
}

function dashboard_cli(): string
{
    return getenv('SERVERCTL_DASHBOARD_CLI') ?: '/usr/local/bin/serverctl';
}
