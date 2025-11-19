#!/bin/bash
# -------------------------------------------------------------------
# Apache + PHP-FPM auto optimization script (CPU/RAM aware)
# Includes dependency checks for FPM + required Apache modules
# -------------------------------------------------------------------

set -euo pipefail

echo "🔍 Detectando versión de PHP..."
PHP_VERSION=$(ls /etc/php | grep -E '^[0-9]+\.[0-9]+' | sort -r | head -n1)
PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
PHP_FPM_CONF="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
PHP_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"
APACHE_MPM_CONF="/etc/apache2/mods-available/mpm_event.conf"

CORES=$(nproc)
RAM_MB=$(free -m | awk '/^Mem:/{print $2}')

echo "🧠 Detectado: ${CORES} CPU(s), ${RAM_MB} MB RAM"
echo "📦 Comprobando módulos y servicios..."

# --- Verifica PHP-FPM instalado ---
if ! dpkg -l | grep -q "php${PHP_VERSION}-fpm"; then
    echo "⚙️ Instalando php${PHP_VERSION}-fpm..."
    apt-get update -qq
    apt-get install -y "php${PHP_VERSION}-fpm"
fi

# --- Asegura módulos Apache necesarios ---
for mod in proxy proxy_fcgi setenvif; do
    if ! a2query -m "$mod" 2>/dev/null | grep -q enabled; then
        echo "🧩 Habilitando módulo Apache: $mod"
        a2enmod "$mod"
    fi
done

# --- Calcula parámetros dinámicos ---
PM_MAX_CHILDREN=$((RAM_MB / 128))
(( PM_MAX_CHILDREN < 4 )) && PM_MAX_CHILDREN=4
(( PM_MAX_CHILDREN > 32 )) && PM_MAX_CHILDREN=32

PM_START=$(( PM_MAX_CHILDREN / 4 ))
PM_MIN=$PM_START
PM_MAX=$(( PM_START * 2 ))
PM_MAX_REQUESTS=500

APACHE_WORKERS=$(( CORES * 50 ))
APACHE_MAX_CONN=5000

echo "📊 Configuración calculada:"
echo "  → pm.max_children = ${PM_MAX_CHILDREN}"
echo "  → Apache MaxRequestWorkers = ${APACHE_WORKERS}"

# --- PHP-FPM tuning ---
sed -ri "s/^pm\s*=.*/pm = dynamic/" "$PHP_FPM_CONF"
sed -ri "s/^pm\.max_children\s*=.*/pm.max_children = ${PM_MAX_CHILDREN}/" "$PHP_FPM_CONF"
sed -ri "s/^pm\.start_servers\s*=.*/pm.start_servers = ${PM_START}/" "$PHP_FPM_CONF"
sed -ri "s/^pm\.min_spare_servers\s*=.*/pm.min_spare_servers = ${PM_MIN}/" "$PHP_FPM_CONF"
sed -ri "s/^pm\.max_spare_servers\s*=.*/pm.max_spare_servers = ${PM_MAX}/" "$PHP_FPM_CONF"
sed -ri "s/^pm\.max_requests\s*=.*/pm.max_requests = ${PM_MAX_REQUESTS}/" "$PHP_FPM_CONF"
grep -q "^request_terminate_timeout" "$PHP_FPM_CONF" \
  && sed -ri 's/^request_terminate_timeout\s*=.*/request_terminate_timeout = 60s/' "$PHP_FPM_CONF" \
  || echo "request_terminate_timeout = 60s" >> "$PHP_FPM_CONF"

# --- PHP.ini tuning ---
sed -ri 's/^memory_limit\s*=.*/memory_limit = 256M/' "$PHP_INI"
sed -ri 's/^max_execution_time\s*=.*/max_execution_time = 60/' "$PHP_INI"
sed -ri 's/^max_input_time\s*=.*/max_input_time = 60/' "$PHP_INI"
sed -ri 's/^post_max_size\s*=.*/post_max_size = 32M/' "$PHP_INI"
sed -ri 's/^upload_max_filesize\s*=.*/upload_max_filesize = 32M/' "$PHP_INI"
sed -ri 's/^display_errors\s*=.*/display_errors = Off/' "$PHP_INI"
sed -ri 's/^log_errors\s*=.*/log_errors = On/' "$PHP_INI"
grep -q "^error_log" "$PHP_INI" || echo "error_log = /var/log/php${PHP_VERSION}-fpm.log" >> "$PHP_INI"

# --- Apache MPM tuning ---
cat > "$APACHE_MPM_CONF" <<EOF
<IfModule mpm_event_module>
    StartServers             ${PM_START}
    MinSpareThreads          25
    MaxSpareThreads          75
    ThreadLimit              64
    ThreadsPerChild          25
    MaxRequestWorkers        ${APACHE_WORKERS}
    MaxConnectionsPerChild   ${APACHE_MAX_CONN}
</IfModule>
EOF

# --- Ajustes de VirtualHosts ---
for enabled in /etc/apache2/sites-enabled/*.conf; do
    [ -L "$enabled" ] || continue
    base=$(basename "$enabled")
    target="/etc/apache2/sites-available/$base"

    echo "🧩 Revisando $target"

    # Añadir bloque PHP-FPM dentro del VirtualHost si no existe
    if ! grep -q "FilesMatch.*\.php" "$target"; then
        # Buscar la última línea del VirtualHost (</VirtualHost>)
        sed -i '/<\/VirtualHost>/i\
    # --- PHP-FPM handler ---\
    <FilesMatch "\\.php$">\
        SetHandler "proxy:unix:/run/php/php'"${PHP_VERSION}"'-fpm.sock|fcgi://localhost/"\
    </FilesMatch>\
' "$target"
    fi

    # Añadir ServerSignature y ServerTokens al final si no existen
    grep -q "ServerSignature Off" "$target" || echo "ServerSignature Off" >> "$target"
    grep -q "ServerTokens Prod" "$target" || echo "ServerTokens Prod" >> "$target"
done

# --- Global Apache tuning ---
APACHE_CONF="/etc/apache2/apache2.conf"
sed -ri 's/^KeepAlive\s+.*/KeepAlive On/' "$APACHE_CONF"
grep -q "^MaxKeepAliveRequests" "$APACHE_CONF" && sed -ri 's/^MaxKeepAliveRequests.*/MaxKeepAliveRequests 100/' "$APACHE_CONF" || echo "MaxKeepAliveRequests 100" >> "$APACHE_CONF"
grep -q "^KeepAliveTimeout" "$APACHE_CONF" && sed -ri 's/^KeepAliveTimeout.*/KeepAliveTimeout 5/' "$APACHE_CONF" || echo "KeepAliveTimeout 5" >> "$APACHE_CONF"
grep -q "^Timeout" "$APACHE_CONF" && sed -ri 's/^Timeout.*/Timeout 30/' "$APACHE_CONF" || echo "Timeout 30" >> "$APACHE_CONF"

# --- Reinicios ---
echo "🔁 Reiniciando servicios..."
systemctl daemon-reload
systemctl restart "${PHP_FPM_SERVICE}"
systemctl restart apache2

systemctl is-active --quiet "${PHP_FPM_SERVICE}" && echo "✅ PHP-FPM en ejecución"
systemctl is-active --quiet apache2 && echo "✅ Apache operativo"

echo "🎯 Optimización completada: ${CORES} CPU(s), ${RAM_MB} MB RAM"