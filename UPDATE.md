# Updates

Update the installed serverctl code from the `main` branch on GitHub:

```bash
sudo serverctl update serverctl
```

```bash
serverctl update check
sudo serverctl update security
sudo serverctl update all
```

`check` refreshes Ubuntu's package index, simulates the current-release upgrade, separates security and normal updates, and installs nothing. `security` invokes unattended-upgrades after safety checks. `all` runs the normal `apt-get upgrade` path and never starts a full or major distribution upgrade.

Before installation, serverctl checks APT/dpkg locks, disk space, memory, load, Nginx configuration, all installed PHP-FPM services, MariaDB, SSL expiry, and managed websites. It then stores a configuration snapshot under `/var/backups/serverctl/system-update`, shows the package summary and important packages, and asks for confirmation.

After APT finishes, Nginx, PHP-FPM, MariaDB, ports, SSL websites, disk, and memory are checked again. A failed post-check is recorded as `WARNING`; serverctl preserves the backup and update log and never attempts a blind package downgrade. View records with:

```bash
serverctl update history
serverctl update health
serverctl update reboot-status
```

Before kernel, Nginx, PHP, or MariaDB updates, confirm a recent verified off-host backup and plan a maintenance window. After updates, run `serverctl health`, `serverctl security status`, and one application-level check per site.
