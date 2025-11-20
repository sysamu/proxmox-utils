#!/bin/bash
# PHP installer with customizable version and optional modules file
# Usage: ./php_installer.sh [VERSION] [--modules FILE] [--uninstall]
# Examples:
#   ./php_installer.sh                        # Installs PHP 8.4 (base + dev + fpm)
#   ./php_installer.sh 8.3                    # Installs PHP 8.3 (base + dev + fpm)
#   ./php_installer.sh --modules modules.txt  # Installs PHP 8.4 + modules from file
#   ./php_installer.sh 8.3 --modules modules.txt # Installs PHP 8.3 + modules from file
#   ./php_installer.sh --uninstall            # Uninstalls PHP 8.4 (uses php_modules.txt if exists)
#   ./php_installer.sh 8.3 --uninstall        # Uninstalls PHP 8.3

set -euo pipefail

# Default PHP version
PHP_VERSION="8.4"
MODULES_FILE=""
UNINSTALL_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --modules)
            MODULES_FILE="$2"
            shift 2
            ;;
        --uninstall)
            UNINSTALL_MODE=true
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Usage: $0 [VERSION] [--modules FILE] [--uninstall]"
            exit 1
            ;;
        *)
            # If it's not a flag, assume it's the PHP version
            PHP_VERSION="$1"
            shift
            ;;
    esac
done

# Arrays for tracking
INSTALL_LIST=()
FAILED_MODULES=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Uninstall mode
if [[ "$UNINSTALL_MODE" == true ]]; then
    echo -e "${RED}🗑️  PHP ${PHP_VERSION} Uninstaller${NC}"
    echo "================================"
    echo

    # Check if php_modules.txt exists in current directory
    if [[ -z "$MODULES_FILE" && -f "php_modules.txt" ]]; then
        MODULES_FILE="php_modules.txt"
        echo -e "${BLUE}ℹ  Encontrado php_modules.txt en el directorio actual${NC}"
        echo
    fi

    # Build uninstall list
    UNINSTALL_LIST=()
    PHP_BASE="php${PHP_VERSION}"
    PHP_DEV="php${PHP_VERSION}-dev"
    PHP_FPM="php${PHP_VERSION}-fpm"

    # Add base packages
    UNINSTALL_LIST+=("$PHP_BASE" "$PHP_DEV" "$PHP_FPM")

    # Process modules file if exists
    if [[ -n "$MODULES_FILE" && -f "$MODULES_FILE" ]]; then
        echo -e "${BLUE}📄 Procesando módulos desde: $MODULES_FILE${NC}"
        while IFS= read -r line; do
            mod=$(echo "$line" | sed 's/#.*//' | tr -d '[:space:]')
            [[ -z "$mod" ]] && continue
            pkg="php${PHP_VERSION}-${mod}"

            # Check if package is installed
            if dpkg -l | grep -q "^ii.*$pkg"; then
                UNINSTALL_LIST+=("$pkg")
                echo -e "   ${GREEN}✓${NC} $pkg (instalado)"
            else
                echo -e "   ${YELLOW}⚠${NC}  $pkg (no instalado)"
            fi
        done < "$MODULES_FILE"
        echo
    fi

    echo -e "${BLUE}📦 Paquetes a desinstalar:${NC}"
    echo "   Total: ${#UNINSTALL_LIST[@]}"
    printf '   - %s\n' "${UNINSTALL_LIST[@]}"
    echo

    # Confirmation prompt
    echo -e "${RED}⚠️  ADVERTENCIA: Esta acción eliminará los paquetes listados${NC}"
    read -p "¿Desea continuar con la desinstalación? (s/N) " yn
    if [[ "$yn" != "s" && "$yn" != "S" ]]; then
        echo -e "${YELLOW}⏹  Desinstalación cancelada${NC}"
        exit 0
    fi

    echo
    echo -e "${BLUE}🗑️  Desinstalando paquetes...${NC}"
    if apt remove --purge -y "${UNINSTALL_LIST[@]}"; then
        echo
        echo -e "${GREEN}✅ Desinstalación completada${NC}"

        # Stop and disable PHP-FPM service if exists
        FPM_SERVICE="php${PHP_VERSION}-fpm"
        if systemctl list-units --full -all | grep -q "$FPM_SERVICE.service"; then
            echo
            echo -e "${BLUE}🔧 Deteniendo servicio PHP-FPM...${NC}"
            systemctl stop "$FPM_SERVICE" 2>/dev/null || true
            systemctl disable "$FPM_SERVICE" 2>/dev/null || true
            echo -e "   ${GREEN}✓${NC} Servicio $FPM_SERVICE detenido y deshabilitado"
        fi

        echo
        echo -e "${BLUE}🧹 Limpiando dependencias no utilizadas...${NC}"
        apt autoremove -y

        echo
        echo -e "${GREEN}✨ Proceso de desinstalación finalizado${NC}"
    else
        echo
        echo -e "${RED}❌ Hubo errores durante la desinstalación${NC}"
        exit 1
    fi

    exit 0
