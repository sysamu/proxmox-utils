#!/bin/bash
# =====================================================
# Script de configuración de ZFS RAID0 en NVMe
# Autor: Samuel Fernández Rodríguez
# Escenario: nodos proxmox con 4x960 NVMe, 2x960 para SO y 2x960 para VMs
# =====================================================

set -e

POOL_NAME="data"

# =====================================================
# Validación de parámetros
# =====================================================

if [[ -z "$1" || -z "$2" ]]; then
  echo "❌ ERROR: No se han especificado los discos NVMe para el pool."
  echo
  echo "Uso correcto:"
  echo "  $0 /dev/nvmeXn1 /dev/nvmeYn1"
  echo
  echo "Discos detectados actualmente en el sistema:"
  echo "-------------------------------------------"
  lsblk -d -o NAME,SIZE,MODEL | grep nvme || echo "No se detectaron discos NVMe."
  echo
  echo "💡 Revisa qué discos están libres antes de ejecutar el script."
  echo "   (normalmente los usados por el SO son /dev/nvme2n1 y /dev/nvme3n1)"
  exit 1
fi

DISK1="$1"
DISK2="$2"

echo "==============================================="
echo "  Configuración del pool ZFS RAID0 (${POOL_NAME})"
echo "  Discos seleccionados: ${DISK1} + ${DISK2}"
echo "==============================================="

read -p "¿Continuar con la creación del pool? (y/N): " confirm
[[ "$confirm" != "y" && "$confirm" != "Y" ]] && { echo "Cancelado."; exit 1; }

# =====================================================
# Preparación del sistema
# =====================================================

echo ">> Desmontando /var/lib/vz si existe..."
umount -l /var/lib/vz 2>/dev/null || true

echo ">> Destruyendo pools previos si existen..."
zpool destroy -f $POOL_NAME 2>/dev/null || true

# =====================================================
# Creación del pool ZFS RAID0
# =====================================================

echo ">> Creando pool ZFS RAID0 con ${DISK1} y ${DISK2}..."
zpool create -f \
  -o ashift=12 \
  -o autotrim=on \
  -O atime=off \
  -O compression=lz4 \
  -O xattr=sa \
  -O acltype=posixacl \
  -O normalization=formD \
  -O mountpoint=none \
  $POOL_NAME $DISK1 $DISK2

# =====================================================
# Dataset y propiedades
# =====================================================

echo ">> Creando dataset para las VMs..."
zfs create -o mountpoint=/var/lib/vz ${POOL_NAME}/vmdata

echo ">> Estableciendo propiedades adicionales..."
zfs set primarycache=all ${POOL_NAME}
zfs set secondarycache=all ${POOL_NAME}
zfs set relatime=on ${POOL_NAME}/vmdata

# =====================================================
# Verificación
# =====================================================

echo ">> Verificando estado..."
zpool status $POOL_NAME
zfs list

# =====================================================
# Permisos y servicios
# =====================================================

echo ">> Corrigiendo permisos..."
chown root:root /var/lib/vz
chmod 755 /var/lib/vz

echo ">> Reiniciando servicios PVE..."
echo "✅ Pool ZFS '${POOL_NAME}' creado con éxito y montado en /var/lib/vz"