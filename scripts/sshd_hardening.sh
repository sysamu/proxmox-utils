#!/bin/bash
set -e

SSHD_CONFIG="/etc/ssh/sshd_config"
TMP_FILE="$(mktemp)"

cleanup() {
    rm -f "$TMP_FILE"
}
trap cleanup EXIT

# ===== INPUT =====
read -rp "Usuario SSH interno (ej: usuario): " SSH_USER
read -rp "Red interna permitida (CIDR, ej: 192.168.1.0/24): " INTERNAL_NET

if [[ -z "$SSH_USER" || -z "$INTERNAL_NET" ]]; then
    echo "ERROR: usuario y red son obligatorios." >&2
    exit 1
fi

# ===== CHECK ESTADO ACTUAL =====
has_permit_root=$(grep -Eq '^\s*PermitRootLogin\s+prohibit-password\s*$' "$SSHD_CONFIG" && echo yes || echo no)
has_pass_auth=$(grep -Eq '^\s*PasswordAuthentication\s+no\s*$' "$SSHD_CONFIG" && echo yes || echo no)

has_match_block=$(awk -v user="$SSH_USER" -v net="$INTERNAL_NET" '
    $1=="Match" && $2=="User" && $3==user && $4=="Address" && $5==net {found=1}
    END {exit found ? 0 : 1}
' "$SSHD_CONFIG" && echo yes || echo no)

# ===== SI TODO OK, SALIR =====
if [[ "$has_permit_root" == "yes" && "$has_pass_auth" == "yes" && "$has_match_block" == "yes" ]]; then
    echo "sshd ya está correctamente configurado. No se realizan cambios."
    exit 0
fi

echo "Configuración incompleta o incorrecta. Aplicando estado deseado..."

# ===== APLICAR CONFIG COMPLETA =====
cp "$SSHD_CONFIG" "$TMP_FILE"

# Reescribir directivas globales
sed -i '/^\s*PermitRootLogin\s\+/d' "$TMP_FILE"
sed -i '/^\s*PasswordAuthentication\s\+/d' "$TMP_FILE"

echo "PermitRootLogin prohibit-password" >> "$TMP_FILE"
echo "PasswordAuthentication no" >> "$TMP_FILE"

# Eliminar cualquier Match User previo para ese usuario
awk -v user="$SSH_USER" '
    $1=="Match" && $2=="User" && $3==user {skip=1; next}
    skip && $1=="Match" {skip=0}
    !skip
' "$TMP_FILE" > "${TMP_FILE}.new"

mv "${TMP_FILE}.new" "$TMP_FILE"

# Añadir bloque correcto
cat <<EOF >> "$TMP_FILE"

Match User $SSH_USER Address $INTERNAL_NET
EOF

# ===== VALIDAR Y APLICAR =====
if sshd -t -f "$TMP_FILE"; then
    cp "$TMP_FILE" "$SSHD_CONFIG"

    # Detectar servicio SSH correcto según sistema
    if systemctl list-units --type=service --all | grep -q "ssh.service"; then
        systemctl restart ssh
    else
        systemctl restart sshd
    fi

    echo "Cambios aplicados y sshd reiniciado correctamente."
else
    echo "ERROR: sshd_config inválido. No se aplican cambios." >&2
    exit 1
fi