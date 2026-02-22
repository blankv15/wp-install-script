# Changelog

All notable changes to this project will be documented here.

## [1.0.0] - 2026-02-22

### Initial release
- Automated WordPress install on Debian 12/13
- Nginx, MariaDB, PHP-FPM setup
- Auto-detected PHP version
- Random DB password generation
- WordPress salts fetched automatically from WordPress API
- Cloudflare IP allowlist for Nginx
- Fail2Ban with WordPress brute force filter
- Let's Encrypt SSL via Certbot
- Automatic security updates via unattended-upgrades
- Multi-site support (re-run for additional domains)
