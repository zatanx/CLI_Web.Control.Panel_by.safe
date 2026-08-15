# Nginx management

Interactive menu 13 and `serverctl nginx` expose native Nginx/systemd operations without a web listener or management daemon.

```bash
serverctl nginx status
sudo serverctl nginx test
sudo serverctl nginx reload
sudo serverctl nginx restart
sudo serverctl nginx backup
serverctl nginx backup-list
sudo serverctl nginx restore 2026-08-14_140000_123456789
serverctl nginx history
```

Reload validates and backs up first. Restart and stop require confirmation. Restore verifies checksums, backs up the current configuration, restores the selected snapshot, runs `nginx -t`, reloads, and restores the previous snapshot if validation or reload fails.

Configuration browsing is read-only. Safe global settings and website upload/rate/cache controls use allow-listed values, build a staged Nginx tree, validate it, show a unified diff, ask for confirmation, apply atomically, reload, and health-check. Arbitrary directives are intentionally not accepted by the restricted sudo interface.

Nginx snapshots are stored under `/var/backups/serverctl/nginx`. Configuration history is read from the shared serverctl audit log.
