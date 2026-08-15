# Installation

## Requirements

- Ubuntu Server 22.04 or 24.04 LTS (`amd64` or `arm64`)
- Root privileges, 1 GB RAM minimum, 5 GB free disk minimum
- Working DNS and internet access
- A tested SSH key for the administering sudo user
- A clean host; the installer refuses to proceed when existing non-default Nginx sites are enabled

Clone or copy this directory to the server, inspect the installer, then run:

```bash
sudo bash install.sh --profile minimal --php 8.3
```

Profiles:

- `minimal`: the chosen PHP version plus the production core
- `standard`: PHP 8.2, 8.3, 8.4, Lynis, and rkhunter
- `custom`: select PHP versions with `--php-versions` and optional audit tools with `--with-audit`

Ubuntu 24.04 provides PHP 8.3 in its official repository. Ubuntu 22.04 and multi-version installs require `--enable-php-ppa`, which authorizes the external `ppa:ondrej/php` repository. Review and approve that trust decision before using it:

```bash
sudo bash install.sh --profile standard --php 8.3 --enable-php-ppa
sudo bash install.sh --profile custom --php 8.3 --php-versions 8.3,8.4 --with-audit --enable-php-ppa
```

The installer checks OS, release, architecture, RAM, disk, CPU, DNS/internet, and root privileges before changing the system. Its log is `/var/log/serverctl/install.log`.

## After installation

Keep the current SSH session open, verify a second key-based login, and run:

```bash
sudo serverctl health
sudo serverctl security status
sudo serverctl update check
```

The installer places the optional Dashboard source at `/opt/serverctl/dashboard`
but leaves it disabled. After a DNS record and HTTPS certificate exist, enable
it on a dedicated hostname:

```bash
sudo serverctl dashboard status
sudo serverctl dashboard install dashboard.example.com
```

The enable step creates a separate Nginx site, requires the certificate,
redirects HTTP to HTTPS, asks for a Dashboard password, validates `nginx -t`,
and reloads Nginx. See [DASHBOARD.md](DASHBOARD.md) for the security model and
uninstall command.

The installer only disables root SSH login when it can verify `authorized_keys` for the invoking sudo user. It does not automatically disable password authentication; do that only after testing another key-based session.
