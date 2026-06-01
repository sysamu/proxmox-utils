#!/bin/bash
#
# pbs-upgrade-3-to-4.sh
#
# Automates the safe upgrade of Proxmox Backup Server from 3.4.x to 4.x
# (Debian 12 Bookworm -> Debian 13 Trixie).
#
# Designed for OVH Public Cloud instances (B3-16) running PBS on top of
# vanilla Debian 12. See PBS_3_to_4_upgrade.md for the full procedure.
#
# This script automates phases 3-9 of the official guide. The snapshot
# (phase 1), tmux session (phase 2), and final reboot (phase 10) must
# be done manually for safety.
#
# Reference: https://pbs.proxmox.com/wiki/index.php/Upgrade_from_3_to_4

set -euo pipefail

# ----- Colors -----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
}
print_step()    { echo -e "\n${BLUE}▶ $1${NC}"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_info()    { echo -e "${CYAN}ℹ${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1" >&2; }

# ----- Args -----
MODE="upgrade"   # upgrade | post | precheck
REPO_FLAVOR=""   # nosub | enterprise
ASSUME_YES="no"

usage() {
    cat <<EOF
Usage: $0 [--precheck|--post|--backup-config] [--repo nosub|enterprise] [--yes]

  (no flag)       Run full upgrade flow (default).
  --precheck      Only run pre-flight checks and exit.
  --post          Run only post-reboot validation.
  --backup-config Only create the config/sources backup and show SFTP
                  instructions to download it. Makes no other changes.

  --repo nosub|enterprise
                  Which PBS 4 repository to configure.
                  If omitted, the script tries to detect it from
                  the existing PBS 3 repos.

  --yes           Skip interactive confirmations (use with care).

  -h, --help      Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --precheck)        MODE="precheck"; shift ;;
        --post)            MODE="post"; shift ;;
        --backup-config)   MODE="backup-config"; shift ;;
        --repo)            REPO_FLAVOR="$2"; shift 2 ;;
        --yes|-y)          ASSUME_YES="yes"; shift ;;
        -h|--help)         usage; exit 0 ;;
        *)                 print_error "Unknown argument: $1"; usage; exit 1 ;;
    esac
done

# ----- Helpers -----
require_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Este script debe ejecutarse como root. Usa: sudo $0"
        exit 1
    fi
}

confirm() {
    # confirm "Mensaje"
    local prompt="$1"
    if [[ "$ASSUME_YES" == "yes" ]]; then
        print_info "$prompt  [auto-yes]"
        return 0
    fi
    echo ""
    read -rp "$(echo -e "${YELLOW}${prompt} (escribe 'yes' para continuar):${NC} ")" answer
    if [[ "$answer" != "yes" ]]; then
        print_warning "Cancelado por el usuario."
        exit 1
    fi
}

in_tmux_or_screen() {
    [[ -n "${TMUX:-}" || "${TERM:-}" == screen* || -n "${STY:-}" ]]
}

get_pbs_version() {
    # "proxmox-backup-manager version" output (PBS 3.x):
    #   proxmox-backup-server 3.4.8-3 running version: 3.4.6
    # $2 is the installed package version; strip the revision suffix (-3).
    proxmox-backup-manager version 2>/dev/null \
        | awk '/proxmox-backup-server/ {print $2; exit}' \
        | sed 's/-.*//'
}

