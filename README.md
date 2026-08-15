# serverctl

`serverctl` is a lightweight web hosting manager for Ubuntu Server. It manages Nginx, isolated PHP-FPM pools, MariaDB, Let's Encrypt, UFW, Fail2Ban, AppArmor, backups, updates, health checks, and security audits. An optional PHP/Nginx Dashboard is available without adding Node.js or an administration daemon.

## Principles

- One Linux user and one PHP-FPM pool per website
- Validated arguments and allow-listed system commands
- Backup, validate, apply, health-check, and rollback configuration flow
- Confirmation for destructive actions; `--yes` for explicit automation
- Audit every CLI action without logging passwords, tokens, or private keys
- Install only required packages; expose only SSH, HTTP, and HTTPS
- Keep the Dashboard disabled until an administrator supplies a domain and HTTPS certificate

## Quick start

```bash
sudo bash install.sh --profile minimal --php 8.3
sudo serverctl health
sudo serverctl website add example.com --php 8.3
sudo serverctl ssl enable example.com --email admin@example.com
```

For Ubuntu 22.04, or multi-PHP on Ubuntu 24.04, review the third-party repository note in [INSTALL.md](INSTALL.md). Do not deploy directly to production before testing on a disposable Ubuntu VM and confirming restore procedures.

## Documentation

- [Installation](INSTALL.md)
- [CLI reference](CLI.md)
- [Architecture](ARCHITECTURE.md)
- [Security model](SECURITY.md)
- [Backup and restore](BACKUP.md)
- [Updates](UPDATE.md)
- [Nginx management](NGINX.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Web Dashboard](DASHBOARD.md)

The interactive CLI interface retains its 14 main choices. The optional Web Dashboard is a separate PHP-FPM application and is not added as a CLI menu item.
