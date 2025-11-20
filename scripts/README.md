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
./php_installer.sh --modules php_modules.txt

# Install PHP 8.3 with modules from file
./php_installer.sh 8.3 --modules php_modules.txt
```

**Parameters:**
- `VERSION` (optional): PHP version to install (default: `8.4`)
- `--modules FILE` (optional): Path to modules file (e.g., `php_modules.txt`)

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

### 5. `nginx_installer.sh`

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
```

**Parameters:**
- `--skip-confirm` - Skip installation confirmation prompt
- `--site DOMAIN` - Automatically create and configure a site for the specified domain

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
