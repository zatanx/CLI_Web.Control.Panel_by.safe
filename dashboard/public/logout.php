<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/app/csrf.php';

dashboard_security_headers();
dashboard_require_login();
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: index.php');
    exit;
}
dashboard_verify_csrf();
dashboard_audit('LOGOUT', 'SUCCESS');
dashboard_logout();
header('Location: login.php');
exit;
