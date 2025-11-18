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

### 3. `apache_optimizer.sh`

**Purpose:** Automatic optimization of Apache and PHP-FPM based on available CPU and RAM resources.

**Use Case:** VMs or LXC containers running Apache + PHP-FPM (NOT for Proxmox host itself).

**Features:**
- Auto-detects installed PHP version
- Installs PHP-FPM if not present
- Enables required Apache modules (proxy, proxy_fcgi, setenvif)
- Calculates optimal worker/process values based on system resources
- Configures Apache MPM Event module dynamically
- Optimizes PHP-FPM pool settings (dynamic process management)
- Tunes PHP.ini for web server performance
- Configures VirtualHosts with ProxyPassMatch for PHP-FPM socket communication
- Applies security hardening (ServerSignature Off, ServerTokens Prod)
- Optimizes KeepAlive and connection timeout settings

**Usage:**
```bash
# Run inside your Apache VM or LXC container
chmod +x apache_optimizer.sh
sudo ./apache_optimizer.sh
```

**Dynamic Calculations:**
- **PHP-FPM max_children:** `RAM_MB / 128` (minimum: 4, maximum: 32)
- **Apache MaxRequestWorkers:** `CPU_CORES × 50`
- **PM Start/Min/Max:** Calculated proportionally based on max_children
- Process scaling adapts to detected CPU cores and available RAM

**Optimized Settings Applied:**

**PHP.ini:**
- memory_limit = 256M
- max_execution_time = 60s
- max_input_time = 60s
- post_max_size = 32M
- upload_max_filesize = 32M
- display_errors = Off
- log_errors = On

**Apache:**
- KeepAlive: On (100 requests, 5s timeout)
- Global timeout: 30s
- MaxConnectionsPerChild: 5000
- Automatically configures MPM Event module

**PHP-FPM:**
- Process manager: dynamic
- request_terminate_timeout = 60s
- Automatic pm.* values based on RAM

**Important Notes:**
- ⚠️ **Run this script INSIDE the VM/LXC**, not on the Proxmox host
- The script modifies Apache and PHP configuration files
- Services are automatically restarted after configuration
- Works with any PHP version installed (auto-detected)
- VirtualHosts are automatically updated with FPM proxy configuration

**What Gets Modified:**
- `/etc/php/{version}/fpm/pool.d/www.conf`
- `/etc/php/{version}/fpm/php.ini`
- `/etc/apache2/mods-available/mpm_event.conf`
- `/etc/apache2/apache2.conf`
- All enabled VirtualHosts in `/etc/apache2/sites-enabled/`

---

## General Requirements

- Root/sudo privileges
- Proxmox VE environment (for ZFS scripts)
- ZFS utilities installed (usually pre-installed on Proxmox)
- Apache + PHP environment (for apache_optimizer.sh)

## Safety Tips

1. **Always backup important data** before running storage configuration scripts
2. **Double-check disk paths** - using wrong disks can result in data loss
3. **Test in a non-production environment** first if possible
4. Read through each script before executing to understand what it does
5. **apache_optimizer.sh is for VMs/LXCs only** - do not run on Proxmox host

---

## Contributing

Feel free to suggest improvements or report issues with any of these scripts.
