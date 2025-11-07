# Scripts Directory

Collection of automation scripts for Proxmox infrastructure management.

---

## Available Scripts

### 1. `zfs-pool-r0.sh`

**Purpose:** Automated ZFS RAID0 pool configuration for Proxmox nodes with NVMe drives.

**Use Case:** Proxmox nodes with 4x 960GB NVMe drives (2 for OS, 2 for VMs).

**Features:**
- Creates a ZFS RAID0 pool using two specified NVMe disks
- Configures optimal ZFS properties for VM storage
- Sets up compression (LZ4), autotrim, and cache settings
- Mounts the pool at `/var/lib/vz` for Proxmox VM storage

**Usage:**
```bash
chmod +x zfs-pool-r0.sh
./zfs-pool-r0.sh /dev/nvmeXn1 /dev/nvmeYn1
```

**Parameters:**
- `$1`: First NVMe disk path (e.g., `/dev/nvme0n1`)
- `$2`: Second NVMe disk path (e.g., `/dev/nvme1n1`)

**Example:**
```bash
# List available disks first
lsblk -d -o NAME,SIZE,MODEL | grep nvme

# Create RAID0 pool with nvme0n1 and nvme1n1
./zfs-pool-r0.sh /dev/nvme0n1 /dev/nvme1n1
```

**Important Notes:**
- ⚠️ This will **destroy** any existing data on the specified disks
- The script will prompt for confirmation before proceeding
- Make sure you're NOT using OS disks (typically nvme2n1 and nvme3n1 in the target scenario)
- Requires root privileges

---

### 2. `zfs-limit-arc.sh`

**Purpose:** Configure and limit ZFS ARC (Adaptive Replacement Cache) memory usage.

**Use Case:** Prevent ZFS from consuming excessive RAM on Proxmox hosts, especially important when running VMs that need memory.

**Usage:**
```bash
chmod +x zfs-limit-arc.sh
./zfs-limit-arc.sh
```

**What it does:**
- Sets appropriate ARC memory limits for ZFS
- Helps balance memory between ZFS cache and VM memory requirements
- Prevents ZFS from starving VMs of available RAM

**Note:** Review and adjust memory limits in the script based on your host's total RAM before running.

---

## General Requirements

- Root/sudo privileges
- Proxmox VE environment
- ZFS utilities installed (usually pre-installed on Proxmox)

## Safety Tips

1. **Always backup important data** before running storage configuration scripts
2. **Double-check disk paths** - using wrong disks can result in data loss
3. **Test in a non-production environment** first if possible
4. Read through each script before executing to understand what it does

---

## Contributing

Feel free to suggest improvements or report issues with any of these scripts.
