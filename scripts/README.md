# Scripts Directory

Collection of automation scripts for Proxmox infrastructure management.

---

## Quick Installation

All scripts can be downloaded and executed directly from this repository:

```bash
# Download and run immediately
curl -sL https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/SCRIPT_NAME.sh | sudo bash

# Or download first, review, then execute
wget https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/SCRIPT_NAME.sh
chmod +x SCRIPT_NAME.sh
sudo ./SCRIPT_NAME.sh
```

Replace `SCRIPT_NAME.sh` with the desired script from the list below.

---

## Available Scripts

### 🔄 `ESP_sync.sh`

**Quick install:**
```bash
# Download and inspect (recommended - review before running)
wget https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/ESP_sync.sh
chmod +x ESP_sync.sh

# Review the script, then execute
sudo ./ESP_sync.sh
```

**Purpose:** Synchronize EFI System Partition (ESP) across multiple RAID1 disks and optionally reinstall GRUB bootloader.

**Use Case:** Critical tool for Proxmox upgrades on OVH dedicated servers with RAID1 boot configuration (e.g., PVE 7 → PVE 8). During major upgrades, the ESP partitions may become out of sync, causing boot failures where rEFInd shows empty entries and the server enters a boot loop.

**Problem it solves:**

When upgrading Proxmox on OVH servers with RAID1 boot disks:
1. The upgrade updates `/boot/efi` on the primary ESP partition
2. Secondary ESP partition(s) are NOT automatically synchronized
3. On reboot, rEFInd may boot from the outdated ESP partition
4. The default boot entry is empty → server enters boot loop
5. Manual IPMI intervention is required to select the correct rEFInd entry
6. After booting with the correct entry, this script synchronizes all ESP partitions

**Features:**
- 🔍 Auto-detects all EFI System Partitions (labeled `EFI_SYSPART`)
- 🎯 Identifies the currently mounted primary ESP at `/boot/efi`
- ⚠️ Double confirmation system with clear warnings
- 📋 First confirmation: Verify you're syncing the correct ESP with the right kernel/GRUB configuration
- 🔁 Syncs primary ESP to all other EFI partitions using `rsync`
- 🛠️ Optional GRUB reinstallation and update (second confirmation)
- 🔐 Safety checks and clear warning messages

**Usage:**
```bash
chmod +x ESP_sync.sh
sudo ./ESP_sync.sh
```

**What the script does:**

**Step 1: ESP Synchronization**
1. Detects the main ESP partition mounted at `/boot/efi`
2. Shows clear warning about verifying:
   - Correct kernel is running
   - Correct GRUB/rEFInd configuration in `/boot/efi`
   - This is the ESP you want to replicate
3. Requires typing `yes` to proceed
4. Uses `rsync -ax` to sync to all other `EFI_SYSPART` partitions

**Step 2: GRUB Reinstallation (Optional)**
1. After ESP sync, offers optional GRUB reinstallation
2. Warns this is an advanced operation
3. Requires typing `yes` to proceed
4. Executes:
   - `apt install --reinstall grub-efi-amd64`
   - `grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=proxmox --recheck`
   - `update-grub`

**Typical recovery scenario (OVH Proxmox upgrade):**

```bash
# 1. Server fails to boot after Proxmox upgrade
# 2. Connect via IPMI/KVM console
# 3. At rEFInd boot menu, manually select the working boot entry
# 4. Server boots successfully with upgraded Proxmox
# 5. SSH into the server and run this script:

wget https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/ESP_sync.sh
chmod +x ESP_sync.sh
sudo ./ESP_sync.sh

# 6. Confirm ESP synchronization (type: yes)
# 7. Optionally reinstall GRUB (type: yes)
# 8. Reboot - all ESP partitions now have identical boot configuration
```

