# Web Dashboard

The Dashboard is an optional PHP/Nginx/PHP-FPM web interface for the existing
`serverctl` manager. It does not add Node.js, a background daemon, or a new
database. The web UI calls only the structured `serverctl dashboard` commands
and the existing server-manager functions.

## Install and enable

`install.sh` installs the Dashboard source under `/opt/serverctl/dashboard`,
but does not expose it until an HTTPS certificate exists and an administrator
enables it:

```text
sudo serverctl dashboard status
sudo serverctl dashboard install dashboard.example.com
```

The install command asks for a password, stores only a `password_hash()` value
in `/etc/serverctl/dashboard.conf`, creates a separate Nginx site, validates
`nginx -t`, and reloads Nginx. The site redirects HTTP to HTTPS.

The PHP-FPM Dashboard can call only these sudo-approved operations:

- read-only status and website JSON snapshots;
- bounded log reads;
- explicitly whitelisted, confirmed administrative actions.

All mutations require an authenticated administrator session, CSRF validation,
browser confirmation, and an audit entry. Sessions use secure, HttpOnly,
SameSite=Strict cookies and expire after 30 minutes of inactivity. Login is
limited to five failures per 15 minutes per source IP.

## Remove

```text
sudo serverctl dashboard uninstall
```

This removes only the Dashboard files, its configuration, state, and Nginx
site. It does not remove Nginx, PHP-FPM, MariaDB, websites, SSL certificates,
Firewall, or Fail2Ban.
