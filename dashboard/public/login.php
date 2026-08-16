<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/app/csrf.php';

dashboard_security_headers();
dashboard_require_https();
dashboard_session_start();
if (dashboard_logged_in()) {
    header('Location: index.php');
    exit;
}

$error = '';
$csrf = dashboard_csrf_token();
$bot_provider = dashboard_bot_provider();
$bot_enabled = dashboard_bot_enabled();
$bot_site_key = dashboard_bot_site_key();
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $provided_csrf = (string) ($_POST['csrf_token'] ?? '');
    if ($provided_csrf === '' || !hash_equals($csrf, $provided_csrf)) {
        $error = 'Your login form expired. Please try again.';
    }
    $username = trim((string) ($_POST['username'] ?? ''));
    $password = (string) ($_POST['password'] ?? '');
    $bot_token = (string) ($_POST['bot_token'] ?? '');
    if ($error === '' && dashboard_login($username, $password, $bot_token)) {
        header('Location: index.php');
        exit;
    }
    if ($error === '') {
        $error = dashboard_is_configured() ? 'Invalid credentials or temporary login lock.' : 'Dashboard is not configured yet.';
    }
}
?><!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Web Server Manager — Login</title>
    <link rel="stylesheet" href="assets/css/dashboard.css">
    <?php if ($bot_enabled && $bot_provider === 'recaptcha_v3'): ?><script src="https://www.google.com/recaptcha/api.js?render=<?= h($bot_site_key) ?>" defer></script><?php endif; ?>
    <?php if ($bot_enabled && $bot_provider === 'turnstile'): ?><script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script><?php endif; ?>
</head>
<body class="login-page" data-bot-provider="<?= h($bot_enabled ? $bot_provider : 'none') ?>" data-bot-site-key="<?= h($bot_site_key) ?>">
<main class="login-card" aria-labelledby="login-title">
    <div class="brand-mark">WS</div>
    <p class="eyebrow">WEB SERVER MANAGER · v<?= h(SERVERCTL_VERSION) ?></p>
    <h1 id="login-title">Sign in to Dashboard</h1>
    <p class="muted">Secure server operations console</p>
    <?php if ($error !== ''): ?><div class="alert alert-danger" role="alert"><?= h($error) ?></div><?php endif; ?>
    <form method="post" autocomplete="off" data-login-form>
        <input type="hidden" name="csrf_token" value="<?= h($csrf) ?>">
        <input type="hidden" name="bot_token" data-bot-token value="">
        <label for="username">Username</label>
        <input id="username" name="username" type="text" required maxlength="64" autocomplete="username" autofocus>
        <label for="password">Password</label>
        <input id="password" name="password" type="password" required autocomplete="current-password">
        <?php if ($bot_enabled && $bot_provider === 'turnstile'): ?><div class="cf-turnstile" data-sitekey="<?= h($bot_site_key) ?>" data-theme="light"></div><?php endif; ?>
        <?php if ($bot_enabled): ?><div class="alert alert-danger login-bot-error" data-bot-error hidden role="alert"></div><?php endif; ?>
        <button class="button button-primary button-wide" type="submit">Log in</button>
    </form>
    <p class="login-footnote">Protected sessions and administrative audit logging are enabled.</p>
</main>
<script src="assets/js/login.js" defer></script>
</body>
</html>
