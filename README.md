# WordPress Setup Script — Debian + Cloudflare

A single script to provision a production-ready WordPress server on a fresh Debian install. Works with any VPS provider (BinaryLane, DigitalOcean, Hetzner, Vultr, etc.) using Cloudflare as the CDN/proxy.

## What It Does

- Updates the system and installs Nginx, MariaDB, PHP
- Generates a secure random database password
- Downloads the latest WordPress and configures it automatically
- Fetches fresh WordPress salts from the WordPress API
- Configures Nginx with security headers and best practices
- Locks web traffic to Cloudflare IPs only
- Sets up Fail2Ban to block brute force attacks
- Installs a Let's Encrypt SSL certificate via Certbot
- Enables automatic security updates

## Requirements

| Requirement | Version |
|---|---|
| Debian | 12 (Bookworm) or 13 (Trixie) |
| PHP | 8.2+ (auto-detected) |
| Nginx | 1.18+ |
| MariaDB | 10.6+ |
| Certbot | 2.0+ |

## Pre-requisites

Before running the script:

1. **Fresh Debian server** with root SSH access (any VPS provider)
2. **Firewall** — if your provider has an external firewall, allow ports 80, 443, and 22
3. **Domain DNS** — A record pointing to your server IP
4. **Cloudflare** — proxy turned **OFF** (grey cloud) before running the script so Certbot can verify your domain. You turn it back on after.

## Usage

```bash
# Download the script
wget https://raw.githubusercontent.com/blankv15/wp-install-script/main/wp-setup.sh

# Run it as root
sudo bash wp-setup.sh
```

You will be prompted for:
- Your domain (e.g. `example.com` or `app.example.com`)
- Whether to include the `www` version (use `n` for subdomains)
- Your email address (used for SSL cert notifications)

Everything else is automatic.

## After the Script Completes

1. Turn the Cloudflare proxy back **ON** (orange cloud) in your DNS settings
2. Set Cloudflare SSL/TLS mode to **Full (Strict)**
3. Enable **Always Use HTTPS** in Cloudflare
4. Visit `https://yourdomain.com/wp-admin/install.php` to complete WordPress setup
5. Install a security plugin — [Wordfence](https://wordpress.org/plugins/wordfence/) or [Solid Security](https://wordpress.org/plugins/better-wp-security/)
6. Set up offsite backups — [UpdraftPlus](https://wordpress.org/plugins/updraftplus/) to Cloudflare R2 or Backblaze B2

## Running Multiple Sites on the Same Server

The script is designed to be re-run for additional sites. Each run will:
- Create a new database and user with a unique name derived from the domain
- Create a new Nginx config for the domain
- Issue a new SSL certificate

Just run `sudo bash wp-setup.sh` again and enter the new domain.

## Security Features

- Cloudflare IP allowlist — direct server access is blocked, all traffic must go through Cloudflare
- Fail2Ban — bans IPs that repeatedly hit `wp-login.php` or `xmlrpc.php`
- `xmlrpc.php` blocked at Nginx level
- PHP execution blocked in the uploads directory
- `DISALLOW_FILE_EDIT` enabled — prevents editing theme/plugin files from WordPress admin
- Security headers set — X-Frame-Options, X-Content-Type-Options, Referrer-Policy etc
- Automatic security updates enabled via `unattended-upgrades`
- Database credentials are randomly generated per site

## Stack

- **Web server:** Nginx
- **Database:** MariaDB
- **PHP:** PHP-FPM (version auto-detected)
- **SSL:** Let's Encrypt via Certbot
- **CDN/Proxy:** Cloudflare
- **Hosting:** Any Debian VPS provider

## Notes

- The script must be run as root
- Tested on Debian 12 (Bookworm) and Debian 13 (Trixie)
- The generated DB password is shown at the end of the script — save it somewhere safe
- Cloudflare IPs in the allowlist may change over time — check [cloudflare.com/ips](https://www.cloudflare.com/ips/) periodically
