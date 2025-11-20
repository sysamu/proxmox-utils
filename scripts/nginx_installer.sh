#!/bin/bash
# Nginx installer for static content serving (HTTP only, port 80)
# Usage: ./nginx_installer.sh [--skip-confirm] [--site DOMAIN] [--uninstall]
# Examples:
#   ./nginx_installer.sh                              # Install only
#   ./nginx_installer.sh --site images.example.com   # Install + create site
#   ./nginx_installer.sh --skip-confirm --site images.example.com
#   ./nginx_installer.sh --uninstall                  # Uninstall Nginx and all configurations
# Features:
#   - Installs Nginx optimized for static content (images, files, etc.)
#   - Auto-optimizes based on system specs (CPU, RAM)
#   - Configures caching for static assets
#   - Enables gzip compression
#   - Sets up monitoring endpoint (LAN only)
#   - Creates default site template for static serving
#   - Optionally creates a configured site from template

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
SITE_DOMAIN=""
UNINSTALL_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-confirm)
            SKIP_CONFIRM=true
            shift
            ;;
        --site)
            SITE_DOMAIN="$2"
            shift 2
            ;;
        --uninstall)
            UNINSTALL_MODE=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown argument: $1${NC}"
            echo "Usage: $0 [--skip-confirm] [--site DOMAIN] [--uninstall]"
            exit 1
            ;;
    esac
done

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ Este script debe ejecutarse como root (usa sudo)${NC}"
    exit 1
fi

# Uninstall mode
if [[ "$UNINSTALL_MODE" == true ]]; then
    echo -e "${RED}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║   🗑️  Nginx Uninstaller                           ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════╝${NC}"
    echo

    echo -e "${BLUE}📦 Paquetes a desinstalar:${NC}"
    echo "   - nginx"
    echo "   - libnginx-mod-http-cache-purge"
    echo

    echo -e "${BLUE}📁 Directorios y archivos a eliminar:${NC}"
    echo "   - /etc/nginx/ (configuración)"
    echo "   - /var/log/nginx/ (logs)"
    echo "   - /var/cache/nginx/ (caché)"
    echo

    echo -e "${YELLOW}ℹ  /var/www/html/ NO será eliminado (puede contener otros sitios)${NC}"
    echo
    echo -e "${RED}⚠️  ADVERTENCIA: Esta acción eliminará Nginx y todas sus configuraciones${NC}"
    echo -e "${RED}⚠️  Se perderán logs y configuraciones personalizadas${NC}"
    read -p "¿Desea continuar con la desinstalación? (s/N) " yn
    if [[ "$yn" != "s" && "$yn" != "S" ]]; then
        echo -e "${YELLOW}⏹  Desinstalación cancelada${NC}"
        exit 0
    fi

    echo
    echo -e "${BLUE}🛑 Deteniendo servicio Nginx...${NC}"
    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true
    echo -e "   ${GREEN}✓${NC} Servicio Nginx detenido y deshabilitado"

    echo
    echo -e "${BLUE}🗑️  Desinstalando paquetes...${NC}"
    apt remove --purge -y nginx libnginx-mod-http-cache-purge nginx-common nginx-core

    echo
    echo -e "${BLUE}📁 Eliminando directorios de configuración...${NC}"
    rm -rf /etc/nginx
    echo -e "   ${GREEN}✓${NC} /etc/nginx eliminado"

    rm -rf /var/log/nginx
    echo -e "   ${GREEN}✓${NC} /var/log/nginx eliminado"

    rm -rf /var/cache/nginx
    echo -e "   ${GREEN}✓${NC} /var/cache/nginx eliminado"

    echo -e "   ${YELLOW}⊘${NC} /var/www/html preservado (contiene sitios web)"

    echo
    echo -e "${BLUE}🧹 Limpiando dependencias no utilizadas...${NC}"
    apt autoremove -y

    echo
    echo -e "${GREEN}✅ Desinstalación completada${NC}"
    echo -e "${GREEN}✨ Nginx y todas sus configuraciones han sido eliminadas${NC}"

    exit 0
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   🚀 Nginx Installer & Optimizer                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo

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
echo -e "   ${CYAN}O usa el flag --site:${NC} ${YELLOW}$0 --site mysite.com${NC}"
echo

# Create custom site if domain was specified
if [[ -n "$SITE_DOMAIN" ]]; then
    echo
    echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   🌐 Creando sitio personalizado                  ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
    echo

    # Generate safe domain name (replace dots with underscores)
    DOMAIN_SAFE=$(echo "$SITE_DOMAIN" | tr '.' '_')

    echo -e "${CYAN}📝 Configurando sitio: ${YELLOW}${SITE_DOMAIN}${NC}"
    echo

    # Create site configuration from template
    SITE_CONF="/etc/nginx/sites-available/${SITE_DOMAIN}.conf"
    sed -e "s/__DOMAIN__/${SITE_DOMAIN}/g" \
        -e "s/__DOMAIN_SAFE__/${DOMAIN_SAFE}/g" \
        /etc/nginx/templates/nginx-static > "$SITE_CONF"

    echo -e "   ${GREEN}✓${NC} Configuración creada: ${SITE_CONF}"

    # Create web directory
    WEB_DIR="/var/www/${SITE_DOMAIN}"
    mkdir -p "$WEB_DIR"
    chown www-data:www-data "$WEB_DIR"

    echo -e "   ${GREEN}✓${NC} Directorio web creado: ${WEB_DIR}"

    # Create a simple index.html
    cat > "${WEB_DIR}/index.html" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>${SITE_DOMAIN}</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }
        .container {
            background: white;
            padding: 2rem;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.3);
            text-align: center;
        }
        h1 { color: #333; }
        p { color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <h1>${SITE_DOMAIN}</h1>
        <p>Static content server ready!</p>
        <p>Upload your files to: <code>${WEB_DIR}</code></p>
    </div>
</body>
</html>
EOF

    echo -e "   ${GREEN}✓${NC} Página de ejemplo creada"

    # Enable site
    ln -sf "$SITE_CONF" "/etc/nginx/sites-enabled/${SITE_DOMAIN}.conf"
    echo -e "   ${GREEN}✓${NC} Sitio habilitado"

    # Test and reload Nginx
    if nginx -t 2>&1 | grep -q "successful"; then
        systemctl reload nginx
        echo -e "   ${GREEN}✓${NC} Nginx recargado"
        echo
        echo -e "${GREEN}🎉 Sitio creado exitosamente!${NC}"
        echo -e "   ${YELLOW}http://${SITE_DOMAIN}${NC}"
        echo -e "   Archivos en: ${YELLOW}${WEB_DIR}${NC}"
    else
        echo -e "   ${RED}✗${NC} Error en la configuración de Nginx"
        nginx -t
    fi
    echo
fi

echo -e "${GREEN}✨ Proceso finalizado${NC}"
