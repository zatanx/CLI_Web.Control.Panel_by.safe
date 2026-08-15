(() => {
    'use strict';

    const body = document.body;
    const apiUrl = body.dataset.apiUrl || 'api/index.php';
    const csrfToken = body.dataset.csrfToken || '';
    const qs = (selector, root = document) => root.querySelector(selector);
    const qsa = (selector, root = document) => [...root.querySelectorAll(selector)];
    const escapeText = (value) => String(value ?? '');

    const showToast = (message, isError = false) => {
        const toast = qs('[data-toast]');
        if (!toast) return;
        toast.textContent = message;
        toast.style.background = isError ? '#a33243' : '#1f2f49';
        toast.classList.add('show');
        window.setTimeout(() => toast.classList.remove('show'), 3500);
    };

    const setText = (selector, value) => {
        const element = qs(selector);
        if (element) element.textContent = escapeText(value);
    };

    const getPath = (object, path) => path.split('.').reduce((value, key) => value?.[key], object);

    const apiGet = async (resource, params = {}) => {
        const query = new URLSearchParams({ resource, ...params });
        const response = await fetch(`${apiUrl}?${query}`, { credentials: 'same-origin', headers: { Accept: 'application/json' } });
        const data = await response.json();
        if (!response.ok || data.status === 'error') throw new Error(data.message || 'Request failed.');
        return data;
    };

    const apiPost = async (action, target = '', confirmed = false) => {
        const form = new URLSearchParams({ action, target, confirmed: confirmed ? '1' : '0', csrf_token: csrfToken });
        const response = await fetch(apiUrl, { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' }, body: form });
        const data = await response.json();
        if (!response.ok || data.status === 'error') throw new Error(data.message || 'Action failed.');
        return data;
    };

    const renderStatus = (data) => {
        const server = data.server || {};
        const services = data.services || {};
        setText('[data-value="cpu"]', `${server.cpu ?? 0}%`);
        setText('[data-value="ram"]', `${server.ram ?? 0}%`);
        setText('[data-value="disk"]', `${server.disk ?? 0}%`);
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
        try { const result = await apiGet('snapshot'); renderStatus(result.data || {}); const events = await apiGet('events'); renderEvents(events.data || []); }
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

    const loadLogs = async () => {
        try { const type = qs('[data-log-type]')?.value || 'nginx-error'; const result = await apiGet('logs', { type, limit: '100', search: '' }); setText('[data-logs]', (result.data || []).join('\n') || 'No log entries.'); }
        catch (error) { showToast(error.message, true); }
    };

    qsa('[data-section]').forEach((link) => link.addEventListener('click', (event) => {
        event.preventDefault(); const section = link.dataset.section; qsa('[data-section]').forEach((item) => item.classList.toggle('is-active', item === link)); qsa('[data-panel]').forEach((panel) => panel.classList.toggle('is-visible', panel.dataset.panel === section)); qs('#page-title').textContent = section === 'dashboard' ? 'Dashboard Overview' : section.replace('-', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase()); qs('#sidebar')?.classList.remove('open'); if (section === 'websites') loadWebsites();
    }));
    qsa('[data-action]').forEach((button) => button.addEventListener('click', async () => {
        const message = button.dataset.confirm || 'Continue with this administrative action?';
        if (!window.confirm(message)) return;
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