**Important Notes:**
- ⚠️ **Only run this AFTER** you've successfully booted with the correct kernel
- ⚠️ **Verify** that `/boot/efi` contains the correct GRUB/rEFInd configuration before syncing
- ⚠️ **DO NOT** run this if you're uncertain about which ESP is correct
- 🔐 Requires root privileges
- 💾 Works with any number of `EFI_SYSPART` labeled partitions
- 🎯 Automatically skips the primary partition during sync (prevents self-sync)
- 📝 Default behavior is NO for both confirmations (safety first)

**When to use:**
- ⬆️ After major Proxmox VE upgrades (especially on OVH servers)
- 🔄 When GRUB/rEFInd configuration changes on one ESP but not others
- 🛠️ After manually fixing boot issues via IPMI
- 💿 When one ESP partition has been restored from backup
- 🔧 Before critical reboots to ensure boot redundancy

**Technical details:**

The script uses:
- `findmnt -n -o SOURCE /boot/efi` - Identifies the currently mounted ESP
- `blkid -o device -t LABEL=EFI_SYSPART` - Finds all EFI system partitions
- `rsync -ax` - Archive mode with device/special files, no crossing filesystems
- Temporary mount point: `/var/lib/grub/esp`

**Safety mechanisms:**
1. Explicit confirmation required (type `yes`, not just `y`)
2. Clear warnings before each operation
3. Shows which partition is the source
4. Automatically skips self-sync
5. Second confirmation for GRUB operations
6. Graceful cancellation on "NO"

---

### 📦 `backup_files_before_upgrade.sh`

**Quick install:**
```bash
# Download directly to your Proxmox node
wget -O /tmp/backup_files_before_upgrade.sh https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/backup_files_before_upgrade.sh
chmod +x /tmp/backup_files_before_upgrade.sh

# Or using curl
curl -o /tmp/backup_files_before_upgrade.sh https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/backup_files_before_upgrade.sh
chmod +x /tmp/backup_files_before_upgrade.sh
```

**Purpose:** Create a comprehensive backup of critical Proxmox configuration files before system upgrades.

**Use Case:** Essential backup tool before performing Proxmox upgrades, cluster changes, or major configuration modifications.

**Features:**
- 🎨 Visual and colorful terminal output with emojis
- 📦 Backs up essential configuration files:
  - `/etc/pve` - Cluster configuration
  - `/etc/pve/firewall` - Firewall rules
  - `/etc/pve/nodes/*/host.fw` - Host-specific firewall
  - `/etc/passwd` - User accounts
  - `/etc/network/interfaces` - Network configuration
  - `/etc/resolv.conf` - DNS configuration
  - `/etc/hosts` - Host mappings
  - `/etc/fstab` - Filesystem mounts
- 🔒 Preserves file permissions, ownership, ACLs, and extended attributes
- 📝 Automatic filename with hostname and timestamp
- 📊 Displays backup size and location
- 💡 Provides ready-to-use SCP command for downloading

**Usage:**
```bash
# Run on your Proxmox node
sudo /tmp/backup_files_before_upgrade.sh
```

**Download the backup to your local machine:**
```bash
# The script provides the exact command after completion
scp root@YOUR_PROXMOX_IP:/root/proxmox_etc_backup_*.tar.gz .
```

**Example output:**
```
═══════════════════════════════════════════════════════════
📦 Proxmox Configuration Backup Tool
═══════════════════════════════════════════════════════════

ℹ Backup file: proxmox_etc_backup_pve-node1_2025-12-16_14-30.tar.gz

ℹ Files and directories to backup:
  • /etc/pve
  • /etc/pve/firewall
  • /etc/pve/nodes/*/host.fw
  • /etc/passwd
  • /etc/network/interfaces
  • /etc/resolv.conf
  • /etc/hosts
  • /etc/fstab

✓ Backup completed successfully!

ℹ Backup details:
  • File: proxmox_etc_backup_pve-node1_2025-12-16_14-30.tar.gz
  • Size: 2.3M
  • Location: /root/proxmox_etc_backup_pve-node1_2025-12-16_14-30.tar.gz

═══════════════════════════════════════════════════════════
✓ Backup ready
═══════════════════════════════════════════════════════════

⚠ Remember to download this backup to a safe location!
ℹ You can use: scp root@192.168.1.100:/root/proxmox_etc_backup_pve-node1_2025-12-16_14-30.tar.gz .
```