# ===== PRECHECK =====
precheck() {
    print_header "🔎 Pre-flight checks"

    # Root
    print_success "Ejecutando como root"

    # tmux / screen
    if in_tmux_or_screen; then
        print_success "Sesión multiplexor detectada (tmux/screen)"
    else
        print_warning "NO estás dentro de tmux/screen."
        print_warning "Si la conexión SSH cae durante el upgrade, el proceso se interrumpirá."
        if [[ "$MODE" != "post" ]]; then
            confirm "¿Continuar de todas formas?"
        fi
    fi

    # Comando pbs
    if ! command -v proxmox-backup-manager >/dev/null 2>&1; then
        print_error "proxmox-backup-manager no encontrado. ¿Es realmente un PBS?"
        exit 1
    fi
    print_success "PBS detectado"

    # Versión actual
    local current_ver
    current_ver="$(get_pbs_version || true)"
    print_info "Versión actual PBS: ${current_ver:-desconocida}"

    # Debian version
    if [[ -f /etc/debian_version ]]; then
        local deb_ver
        deb_ver="$(cat /etc/debian_version)"
        print_info "Debian: $deb_ver"
    fi

    # Espacio en raíz
    local free_gb
    free_gb=$(df --output=avail -BG / | tail -1 | tr -dc '0-9')
    if [[ "$free_gb" -lt 10 ]]; then
        print_error "Espacio libre en / insuficiente: ${free_gb}G (mínimo 10G)"
        exit 1
    fi
    print_success "Espacio libre en /: ${free_gb}G"

    # Tareas activas — bloqueo estricto, no hay override
    # "task list" sin --all devuelve solo las running; [] significa ninguna.
    local running_tasks
    running_tasks=$(proxmox-backup-manager task list --output-format json-pretty 2>/dev/null \
        | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)
    if [[ "$running_tasks" -gt 0 ]]; then
        print_error "Hay ${running_tasks} tarea(s) corriendo en PBS. NO es seguro hacer el upgrade ahora."
        print_error "Espera a que terminen antes de continuar."
        print_info "Consulta el estado con: proxmox-backup-manager task list"
        exit 1
    fi
    print_success "No hay tareas activas"

    # Snapshot recordatorio
    if [[ "$MODE" != "post" ]]; then
        print_warning "¿Has creado un SNAPSHOT en el panel OVH Public Cloud?"
        print_warning "Sin snapshot no hay rollback rápido si algo falla."
        confirm "Confirma que el snapshot OVH está creado y completado"
    fi
}

# ===== BACKUP CONFIG =====
detect_public_host() {
    # Intenta resolver un identificador "presentable" para mostrar en la URL SFTP.
    # Orden: hostname FQDN -> IP pública (curl) -> primera IP no-loopback.
    local host=""

    host="$(hostname -f 2>/dev/null || true)"
    if [[ -n "$host" && "$host" != "localhost"* && "$host" == *.* ]]; then
        echo "$host"
        return
    fi

    if command -v curl >/dev/null 2>&1; then
        host="$(curl -fsS --max-time 3 https://api.ipify.org 2>/dev/null || true)"
        if [[ -n "$host" ]]; then
            echo "$host"
            return
        fi
    fi

    host="$(hostname -I 2>/dev/null | awk '{print $1}')"
    if [[ -n "$host" ]]; then
        echo "$host"
        return
    fi

    echo "<tu-host-o-ip>"
}

