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
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $provided_csrf = (string) ($_POST['csrf_token'] ?? '');
    if ($provided_csrf === '' || !hash_equals($csrf, $provided_csrf)) {
        $error = 'Your login form expired. Please try again.';
    }
    $username = trim((string) ($_POST['username'] ?? ''));
    $password = (string) ($_POST['password'] ?? '');
    if ($error === '' && dashboard_login($username, $password)) {
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
</head>
<body class="login-page">
<main class="login-card" aria-labelledby="login-title">
    <div class="brand-mark">WS</div>
    <p class="eyebrow">WEB SERVER MANAGER</p>
    <h1 id="login-title">Sign in to Dashboard</h1>
    <p class="muted">Secure server operations console</p>
    <?php if ($error !== ''): ?><div class="alert alert-danger" role="alert"><?= h($error) ?></div><?php endif; ?>
    <form method="post" autocomplete="off">
        <input type="hidden" name="csrf_token" value="<?= h($csrf) ?>">
        <label for="username">Username</label>
        <input id="username" name="username" type="text" required maxlength="64" autocomplete="username" autofocus>
        <label for="password">Password</label>
        <input id="password" name="password" type="password" required autocomplete="current-password">
        <button class="button button-primary button-wide" type="submit">Log in</button>
    </form>
    <p class="login-footnote">HTTPS, protected sessions and administrative audit logging are enabled.</p>
</main>
</body>
</html>
