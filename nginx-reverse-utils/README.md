# Nginx Reverse Proxy Utils

Utilities for automated management of Nginx reverse proxies with SSL/TLS certificates via Certbot and Cloudflare DNS.

## Structure

```
nginx-reverse-utils/
├── bash-utils/
│   └── nginx-bash-aliases    # Bash functions to automatically create sites
└── templates/
    ├── nginx-subdomain        # Template for standard HTTP reverse proxy
    └── nginx-wss              # Template for WebSocket Secure (WSS)
```

## Prerequisites

- **Nginx** installed and configured
- **Certbot** with Cloudflare plugin (`python3-certbot-dns-cloudflare`)
- **Cloudflare credentials** at `/etc/nginx/.secrets/certbot/cloudflare.ini`
- Templates directory at `/etc/nginx/templates/`
- Linux operating system (Debian/Ubuntu recommended)

## Installation

### 1. Copy Nginx Templates

```bash
# Create templates directory if it doesn't exist
sudo mkdir -p /etc/nginx/templates

# Copy templates
sudo cp templates/nginx-subdomain /etc/nginx/templates/
sudo cp templates/nginx-wss /etc/nginx/templates/
```

### 2. Configure Cloudflare Credentials

```bash
# Create secrets directory
sudo mkdir -p /etc/nginx/.secrets/certbot

# Create credentials file
sudo nano /etc/nginx/.secrets/certbot/cloudflare.ini
```

Content of `cloudflare.ini` file:
```ini
dns_cloudflare_api_token = YOUR_CLOUDFLARE_API_TOKEN
```

```bash
# Secure with restrictive permissions
sudo chmod 600 /etc/nginx/.secrets/certbot/cloudflare.ini
```

### 3. Load Bash Functions

Add to the end of your `~/.bashrc` or `~/.zshrc`:

```bash
source /path/to/nginx-reverse-utils/bash-utils/nginx-bash-aliases
```

Or copy the content directly into your shell configuration file.

Then reload the configuration:
```bash
source ~/.bashrc  # or source ~/.zshrc
```

## Available Functions

### `sites`

Alias to quickly access the enabled sites directory:

```bash
sites
# Equivalent to: cd /etc/nginx/sites-enabled
```

### `gensitecert`

Generates an HTTP/HTTPS reverse proxy site with automatic SSL certificate.

**Syntax:**
```bash
gensitecert <domain> <upstream_host> [port]
```

**Parameters:**
- `domain`: Full domain name (FQDN) for the site
- `upstream_host`: Backend server host or IP
- `port`: Backend port (default: 80)

**Examples:**
```bash
# Basic reverse proxy (port 80)
gensitecert subdomain.example.com upstream.example.com

# With custom port
gensitecert api.example.com backend.example.com 8080
```

**Automated process:**
1. Generates Nginx configuration from template
2. Requests SSL certificate via Cloudflare DNS
3. Applies certificate with Certbot's nginx plugin
4. Reloads Nginx
5. Site becomes available at `https://<domain>`

### `genwsscert`

Generates a WebSocket Secure (WSS) site with SSL certificate.

**Syntax:**
```bash
genwsscert <domain> <upstream_name> [port]
```

**Parameters:**
- `domain`: Full domain name (FQDN)
- `upstream_name`: Upstream name for WebSocket backend
- `port`: WebSocket backend port (default: 8080)

**Example:**
```bash
genwsscert wss.example.com upstream_ws 8080
```

**Automated process:**
1. Creates Nginx configuration with upstream and WebSocket proxy
2. Requests SSL certificate via Cloudflare DNS
3. Uncomments certificate lines in configuration
4. Reloads Nginx
5. WSS site becomes available at `wss://<domain>`

## Templates

### nginx-subdomain

Template for standard HTTP/HTTPS reverse proxy.

**Substitution variables:**
- `__DOMAIN__`: The full domain
- `__DOMAIN_SAFE__`: Domain version with dots replaced by underscores (for log file names)
- `__UPSTREAM__`: Backend host and port

**Features:**
- Large client headers (64k) for complex APIs
- Security headers included
- Search engine robots blocking
- Separate logs per domain

### nginx-wss

Template for WebSocket Secure connections.

**Substitution variables:**
- `__DOMAIN__`: The full domain
- `__DOMAIN_SAFE__`: Safe domain version for file names
- `__UPSTREAM__`: WebSocket backend host
- `__PORT__`: Backend port

**Features:**
- Upstream with `ip_hash` for session persistence
- SSL on port 443
- WebSocket-specific headers (Upgrade, Connection)
- Separate logs for WSS access and errors

## Required Nginx Snippets

Templates depend on the following snippets in `/etc/nginx/snippets/`:

- `security.conf`: HTTP security headers
- `ssl_wss.conf`: SSL configuration for WSS
- `wss_options.conf`: WebSocket proxy headers
- `proxy_options.conf`: Standard HTTP proxy headers
- `block_robots_snippet.conf`: Robot indexing blocking

## Troubleshooting

### Error: "Nginx template not found"

Verify templates are in `/etc/nginx/templates/`:
```bash
ls -la /etc/nginx/templates/
```

### Error: "Certbot DNS failed"

Verify Cloudflare credentials:
```bash
sudo cat /etc/nginx/.secrets/certbot/cloudflare.ini
# Make sure the API token is valid
```

### Certificate not applying

Check Certbot logs:
```bash
sudo certbot certificates
sudo tail -f /var/log/letsencrypt/letsencrypt.log
```

### Nginx not reloading

Test configuration manually:
```bash
sudo nginx -t
sudo systemctl status nginx
```

## Security Notes

- Cloudflare credentials must have `600` permissions (owner read-only)
- Certificates are automatically renewed by Certbot
- Recommended to configure a cronjob for automatic renewal:
  ```bash
  0 0 * * * certbot renew --quiet
  ```

## Contributing

To improve these utilities, make sure to:
1. Test functions in a development environment first
2. Document any template changes
3. Update examples if you change the syntax

## License

Part of the `proxmox-utils` project. See LICENSE in the repository root.
