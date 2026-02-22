#!/bin/bash
# =============================================================================
# WordPress Setup Script for Debian (BinaryLane + Cloudflare)
# Usage: sudo bash wp-setup.sh
# =============================================================================

set -e

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── Root check ────────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  error "Please run as root: sudo bash wp-setup.sh"
fi

# ── Gather inputs ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       WordPress Setup — Debian + Cloudflare  ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""

read -p "Domain (e.g. example.com, no www): " DOMAIN
read -p "Email (for SSL cert): " EMAIL

# Derive safe names from domain for DB
SAFE_NAME=$(echo "$DOMAIN" | tr '.' '_' | tr '-' '_')
DB_NAME="wp_${SAFE_NAME}"
DB_USER="wpuser_${SAFE_NAME}"
DB_PASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)
WP_DIR="/var/www/${DOMAIN}"

echo ""
info "Domain:   $DOMAIN"
info "WP Dir:   $WP_DIR"
info "DB Name:  $DB_NAME"
info "DB User:  $DB_USER"
echo ""
read -p "Continue? (y/n): " CONFIRM
[[ "$CONFIRM" != "y" ]] && exit 0

# ── System update ─────────────────────────────────────────────────────────────
info "Updating system..."
apt update && apt upgrade -y
apt install -y curl wget ufw fail2ban unattended-upgrades
success "System updated"

# ── UFW firewall ──────────────────────────────────────────────────────────────
info "Configuring firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
success "Firewall configured"

# ── Nginx ─────────────────────────────────────────────────────────────────────
info "Installing Nginx..."
apt install -y nginx
systemctl enable nginx --now
rm -f /etc/nginx/sites-enabled/default
success "Nginx installed"

# ── MariaDB ───────────────────────────────────────────────────────────────────
info "Installing MariaDB..."
apt install -y mariadb-server
systemctl enable mariadb --now

# Secure MariaDB non-interactively
mysql -u root <<EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
success "MariaDB installed and secured"

# ── PHP ───────────────────────────────────────────────────────────────────────
info "Installing PHP..."
apt install -y php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-zip php-intl php-bcmath php-imagick

# Detect PHP version
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
PHP_INI="/etc/php/${PHP_VER}/fpm/php.ini"
PHP_SOCK="/run/php/php${PHP_VER}-fpm.sock"

info "Detected PHP $PHP_VER"

# Tune PHP
sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$PHP_INI"
sed -i 's/post_max_size = .*/post_max_size = 64M/' "$PHP_INI"
sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
sed -i 's/memory_limit = .*/memory_limit = 256M/' "$PHP_INI"

systemctl restart "php${PHP_VER}-fpm"
success "PHP $PHP_VER installed and tuned"

# ── Database ──────────────────────────────────────────────────────────────────
info "Creating database..."
mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
success "Database created"

# ── WordPress ─────────────────────────────────────────────────────────────────
info "Downloading WordPress..."
cd /tmp
wget -q https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
rm -rf "$WP_DIR"
mv wordpress "$WP_DIR"

# Fetch salts
info "Fetching WordPress salts..."
SALTS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)

# Write wp-config.php
cat > "${WP_DIR}/wp-config.php" <<WPCONFIG
<?php
define( 'DB_NAME',     '${DB_NAME}' );
define( 'DB_USER',     '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASS}' );
define( 'DB_HOST',     'localhost' );
define( 'DB_CHARSET',  'utf8mb4' );
define( 'DB_COLLATE',  '' );

${SALTS}

\$table_prefix = 'wp_';

define( 'WP_HOME',    'https://${DOMAIN}' );
define( 'WP_SITEURL', 'https://${DOMAIN}' );

define( 'FORCE_SSL_ADMIN',    true );
define( 'DISALLOW_FILE_EDIT', true );
define( 'WP_DEBUG',           false );

if ( isset( \$_SERVER['HTTP_X_FORWARDED_PROTO'] ) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' ) {
    \$_SERVER['HTTPS'] = 'on';
}

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}

require_once ABSPATH . 'wp-settings.php';
WPCONFIG

# Permissions
chown -R www-data:www-data "$WP_DIR"
find "$WP_DIR" -type d -exec chmod 755 {} \;
find "$WP_DIR" -type f -exec chmod 644 {} \;
chmod 640 "${WP_DIR}/wp-config.php"

success "WordPress downloaded and configured"

