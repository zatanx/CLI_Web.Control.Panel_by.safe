# Security

## Defaults

- UFW denies incoming traffic except the detected SSH port, 80, and 443.
- MariaDB binds to `127.0.0.1`; anonymous accounts, remote root rows, and the test database are removed.
- Fail2Ban enables `sshd`, `nginx-http-auth`, and `nginx-limit-req` jails.
- PHP disables display errors, URL includes, and exposure; strict and secure session cookies are enabled.
- Nginx blocks dotfiles, `.env`, repository metadata, SQL/log files, and PHP execution below upload/file directories.
- Site directories are never configured with mode `777`.

Run `sudo serverctl security scan`. Suspicious PHP and permission checks report findings but never delete or repair files automatically. Treat pattern matches as leads, not proof of compromise.

The audit log is `/var/log/serverctl/audit.log`. It records time, local user, SSH source address, action, result, and a non-sensitive detail. Secrets must never be supplied as command-line arguments.

The sudo policy grants the `serverctl-admin` group only the immutable root-owned entry point. Keep `/opt/serverctl`, its modules, and `/etc/serverctl` owned by root and not group-writable.

Before production, verify AppArmor profiles, external firewall policy, SSH allow-lists, application CSP needs, file ownership, exposed ports, alerts, and off-host backups for the actual environment.

`sudo serverctl security ssh harden` disables root login. Add `--disable-password` only while connected through the intended non-root sudo account with a verified `authorized_keys` file. Keep the current session open and prove a second key-based login before disconnecting; serverctl validates `sshd` and rolls back a failed reload, but it cannot prove that a remote key works end to end.
