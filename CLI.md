# CLI reference

Global flags are `--no-color` and `--yes`. Exit codes are: `0` success, `1` general error, `2` invalid argument, `3` permission error, `4` validation error, `5` system error.

```text
serverctl                              Interactive menu
serverctl status [--watch]
serverctl health

# Website names may be public domains, localhost, or IPv4 addresses. HTTP-only
# localhost/private-LAN sites do not require an SSL certificate.
serverctl website list
serverctl website add DOMAIN|IP|localhost [--php 8.2|8.3|8.4] [--yes]
serverctl website remove DOMAIN|IP|localhost [--yes] [--no-backup]
serverctl website health DOMAIN|IP|localhost
serverctl website csp DOMAIN|IP|localhost 'POLICY' [--yes]

serverctl php list
serverctl php set DOMAIN VERSION [--yes]
serverctl php health DOMAIN

serverctl ssl enable DOMAIN [--email ADDRESS] [--yes]
serverctl ssl status [DOMAIN]
serverctl ssl health DOMAIN

serverctl database list
serverctl database create NAME [--yes]
serverctl database remove NAME [--yes] [--no-backup]
serverctl database health [NAME]

serverctl sftp list
serverctl sftp password DOMAIN|IP|localhost
serverctl sftp enable DOMAIN|IP|localhost
serverctl sftp disable DOMAIN|IP|localhost

serverctl backup create [--all|--website DOMAIN|--database NAME] [--encrypt]
serverctl backup list
serverctl backup verify ARCHIVE
serverctl backup encrypt ARCHIVE
serverctl backup restore ARCHIVE [--yes]
serverctl backup delete ARCHIVE [--yes]
serverctl backup sync

serverctl logs nginx|php|mariadb|fail2ban|firewall|system|serverctl [--lines 50|100|500] [--follow] [--search TEXT]

serverctl security status
serverctl security scan
serverctl security ports
serverctl security permissions
serverctl security php-scan
serverctl security suid
serverctl security services
serverctl security updates
serverctl security audit
serverctl security ssh
serverctl security ssh harden [--disable-password]

serverctl firewall status|list|reload
serverctl firewall add PORT [tcp|udp] [SOURCE_IP_OR_CIDR]
serverctl firewall remove RULE_NUMBER

serverctl fail2ban status|list
serverctl fail2ban ban IP
serverctl fail2ban unban IP

serverctl update check|security|all
serverctl update history
serverctl update health
serverctl update reboot-status

serverctl dashboard status
serverctl dashboard snapshot
serverctl dashboard websites
serverctl dashboard logs TYPE [50|100|500] [SEARCH]
serverctl dashboard action ACTION [TARGET]
serverctl dashboard install DOMAIN [--user USER] [--password-hash HASH]
serverctl dashboard uninstall

serverctl nginx status|test|reload|restart|stop|start
serverctl nginx config main|available|enabled|snippets|included
serverctl nginx global show
serverctl nginx global set worker_processes auto|1-64
serverctl nginx global set worker_connections 128-65535
serverctl nginx global set keepalive_timeout|client_body_timeout|client_header_timeout|send_timeout VALUE
serverctl nginx global set client_max_body_size SIZE
serverctl nginx global set gzip on|off
serverctl nginx website list
serverctl nginx website view DOMAIN
serverctl nginx website set DOMAIN upload-limit SIZE
serverctl nginx website set DOMAIN rate-limit BURST
serverctl nginx website set DOMAIN static-cache on|off
serverctl nginx website access DOMAIN list
serverctl nginx website access DOMAIN allow|deny IP_OR_CIDR
serverctl nginx website access DOMAIN clear
serverctl nginx security
serverctl nginx access-log|error-log [global|DOMAIN] [--lines 50|100|500] [--follow] [--search TEXT]
serverctl nginx backup
serverctl nginx backup-list
serverctl nginx restore BACKUP_NAME
serverctl nginx history
```

Destructive commands default to a typed confirmation. For unattended automation, `--yes` is an explicit acknowledgement; website and database removal still create a backup unless `--no-backup` is also supplied.
