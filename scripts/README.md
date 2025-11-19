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
./php_installer.sh 8.4 php_modules.txt
```

**Parameters:**
- `$1` (optional): PHP version to install (default: `8.4`)
- `$2` (optional): Path to modules file (e.g., `php_modules.txt`)

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
./php_installer.sh 8.4 php_modules.txt
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
./php_installer.sh 8.4 php_modules.txt
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
