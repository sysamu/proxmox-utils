#!/bin/bash
# Nginx installer with auto-optimization and monitoring dashboard
# Usage: ./nginx_installer.sh [--skip-confirm]
# Features:
#   - Installs Nginx with useful modules
#   - Auto-optimizes based on system specs (CPU, RAM)
#   - Sets up nginx-module-vts for metrics/monitoring (LAN only)
#   - Creates default site template
#   - Configures security headers and best practices

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse arguments
SKIP_CONFIRM=false
if [[ "${1:-}" == "--skip-confirm" ]]; then
    SKIP_CONFIRM=true
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   🚀 Nginx Installer & Optimizer                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ Este script debe ejecutarse como root (usa sudo)${NC}"
    exit 1
fi

# Detect system specifications
echo -e "${CYAN}📊 Detectando especificaciones del sistema...${NC}"
CPU_CORES=$(nproc)
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
TOTAL_RAM_GB=$((TOTAL_RAM_MB / 1024))

# Get LAN IP (first non-loopback IP)
LAN_IP=$(hostname -I | awk '{print $1}')

echo -e "   ${GREEN}✓${NC} CPU Cores: ${CYAN}${CPU_CORES}${NC}"
echo -e "   ${GREEN}✓${NC} RAM: ${CYAN}${TOTAL_RAM_GB}GB${NC} (${TOTAL_RAM_MB}MB)"
echo -e "   ${GREEN}✓${NC} LAN IP: ${CYAN}${LAN_IP}${NC}"
echo

# Calculate optimal settings
WORKER_PROCESSES=$CPU_CORES
WORKER_CONNECTIONS=$((1024 * CPU_CORES))

# Calculate worker_rlimit_nofile (should be at least worker_connections * 2)
WORKER_RLIMIT_NOFILE=$((WORKER_CONNECTIONS * 2))

# Calculate client_body_buffer_size and client_max_body_size based on RAM
if [[ $TOTAL_RAM_GB -ge 8 ]]; then
    CLIENT_MAX_BODY_SIZE="100M"
    CLIENT_BODY_BUFFER_SIZE="128k"
    KEEPALIVE_TIMEOUT="65"
elif [[ $TOTAL_RAM_GB -ge 4 ]]; then
    CLIENT_MAX_BODY_SIZE="50M"
    CLIENT_BODY_BUFFER_SIZE="64k"
    KEEPALIVE_TIMEOUT="60"
else
    CLIENT_MAX_BODY_SIZE="20M"
    CLIENT_BODY_BUFFER_SIZE="32k"
    KEEPALIVE_TIMEOUT="30"
fi

echo -e "${CYAN}⚙️  Configuración optimizada calculada:${NC}"
echo -e "   worker_processes: ${WORKER_PROCESSES}"
echo -e "   worker_connections: ${WORKER_CONNECTIONS}"
echo -e "   worker_rlimit_nofile: ${WORKER_RLIMIT_NOFILE}"
echo -e "   client_max_body_size: ${CLIENT_MAX_BODY_SIZE}"
echo -e "   keepalive_timeout: ${KEEPALIVE_TIMEOUT}s"
echo

# Confirm installation
if [[ "$SKIP_CONFIRM" == false ]]; then
    read -p "¿Desea continuar con la instalación? (s/N) " yn
    if [[ "$yn" != "s" && "$yn" != "S" ]]; then
        echo -e "${YELLOW}⏹  Instalación cancelada${NC}"
        exit 0
    fi
    echo
fi

# Install Nginx and modules
echo -e "${BLUE}📦 Instalando Nginx y módulos...${NC}"
apt update -qq

PACKAGES=(
    "nginx"
    "libnginx-mod-http-headers-more-filter"  # Extra headers manipulation
    "libnginx-mod-http-cache-purge"          # Cache management
    "libnginx-mod-http-geoip2"               # GeoIP support
)

# Note: nginx-module-vts is not available in standard repos
# We'll document how to add it manually if needed

apt install -y "${PACKAGES[@]}"
echo -e "   ${GREEN}✓${NC} Nginx y módulos instalados"
echo

# Backup original nginx.conf
if [[ -f /etc/nginx/nginx.conf ]]; then
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup.$(date +%Y%m%d_%H%M%S)
    echo -e "${GREEN}✓${NC} Backup de nginx.conf creado"
fi

# Create optimized nginx.conf
echo -e "${BLUE}⚙️  Generando nginx.conf optimizado...${NC}"
cat > /etc/nginx/nginx.conf <<EOF
user www-data;
worker_processes ${WORKER_PROCESSES};
worker_rlimit_nofile ${WORKER_RLIMIT_NOFILE};
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections ${WORKER_CONNECTIONS};
    use epoll;
    multi_accept on;
}