**When to use:**
- ⬆️ Before major Proxmox VE upgrades
- 🔧 Before making significant configuration changes
- 📅 As part of regular backup routines
- 🖥️ Before cluster modifications
- 🌐 Prior to network configuration changes
- 🔥 Before firewall rule changes

**Important notes:**
- ⚠️ Requires root privileges to access all configuration files
- 💾 Store backups in a safe location outside the Proxmox node
- 🔄 Create backups before each major change
- 📦 Backup file includes timestamp for version control

---

### 1. `zfs-pool-r0.sh`

**Quick install:**
```bash
# Download and inspect
wget https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/zfs-pool-r0.sh
chmod +x zfs-pool-r0.sh

# Then run with your disk paths
sudo ./zfs-pool-r0.sh /dev/nvme0n1 /dev/nvme1n1
```

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

**Quick install:**
```bash
wget https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/zfs-limit-arc.sh
chmod +x zfs-limit-arc.sh
sudo ./zfs-limit-arc.sh
```

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

**Quick install:**
```bash
# Download and run directly (auto-detects PHP version)
curl -sL https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/apache_optimizer.sh | sudo bash

# Or download, review, then execute
wget https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/apache_optimizer.sh
chmod +x apache_optimizer.sh
sudo ./apache_optimizer.sh
```

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
- Configures VirtualHosts with FilesMatch directive for PHP-FPM socket communication
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

### 4. `php_installer.sh`

**Quick install:**
```bash
# Install PHP 8.4 with default modules
curl -sL https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/php_installer.sh | sudo bash

# Download to customize version or add modules
wget https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/php_installer.sh
chmod +x php_installer.sh

# Examples:
sudo ./php_installer.sh                             # PHP 8.4 base + fpm
sudo ./php_installer.sh 8.3                         # PHP 8.3 base + fpm
sudo ./php_installer.sh --modules php_modules.txt   # PHP 8.4 + custom modules
sudo ./php_installer.sh 8.3 --modules php_modules.txt
sudo ./php_installer.sh --uninstall                 # Uninstall PHP 8.4
sudo ./php_installer.sh 8.3 --uninstall             # Uninstall PHP 8.3
```

**Purpose:** Install PHP with custom version and modules.

**Two Main Use Cases:**

1. **Installing PHP from scratch** - Just need PHP with specific modules
2. **Migrating/Updating PHP** - Replicating exact module setup from old server to new one (e.g., CentOS 7 PHP 5.4 → Ubuntu 24 PHP 8.4)

**Features:**
- Installs PHP with custom version (default: 8.4)
- Always installs base packages: `php`, `php-dev`, `php-fpm`
- Optional module installation from file
- Enables and starts PHP-FPM service automatically
- Validates module availability before installation
- Reports unavailable modules with ChatGPT-ready prompt

**Usage:**
```bash
chmod +x php_installer.sh

# Install PHP 8.4 (base + dev + fpm only)
./php_installer.sh

# Install PHP 8.3 (base + dev + fpm only)
./php_installer.sh 8.3

# Install PHP 8.4 with modules from file
./php_installer.sh --modules php_modules.txt

# Install PHP 8.3 with modules from file
./php_installer.sh 8.3 --modules php_modules.txt

# Uninstall PHP 8.4 (uses php_modules.txt if exists in current directory)
./php_installer.sh --uninstall

# Uninstall PHP 8.3
./php_installer.sh 8.3 --uninstall
```