fi

echo -e "${BLUE}🐘 PHP ${PHP_VERSION} Installer${NC}"
echo "================================"
echo

# Get OS information for later use
OS_NAME=$(grep '^NAME=' /etc/os-release | cut -d'"' -f2)
OS_VERSION=$(grep '^VERSION=' /etc/os-release | cut -d'"' -f2)
OS_ID=$(grep '^ID=' /etc/os-release | cut -d'=' -f2)
OS_VERSION_ID=$(grep '^VERSION_ID=' /etc/os-release | cut -d'"' -f2)

echo -e "${BLUE}📋 Sistema detectado:${NC}"
echo "   OS: $OS_NAME $OS_VERSION"
echo "   ID: $OS_ID $OS_VERSION_ID"
echo

# Add ondrej/php repository if on Ubuntu/Debian
echo -e "${BLUE}📦 Configurando repositorio PHP...${NC}"
if [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" ]]; then
    # Install software-properties-common if not present
    if ! dpkg -l | grep -q software-properties-common; then
        echo "   Instalando software-properties-common..."
        apt update -qq
        apt install -y software-properties-common >/dev/null 2>&1
    fi

    # Add ondrej/php repository
    if ! grep -q "ondrej/php" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        echo "   Añadiendo repositorio ondrej/php..."
        add-apt-repository ppa:ondrej/php -y >/dev/null 2>&1
        apt update -qq
        echo -e "   ${GREEN}✓${NC} Repositorio ondrej/php añadido"
    else
        echo -e "   ${GREEN}✓${NC} Repositorio ondrej/php ya está configurado"
    fi
else
    echo -e "   ${YELLOW}⚠${NC}  Sistema no es Ubuntu/Debian, saltando configuración de PPA"
fi
echo

# Always install php-dev and php-fpm packages
PHP_BASE="php${PHP_VERSION}"
PHP_DEV="php${PHP_VERSION}-dev"
PHP_FPM="php${PHP_VERSION}-fpm"

echo -e "${BLUE}📦 Paquetes base de PHP:${NC}"
echo "   - $PHP_BASE"
echo "   - $PHP_DEV"
echo "   - $PHP_FPM"

INSTALL_LIST+=("$PHP_BASE" "$PHP_DEV" "$PHP_FPM")

# Process modules file if provided
if [[ -n "$MODULES_FILE" ]]; then
    if [[ ! -f "$MODULES_FILE" ]]; then
        echo -e "${RED}❌ Error: El archivo '$MODULES_FILE' no existe${NC}"
        exit 1
    fi

    echo
    echo -e "${BLUE}📄 Procesando módulos desde: $MODULES_FILE${NC}"

    while IFS= read -r line; do
        # Remove comments and whitespace
        mod=$(echo "$line" | sed 's/#.*//' | tr -d '[:space:]')
        [[ -z "$mod" ]] && continue

        # Build package name
        pkg="php${PHP_VERSION}-${mod}"

        # Check if package exists in apt
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            INSTALL_LIST+=("$pkg")
            echo -e "   ${GREEN}✓${NC} $pkg (disponible)"
        else
            FAILED_MODULES+=("$mod")
            echo -e "   ${YELLOW}⚠${NC}  $pkg (no disponible)"
        fi

    done < "$MODULES_FILE"
else
    echo
    echo -e "${YELLOW}ℹ  No se especificó archivo de módulos, solo se instalará PHP base + dev${NC}"
fi

echo
echo -e "${BLUE}📦 Resumen de instalación:${NC}"
echo "   Total de paquetes: ${#INSTALL_LIST[@]}"
printf '   - %s\n' "${INSTALL_LIST[@]}"

echo
read -p "¿Desea continuar con la instalación? (s/N) " yn
if [[ "$yn" != "s" && "$yn" != "S" ]]; then
    echo -e "${YELLOW}⏹  Instalación cancelada${NC}"
    exit 0
fi

echo
echo -e "${BLUE}🔄 Actualizando repositorios...${NC}"
apt update -qq

echo -e "${BLUE}📥 Instalando paquetes...${NC}"
if apt install -y "${INSTALL_LIST[@]}"; then
    echo
    echo -e "${GREEN}✅ Instalación completada correctamente${NC}"
else
    echo
    echo -e "${RED}❌ Hubo errores durante la instalación${NC}"
    exit 1
fi

# Show PHP version
echo
echo -e "${BLUE}🐘 Versión instalada:${NC}"
php -v | head -n 1

# Enable and start PHP-FPM service
echo
echo -e "${BLUE}🔧 Configurando servicio PHP-FPM...${NC}"
FPM_SERVICE="php${PHP_VERSION}-fpm"

if systemctl enable "$FPM_SERVICE" 2>/dev/null; then
    echo -e "   ${GREEN}✓${NC} Servicio $FPM_SERVICE habilitado (inicio automático)"
else
    echo -e "   ${YELLOW}⚠${NC}  No se pudo habilitar el servicio $FPM_SERVICE"
fi

if systemctl start "$FPM_SERVICE" 2>/dev/null; then
    echo -e "   ${GREEN}✓${NC} Servicio $FPM_SERVICE iniciado"
else
    echo -e "   ${YELLOW}⚠${NC}  No se pudo iniciar el servicio $FPM_SERVICE"
fi

# Check service status
if systemctl is-active --quiet "$FPM_SERVICE"; then
    echo -e "   ${GREEN}✓${NC} Servicio $FPM_SERVICE está activo y corriendo"
else
    echo -e "   ${RED}✗${NC} Servicio $FPM_SERVICE NO está corriendo"
fi

# Report failed modules if any
if [[ ${#FAILED_MODULES[@]} -gt 0 ]]; then
    echo
    echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}⚠  MÓDULOS QUE NO PUDIERON INSTALARSE (${#FAILED_MODULES[@]})${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}"
    echo
    echo "Los siguientes módulos no están disponibles en los repositorios:"
    printf '   - %s\n' "${FAILED_MODULES[@]}"

    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}💡 PROMPT PARA ChatGPT${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${GREEN}┌─────────────────────────────────────────────────────┐${NC}"
    cat <<-EOF
	│ Estos módulos de PHP NO EXISTEN en mi sistema:
	│
	│ OS: $OS_NAME $OS_VERSION ($OS_ID $OS_VERSION_ID)
	│ PHP: $PHP_VERSION
	│
	│ Módulos que NO EXISTEN:
EOF
    for mod in "${FAILED_MODULES[@]}"; do
        echo "	│ - $mod"
    done
    echo "	│"
    echo -e "${GREEN}└─────────────────────────────────────────────────────┘${NC}"
    echo
    echo -e "${YELLOW}(Copia y pega en ChatGPT si necesitas ayuda)${NC}"
    echo
fi

echo
echo -e "${GREEN}✨ Proceso finalizado${NC}"
