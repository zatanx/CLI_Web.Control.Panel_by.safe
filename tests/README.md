# Tests

Run on Linux (or a compatible Bash environment):

```bash
bash -n install.sh bin/serverctl lib/*.sh tests/test.sh
bash tests/test.sh
```

The test harness redirects every managed filesystem path to a temporary root and enables `SERVERCTL_TEST_MODE`; service, user, firewall, and database commands are therefore not executed. It covers validation against command injection/path traversal, registry safety, website isolation config, PHP switching, database metadata, backup integrity, and guarded removal.

Production acceptance still requires a disposable Ubuntu 22.04/24.04 VM because Nginx, PHP-FPM, MariaDB, UFW, Fail2Ban, AppArmor, Certbot/DNS, systemd timers, SSH lockout prevention, and real restore behavior cannot be validated faithfully in a filesystem-only test.

Recommended VM matrix:

- Minimal Ubuntu 24.04 / official PHP 8.3
- Standard Ubuntu 24.04 / approved PHP PPA
- Minimal and standard Ubuntu 22.04 / approved PHP PPA
- Fresh install, duplicate install refusal/idempotency review, add/remove site, PHP switch, live ACME staging certificate, database isolation, backup/restore, firewall recovery, Fail2Ban jail, AppArmor enforce status, reboot, and unattended upgrade
