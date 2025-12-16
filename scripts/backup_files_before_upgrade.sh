#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored messages
print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    echo -e "  ${YELLOW}Please use: sudo $0${NC}\n"
    exit 1
fi

print_header "📦 Proxmox Configuration Backup Tool"

# Generate backup filename with hostname and timestamp
BACKUP_FILE="proxmox_etc_backup_$(hostname)_$(date +%F_%H-%M).tar.gz"

print_info "Backup file: ${GREEN}$BACKUP_FILE${NC}"
echo ""

# List of files/directories to backup
print_info "Files and directories to backup:"
echo -e "  ${CYAN}•${NC} /etc/pve"
echo -e "  ${CYAN}•${NC} /etc/pve/firewall"
echo -e "  ${CYAN}•${NC} /etc/pve/nodes/*/host.fw"
echo -e "  ${CYAN}•${NC} /etc/passwd"
echo -e "  ${CYAN}•${NC} /etc/network/interfaces"
echo -e "  ${CYAN}•${NC} /etc/resolv.conf"
echo -e "  ${CYAN}•${NC} /etc/hosts"
echo -e "  ${CYAN}•${NC} /etc/fstab"
echo ""

# Create backup
print_info "Creating backup..."
echo ""

if tar --numeric-owner \
    --xattrs \
    --acls \
    -czvf "$BACKUP_FILE" \
    /etc/pve \
    /etc/pve/firewall \
    /etc/pve/nodes/*/host.fw \
    /etc/passwd \
    /etc/network/interfaces \
    /etc/resolv.conf \
    /etc/hosts \
    /etc/fstab 2>/dev/null; then

    echo ""
    print_success "Backup completed successfully!"

    # Get backup file size
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)

    echo ""
    print_info "Backup details:"
    echo -e "  ${CYAN}•${NC} File: ${GREEN}$BACKUP_FILE${NC}"
    echo -e "  ${CYAN}•${NC} Size: ${GREEN}$BACKUP_SIZE${NC}"
    echo -e "  ${CYAN}•${NC} Location: ${GREEN}$(pwd)/$BACKUP_FILE${NC}"

    print_header "✓ Backup ready"

    print_warning "Remember to download this backup to a safe location!"
    print_info "You can use: ${YELLOW}scp root@$(hostname -I | awk '{print $1}'):$(pwd)/$BACKUP_FILE .${NC}"
    echo ""

else
    echo ""
    print_error "Backup failed!"
    exit 1
fi
