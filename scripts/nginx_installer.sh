#!/bin/bash
# Nginx installer for static content serving (HTTP only, port 80)
# Usage: ./nginx_installer.sh [--skip-confirm]
# Features:
#   - Installs Nginx optimized for static content (images, files, etc.)
#   - Auto-optimizes based on system specs (CPU, RAM)
#   - Configures caching for static assets
#   - Enables gzip compression
#   - Sets up monitoring endpoint (LAN only)
#   - Creates default site template for static serving

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
    "libnginx-mod-http-cache-purge"  # Cache management
)

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

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ##
    # Logging Settings
    ##
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log warn;

    ##
    # Gzip Compression
    ##
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 256;
    gzip_types text/plain text/css text/xml text/javascript
               application/json application/javascript application/xml+rss
               application/rss+xml font/truetype font/opentype
               application/vnd.ms-fontobject image/svg+xml;
    gzip_disable "msie6";

    ##
    # Static File Caching
    ##
    # Cache directory: levels=1:2 creates subdirectories for efficient lookup
    # keys_zone=static_cache:10m allocates 10MB for cache keys (~80,000 keys)
    # max_size=1g limits cache to 1GB
    # inactive=60m removes cached items not accessed in 60 minutes
    proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=static_cache:10m max_size=1g inactive=60m use_temp_path=off;

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

# Create static file caching snippet
echo -e "${BLUE}💾 Creando snippets de caché...${NC}"
cat > /etc/nginx/snippets/static_cache.conf <<'EOF'
# Static file caching configuration
location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|webp|woff|woff2|ttf|eot)$ {
    expires 30d;
    add_header Cache-Control "public, immutable";
    access_log off;
}

# Additional static assets
location ~* \.(pdf|zip|tar|gz|rar)$ {
    expires 7d;
    add_header Cache-Control "public";
}
EOF

echo -e "   ${GREEN}✓${NC} Cache snippets creados"
echo

# Create cache directory
mkdir -p /var/cache/nginx
chown www-data:www-data /var/cache/nginx

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
echo -e "   ${GREEN}✓${NC} Cache directory creado en /var/cache/nginx"
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
    index index.html index.htm;

    # Static file caching
    include snippets/static_cache.conf;

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

cat > /etc/nginx/templates/nginx-static <<'EOF'
# Template for static content serving (images, files, etc.)
# Usage: Replace __DOMAIN__ and __DOMAIN_SAFE__
server {
    listen 80;
    server_name __DOMAIN__;

    root /var/www/__DOMAIN__;
    index index.html;

    # Static file caching
    include snippets/static_cache.conf;

    location / {
        try_files $uri $uri/ =404;
    }

    # Deny access to hidden files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    access_log /var/log/nginx/__DOMAIN_SAFE___access.log;
    error_log /var/log/nginx/__DOMAIN_SAFE___error.log;
}
EOF

echo -e "   ${GREEN}✓${NC} Template para sitios estáticos creado en /etc/nginx/templates/"
echo

# Create default index.html
echo -e "${BLUE}📄 Creando página de bienvenida...${NC}"
cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Nginx Static Server</title>
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
        .feature {
            color: #059669;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="success">✓</div>
        <h1>Nginx Static Server Ready!</h1>
        <p>Optimized for serving static content (images, files, etc.)</p>
        <div class="info">
            <strong class="feature">Features enabled:</strong><br>
            • <strong>Gzip compression</strong> for text files<br>
            • <strong>Browser caching</strong> for static assets<br>
            • <strong>Performance optimization</strong> based on system specs<br>
            <br>
            <strong>Next steps:</strong><br>
            • Upload files to <code>/var/www/html/</code><br>
            • Use template from <code>/etc/nginx/templates/nginx-static</code><br>
            • Monitor at <code>http://[LAN_IP]:8080/nginx_status</code>
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
echo -e "   ${GREEN}✓${NC} Nginx instalado y optimizado para contenido estático"
echo -e "   ${GREEN}✓${NC} Worker processes: ${WORKER_PROCESSES}"
echo -e "   ${GREEN}✓${NC} Worker connections: ${WORKER_CONNECTIONS}"
echo -e "   ${GREEN}✓${NC} Gzip compression: Habilitado"
echo -e "   ${GREEN}✓${NC} Browser caching: 30 días para imágenes/CSS/JS"
echo -e "   ${GREEN}✓${NC} Cache directory: /var/cache/nginx"
echo
echo -e "${CYAN}🌐 Acceso:${NC}"
echo -e "   • Sitio principal: ${YELLOW}http://$(hostname -I | awk '{print $1}')${NC}"
echo -e "   • Monitoreo (LAN): ${YELLOW}http://${LAN_IP}:8080/nginx_status${NC}"
echo
echo -e "${CYAN}📁 Archivos importantes:${NC}"
echo -e "   • Configuración: ${YELLOW}/etc/nginx/nginx.conf${NC}"
echo -e "   • Sites: ${YELLOW}/etc/nginx/sites-available/${NC}"
echo -e "   • Template: ${YELLOW}/etc/nginx/templates/nginx-static${NC}"
echo -e "   • Cache snippet: ${YELLOW}/etc/nginx/snippets/static_cache.conf${NC}"
echo -e "   • Logs: ${YELLOW}/var/log/nginx/${NC}"
echo -e "   • Web root: ${YELLOW}/var/www/html/${NC}"
echo
echo -e "${CYAN}💡 Crear nuevo sitio estático:${NC}"
echo -e "   1. Copia el template: ${YELLOW}cp /etc/nginx/templates/nginx-static /etc/nginx/sites-available/mysite.conf${NC}"
echo -e "   2. Edita y reemplaza __DOMAIN__ y __DOMAIN_SAFE__"
echo -e "   3. Crea el directorio: ${YELLOW}mkdir -p /var/www/mysite${NC}"
echo -e "   4. Habilita el sitio: ${YELLOW}ln -s /etc/nginx/sites-available/mysite.conf /etc/nginx/sites-enabled/${NC}"
echo -e "   5. Recarga Nginx: ${YELLOW}nginx -t && systemctl reload nginx${NC}"
echo