**Parameters:**
- `VERSION` (optional): PHP version to install/uninstall (default: `8.4`)
- `--modules FILE` (optional): Path to modules file (e.g., `php_modules.txt`)
- `--uninstall` (optional): Uninstall PHP and all installed modules (requires confirmation)

---

#### Use Case 1: Installing PHP from Scratch

If you just want to install PHP with some modules you need (NOT migrating from another server):

**Step 1: Create your modules list**

Simply create a `php_modules.txt` file with the modules you need:

```bash
nano php_modules.txt
```

Example content:
```
# Web essentials
curl
mbstring
xml
zip

# Database
mysql

# Image processing
gd

# Caching
opcache
```

**Step 2: Run the installer**

```bash
./php_installer.sh --modules php_modules.txt

# Or with specific PHP version
./php_installer.sh 8.4 --modules php_modules.txt
```

That's it! No need to follow the migration steps below.

---

#### Use Case 2: Migrating/Updating PHP from Old Server

**⚠️ ONLY follow this if you want to replicate the exact PHP setup from an old server to a new one.**

When migrating from an old server to a new one and you want to replicate the same PHP modules:

**Step 1: Get module list from old server**

SSH into your old server and run:
```bash
php -m
```

Example output:
```
[PHP Modules]
bz2
calendar
Core
ctype
curl
date
ereg
exif
fileinfo
filter
ftp
gettext
gmp
hash
iconv
json
libxml
mhash
openssl
pcntl
pcre
Phar
readline
Reflection
session
shmop
SimpleXML
sockets
SPL
standard
tokenizer
xml
zip
zlib

[Zend Modules]
```

**Step 2: Ask ChatGPT for compatible modules**

Copy this prompt and replace the placeholders:

```
Dame la lista de módulos de PHP compatibles para mi nuevo servidor.

Servidor ORIGEN:
- OS: CentOS 7
- PHP: 5.4
- Módulos actuales:
[paste output of php -m here]

Servidor DESTINO:
- OS: Ubuntu 24.04
- PHP: 8.4

Por favor dame solo el listado de nombres de módulos (uno por línea)
que puedo poner en php_modules.txt para instalar con apt.
Excluye módulos que ya vienen por defecto en PHP 8.4.
```

**Step 3: Create php_modules.txt**

ChatGPT will give you a list. Create a file with one module per line:

```bash
nano php_modules.txt
```

Example content:
```
# Core extensions
curl
mbstring
xml
zip
gd

# Database
mysql
pgsql
sqlite3

# Caching
opcache
apcu

# Other
intl
bcmath
gmp
soap
```

**Step 4: Run the installer**

```bash
./php_installer.sh 8.4 --modules php_modules.txt
```

**What the script does:**
1. Detects your OS information (`/etc/os-release`)
2. Shows you which packages will be installed
3. Validates each module exists in apt repositories
4. Installs available modules
5. Enables and starts PHP-FPM service
6. Reports any modules that don't exist

**If modules fail to install:**

The script will show you a ready-to-copy prompt:
```
┌─────────────────────────────────────────────────────┐
│ Estos módulos de PHP NO EXISTEN en mi sistema:
│
│ OS: Ubuntu 24.04 LTS (ubuntu 24.04)
│ PHP: 8.4
│
│ Módulos que NO EXISTEN:
│ - ereg
│ - mhash
│
└─────────────────────────────────────────────────────┘

(Copia y pega en ChatGPT si necesitas ayuda)
```

Just copy/paste that into ChatGPT and it will tell you if those modules:
- Have been renamed
- Are included by default in the new PHP version
- Simply don't exist anymore

**Important Notes:**
- The script does NOT automatically search for alternatives
- If a module doesn't exist, it's skipped (no installation failure)
- Core modules like `Core`, `standard`, `SPL` don't need to be in the file
- Module names should NOT include the `php8.4-` prefix, just the name (e.g., `curl`, not `php8.4-curl`)

---

### 5. `sshd_hardening.sh`