# ── Cloudflare IP allowlist ───────────────────────────────────────────────────
info "Writing Cloudflare IP allowlist..."
mkdir -p /etc/nginx/snippets
cat > /etc/nginx/snippets/cloudflare-ips.conf <<'EOF'
# Cloudflare IPv4
allow 173.245.48.0/20;
allow 103.21.244.0/22;
allow 103.22.200.0/22;
allow 103.31.4.0/22;
allow 141.101.64.0/18;
allow 108.162.192.0/18;
allow 190.93.240.0/20;
allow 188.114.96.0/20;
allow 197.234.240.0/22;
allow 198.41.128.0/17;
allow 162.158.0.0/15;
allow 104.16.0.0/13;
allow 104.24.0.0/14;
allow 172.64.0.0/13;
allow 131.0.72.0/22;
# Cloudflare IPv6
allow 2400:cb00::/32;
allow 2606:4700::/32;
allow 2803:f800::/32;
allow 2405:b500::/32;
allow 2405:8100::/32;
allow 2a06:98c0::/29;
allow 2c0f:f248::/32;
deny all;
EOF
success "Cloudflare IPs configured"

# ── Nginx site config ─────────────────────────────────────────────────────────
info "Writing Nginx config..."
cat > "/etc/nginx/sites-available/${DOMAIN}" <<NGINXCONF
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};
    root ${WP_DIR};
    index index.php index.html;

    access_log /var/log/nginx/${DOMAIN}.access.log;
    error_log  /var/log/nginx/${DOMAIN}.error.log;

    include snippets/cloudflare-ips.conf;

    client_max_body_size 64M;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;

    location ~ /\.(ht|git|env) { deny all; }
    location = /wp-config.php  { deny all; }

    location = /xmlrpc.php {
        deny all;
        access_log off;
        log_not_found off;
    }

    location ~* /wp-content/uploads/.*\.php$ { deny all; }

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCK};
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_hide_header X-Powered-By;
    }

    location ~* \.(jpg|jpeg|gif|png|webp|svg|ico|css|js|woff2?)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
}
NGINXCONF

ln -sf "/etc/nginx/sites-available/${DOMAIN}" "/etc/nginx/sites-enabled/${DOMAIN}"
nginx -t && systemctl reload nginx
success "Nginx configured"

# ── Fail2Ban ──────────────────────────────────────────────────────────────────
info "Configuring Fail2Ban..."
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port    = 22
logpath = /var/log/auth.log

[nginx-http-auth]
enabled = true

[wordpress]
enabled  = true
filter   = wordpress
logpath  = /var/log/nginx/access.log
maxretry = 5
EOF

cat > /etc/fail2ban/filter.d/wordpress.conf <<'EOF'
[Definition]
failregex = ^<HOST> .* "POST /wp-login.php
            ^<HOST> .* "POST /xmlrpc.php
ignoreregex =
EOF

systemctl enable fail2ban --now
success "Fail2Ban configured"

# ── Automatic security updates ────────────────────────────────────────────────
info "Enabling automatic security updates..."
echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades
systemctl enable unattended-upgrades --now
success "Auto updates enabled"

# ── SSL ───────────────────────────────────────────────────────────────────────
echo ""
warn "SSL Setup — Before running Certbot:"
warn "1. Make sure your domain's DNS A record points to this server IP"
warn "2. Turn OFF the Cloudflare proxy (grey cloud) temporarily"
warn "3. Then press Enter to continue"
read -p "Press Enter when ready..."

info "Installing Certbot..."
apt install -y certbot python3-certbot-nginx
certbot --nginx -d "${DOMAIN}" -d "www.${DOMAIN}" --email "$EMAIL" --agree-tos --non-interactive
systemctl enable certbot.timer
success "SSL certificate installed"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Setup Complete!                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Site URL:    ${BLUE}https://${DOMAIN}/wp-admin/install.php${NC}"
echo -e "  DB Name:     ${YELLOW}${DB_NAME}${NC}"
echo -e "  DB User:     ${YELLOW}${DB_USER}${NC}"
echo -e "  DB Password: ${RED}${DB_PASS}${NC}"
echo ""
echo -e "${YELLOW}Save the DB password above — it won't be shown again!${NC}"
echo ""
echo -e "Next steps:"
echo -e "  1. Turn the Cloudflare proxy back ON (orange cloud)"
echo -e "  2. Set Cloudflare SSL/TLS to Full (Strict)"
echo -e "  3. Visit https://${DOMAIN}/wp-admin/install.php"
echo ""
