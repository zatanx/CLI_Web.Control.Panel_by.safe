<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/app/functions.php';

dashboard_security_headers();
dashboard_require_login();
$csrf = dashboard_csrf_token();
$user = (string) ($_SESSION['user'] ?? 'admin');
?><!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Web Server Manager</title>
    <link rel="stylesheet" href="assets/css/dashboard.css">
</head>
<body data-api-url="api/index.php" data-csrf-token="<?= h($csrf) ?>">
<div class="app-shell">
    <aside class="sidebar" id="sidebar">
        <div class="sidebar-brand">
            <div class="brand-mark">WS</div>
            <div><strong>WEB SERVER</strong><span>MANAGER</span></div>
        </div>
        <nav aria-label="Dashboard navigation">
            <p class="nav-label">Overview</p>
            <a class="nav-item is-active" href="#dashboard" data-section="dashboard"><span class="nav-icon">⌂</span>Dashboard</a>
            <p class="nav-label">Services</p>
            <a class="nav-item" href="#websites" data-section="websites"><span class="nav-icon">◫</span>Websites</a>
            <a class="nav-item" href="#nginx" data-section="nginx"><span class="nav-icon">N</span>Nginx</a>
            <a class="nav-item" href="#php-fpm" data-section="php-fpm"><span class="nav-icon">P</span>PHP-FPM</a>
            <a class="nav-item" href="#mariadb" data-section="mariadb"><span class="nav-icon">◆</span>MariaDB</a>
            <a class="nav-item" href="#ssl" data-section="ssl"><span class="nav-icon">◇</span>SSL Certificates</a>
            <p class="nav-label">Administration</p>
            <details class="nav-group" open>
                <summary><span class="nav-icon">⚿</span>Security</summary>
                <a class="nav-subitem" href="#firewall" data-section="firewall">Firewall</a>
                <a class="nav-subitem" href="#fail2ban" data-section="fail2ban">Fail2Ban</a>
            </details>
            <a class="nav-item" href="#bot-protection" data-section="bot-protection"><span class="nav-icon">B</span>Bot Protection</a>
            <a class="nav-item" href="#logs" data-section="logs"><span class="nav-icon">▤</span>Logs</a>
            <a class="nav-item" href="#cron" data-section="cron"><span class="nav-icon">◷</span>Cron Jobs</a>
            <a class="nav-item" href="#backup" data-section="backup"><span class="nav-icon">▣</span>Backup</a>
            <a class="nav-item" href="#updates" data-section="updates"><span class="nav-icon">↻</span>System Update</a>
            <a class="nav-item" href="#settings" data-section="settings"><span class="nav-icon">⚙</span>Settings</a>
        </nav>
        <div class="sidebar-footer">
            <form method="post" action="logout.php">
                <input type="hidden" name="csrf_token" value="<?= h($csrf) ?>">
                <button class="logout-button" type="submit"><span class="nav-icon">↪</span>Logout</button>
            </form>
        </div>
    </aside>

    <div class="main-column">
        <header class="topbar">
            <button class="menu-toggle" type="button" aria-label="Toggle navigation" data-sidebar-toggle>☰</button>
            <div><p class="eyebrow">CONTROL PANEL · v<?= h(SERVERCTL_VERSION) ?></p><h1 id="page-title">Dashboard Overview</h1></div>
            <div class="topbar-actions"><span class="user-chip"><span class="user-dot"></span><?= h($user) ?></span><button class="button button-ghost" type="button" data-refresh>Refresh now</button></div>
        </header>

        <main class="content" id="dashboard">
            <div class="page-intro"><div><p class="muted">Live server health and operations</p></div><span class="last-updated" data-last-updated>Waiting for status…</span></div>
            <div class="alert-list" data-alerts></div>

            <section class="dashboard-section is-visible" data-panel="dashboard">
                <div class="section-heading"><div><h2>System health</h2><p class="muted">Refreshes automatically every 30 seconds.</p></div><span class="health-badge" data-health>Unknown</span></div>
                <div class="status-grid status-grid-four">
                    <article class="status-card metric-card"><div class="card-top"><span>CPU</span><span class="card-symbol">◒</span></div><strong data-value="cpu">—</strong><small>Usage</small><div class="meter"><i data-meter="cpu"></i></div></article>
                    <article class="status-card metric-card"><div class="card-top"><span>RAM</span><span class="card-symbol">▥</span></div><strong data-value="ram">—</strong><small>Memory usage</small><div class="meter"><i data-meter="ram"></i></div></article>
                    <article class="status-card metric-card"><div class="card-top"><span>Disk</span><span class="card-symbol">▤</span></div><strong data-value="disk">—</strong><small>Root volume</small><div class="meter"><i data-meter="disk"></i></div></article>
                    <article class="status-card metric-card"><div class="card-top"><span>Load</span><span class="card-symbol">∿</span></div><strong data-value="load">—</strong><small>1-minute average</small><div class="metric-status" data-load-status>—</div></article>
                </div>
                <div class="status-grid status-grid-five service-cards">
                    <article class="status-card service-card" data-service-card="nginx"><span class="service-mark">N</span><div><span>Nginx</span><strong data-service="nginx">—</strong></div></article>
                    <article class="status-card service-card" data-service-card="php_fpm"><span class="service-mark">P</span><div><span>PHP-FPM</span><strong data-service="php_fpm">—</strong></div></article>
                    <article class="status-card service-card" data-service-card="mariadb"><span class="service-mark">◆</span><div><span>MariaDB</span><strong data-service="mariadb">—</strong></div></article>
                    <article class="status-card service-card" data-service-card="fail2ban"><span class="service-mark">⚿</span><div><span>Fail2Ban</span><strong data-service="fail2ban">—</strong></div></article>
                    <article class="status-card service-card" data-service-card="firewall"><span class="service-mark">◈</span><div><span>Firewall</span><strong data-service="firewall">—</strong></div></article>
                </div>
                <div class="status-grid status-grid-four summary-cards">
                    <article class="status-card summary-card"><span>Websites</span><strong data-summary="websites.total">—</strong><small data-summary-label="websites">Registered sites</small></article>
                    <article class="status-card summary-card"><span>SSL</span><strong data-summary="websites.https">—</strong><small>HTTPS enabled</small></article>
                    <article class="status-card summary-card"><span>Security</span><strong data-summary="security.score">—</strong><small>Score / 100</small></article>
                    <article class="status-card summary-card"><span>Updates</span><strong data-summary="updates.available">—</strong><small data-summary-label="updates">Available</small></article>
                </div>
                <div class="two-column">
                    <section class="panel"><div class="panel-heading"><div><h2>Recent events</h2><p class="muted">Administrative activity</p></div></div><div class="table-wrap"><table><thead><tr><th>Time</th><th>Action</th><th>Result</th></tr></thead><tbody data-events><tr><td colspan="3" class="empty-state">Loading…</td></tr></tbody></table></div></section>
                    <section class="panel"><div class="panel-heading"><div><h2>System information</h2><p class="muted">Host runtime details</p></div></div><dl class="info-list"><div><dt>Hostname</dt><dd data-info="hostname">—</dd></div><div><dt>Operating system</dt><dd data-info="os">—</dd></div><div><dt>Kernel</dt><dd data-info="kernel">—</dd></div><div><dt>Uptime</dt><dd data-info="uptime">—</dd></div><div><dt>Load average</dt><dd data-info="load">—</dd></div></dl></section>
                </div>
            </section>

            <section class="dashboard-section" data-panel="websites"><div class="section-heading"><div><h2>Websites</h2><p class="muted">Registered websites, PHP versions and certificate state.</p></div></div><section class="panel"><div class="table-wrap"><table><thead><tr><th>Domain</th><th>Status</th><th>HTTPS</th><th>PHP</th><th>SSL days</th><th>Document root</th></tr></thead><tbody data-websites><tr><td colspan="6" class="empty-state">Loading…</td></tr></tbody></table></div></section></section>
            <section class="dashboard-section" data-panel="cron">
                <div class="section-heading"><div><h2>Cron Jobs</h2><p class="muted">Validated, ID-based scheduled tasks. Website jobs run as the website owner.</p></div><span class="health-badge" data-cron-service>Unknown</span></div>
                <div class="status-grid status-grid-four summary-cards cron-summary">
                    <article class="status-card summary-card"><span>Total jobs</span><strong data-cron-summary="total">0</strong><small>Managed jobs</small></article>
                    <article class="status-card summary-card"><span>Enabled</span><strong data-cron-summary="enabled">0</strong><small>Active schedules</small></article>
                    <article class="status-card summary-card"><span>Disabled</span><strong data-cron-summary="disabled">0</strong><small>Preserved jobs</small></article>
                    <article class="status-card summary-card"><span>Failed recently</span><strong data-cron-summary="failed_recently">0</strong><small>Failed or timed out</small></article>
                </div>
                <div class="two-column cron-layout">
                    <section class="panel">
                        <div class="panel-heading"><div><h3>Managed jobs</h3><p class="muted">Run, pause, inspect or remove a job by its trusted ID.</p></div><button class="button button-ghost" type="button" data-cron-refresh>Refresh</button></div>
                        <div class="table-wrap"><table><thead><tr><th>ID</th><th>User</th><th>Schedule</th><th>Status</th><th>Last run</th><th>Actions</th></tr></thead><tbody data-cron-jobs><tr><td colspan="6" class="empty-state">Loading…</td></tr></tbody></table></div>
                    </section>
                    <section class="panel cron-form-panel">
                        <h3 data-cron-form-title>Add Website Cron Job</h3>
                        <p class="muted">The command is generated from the selected website and script filename.</p>
                        <form data-cron-form>
                            <input type="hidden" data-cron-edit-id value="">
                            <label>Website<input type="text" data-cron-website maxlength="253" required placeholder="example.com"></label>
                            <label>Schedule<select data-cron-schedule><option value="* * * * *">Every Minute</option><option value="*/5 * * * *" selected>Every 5 Minutes</option><option value="*/10 * * * *">Every 10 Minutes</option><option value="*/15 * * * *">Every 15 Minutes</option><option value="*/30 * * * *">Every 30 Minutes</option><option value="0 * * * *">Every Hour</option><option value="0 0 * * *">Every Day</option><option value="0 0 * * 0">Every Week</option><option value="0 0 1 * *">Every Month</option><option value="custom">Custom Cron Expression</option></select><input type="text" data-cron-custom-schedule maxlength="100" placeholder="*/5 * * * *" hidden></label>
                            <label>Script filename<input type="text" data-cron-script maxlength="128" required placeholder="cron.php"></label>
                            <label>Description<input type="text" data-cron-description maxlength="200" placeholder="Process orders"></label>
                            <label class="checkbox-label"><input type="checkbox" data-cron-enabled checked> Enabled</label>
                            <div><button class="button button-primary" type="submit">Save Cron Job</button><button class="button button-secondary" type="button" data-cron-cancel hidden>Cancel Edit</button></div>
                        </form>
                    </section>
                </div>
                <section class="panel cron-details-panel" data-cron-details hidden>
                    <div class="panel-heading"><div><h3>Cron Job Details</h3><p class="muted" data-cron-detail-description>—</p></div><button class="button button-secondary" type="button" data-cron-detail-close>Close</button></div>
                    <dl class="info-list"><div><dt>ID / User</dt><dd data-cron-detail-user>—</dd></div><div><dt>Status</dt><dd data-cron-detail-status>—</dd></div><div><dt>Schedule</dt><dd data-cron-detail-schedule>—</dd></div><div><dt>Command</dt><dd data-cron-detail-command>—</dd></div><div><dt>Last run / Exit code</dt><dd data-cron-detail-last>—</dd></div><div><dt>Next run</dt><dd data-cron-detail-next>—</dd></div></dl>
                    <pre class="log-viewer" data-cron-logs>No log entries.</pre>
                </section>
            </section>
            <section class="dashboard-section" data-panel="nginx"><div class="section-heading"><div><h2>Nginx</h2><p class="muted">Configuration and service controls.</p></div></div><div class="action-grid"><div class="panel"><h3>Service status</h3><p class="large-status" data-section-service="nginx">—</p><button class="button button-secondary" type="button" data-action="nginx-reload">Reload Nginx</button><button class="button button-danger" type="button" data-action="nginx-restart" data-confirm="This will briefly interrupt connections. Continue?">Restart Nginx</button></div><div class="panel"><h3>Safe operation</h3><p class="muted">Every reload validates the Nginx configuration first. Administrative actions are confirmed, CSRF-protected and audited.</p></div></div></section>
            <section class="dashboard-section" data-panel="php-fpm"><div class="section-heading"><div><h2>PHP-FPM</h2><p class="muted">Runtime service status and default version.</p></div></div><div class="panel"><div class="detail-row"><span>Default version</span><strong data-php-version>—</strong></div><div class="detail-row"><span>Service</span><strong data-section-service="php_fpm">—</strong></div></div></section>
            <section class="dashboard-section" data-panel="mariadb"><div class="section-heading"><div><h2>MariaDB</h2><p class="muted">Database service health. Credentials are never displayed.</p></div></div><div class="panel"><div class="detail-row"><span>Service</span><strong data-section-service="mariadb">—</strong></div><div class="detail-row"><span>Registered databases</span><strong>Use CLI database list</strong></div></div></section>
            <section class="dashboard-section" data-panel="ssl"><div class="section-heading"><div><h2>SSL Certificates</h2><p class="muted">Certificate coverage and expiry warnings.</p></div></div><div class="panel"><div class="detail-row"><span>HTTPS websites</span><strong data-summary="websites.https">—</strong></div><div class="detail-row"><span>Expiring within 30 days</span><strong data-summary="websites.ssl_expiring">—</strong></div></div></section>
            <section class="dashboard-section" data-panel="firewall"><div class="section-heading"><div><h2>Firewall</h2><p class="muted">Changes require confirmation and administrator access.</p></div></div><div class="action-grid"><div class="panel"><h3>Status</h3><p class="large-status" data-section-service="firewall">—</p><button class="button button-secondary" type="button" data-action="firewall-reload" data-confirm="Reload the firewall configuration?">Reload Firewall</button></div><div class="panel"><h3>Protection</h3><p class="muted">The Dashboard does not expose a one-click disable control.</p></div></div></section>
            <section class="dashboard-section" data-panel="fail2ban"><div class="section-heading"><div><h2>Fail2Ban</h2><p class="muted">Active jails and blocked IP addresses.</p></div></div><div class="panel"><div class="detail-row"><span>Service</span><strong data-section-service="fail2ban">—</strong></div><div class="detail-row"><span>Total blocked IPs</span><strong data-fail2ban-total>—</strong></div><div class="table-wrap"><table><thead><tr><th>Jail</th><th>Blocked</th><th>IP addresses</th><th>Actions</th></tr></thead><tbody data-fail2ban-jails><tr><td colspan="4" class="empty-state">Loading…</td></tr></tbody></table></div><p class="muted">Use Unblock to remove an IP from every active Fail2Ban jail.</p></div></section>
            <section class="dashboard-section" data-panel="logs"><div class="section-heading"><div><h2>Logs</h2><p class="muted">Output is escaped before rendering.</p></div></div><section class="panel"><div class="toolbar"><label>Source <select data-log-type><option value="nginx-error">Nginx error</option><option value="nginx-access">Nginx access</option><option value="security">Security</option><option value="audit">Audit</option><option value="system">System</option></select></label><button class="button button-secondary" type="button" data-load-logs>Load last 100</button></div><pre class="log-viewer" data-logs>Choose a log source to load it.</pre></section></section>
            <section class="dashboard-section" data-panel="backup"><div class="section-heading"><div><h2>Backup</h2><p class="muted">Create a full backup through the existing backup workflow.</p></div></div><section class="panel"><p class="muted">The backup archive includes the registered server state and configuration. Restore remains available from the CLI after review.</p><button class="button button-secondary" type="button" data-action="backup-all" data-confirm="Create a full server backup now?">Create full backup</button></section></section>
            <section class="dashboard-section" data-panel="updates"><div class="section-heading"><div><h2>System Update</h2><p class="muted">Update counts come from the existing System Update module.</p></div></div><section class="panel"><div class="detail-row"><span>Updates available</span><strong data-summary="updates.available">—</strong></div><div class="detail-row"><span>Security updates</span><strong data-summary="updates.security">—</strong></div><div class="detail-row"><span>Reboot required</span><strong data-summary="updates.reboot_required">—</strong></div><button class="button button-secondary" type="button" data-action="update-check" data-confirm="Refresh Ubuntu package indexes?">Refresh update check</button></section></section>
            <section class="dashboard-section" data-panel="bot-protection"><div class="section-heading"><div><h2>Bot Protection</h2><p class="muted">Configure the bot challenge for domain login. LAN/IP login keeps the local access rule.</p></div></div><section class="panel bot-settings"><div class="detail-row"><span>Status</span><strong data-bot-status>Bot protection disabled</strong></div><label for="bot-provider">Service</label><select id="bot-provider" data-bot-provider><option value="none">Disabled</option><option value="recaptcha_v3">Google reCAPTCHA v3</option><option value="turnstile">Cloudflare Turnstile</option></select><label for="bot-site-key">Site key</label><input id="bot-site-key" data-bot-site-key type="text" maxlength="512" autocomplete="off" placeholder="Public site key"><label for="bot-secret">Secret key</label><input id="bot-secret" data-bot-secret type="password" maxlength="512" autocomplete="new-password" placeholder="Enter secret key to save"><p class="muted bot-settings-note">The secret key is stored server-side and is never shown in the Dashboard. Re-enter it when saving changes.</p><button class="button button-primary" type="button" data-bot-save data-confirm="Save Bot Protection settings?">Save Bot Protection</button></section></section>
            <section class="dashboard-section" data-panel="settings"><div class="section-heading"><div><h2>Settings</h2><p class="muted">Dashboard security defaults are configured outside the public directory.</p></div></div><section class="panel"><div class="detail-row"><span>Session timeout</span><strong>30 minutes</strong></div><div class="detail-row"><span>Automatic refresh</span><strong>30 seconds</strong></div><div class="detail-row"><span>Mode</span><strong>Administrator</strong></div></section></section>
        </main>
    </div>
</div>
<div class="confirm-modal-backdrop" data-confirm-modal hidden aria-hidden="true">
    <section class="confirm-modal" role="dialog" aria-modal="true" aria-labelledby="confirm-modal-title" aria-describedby="confirm-modal-message">
        <h2 id="confirm-modal-title">Confirm action</h2>
        <p class="muted" data-confirm-message></p>
        <div class="confirm-modal-actions">
            <button class="button button-secondary" type="button" data-confirm-cancel>Cancel</button>
            <button class="button button-danger" type="button" data-confirm-accept>Confirm</button>
        </div>
    </section>
</div>
<div class="toast" data-toast role="status" aria-live="polite"></div>
<script src="assets/js/dashboard.js" defer></script>
</body>
</html>