**Quick install:**
```bash
# Download and review (recommended - this modifies SSH access)
wget https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/sshd_hardening.sh
chmod +x sshd_hardening.sh

# Review the script thoroughly, then execute
sudo ./sshd_hardening.sh
```

**Purpose:** Automated SSH hardening with idempotent configuration for secure access control.

**Use Case:** Lock down SSH access on Proxmox nodes or any Linux server by disabling password authentication and restricting access to specific users from internal networks only.

**Features:**
- Idempotent: Checks current configuration before making changes
- Disables root login with password (allows key-based only)
- Disables password authentication globally
- Creates user-specific access rules with network restrictions
- Validates configuration before applying (prevents lockouts)
- Interactive prompts for user and network specification
- Automatic sshd service restart after changes

**Usage:**
```bash
chmod +x sshd_hardening.sh
sudo ./sshd_hardening.sh
```

**What the script does:**

**Step 1: Input Collection**
1. Prompts for internal SSH user (e.g., `admin`, `deploy`)
2. Prompts for allowed network in CIDR notation (e.g., `192.168.1.0/24`)
3. Validates that both values are provided

**Step 2: Configuration Check**
1. Verifies if `PermitRootLogin prohibit-password` is set
2. Verifies if `PasswordAuthentication no` is set
3. Checks if the specific `Match User` block already exists
4. If all settings are correct, exits without changes

**Step 3: Apply Hardening (if needed)**
1. Creates temporary copy of `/etc/ssh/sshd_config`
2. Removes any existing `PermitRootLogin` directives
3. Removes any existing `PasswordAuthentication` directives
4. Adds `PermitRootLogin prohibit-password`
5. Adds `PasswordAuthentication no`
6. Removes any previous `Match User` block for the specified user
7. Adds new `Match User` block with network restriction:
   ```
   Match User <username>
       AllowUsers <username>@<network>
   ```

**Step 4: Validation and Deployment**
1. Tests configuration with `sshd -t` before applying
2. If valid: applies changes and restarts sshd
3. If invalid: aborts without making changes (prevents lockout)

**Example session:**
```bash
sudo ./sshd_hardening.sh

Usuario SSH interno (ej: usuario): admin
Red interna permitida (CIDR, ej: 192.168.1.0/24): 10.0.0.0/24

Configuración incompleta o incorrecta. Aplicando estado deseado...
Cambios aplicados y sshd reiniciado correctamente.
```

**Configuration applied:**
```
# Global settings
PermitRootLogin prohibit-password
PasswordAuthentication no

# User-specific rules
Match User admin
    AllowUsers admin@10.0.0.0/24
```

**Important notes:**
- **CRITICAL:** Ensure you have SSH key-based authentication configured BEFORE running this script
- **CRITICAL:** Test SSH access from another session before closing your current one
- The script disables password authentication entirely
- Root login is restricted to key-based authentication only
- Only the specified user from the specified network can connect
- Idempotent: Safe to run multiple times with same or different parameters
- Always validates configuration before applying to prevent SSH lockout

**When to use:**
- After initial Proxmox installation
- When securing new VM or LXC containers
- As part of server hardening procedures
- Before exposing servers to untrusted networks
- When implementing zero-trust network policies

**Safety mechanisms:**
1. Configuration validation before applying (`sshd -t`)
2. Uses temporary file for changes
3. Automatic cleanup on exit
4. Clear error messages if validation fails
5. Idempotent behavior (checks before modifying)
6. No changes if already correctly configured

**Technical details:**
- Uses `grep -Eq` for regex pattern matching
- Uses `awk` for complex multi-line block detection
- Preserves existing sshd_config structure
- Removes duplicate/conflicting directives automatically
- Appends new configuration at the end of file