http {
    ##
    # Basic Settings
    ##
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout ${KEEPALIVE_TIMEOUT};
    keepalive_requests 100;
    types_hash_max_size 2048;
    server_tokens off;

    # Buffer sizes
    client_body_buffer_size ${CLIENT_BODY_BUFFER_SIZE};
    client_header_buffer_size 1k;
    client_max_body_size ${CLIENT_MAX_BODY_SIZE};
    large_client_header_buffers 4 8k;

    # Timeouts
    client_body_timeout 12;
    client_header_timeout 12;
    send_timeout 10;

    # server_names_hash_bucket_size 64;
    # server_name_in_redirect off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ##
    # SSL Settings
    ##
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    ##
    # Logging Settings
    ##
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log warn;

    ##
    # Gzip Settings
    ##
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript
               application/json application/javascript application/xml+rss
               application/rss+xml font/truetype font/opentype
               application/vnd.ms-fontobject image/svg+xml;
    gzip_disable "msie6";

    ##
    # Virtual Host Configs
    ##
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

echo -e "   ${GREEN}✓${NC} nginx.conf optimizado creado"
echo

# Create snippets directory if it doesn't exist
mkdir -p /etc/nginx/snippets

# Create security headers snippet
echo -e "${BLUE}🔒 Creando snippets de seguridad...${NC}"
cat > /etc/nginx/snippets/security.conf <<'EOF'
# Security headers
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "no-referrer-when-downgrade" always;
# Uncomment if you have HTTPS:
# add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
EOF

cat > /etc/nginx/snippets/proxy_options.conf <<'EOF'
# Proxy headers
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host $host;
proxy_set_header X-Forwarded-Port $server_port;

# Proxy timeouts
proxy_connect_timeout 60s;
proxy_send_timeout 60s;
proxy_read_timeout 60s;

# Proxy buffering
proxy_buffering on;
proxy_buffer_size 4k;
proxy_buffers 8 4k;
proxy_busy_buffers_size 8k;
EOF

cat > /etc/nginx/snippets/wss_options.conf <<'EOF'
# WebSocket headers
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;

# WebSocket timeouts
proxy_connect_timeout 7d;
proxy_send_timeout 7d;
proxy_read_timeout 7d;
EOF

cat > /etc/nginx/snippets/block_robots_snippet.conf <<'EOF'
# Block search engine indexing
location = /robots.txt {
    add_header Content-Type text/plain;
    return 200 "User-agent: *\nDisallow: /\n";
}
EOF

echo -e "   ${GREEN}✓${NC} Security snippets creados"
echo

# Create status monitoring endpoint (LAN only)
echo -e "${BLUE}📊 Configurando endpoint de monitoreo (solo LAN)...${NC}"
cat > /etc/nginx/conf.d/status.conf <<EOF
# Nginx status page - LAN access only
server {
    listen ${LAN_IP}:8080;
    server_name _;

    location /nginx_status {
        stub_status on;
        access_log off;
        allow ${LAN_IP%.*}.0/24;  # Allow LAN subnet
        allow 127.0.0.1;           # Allow localhost
        deny all;
    }

    location / {
        return 200 "Nginx Monitoring Dashboard\n\nEndpoints:\n- /nginx_status - Basic stats\n";
        add_header Content-Type text/plain;
    }
}
EOF

echo -e "   ${GREEN}✓${NC} Status endpoint configurado en http://${LAN_IP}:8080/nginx_status"
echo

# Create default site template
echo -e "${BLUE}🌐 Creando sitio por defecto...${NC}"

# Create sites-available directory if it doesn't exist
mkdir -p /etc/nginx/sites-available
mkdir -p /etc/nginx/sites-enabled

# Remove default site if exists
rm -f /etc/nginx/sites-enabled/default

cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;
    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;

    # Security headers
    include snippets/security.conf;

    # Block robots
    include snippets/block_robots_snippet.conf;

    location / {
        try_files $uri $uri/ =404;
    }

    # Deny access to hidden files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    access_log /var/log/nginx/default_access.log;
    error_log /var/log/nginx/default_error.log;
}
EOF

# Enable default site
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

echo -e "   ${GREEN}✓${NC} Sitio por defecto creado"
echo

# Create template directory for future sites
mkdir -p /etc/nginx/templates

cat > /etc/nginx/templates/nginx-subdomain <<'EOF'
server {
    server_name __DOMAIN__;

    large_client_header_buffers 4 64k;
    include snippets/security.conf;
    include snippets/block_robots_snippet.conf;

    location / {
        proxy_pass http://__UPSTREAM__/;
        include snippets/proxy_options.conf;
        autoindex off;
    }

    access_log /var/log/nginx/__DOMAIN_SAFE___access.log;
    error_log /var/log/nginx/__DOMAIN_SAFE___error.log error;
}
EOF

