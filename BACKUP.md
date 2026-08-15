# Backup and restore

```bash
sudo serverctl backup create --website example.com
sudo serverctl backup create --database erp
sudo serverctl backup create --all
sudo serverctl backup create --all --encrypt
sudo serverctl backup list
sudo serverctl backup verify serverctl-all-YYYYMMDD-HHMMSS.tar.gz
sudo serverctl backup restore serverctl-website-example.com-YYYYMMDD-HHMMSS.tar.gz
sudo serverctl backup sync
```

Archives contain `SHA256SUMS`; verification checks gzip/tar integrity and every payload checksum. `--encrypt` invokes GnuPG symmetric AES-256 encryption in an interactive terminal so the passphrase does not appear in arguments, logs, the web root, Git, or the database. Losing the passphrase makes recovery impossible.

Website and database archives support guarded restore. A full-server archive is verified but intentionally requires component-by-component maintenance-window recovery to avoid overwriting a live host blindly.

The local path defaults to `/var/backups/serverctl` with 30-day retention. Local backup is not disaster recovery. Copy encrypted archives to a separately administered NAS/NFS/SFTP/rsync destination, monitor transfer success, and perform regular restore tests on an isolated server.

Nginx configuration snapshots use `/var/backups/serverctl/nginx`; pre-update configuration snapshots use `/var/backups/serverctl/system-update`. Both include checksums and protected metadata.

For a mounted NAS/NFS/SMB share, set `REMOTE_BACKUP_TARGET=/mnt/backup/server01`. For rsync over SSH, set `REMOTE_BACKUP_TARGET=backupuser@backup.example:/srv/server01` in the root-owned `/etc/serverctl/serverctl.conf`, install a restricted SSH key for root's non-interactive backup connection, then test `serverctl backup sync`. The target format is validated and never evaluated by a shell.
