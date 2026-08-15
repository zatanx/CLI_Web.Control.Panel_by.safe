# Architecture

```text
Internet -> external firewall -> UFW -> AppArmor -> Nginx
                                                 -> optional Dashboard -> PHP-FPM -> sudo-whitelisted serverctl action
                                                 -> per-site PHP-FPM socket/user
                                                 -> MariaDB on 127.0.0.1

Administrator -> VPN/LAN -> SSH key -> sudo serverctl -> validated action
```

`/usr/local/bin/serverctl` links to `/opt/serverctl/bin/serverctl`. Modules live in `/opt/serverctl/lib`, configuration in `/etc/serverctl`, state records in `/var/lib/serverctl`, logs in `/var/log/serverctl`, and backups in `/var/backups/serverctl`.

Each site uses `/var/www/<domain>/public`, a deterministic Linux user, a dedicated PHP-FPM pool, and a Unix socket under `/run/php/serverctl`. Nginx never sends user input to a shell. State files contain metadata only, not database passwords.

There is no resident serverctl daemon. The optional Dashboard is served only by
Nginx + PHP-FPM after an administrator configures an HTTPS certificate; it uses
PHP sessions, CSRF tokens, rate limiting, security headers, and a narrow sudo
allowlist instead of an open management port. Scheduled work uses systemd timers.