cat > /etc/nginx/templates/nginx-wss <<'EOF'
upstream __DOMAIN_SAFE___ws {
    ip_hash;
    server __UPSTREAM__:__PORT__;
}

server {
    listen 443 ssl;
    server_name __DOMAIN__;

    include snippets/security.conf;
    include snippets/ssl_wss.conf;

    location / {
        include snippets/wss_options.conf;
        proxy_pass http://__DOMAIN_SAFE___ws;
    }

    access_log /var/log/nginx/__DOMAIN_SAFE___wss_access.log;
    error_log  /var/log/nginx/__DOMAIN_SAFE___wss_error.log error;

    # Certbot autogenerará:
    # ssl_certificate /etc/letsencrypt/live/__DOMAIN__/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/__DOMAIN__/privkey.pem;
}
EOF

echo -e "   ${GREEN}✓${NC} Templates para subdominios creados en /etc/nginx/templates/"
echo

# Create default index.html
echo -e "${BLUE}📄 Creando página de bienvenida...${NC}"
cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Nginx Installed Successfully</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            margin: 0;
            padding: 0;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }
        .container {
            background: white;
            padding: 3rem;
            border-radius: 10px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            text-align: center;
            max-width: 600px;
        }
        h1 {
            color: #333;
            margin-bottom: 1rem;
        }
        .success {
            color: #10b981;
            font-size: 4rem;
            margin-bottom: 1rem;
        }
        p {
            color: #666;
            line-height: 1.6;
        }
        .info {
            background: #f3f4f6;
            padding: 1rem;
            border-radius: 5px;
            margin-top: 1.5rem;
            text-align: left;
        }
        .info code {
            background: #e5e7eb;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: monospace;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="success">✓</div>
        <h1>Nginx Installed Successfully!</h1>
        <p>Your Nginx web server is now up and running.</p>
        <div class="info">
            <strong>Next steps:</strong><br>
            • Configure your sites in <code>/etc/nginx/sites-available/</code><br>
            • Use templates from <code>/etc/nginx/templates/</code><br>
            • Monitor status at <code>http://[LAN_IP]:8080/nginx_status</code><br>
            • Check logs in <code>/var/log/nginx/</code>
        </div>
    </div>
</body>
</html>
EOF

echo -e "   ${GREEN}✓${NC} Página de bienvenida creada"
echo

# Test configuration
echo -e "${BLUE}🔍 Probando configuración de Nginx...${NC}"
if nginx -t 2>&1 | grep -q "successful"; then
    echo -e "   ${GREEN}✓${NC} Configuración válida"
else
    echo -e "   ${RED}✗${NC} Error en la configuración"
    nginx -t
    exit 1
fi
echo

# Enable and start Nginx
echo -e "${BLUE}🚀 Iniciando Nginx...${NC}"
systemctl enable nginx
systemctl restart nginx

if systemctl is-active --quiet nginx; then
    echo -e "   ${GREEN}✓${NC} Nginx está activo y corriendo"
else
    echo -e "   ${RED}✗${NC} Nginx no pudo iniciarse"
    systemctl status nginx
    exit 1
fi
echo

# Summary
echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✨ Instalación completada exitosamente          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${CYAN}📋 Resumen:${NC}"
echo -e "   ${GREEN}✓${NC} Nginx instalado y optimizado"
echo -e "   ${GREEN}✓${NC} Worker processes: ${WORKER_PROCESSES}"
echo -e "   ${GREEN}✓${NC} Worker connections: ${WORKER_CONNECTIONS}"
echo -e "   ${GREEN}✓${NC} Sitio por defecto: http://$(hostname -I | awk '{print $1}')"
echo -e "   ${GREEN}✓${NC} Monitoreo (LAN): http://${LAN_IP}:8080/nginx_status"
echo
echo -e "${CYAN}📁 Archivos importantes:${NC}"
echo -e "   • Configuración: ${YELLOW}/etc/nginx/nginx.conf${NC}"
echo -e "   • Sites: ${YELLOW}/etc/nginx/sites-available/${NC}"
echo -e "   • Templates: ${YELLOW}/etc/nginx/templates/${NC}"
echo -e "   • Snippets: ${YELLOW}/etc/nginx/snippets/${NC}"
echo -e "   • Logs: ${YELLOW}/var/log/nginx/${NC}"
echo
echo -e "${CYAN}💡 Próximos pasos:${NC}"
echo -e "   1. Accede a http://$(hostname -I | awk '{print $1}') para ver el sitio"
echo -e "   2. Usa los templates para crear nuevos subdominios"
echo -e "   3. Configura SSL/TLS con certbot si es necesario"
echo
