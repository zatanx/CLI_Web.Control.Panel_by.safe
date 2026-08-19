(() => {
    'use strict';

    const body = document.body;
    const apiUrl = body.dataset.apiUrl || 'api/index.php';
    const csrfToken = body.dataset.csrfToken || '';
    const qs = (selector, root = document) => root.querySelector(selector);
    const qsa = (selector, root = document) => [...root.querySelectorAll(selector)];
    const escapeText = (value) => String(value ?? '');
    const formatBytes = (bytes) => {
        let value = Number(bytes);
        if (!Number.isFinite(value) || value <= 0) return '—';
        const units = ['B', 'KB', 'MB', 'GB', 'TB']; let index = 0;
        while (value >= 1024 && index < units.length - 1) { value /= 1024; index += 1; }
        return `${value >= 10 || index === 0 ? Math.round(value) : value.toFixed(1)} ${units[index]}`;
    };
    const confirmModal = qs('[data-confirm-modal]');
    const confirmMessage = qs('[data-confirm-message]', confirmModal || document);
    const confirmAccept = qs('[data-confirm-accept]', confirmModal || document);
    const confirmCancel = qs('[data-confirm-cancel]', confirmModal || document);
    let confirmResolve = null;
    let previousFocus = null;
    let botSettingsDirty = false;

    const showToast = (message, isError = false) => {
        const toast = qs('[data-toast]');
        if (!toast) return;
        toast.textContent = message;
        toast.style.background = isError ? '#a33243' : '#1f2f49';
        toast.classList.add('show');
        window.setTimeout(() => toast.classList.remove('show'), 3500);
    };

    const closeConfirmModal = (confirmed) => {
        if (!confirmModal || !confirmResolve) return;
        const resolve = confirmResolve;
        confirmResolve = null;
        confirmModal.hidden = true;
        confirmModal.setAttribute('aria-hidden', 'true');
        body.classList.remove('modal-open');
        previousFocus?.focus();
        previousFocus = null;
        resolve(confirmed);
    };

    const showConfirmModal = (message) => {
        if (!confirmModal) return Promise.resolve(window.confirm(message));
        previousFocus = document.activeElement;
        confirmMessage.textContent = message;
        confirmModal.hidden = false;
        confirmModal.setAttribute('aria-hidden', 'false');
        body.classList.add('modal-open');
        window.requestAnimationFrame(() => confirmAccept?.focus());
        return new Promise((resolve) => { confirmResolve = resolve; });
    };

    confirmAccept?.addEventListener('click', () => closeConfirmModal(true));
    confirmCancel?.addEventListener('click', () => closeConfirmModal(false));
    confirmModal?.addEventListener('click', (event) => {
        if (event.target === confirmModal) closeConfirmModal(false);
    });
    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' && confirmResolve) closeConfirmModal(false);
    });

    const setText = (selector, value) => {
        const element = qs(selector);
        if (element) element.textContent = escapeText(value);
    };

    const getPath = (object, path) => path.split('.').reduce((value, key) => value?.[key], object);

    const parseApiResponse = async (response, request) => {
        const raw = await response.text();
        let data;
        try {
            data = raw === '' ? {} : JSON.parse(raw);
        } catch (error) {
            console.error('[Dashboard API] Invalid JSON response', {
                request,
                status: response.status,
                statusText: response.statusText,
                body: raw.slice(0, 2000),
                error,
            });
            throw new Error(`API returned invalid JSON (HTTP ${response.status}).`);
        }
        if (!response.ok || data.status === 'error') {
            console.error('[Dashboard API] Request failed', {
                request,
                status: response.status,
                statusText: response.statusText,
                response: data,
            });
            throw new Error(data.message || `Request failed (HTTP ${response.status}).`);
        }
        return data;
    };

    const apiGet = async (resource, params = {}) => {
        const query = new URLSearchParams({ resource, ...params });
        const request = `GET ${apiUrl}?${query}`;
        try {
            const response = await fetch(`${apiUrl}?${query}`, { credentials: 'same-origin', headers: { Accept: 'application/json' } });
            return await parseApiResponse(response, request);
        } catch (error) {
            console.error('[Dashboard API] GET error', { request, error });
            throw error;
        }
    };

    const apiPost = async (action, target = '', confirmed = false, extra = {}) => {
        const form = new URLSearchParams({ action, target, confirmed: confirmed ? '1' : '0', csrf_token: csrfToken, ...extra });
        const request = `POST ${apiUrl}`;
        try {
            const response = await fetch(apiUrl, { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' }, body: form });
            return await parseApiResponse(response, request);
        } catch (error) {
            console.error('[Dashboard API] POST error', { request, error });
            throw error;
        }
    };

    const renderStatus = (data) => {
        const server = data.server || {};
        const services = data.services || {};
        setText('[data-value="cpu"]', `${server.cpu ?? 0}%`);
        setText('[data-value="ram"]', `${server.ram ?? 0}%`);
        setText('[data-value="disk"]', `${server.disk ?? 0}%`);
        const ramCapacity = qs('[data-value="ram"]')?.closest('.metric-card')?.querySelector('small');
        const diskCapacity = qs('[data-value="disk"]')?.closest('.metric-card')?.querySelector('small');
        if (ramCapacity) ramCapacity.textContent = `Used ${formatBytes(Number(server.ram_used_kb || 0) * 1024)} / ${formatBytes(Number(server.ram_total_kb || 0) * 1024)}`;
        if (diskCapacity) diskCapacity.textContent = `Used ${formatBytes(server.disk_used_bytes)} / ${formatBytes(server.disk_total_bytes)}`;
        setText('[data-value="load"]', server.load ?? '0');
        setText('[data-load-status]', Number(server.load) > 2 ? 'Elevated' : 'Normal');
        ['cpu', 'ram', 'disk'].forEach((key) => {
            const value = Math.max(0, Math.min(100, Number(server[key] || 0)));
            const meter = qs(`[data-meter="${key}"]`);
            if (meter) { meter.style.width = `${value}%`; meter.classList.toggle('warn', value >= 80 && value < 95); meter.classList.toggle('critical', value >= 95); }
        });
        Object.entries(services).forEach(([key, value]) => {
            setText(`[data-service="${key}"]`, value);
            qsa(`[data-section-service="${key}"]`).forEach((element) => { element.textContent = String(value).toUpperCase(); element.classList.toggle('ok', value === 'running'); element.classList.toggle('bad', value !== 'running'); });
            const card = qs(`[data-service-card="${key}"]`);
            if (card) { card.classList.toggle('ok', value === 'running'); card.classList.toggle('bad', value !== 'running'); }
        });
        qsa('[data-summary]').forEach((element) => { element.textContent = escapeText(getPath(data, element.dataset.summary)); });
        setText('[data-php-version]', data.php?.default_version || '—');
        const bot = data.bot_protection || {};
        const botProvider = qs('[data-bot-provider]');
        const botSiteKey = qs('[data-bot-site-key]');
        if (!botSettingsDirty) {
            if (botProvider) botProvider.value = bot.provider || 'none';
            if (botSiteKey) botSiteKey.value = bot.site_key || '';
        }
        const botLabels = { none: 'Disabled', recaptcha_v3: 'Google reCAPTCHA v3', turnstile: 'Cloudflare Turnstile' };
        const botStatus = bot.enabled === 'yes' ? `${botLabels[bot.provider] || bot.provider} enabled` : 'Bot protection disabled';
        setText('[data-bot-status]', botStatus);
        const botSecret = qs('[data-bot-secret]');
        if (botSecret && !botSettingsDirty) botSecret.value = '';
        [botSiteKey, botSecret].forEach((element) => { if (element) element.disabled = botProvider?.value === 'none'; });
        Object.entries(server).forEach(([key, value]) => setText(`[data-info="${key}"]`, value));
        const score = Number(data.security?.score || 0);
        const health = qs('[data-health]');
        if (health) { const state = score >= 75 ? 'good' : score >= 60 ? 'warning' : 'critical'; health.textContent = state === 'good' ? 'Good' : state === 'warning' ? 'Warning' : 'Critical'; health.className = `health-badge ${state}`; }
        const alerts = [];
        if (Number(data.websites?.ssl_expiring || 0) > 0) alerts.push(`SSL certificates expiring soon: ${data.websites.ssl_expiring}`);
        if (Number(data.disk || server.disk || 0) >= 80) alerts.push(`Disk usage is high: ${data.disk || server.disk}%`);
        if (data.updates?.reboot_required === 'yes') alerts.push('A system reboot is required.');
        if (services.nginx !== 'running') alerts.push('Nginx is not running.');
        const alertRoot = qs('[data-alerts]');
        if (alertRoot) alertRoot.innerHTML = alerts.map((alert) => `<div class="alert alert-warning">${escapeText(alert)}</div>`).join('');
        setText('[data-last-updated]', `Updated ${new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`);
    };

    const loadSnapshot = async () => {
        try { const result = await apiGet('snapshot'); renderStatus(result.data || {}); const events = await apiGet('events'); renderEvents(events.data || []); await loadFail2ban(); }
        catch (error) { showToast(error.message, true); }
    };

    const renderEvents = (events) => {
        const root = qs('[data-events]');
        if (!root) return;
        root.replaceChildren();
        if (!events.length) { root.innerHTML = '<tr><td colspan="3" class="empty-state">No events recorded yet.</td></tr>'; return; }
        events.slice(0, 8).forEach((event) => { const row = document.createElement('tr'); [event.time, event.action, event.result].forEach((value) => { const cell = document.createElement('td'); cell.textContent = escapeText(value); row.appendChild(cell); }); root.appendChild(row); });
    };

    const loadWebsites = async () => {
        try {
            const result = await apiGet('websites'); const root = qs('[data-websites]'); if (!root) return; root.replaceChildren();
            if (!result.data?.length) { root.innerHTML = '<tr><td colspan="6" class="empty-state">No websites registered.</td></tr>'; return; }
            result.data.forEach((site) => { const row = document.createElement('tr'); [site.domain, site.status, site.https === 'yes' ? 'Enabled' : 'No', site.php_version, site.ssl_days < 0 ? '—' : site.ssl_days, site.document_root].forEach((value) => { const cell = document.createElement('td'); cell.textContent = escapeText(value); row.appendChild(cell); }); root.appendChild(row); });
        } catch (error) { showToast(error.message, true); }
    };

    let cronJobs = [];
    const cronForm = qs('[data-cron-form]');
    const cronSchedule = qs('[data-cron-schedule]');
    const cronCustomSchedule = qs('[data-cron-custom-schedule]');
    const cronEditId = qs('[data-cron-edit-id]');
    const cronFormTitle = qs('[data-cron-form-title]');
    const cronCancel = qs('[data-cron-cancel]');

    const cronScheduleValue = () => cronSchedule?.value === 'custom' ? (cronCustomSchedule?.value || '').trim() : (cronSchedule?.value || '');
    const syncCronSchedule = () => { if (cronCustomSchedule) cronCustomSchedule.hidden = cronSchedule?.value !== 'custom'; };
    cronSchedule?.addEventListener('change', syncCronSchedule);

    const renderCronDetails = async (job) => {
        const panel = qs('[data-cron-details]');
        if (!panel) return;
        panel.hidden = false;
        setText('[data-cron-detail-description]', job.description || 'No description');
        setText('[data-cron-detail-user]', `${job.id} / ${job.user}`);
        setText('[data-cron-detail-status]', job.status);
        setText('[data-cron-detail-schedule]', job.schedule);
        setText('[data-cron-detail-command]', job.command);
        setText('[data-cron-detail-last]', `${job.last_run || '—'} / ${job.last_exit_code || '—'}`);
        setText('[data-cron-detail-next]', job.next_run || '—');
        try {
            const result = await apiGet('cron-logs', { id: String(job.id), limit: '100' });
            setText('[data-cron-logs]', (result.data || []).join('\n') || 'No log entries.');
        } catch (error) { setText('[data-cron-logs]', error.message); }
    };

    const beginCronEdit = (job) => {
        if (job.type !== 'website') { showToast('Only Website Cron jobs can be edited in the Dashboard.', true); return; }
        if (cronEditId) cronEditId.value = String(job.id);
        if (cronFormTitle) cronFormTitle.textContent = `Edit Website Cron Job #${job.id}`;
        if (cronCancel) cronCancel.hidden = false;
        if (qs('[data-cron-website]')) qs('[data-cron-website]').value = job.website || '';
        if (qs('[data-cron-script]')) qs('[data-cron-script]').value = (job.command || '').split(' ').pop() || '';
        if (qs('[data-cron-description]')) qs('[data-cron-description]').value = job.description || '';
        if (qs('[data-cron-enabled]')) qs('[data-cron-enabled]').checked = job.enabled === 'yes';
        const preset = [...(cronSchedule?.options || [])].find((option) => option.value === job.schedule);
        if (cronSchedule) cronSchedule.value = preset ? job.schedule : 'custom';
        if (cronCustomSchedule) cronCustomSchedule.value = preset ? '' : job.schedule;
        syncCronSchedule();
        cronForm?.scrollIntoView({ behavior: 'smooth', block: 'center' });
    };

    const resetCronForm = () => {
        cronForm?.reset();
        if (cronEditId) cronEditId.value = '';
        if (cronFormTitle) cronFormTitle.textContent = 'Add Website Cron Job';
        if (cronSchedule) cronSchedule.value = '*/5 * * * *';
        if (cronCancel) cronCancel.hidden = true;
        syncCronSchedule();
    };

    const renderCron = (data, status) => {
        cronJobs = Array.isArray(data.jobs) ? data.jobs : [];
        const summary = data.summary || {};
        qsa('[data-cron-summary]').forEach((element) => { element.textContent = String(summary[element.dataset.cronSummary] ?? 0); });
        const service = status?.service ? `${String(status.service).toUpperCase()}: ${String(status.state || 'stopped').toUpperCase()}` : 'Unavailable';
        setText('[data-cron-service]', service);
        const root = qs('[data-cron-jobs]');
        if (!root) return;
        root.replaceChildren();
        if (!cronJobs.length) { root.innerHTML = '<tr><td colspan="6" class="empty-state">No Cron jobs configured.</td></tr>'; return; }
        cronJobs.forEach((job) => {
            const row = document.createElement('tr');
            [job.id, job.user, job.schedule, job.status, job.last_run || '—'].forEach((value) => { const cell = document.createElement('td'); cell.textContent = escapeText(value); row.appendChild(cell); });
            const actions = document.createElement('td'); actions.className = 'cron-actions';
            const addAction = (label, action, danger = false) => { const button = document.createElement('button'); button.type = 'button'; button.className = `button ${danger ? 'button-danger' : 'button-secondary'} button-small`; button.textContent = label; button.dataset.cronAction = action; button.dataset.cronId = String(job.id); actions.appendChild(button); };
            addAction('View', 'view');
            if (job.type === 'website') addAction('Edit', 'edit');
            addAction(job.enabled === 'yes' ? 'Disable' : 'Enable', job.enabled === 'yes' ? 'disable' : 'enable');
            addAction('Run Now', 'run');
            addAction('Delete', 'delete', true);
            row.appendChild(actions); root.appendChild(row);
        });
    };

    const loadCron = async () => {
        try { const [jobs, status] = await Promise.all([apiGet('cron'), apiGet('cron-status')]); renderCron(jobs.data || {}, status.data || {}); }
        catch (error) { showToast(error.message, true); }
    };

    qs('[data-cron-detail-close]')?.addEventListener('click', () => { const panel = qs('[data-cron-details]'); if (panel) panel.hidden = true; });
    qs('[data-cron-refresh]')?.addEventListener('click', loadCron);
    cronCancel?.addEventListener('click', resetCronForm);
    qs('[data-cron-jobs]')?.addEventListener('click', async (event) => {
        const button = event.target.closest('button[data-cron-action]');
        if (!button) return;
        const job = cronJobs.find((item) => String(item.id) === button.dataset.cronId);
        if (!job) return;
        const action = button.dataset.cronAction;
        if (action === 'view') { await renderCronDetails(job); return; }
        if (action === 'edit') { beginCronEdit(job); return; }
        const apiAction = `cron-${action}`;
        const message = action === 'delete' ? 'This Cron job will be permanently removed. Continue?' : action === 'run' ? 'Run this trusted Cron job now?' : `${action[0].toUpperCase()}${action.slice(1)} this Cron job?`;
        if (!(await showConfirmModal(message))) return;
        button.disabled = true;
        try { await apiPost(apiAction, button.dataset.cronId, true); showToast('Cron action completed.'); await loadCron(); }
        catch (error) { showToast(error.message, true); }
        finally { button.disabled = false; }
    });
    cronForm?.addEventListener('submit', async (event) => {
        event.preventDefault();
        const id = cronEditId?.value || '';
        const extra = { website: qs('[data-cron-website]')?.value.trim() || '', schedule: cronScheduleValue(), script: qs('[data-cron-script]')?.value.trim() || '', description: qs('[data-cron-description]')?.value.trim() || '', enabled: qs('[data-cron-enabled]')?.checked ? 'yes' : 'no' };
        if (!extra.schedule || !extra.website || !extra.script) { showToast('Website, schedule and script are required.', true); return; }
        const action = id ? 'cron-edit-website' : 'cron-add-website';
        if (!(await showConfirmModal(id ? 'Save changes to this Cron job?' : 'Create this Website Cron job?'))) return;
        try { await apiPost(action, id, true, extra); showToast('Cron job saved.'); resetCronForm(); await loadCron(); }
        catch (error) { showToast(error.message, true); }
    });
    syncCronSchedule();

    const renderFail2ban = (data) => {
        setText('[data-fail2ban-total]', data.total_banned ?? 0);
        const root = qs('[data-fail2ban-jails]');
        if (!root) return;
        root.replaceChildren();
        const jails = Array.isArray(data.jails) ? data.jails : [];
        if (!jails.length) {
            const row = document.createElement('tr'); const cell = document.createElement('td');
            cell.colSpan = 4; cell.className = 'empty-state'; cell.textContent = data.service === 'running' ? 'No blocked IPs.' : `Fail2Ban is ${data.service || 'unavailable'}.`;
            row.appendChild(cell); root.appendChild(row); return;
        }
        jails.forEach((jail) => {
            const row = document.createElement('tr');
            const name = document.createElement('td'); name.textContent = jail.name || '—';
            const count = document.createElement('td'); count.textContent = String(jail.currently_banned ?? 0);
            const ips = document.createElement('td'); ips.className = 'ip-list';
            const actions = document.createElement('td');
            const bannedIps = Array.isArray(jail.banned_ips) ? jail.banned_ips : [];
            if (!bannedIps.length) {
                ips.textContent = 'None';
            } else {
                bannedIps.forEach((ip) => {
                    const item = document.createElement('span'); item.className = 'ip-entry';
                    const label = document.createElement('code'); label.textContent = ip;
                    const button = document.createElement('button'); button.type = 'button'; button.className = 'button button-secondary button-small'; button.textContent = 'Unblock'; button.dataset.fail2banUnban = ip;
                    item.append(label); ips.appendChild(item); actions.appendChild(button);
                });
            }
            row.append(name, count, ips, actions); root.appendChild(row);
        });
    };

    const loadFail2ban = async () => {
        try { const result = await apiGet('fail2ban'); renderFail2ban(result.data || {}); }
        catch (error) { console.error('[Dashboard API] Fail2Ban error', error); }
    };

    qs('[data-fail2ban-jails]')?.addEventListener('click', async (event) => {
        const button = event.target.closest('button[data-fail2ban-unban]');
        if (!button) return;
        const ip = button.dataset.fail2banUnban || '';
        if (!(await showConfirmModal(`Unblock ${ip} from all Fail2Ban jails?`))) return;
        button.disabled = true;
        try { await apiPost('fail2ban-unban', ip, true); showToast(`Unblocked ${ip}.`); await loadFail2ban(); }
        catch (error) { showToast(error.message, true); button.disabled = false; }
    });

    const loadLogs = async () => {
        try { const type = qs('[data-log-type]')?.value || 'nginx-error'; const result = await apiGet('logs', { type, limit: '100', search: '' }); setText('[data-logs]', (result.data || []).join('\n') || 'No log entries.'); }
        catch (error) { showToast(error.message, true); }
    };

    qsa('[data-section]').forEach((link) => link.addEventListener('click', (event) => {
        event.preventDefault(); const section = link.dataset.section; qsa('[data-section]').forEach((item) => item.classList.toggle('is-active', item === link)); qsa('[data-panel]').forEach((panel) => panel.classList.toggle('is-visible', panel.dataset.panel === section)); qs('#page-title').textContent = section === 'dashboard' ? 'Dashboard Overview' : section.replace('-', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase()); qs('#sidebar')?.classList.remove('open'); if (section === 'websites') loadWebsites(); if (section === 'fail2ban') loadFail2ban(); if (section === 'cron') loadCron();
    }));
    const botProvider = qs('[data-bot-provider]');
    const botSiteKey = qs('[data-bot-site-key]');
    const botSecret = qs('[data-bot-secret]');
    const botSave = qs('[data-bot-save]');
    const syncBotFields = () => {
        const disabled = botProvider?.value === 'none';
        [botSiteKey, botSecret].forEach((element) => { if (element) element.disabled = disabled; });
    };
    [botProvider, botSiteKey, botSecret].forEach((element) => element?.addEventListener('input', () => { botSettingsDirty = true; syncBotFields(); }));
    botProvider?.addEventListener('change', () => { botSettingsDirty = true; syncBotFields(); });
    botSave?.addEventListener('click', async () => {
        const provider = botProvider?.value || 'none';
        const siteKey = provider === 'none' ? '' : (botSiteKey?.value || '').trim();
        const secret = provider === 'none' ? '' : (botSecret?.value || '');
        if (provider !== 'none' && (!siteKey || !secret)) {
            showToast('Enter both the site key and secret key.', true);
            return;
        }
        if (!(await showConfirmModal(botSave.dataset.confirm || 'Save Bot Protection settings?'))) return;
        botSave.disabled = true;
        try {
            await apiPost('bot-protection-set', '', true, { provider, site_key: siteKey, secret });
            showToast('Bot Protection settings saved.');
            botSettingsDirty = false;
            await loadSnapshot();
        } catch (error) { showToast(error.message, true); }
        finally { botSave.disabled = false; }
    });
    qsa('[data-action]').forEach((button) => button.addEventListener('click', async () => {
        const message = button.dataset.confirm || 'Continue with this administrative action?';
        if (!(await showConfirmModal(message))) return;
        button.disabled = true;
        try { await apiPost(button.dataset.action, '', true); showToast('Action completed.'); await loadSnapshot(); }
        catch (error) { showToast(error.message, true); }
        finally { button.disabled = false; }
    }));
    qs('[data-refresh]')?.addEventListener('click', loadSnapshot);
    qs('[data-load-logs]')?.addEventListener('click', loadLogs);
    qs('[data-sidebar-toggle]')?.addEventListener('click', () => qs('#sidebar')?.classList.toggle('open'));
    loadSnapshot();
    window.setInterval(loadSnapshot, 30000);
})();
