#!/usr/bin/env bash
# proxmox-vm-template.sh — Create a Proxmox cloud-init ready VM template
# Usage: sudo bash proxmox-vm-template.sh [options]
#
# Designed to run on a Proxmox VE node.
# Uses a Debian genericcloud image (cloud-init preinstalled, no manual steps needed).

set -euo pipefail

### ─── DEFAULTS ──────────────────────────────────────────────────────────────
VMID=9000
NAME="debian-13-trixie-template"
STORAGE="local-lvm"
BRIDGE="vmbr0"
MEMORY=1024
CORES=2
DISK_SIZE="8G"
IMAGE_URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
IMAGE_FILE="debian-13-genericcloud-amd64.qcow2"
WORK_DIR="/var/tmp"

### ─── ARGUMENT PARSING ───────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --vmid     N       VM ID for the template (default: $VMID)
  --name     NAME    VM name (default: $NAME)
  --storage  POOL    Proxmox storage pool (default: $STORAGE)
  --bridge   BR      Network bridge (default: $BRIDGE)
  --memory   MB      RAM in MB (default: $MEMORY)
  --cores    N       vCPU count (default: $CORES)
  --disk     SIZE    Final disk size, e.g. 8G (default: $DISK_SIZE)
  --url      URL     Cloud image URL (default: Debian 13 Trixie genericcloud)
  --workdir  DIR     Working directory for image download (default: $WORK_DIR)
  --help             Show this help

Examples:
  sudo bash $(basename "$0")
  sudo bash $(basename "$0") --vmid 9001 --storage ceph-pool --disk 20G
  sudo bash $(basename "$0") --name ubuntu-24-template --url https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --vmid)    VMID="$2";     shift 2 ;;
        --name)    NAME="$2";     shift 2 ;;
        --storage) STORAGE="$2";  shift 2 ;;
        --bridge)  BRIDGE="$2";   shift 2 ;;
        --memory)  MEMORY="$2";   shift 2 ;;
        --cores)   CORES="$2";    shift 2 ;;
        --disk)    DISK_SIZE="$2"; shift 2 ;;
        --url)     IMAGE_URL="$2"; IMAGE_FILE="${IMAGE_URL##*/}"; shift 2 ;;
        --workdir) WORK_DIR="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

### ─── PREFLIGHT CHECKS ───────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

for cmd in qm pvesm wget; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: '$cmd' not found. Run this on a Proxmox VE node." >&2
        exit 1
    fi
done

# Check if VMID already exists
if qm status "$VMID" &>/dev/null; then
    echo "Error: VM $VMID already exists. Use --vmid to choose a different ID or remove the existing VM." >&2
    exit 1
fi

# Check storage exists
if ! pvesm status | awk '{print $1}' | grep -qx "$STORAGE"; then
    echo "Error: Storage '$STORAGE' not found. Available storages:" >&2
    pvesm status | awk 'NR>1 {print "  " $1}' >&2
    exit 1
fi

### ─── DOWNLOAD IMAGE ─────────────────────────────────────────────────────────
IMAGE_PATH="$WORK_DIR/$IMAGE_FILE"

echo ">> Downloading cloud image..."
if [[ -f "$IMAGE_PATH" ]]; then
    echo "   Found cached image: $IMAGE_PATH (skipping download)"
else
    wget -q --show-progress -O "$IMAGE_PATH" "$IMAGE_URL"
    echo "   Saved to: $IMAGE_PATH"
fi

### ─── CREATE VM ──────────────────────────────────────────────────────────────
echo ">> Creating VM $VMID ($NAME)..."
qm create "$VMID" \
    --name "$NAME" \
    --memory "$MEMORY" \
    --cores "$CORES" \
    --cpu host \
    --machine q35 \
    --bios ovmf \
    --efidisk0 "$STORAGE":0,efitype=4m,pre-enrolled-keys=0 \
    --net0 virtio,bridge="$BRIDGE" \
    --ostype l26 \
    --tablet 0 \
    --onboot 0

### ─── IMPORT AND CONFIGURE DISK ─────────────────────────────────────────────
echo ">> Importing disk to $STORAGE..."
qm importdisk "$VMID" "$IMAGE_PATH" "$STORAGE" --format qcow2

echo ">> Attaching disk and configuring boot order..."
qm set "$VMID" \
    --scsihw virtio-scsi-single \
    --scsi0 "$STORAGE":vm-"$VMID"-disk-1,discard=on,iothread=1 \
    --boot order=scsi0

### ─── RESIZE DISK ────────────────────────────────────────────────────────────
echo ">> Resizing disk to $DISK_SIZE..."
qm resize "$VMID" scsi0 "$DISK_SIZE"

### ─── CONFIGURE CLOUD-INIT ──────────────────────────────────────────────────
echo ">> Configuring cloud-init drive..."
qm set "$VMID" \
    --ide2 "$STORAGE":cloudinit \
    --citype nocloud

echo ">> Configuring serial console and guest agent..."
qm set "$VMID" \
    --serial0 socket \
    --vga serial0 \
    --agent enabled=1,fstrim_cloned_disks=1

### ─── SET DEFAULT CLOUD-INIT VALUES ─────────────────────────────────────────
# These are overridden per-clone via Terraform cloud-init config
echo ">> Setting default cloud-init parameters..."
qm set "$VMID" \
    --ciuser debian \
    --ipconfig0 ip=dhcp

### ─── CONVERT TO TEMPLATE ───────────────────────────────────────────────────
echo ">> Converting to template..."
qm template "$VMID"

### ─── CLEANUP ────────────────────────────────────────────────────────────────
echo ">> Cleaning up downloaded image..."
rm -f "$IMAGE_PATH"

### ─── DONE ───────────────────────────────────────────────────────────────────
echo ""
echo "==========================================="
echo "  Template created successfully!"
echo "  VM ID   : $VMID"
echo "  Name    : $NAME"
echo "  Storage : $STORAGE"
echo "  Disk    : $DISK_SIZE"
echo "==========================================="
echo ""
echo "Clone with Terraform using something like:"
echo ""
echo "  resource \"proxmox_vm_qemu\" \"vm\" {"
echo "    clone       = \"$NAME\""
echo "    full_clone  = false"
echo "    os_type     = \"cloud-init\""
echo "    ciuser      = \"debian\""
echo "    sshkeys     = file(\"~/.ssh/id_rsa.pub\")"
echo "    ipconfig0   = \"ip=dhcp\""
echo "  }"
echo ""