backup_config() {
    print_step "Paso A — Backup de configuración"

    local backup_dir="/root/pbs-upgrade-backup"
    local stamp
    stamp="$(date +%F_%H-%M)"
    mkdir -p "$backup_dir"

    local tarball="$backup_dir/pbs3-etc-${stamp}.tar.gz"
    tar czf "$tarball" -C /etc proxmox-backup
    cp /etc/apt/sources.list "$backup_dir/sources.list.bookworm.${stamp}.bak" 2>/dev/null || true
    cp -r /etc/apt/sources.list.d "$backup_dir/sources.list.d.bookworm.${stamp}.bak" 2>/dev/null || true
    cp /etc/fstab "$backup_dir/fstab.${stamp}.bak"
    cp /etc/network/interfaces "$backup_dir/interfaces.${stamp}.bak" 2>/dev/null || true
    cp /etc/hosts "$backup_dir/hosts.${stamp}.bak" 2>/dev/null || true

    local tar_size
    tar_size="$(du -h "$tarball" | cut -f1)"

    print_success "Backup creado en: $backup_dir"
    ls -lh "$backup_dir/" | sed 's/^/    /'
    echo ""
    print_info "Archivo principal: ${GREEN}$tarball${NC} (${tar_size})"
    echo ""

    local host
    host="$(detect_public_host)"

    print_warning "DESCARGA este directorio fuera del servidor antes de continuar."
    echo ""
    echo -e "  ${CYAN}📥 Opciones para descargarlo:${NC}"
    echo ""
    echo -e "  ${YELLOW}1. SFTP en cliente gráfico (FileZilla, WinSCP, Cyberduck):${NC}"
    echo -e "       Host     : ${GREEN}${host}${NC}"
    echo -e "       Protocol : ${GREEN}SFTP${NC}"
    echo -e "       Port     : ${GREEN}22${NC}"
    echo -e "       User     : ${GREEN}root${NC}  (o tu usuario con acceso)"
    echo -e "       Path     : ${GREEN}${backup_dir}${NC}"
    echo -e "       URL      : ${GREEN}sftp://root@${host}${backup_dir}${NC}"
    echo ""
    echo -e "  ${YELLOW}2. SCP desde tu workstation (terminal):${NC}"
    echo -e "       ${CYAN}scp -r root@${host}:${backup_dir} ./pbs-backup-local/${NC}"
    echo ""
    echo -e "  ${YELLOW}3. SFTP CLI desde tu workstation:${NC}"
    echo -e "       ${CYAN}sftp root@${host}${NC}"
    echo -e "       ${CYAN}sftp> get -r ${backup_dir}${NC}"
    echo ""

    if [[ "$MODE" == "backup-config" ]]; then
        print_success "Modo --backup-config: backup completado, sin más acciones."
        return
    fi

    confirm "¿Ya descargaste el backup a un lugar seguro?"
}

# ===== UPDATE TO LATEST PBS 3 =====
update_to_latest_pbs3() {
    print_step "Paso B — Actualizar a la última PBS 3.4.x"

    apt update
    DEBIAN_FRONTEND=noninteractive apt -y dist-upgrade

    local v
    v="$(get_pbs_version || true)"
    print_info "Versión PBS tras update: ${v:-desconocida}"

    # Debe ser 3.4.2+
    if [[ -z "$v" ]] || ! echo "$v" | grep -qE '^3\.'; then
        print_error "PBS no está en rama 3.x tras update. Abortando."
        exit 1
    fi
    print_success "PBS al día en rama 3.x"
}

