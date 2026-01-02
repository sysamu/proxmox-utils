#!/bin/bash

set -euo pipefail

MOUNTPOINT="/var/lib/grub/esp"
MAIN_PARTITION=$(findmnt -n -o SOURCE /boot/efi)

echo "=========================================="
echo "⚠️  ESP SYNCHRONIZATION"
echo "=========================================="
echo "Main ESP partition detected: ${MAIN_PARTITION}"
echo ""
echo "⚠️  WARNING: Before proceeding, make sure that:"
echo "   • You are running the correct kernel"
echo "   • The current /boot/efi has the correct GRUB/rEFInd configuration"
echo "   • This is the ESP you want to replicate to other partitions"
echo ""
read -p "Are you sure you want to sync this ESP to all other EFI_SYSPART partitions? (yes/NO): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Operation cancelled"
    exit 0
fi

echo "Starting ESP synchronization..."
mkdir -p "${MOUNTPOINT}"

while read -r partition; do
    if [[ "${partition}" == "${MAIN_PARTITION}" ]]; then
        continue
    fi
    echo "Working on ${partition}"
    mount "${partition}" "${MOUNTPOINT}"
    rsync -ax "/boot/efi/" "${MOUNTPOINT}/"
    umount "${MOUNTPOINT}"
done < <(blkid -o device -t LABEL=EFI_SYSPART)

# Optional: Reinstall and update GRUB
echo ""
echo "=========================================="
echo "⚠️  GRUB REINSTALLATION (OPTIONAL)"
echo "=========================================="
echo "This will reinstall GRUB bootloader on the EFI partition."
echo "This is recommended to ensure bootloader consistency across all ESP partitions,"
echo "but it's an advanced operation that modifies your boot configuration."
echo ""
echo "⚠️  WARNING: Be sure you understand what this does before proceeding!"
echo ""
read -p "Do you want to reinstall and update GRUB? (yes/NO): " -r
echo ""

if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Reinstalling GRUB..."
    apt install --reinstall grub-efi-amd64
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=proxmox --recheck
    update-grub
    echo "✓ GRUB reinstalled and updated successfully"
else
    echo "Skipping GRUB reinstallation"
fi