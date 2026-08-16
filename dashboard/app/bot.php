<?php
declare(strict_types=1);

function dashboard_bot_provider(): string
{
    $provider = strtolower(trim((string) dashboard_config('DASHBOARD_BOT_PROVIDER', 'none')));
    return in_array($provider, ['none', 'recaptcha_v3', 'turnstile'], true) ? $provider : 'none';
}

function dashboard_bot_site_key(): string
{
    return trim((string) dashboard_config('DASHBOARD_BOT_SITE_KEY', ''));
}

function dashboard_bot_secret(): string
{
    return trim((string) dashboard_config('DASHBOARD_BOT_SECRET', ''));
}

function dashboard_bot_enabled(): bool
{
    return dashboard_bot_provider() !== 'none'
        && dashboard_bot_site_key() !== ''
        && dashboard_bot_secret() !== '';
}

function dashboard_bot_login_enabled(): bool
{
    return dashboard_bot_enabled() && !dashboard_request_is_local_host();
}

function dashboard_bot_verify_request(string $endpoint, array $payload): ?array
{
    if (!function_exists('curl_init')) {
        error_log('[serverctl-dashboard] Bot protection requires the PHP cURL extension.');
        return null;
    }
    $handle = curl_init($endpoint);
    if ($handle === false) {
        return null;
    }
    curl_setopt_array($handle, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => http_build_query($payload, '', '&', PHP_QUERY_RFC3986),
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 4,
        CURLOPT_TIMEOUT => 8,
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_SSL_VERIFYHOST => 2,
        CURLOPT_USERAGENT => 'serverctl-dashboard',
    ]);
    $raw = curl_exec($handle);
    $error = curl_error($handle);
    curl_close($handle);
    if ($raw === false) {
        error_log(sprintf('[serverctl-dashboard] Bot protection verification request failed: %s', $error));
        return null;
    }
    $decoded = json_decode((string) $raw, true);
    return is_array($decoded) ? $decoded : null;
}

function dashboard_bot_verify_login(string $token): bool
{
    if (!dashboard_bot_login_enabled()) {
        return true;
    }
    $token = trim($token);
    if ($token === '' || strlen($token) > 2048 || preg_match('/[\r\n]/', $token)) {
        error_log('[serverctl-dashboard] Bot protection rejected an empty or malformed login token.');
        return false;
    }
    $provider = dashboard_bot_provider();
    $payload = [
        'secret' => dashboard_bot_secret(),
        'response' => $token,
        'remoteip' => dashboard_client_ip(),
    ];
    if ($provider === 'recaptcha_v3') {
        $response = dashboard_bot_verify_request('https://www.google.com/recaptcha/api/siteverify', $payload);
        if (($response['success'] ?? false) !== true || ($response['action'] ?? '') !== 'login') {
            error_log('[serverctl-dashboard] reCAPTCHA login verification failed.');
            return false;
        }
        $threshold = (float) dashboard_config('DASHBOARD_BOT_RECAPTCHA_THRESHOLD', '0.5');
        $threshold = $threshold >= 0.0 && $threshold <= 1.0 ? $threshold : 0.5;
        $score = (float) ($response['score'] ?? 0.0);
        if ($score < $threshold) {
            error_log(sprintf('[serverctl-dashboard] reCAPTCHA login score %.3f was below threshold %.3f.', $score, $threshold));
            return false;
        }
        return true;
    }
    $response = dashboard_bot_verify_request('https://challenges.cloudflare.com/turnstile/v0/siteverify', $payload);
    if (($response['success'] ?? false) !== true) {
        error_log('[serverctl-dashboard] Turnstile login verification failed.');
        return false;
    }
    return true;
}