# ===== DETECT REPO FLAVOR =====
detect_repo_flavor() {
    if [[ -n "$REPO_FLAVOR" ]]; then
        return
    fi
    # Only look at active (non-commented) lines in non-backup files
    if grep -rhs "enterprise.proxmox.com/debian/pbs" \
           /etc/apt/sources.list \
           /etc/apt/sources.list.d/*.list \
           /etc/apt/sources.list.d/*.sources \
           2>/dev/null \
       | grep -qv '^\s*#'; then
        REPO_FLAVOR="enterprise"
    else
        REPO_FLAVOR="nosub"
    fi
    print_info "Repo PBS 4 a configurar (auto-detectado): $REPO_FLAVOR"
}

# ===== RUN pbs3to4 =====
run_pbs3to4() {
    print_step "Paso C — Ejecutar pbs3to4 --full"

    if ! command -v pbs3to4 >/dev/null 2>&1; then
        print_warning "Comando 'pbs3to4' no disponible — debería venir con PBS 3.4.2+."
        print_warning "Continuando sin esta verificación. Revisa la guía oficial."
        return
    fi

    if pbs3to4 --full; then
        print_success "pbs3to4 completado"
    else
        print_error "pbs3to4 reportó problemas. Revisa la salida arriba."
        confirm "¿Continuar a pesar de los warnings/errores?"
    fi
}

# ===== MAINTENANCE MODE =====
enable_maintenance() {
    print_step "Paso D — Modo mantenimiento (read-only) en datastores"

    local datastores
    datastores=$(proxmox-backup-manager datastore list --output-format json 2>/dev/null \
                 | python3 -c 'import json,sys; [print(d["name"]) for d in json.load(sys.stdin)]' \
                 2>/dev/null || true)

    if [[ -z "$datastores" ]]; then
        print_warning "No se pudieron listar datastores automáticamente. Activa el modo mantenimiento a mano si quieres."
        return
    fi

    while read -r ds; do
        [[ -z "$ds" ]] && continue
        if proxmox-backup-manager datastore update "$ds" --maintenance-mode read-only 2>/dev/null; then
            print_success "Datastore '$ds' → read-only"
        else
            print_warning "No se pudo actualizar '$ds' (puede que ya esté en modo mantenimiento)"
        fi
    done <<< "$datastores"
}

# ===== SWITCH REPOS =====
switch_repos() {
    print_step "Paso E — Cambiar repositorios Debian a Trixie y añadir PBS 4"

    # Asegurar keyring proxmox
    if [[ ! -f /usr/share/keyrings/proxmox-archive-keyring.gpg ]]; then
        apt install -y proxmox-archive-keyring
    fi
    print_success "Keyring de Proxmox presente"

    # sources.list principal
    if grep -q bookworm /etc/apt/sources.list 2>/dev/null; then
        sed -i.bak 's/bookworm/trixie/g' /etc/apt/sources.list
        print_success "/etc/apt/sources.list: bookworm → trixie (backup: .bak)"
    fi

    # sources.list.d/*.list (que no sean de Proxmox PBS antiguo)
    for f in /etc/apt/sources.list.d/*.list; do
        [[ -e "$f" ]] || continue
        if grep -q bookworm "$f"; then
            sed -i.bak 's/bookworm/trixie/g' "$f"
            print_success "$f: bookworm → trixie"
        fi
    done

    # Eliminar repos PBS 3 antiguos
    for old in pbs-enterprise.list pbs-no-subscription.list pbs-install-repo.list \
               pbs-enterprise.sources pbs-no-subscription.sources; do
        if [[ -f "/etc/apt/sources.list.d/$old" ]]; then
            mv "/etc/apt/sources.list.d/$old" "/etc/apt/sources.list.d/${old}.pbs3.bak"
            print_success "Repo PBS 3 desactivado: $old"
        fi
    done

    # Añadir repo PBS 4
    detect_repo_flavor
    if [[ "$REPO_FLAVOR" == "enterprise" ]]; then
        cat > /etc/apt/sources.list.d/pbs-enterprise.sources <<'EOF'
Types: deb
URIs: https://enterprise.proxmox.com/debian/pbs
Suites: trixie
Components: pbs-enterprise
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
        print_success "Repo PBS 4 Enterprise añadido — verificando acceso..."
        # Test: if enterprise returns 401 (no active subscription), fall back to nosub
        if apt-get update -o Dir::Etc::sourcelist="sources.list.d/pbs-enterprise.sources" \
                          -o Dir::Etc::sourcelistd="/dev/null" \
                          -o APT::Get::List-Cleanup="0" 2>&1 \
           | grep -q "401\|Unauthorized"; then
            print_warning "Enterprise repo devolvió 401 — sin suscripción activa."
            print_warning "Cambiando automáticamente a no-subscription..."
            rm -f /etc/apt/sources.list.d/pbs-enterprise.sources
            REPO_FLAVOR="nosub"
        else
            print_success "Repo PBS 4 Enterprise accesible"
        fi
    fi

    if [[ "$REPO_FLAVOR" == "nosub" ]]; then
        cat > /etc/apt/sources.list.d/pbs-no-subscription.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pbs
Suites: trixie
Components: pbs-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
        print_success "Repo PBS 4 No-Subscription añadido"
    fi

    print_info "Actualizando índices apt..."
    apt update
}

# ===== DIST UPGRADE =====
dist_upgrade() {
    print_step "Paso F — apt dist-upgrade (Debian 12 → 13, PBS 3 → 4)"

    print_warning "Esto puede tardar 5-60 minutos."
    print_warning "Durante el proceso pueden aparecer prompts sobre archivos de configuración."
    print_warning "Recomendación general: MANTENER tu versión (N) en archivos /etc personalizados,"
    print_warning "salvo sshd_config si no lo has tocado (entonces aceptar la nueva)."
    confirm "¿Lanzar el dist-upgrade ahora?"

    # No usamos noninteractive porque el usuario debe decidir sobre conffiles
    apt dist-upgrade
}

# ===== POST-REBOOT VALIDATION =====
post_validate() {
    print_header "✅ Validación post-upgrade"

    local pbs_ver deb_ver kver
    pbs_ver="$(get_pbs_version || true)"
    deb_ver="$(cat /etc/debian_version 2>/dev/null || echo '?')"
    kver="$(uname -r)"

    echo -e "  PBS version    : ${GREEN}${pbs_ver:-?}${NC}"
    echo -e "  Debian version : ${GREEN}${deb_ver}${NC}"
    echo -e "  Kernel         : ${GREEN}${kver}${NC}"
    echo ""

    if [[ "$pbs_ver" =~ ^4\. ]]; then
        print_success "PBS está en rama 4.x"
    else
        print_error "PBS NO está en rama 4.x — revisa la salida anterior"
    fi

    if [[ "$deb_ver" =~ ^13 ]]; then
        print_success "Debian está en rama 13 (Trixie)"
    else
        print_error "Debian NO está en rama 13 — revisa /etc/apt/sources.list"
    fi

    echo ""
    print_info "Estado de servicios:"
    systemctl status proxmox-backup-proxy.service proxmox-backup.service --no-pager -l \
        | sed 's/^/    /' || true

    echo ""
    print_info "Datastores:"
    proxmox-backup-manager datastore list || print_warning "No se pudieron listar datastores"

    echo ""
    print_info "Para desactivar el modo mantenimiento en los datastores:"
    echo -e "    ${CYAN}for ds in \$(proxmox-backup-manager datastore list --output-format json | python3 -c 'import json,sys;[print(d[\"name\"]) for d in json.load(sys.stdin)]'); do${NC}"
    echo -e "    ${CYAN}    proxmox-backup-manager datastore update \"\$ds\" --delete maintenance-mode${NC}"
    echo -e "    ${CYAN}done${NC}"
    echo ""

    print_info "Antes de eliminar el snapshot OVH:"
    echo "    1. Lanza un backup nuevo desde un cliente PVE."
    echo "    2. Lanza un verify completo en cada datastore."
    echo "    3. Limpia la caché del navegador (Ctrl+Shift+R) y abre la UI."
}

# ===== MAIN =====
main() {
    require_root

    if [[ "$MODE" == "post" ]]; then
        post_validate
        exit 0
    fi

    if [[ "$MODE" == "backup-config" ]]; then
        print_header "💾 PBS config backup (modo standalone)"
        print_info "Solo se generará un backup de /etc/proxmox-backup y las APT sources."
        print_info "No se modificará nada más en el sistema."
        backup_config
        exit 0
    fi

    print_header "🚀 PBS 3.x → 4.x upgrade helper"
    print_warning "Procedimiento basado en: https://pbs.proxmox.com/wiki/index.php/Upgrade_from_3_to_4"
    print_warning "Lee scripts/PBS_3_to_4_upgrade.md antes de continuar."
    echo ""

    precheck

    if [[ "$MODE" == "precheck" ]]; then
        print_success "Pre-checks OK. Saliendo (modo --precheck)."
        exit 0
    fi

    confirm "¿Iniciar el flujo de upgrade?"

    backup_config
    update_to_latest_pbs3
    run_pbs3to4
    enable_maintenance
    switch_repos
    dist_upgrade

    print_header "🎯 dist-upgrade completado"
    print_success "El sistema está listo para reiniciar."
    print_warning "Ejecuta manualmente:"
    echo -e "    ${CYAN}systemctl reboot${NC}"
    echo ""
    print_info "Tras el reinicio, valida el sistema con:"
    echo -e "    ${CYAN}sudo $0 --post${NC}"
    echo ""
}

main "$@"