**Pre-flight checklist:**
1. Ensure SSH key authentication is already configured
2. Test key-based login works: `ssh -i ~/.ssh/id_rsa user@server`
3. Verify you have another way to access the server (console, IPMI, KVM)
4. Keep current SSH session open until new connection is verified
5. Have the correct network CIDR ready (check with `ip a` or `ifconfig`)

**Recovery from lockout:**
If you get locked out, use console access (IPMI/KVM) to:
```bash
# Restore original configuration
sudo cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
sudo systemctl restart sshd

# Or temporarily enable password auth
sudo sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

---

### 6. `nginx_installer.sh`

**Quick install:**
```bash
# Interactive installation (recommended - asks for confirmation)
curl -sL https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/nginx_installer.sh | sudo bash

# Silent install (no prompts)
wget https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/nginx_installer.sh
chmod +x nginx_installer.sh
sudo ./nginx_installer.sh --skip-confirm

# Install and create a site automatically
sudo ./nginx_installer.sh --site images.example.com

# One-liner with site creation (after downloading)
wget -q https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/nginx_installer.sh && \
chmod +x nginx_installer.sh && \
sudo ./nginx_installer.sh --skip-confirm --site images.example.com

# Uninstall Nginx completely
sudo ./nginx_installer.sh --uninstall

# Reconfigure for new system specs (after VM resize)
sudo ./nginx_installer.sh --reconfigure
```

**Purpose:** Install and auto-configure Nginx optimized for serving static content (HTTP only, port 80).

**Features:**
- Installs Nginx optimized for static files (images, CSS, JS, fonts, etc.)
- Auto-optimizes configuration based on system specs (CPU cores, RAM)
- Configures browser caching for static assets (30 days for images/fonts, 7 days for documents)
- Enables gzip compression for text-based files
- Sets up cache directory for Nginx proxy cache
- Creates monitoring dashboard accessible only from LAN
- HTTP only (port 80) - SSL/TLS handled by upstream reverse proxy

**Usage:**
```bash
chmod +x nginx_installer.sh

# Interactive installation (asks for confirmation)
sudo ./nginx_installer.sh

# Silent installation (no confirmation)
sudo ./nginx_installer.sh --skip-confirm

# Install and create a site automatically
sudo ./nginx_installer.sh --site images.example.com

# Combined: silent install + create site
sudo ./nginx_installer.sh --skip-confirm --site images.example.com

# Uninstall Nginx and all configurations
sudo ./nginx_installer.sh --uninstall

# Reconfigure for new system specs (after VM resize)
sudo ./nginx_installer.sh --reconfigure
```

**Parameters:**
- `--skip-confirm` - Skip installation confirmation prompt
- `--site DOMAIN` - Automatically create and configure a site for the specified domain
- `--uninstall` - Uninstall Nginx, remove all configurations, logs, and cache (requires confirmation)
  - **Note:** `/var/www/html/` is preserved and NOT deleted during uninstall
- `--reconfigure` - Re-optimize nginx.conf for new system specs after VM resize (only updates performance settings, preserves sites and other configs)

**What the script does:**

1. **System Analysis:**
   - Detects CPU cores and RAM
   - Calculates optimal Nginx settings
   - Identifies LAN IP for monitoring endpoint

2. **Installs Nginx with modules:**
   - `nginx` - Core web server
   - `libnginx-mod-http-cache-purge` - Cache management

3. **Auto-optimization:**
   - Sets `worker_processes` = CPU cores
   - Sets `worker_connections` = 1024 × CPU cores
   - Adjusts buffer sizes based on available RAM
   - Configures optimal timeouts for static content

4. **Static file caching:**
   - Browser caching: 30 days for images, fonts, CSS, JS
   - Browser caching: 7 days for PDFs, archives
   - Creates `/var/cache/nginx` for proxy cache
   - Gzip compression enabled for text-based files

5. **Creates snippet:**
   - `/etc/nginx/snippets/static_cache.conf` - Browser caching rules

6. **Monitoring dashboard (LAN only):**
   - Accessible at `http://[LAN_IP]:8080/nginx_status`
   - Shows basic Nginx statistics
   - Only accessible from LAN subnet and localhost

