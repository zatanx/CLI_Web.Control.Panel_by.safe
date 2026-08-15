# Troubleshooting

Start with:

```bash
sudo serverctl health
sudo serverctl status
sudo nginx -t
sudo journalctl -u nginx -u php8.3-fpm -u mariadb -u fail2ban --since today
```

Useful serverctl logs:

```bash
sudo serverctl logs nginx --lines 100
sudo serverctl logs php --lines 100
sudo serverctl logs serverctl --lines 100
```

If a site add or PHP switch fails, serverctl does not reload an invalid configuration. Inspect `/var/log/serverctl/serverctl.log`, the relevant file in `/etc/nginx/sites-available`, and the pool in `/etc/php/<version>/fpm/pool.d`.

For SSL failures, confirm public DNS points to the server, TCP/80 is reachable through both firewalls, the ACME path is not proxied incorrectly, and system time is correct. Use `certbot certificates` and `systemctl status certbot.timer`.

Never solve permission errors with `chmod 777`. Verify the site's recorded user with `serverctl website list`, then correct ownership narrowly.