7. **Creates template:**
   - `/etc/nginx/templates/nginx-static` - Static content serving template

8. **Default site:**
   - Creates a welcome page at `/var/www/html/index.html`
   - Configured with static file caching

**Example output:**

```
📊 Detectando especificaciones del sistema...
   ✓ CPU Cores: 4
   ✓ RAM: 8GB (8192MB)
   ✓ LAN IP: 192.168.1.100

⚙️  Configuración optimizada calculada:
   worker_processes: 4
   worker_connections: 4096
   worker_rlimit_nofile: 8192
   client_max_body_size: 100M
   keepalive_timeout: 65s
```

**After installation:**

- **Main site:** `http://[SERVER_IP]`
- **Monitoring:** `http://[LAN_IP]:8080/nginx_status` (LAN only)
- **Configuration:** `/etc/nginx/nginx.conf`
- **Sites:** `/etc/nginx/sites-available/`
- **Template:** `/etc/nginx/templates/nginx-static`
- **Cache snippet:** `/etc/nginx/snippets/static_cache.conf`
- **Logs:** `/var/log/nginx/`
- **Web root:** `/var/www/html/`

**Creating a new static site:**

**Option 1: Automatic (recommended)**

Use the `--site` flag during installation or run the script again:
```bash
sudo ./nginx_installer.sh --site images.example.com
```

This automatically:
- Creates the site configuration from template
- Replaces `__DOMAIN__` and `__DOMAIN_SAFE__` placeholders
- Creates web directory at `/var/www/images.example.com`
- Creates a sample index.html
- Enables the site
- Tests and reloads Nginx

**Option 2: Manual**

1. Copy the template:
```bash
sudo cp /etc/nginx/templates/nginx-static /etc/nginx/sites-available/images.example.com.conf
```

2. Edit the file and replace placeholders:
```bash
sudo nano /etc/nginx/sites-available/images.example.com.conf
# Replace __DOMAIN__ with: images.example.com
# Replace __DOMAIN_SAFE__ with: images_example_com
```

3. Create the web directory:
```bash
sudo mkdir -p /var/www/images.example.com
sudo chown www-data:www-data /var/www/images.example.com
```

4. Enable the site:
```bash
sudo ln -s /etc/nginx/sites-available/images.example.com.conf /etc/nginx/sites-enabled/
```

5. Test and reload:
```bash
sudo nginx -t && sudo systemctl reload nginx
```

**Monitoring endpoint details:**

Access `http://[LAN_IP]:8080/nginx_status` from your LAN to see:
- Active connections
- Server accepts/handled/requests
- Reading/Writing/Waiting connections

**Caching details:**

Browser caching is automatically applied to:
- **30 days:** `.jpg`, `.jpeg`, `.png`, `.gif`, `.ico`, `.css`, `.js`, `.svg`, `.webp`, `.woff`, `.woff2`, `.ttf`, `.eot`
- **7 days:** `.pdf`, `.zip`, `.tar`, `.gz`, `.rar`
- Gzip compression enabled for text files, JSON, XML, fonts

**Optimization details:**

The script adjusts settings based on RAM:
- **8GB+ RAM:** 100M max body size, 128k buffers, 65s keepalive
- **4-7GB RAM:** 50M max body size, 64k buffers, 60s keepalive
- **<4GB RAM:** 20M max body size, 32k buffers, 30s keepalive

**Important notes:**
- This setup is HTTP only (port 80) - SSL/TLS should be handled by upstream reverse proxy
- Server tokens disabled for security
- Monitoring endpoint restricted to LAN only
- Perfect for serving static assets behind a reverse proxy

---

### 7. `passgen.sh`

**Quick install:**
```bash
# Generate a password (default: 16 chars)
curl -sL https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/passgen.sh | bash

# Generate a passphrase in Spanish
curl -sL https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/passgen.sh | bash -s -- --passphrase

# Generate a base64 tech token
curl -sL https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/passgen.sh | bash -s -- --tech
```

**Purpose:** Generate secure passwords, passphrases, or base64 tokens directly from the terminal.

**Use Case:** Quick generation of secure credentials for services, APIs, databases, or any scenario where you need a strong password without installing additional tools.

**Three modes:**

| Mode | Flag | Output example |
|------|------|----------------|
| Password (default) | — | `Rp5RRL#dYYf6Nzjr` |
| Passphrase | `--passphrase` | `tierra5-campo2-norte8-fuego1` |
| Tech token | `--tech` | `K6k08ssLjPU80jmP9qVG5OVDVE+KX4aP...` |

---

#### Mode: Password (default)

Generates a random password with guaranteed complexity.

**Requirements enforced:**
- Minimum 16 characters
- At least one uppercase letter (A-Z)
- At least one lowercase letter (a-z)
- At least one digit (0-9)
- At least one symbol from: `#?!._-`

**Symbols chosen specifically** to avoid issues with bash, curl, powershell, and shell escaping. No `$`, `\`, `` ` ``, `'`, `"`, `&`, `|`, or `;`.

```bash
# Default: 16 characters
curl -sL .../passgen.sh | bash

# Custom length (minimum 16)
curl -sL .../passgen.sh | bash -s -- --length 24

# Download and run locally
bash passgen.sh
bash passgen.sh --length 32
```

---

#### Mode: Passphrase (`--passphrase`)

Generates a passphrase using random words from the system's Spanish dictionary.

**Requirements:**
- Minimum 4 words
- Words filtered to 4-8 characters, lowercase only, no accents/ñ/dieresis
- Requires a Spanish dictionary at `/usr/share/dict/spanish` (see install instructions below)

```bash
# Default: 4 words separated by hyphens
curl -sL .../passgen.sh | bash -s -- --passphrase

# More words
curl -sL .../passgen.sh | bash -s -- --passphrase --words 6

# Custom separator
curl -sL .../passgen.sh | bash -s -- --passphrase --separator .
```

**Example output:** `tierra5-campo2-norte8-fuego1`

**Important:** The dictionary is NOT included in the repository. This is intentional — embedding the wordlist would expose the keyspace, reducing security.

**Installing the Spanish dictionary:**

| OS | Command |
|----|---------|
| Debian/Ubuntu | `sudo apt install wspanish` |
| macOS (Homebrew) | `brew install aspell && mkdir -p ~/.local/share/dict && aspell dump master es \| sort -u > ~/.local/share/dict/spanish` |

The script searches for the dictionary in: `/usr/share/dict/spanish`, `/usr/local/share/dict/spanish`, and `~/.local/share/dict/spanish`. On macOS, the home directory path avoids SIP restrictions — no `sudo` needed. You only need to do this once.

---

#### Mode: Tech token (`--tech`)

Generates a base64-encoded random token using `openssl rand`.

```bash
# Default: 32 bytes of entropy (44 chars output)
curl -sL .../passgen.sh | bash -s -- --tech

# Custom entropy (64 bytes)
curl -sL .../passgen.sh | bash -s -- --tech --length 64
```

**Requires:** `openssl` (pre-installed on virtually all Linux systems).

---

#### All options

```
passgen.sh [opciones]

MODES:
  (default)        Random password
  --passphrase     Spanish passphrase (requires wspanish)
  --tech           Base64 token (openssl rand)

PASSWORD OPTIONS:
  --length N       Password length (min 16, default: 16)

PASSPHRASE OPTIONS:
  --words N        Number of words (min 4, default: 4)
  --separator C    Word separator (default: -)

TECH OPTIONS:
  --length N       Entropy bytes for openssl (default: 32 → 44 chars)

OTHER:
  --help, -h       Show help
```

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
