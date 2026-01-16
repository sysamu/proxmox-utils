# Pulse - Proxmox Monitoring Dashboard on OVH Public Cloud

This Terraform configuration deploys [Pulse](https://github.com/rcourtman/Pulse) on OVH Public Cloud. Pulse is a unified monitoring dashboard that consolidates metrics and alerts from Proxmox, Docker, and Kubernetes into a single interface.

## What is Pulse?

Pulse is a "single pane of glass" monitoring solution designed for homelabs and sysadmins who want comprehensive monitoring without enterprise complexity.

### Key Features

- **Unified Monitoring**: Tracks Proxmox VE/PBS/PMG, Docker, Podman, Kubernetes, and OCI containers
- **Auto-Discovery**: Automatically locates Proxmox nodes on your network
- **Smart Alerts**: Notifications via Discord, Slack, Telegram, Email, and webhooks
- **Metrics Storage**: Persistent history with configurable retention periods
- **Backup Visualization**: Explores backup jobs and storage consumption
- **AI Features**: Chat assistant, background health checks (Patrol), and alert analysis
- **OIDC/SSO Support**: Enterprise authentication options
- **No Telemetry**: Your data stays private

## Prerequisites

1. **OVH Account** with Public Cloud activated
2. **Existing OVH Public Cloud Project** (get the project ID from API or control panel)
3. **vRack** configured with private networks (see setup below)
4. **Proxmox VE Cluster** (version 7.0 or higher recommended)
5. **SSH Keys** uploaded to OVH (supports multiple keys - recommended)
6. **Terraform** installed (version 1.0 or higher)

### vRack Network Setup in OVH (REQUIRED before Terraform)

**📖 For detailed step-by-step instructions, see [OVH_SETUP.md](OVH_SETUP.md)**

You must create and configure the private networks in OVH **before** running Terraform:

#### Network 1: LAN Network (for Pulse GUI access)
- **Name**: `my-lan-network` (or your preferred name)
- **VLAN ID**: None (or your existing LAN VLAN)
- **Subnet**: `192.168.32.0/19`
- **DHCP**: Enabled with appropriate pool
- **Purpose**: Access Pulse web interface from your LAN

#### Network 2: Monitoring Network (for Proxmox)
- **Name**: `proxmox-monitoring` (or your preferred name)
- **VLAN ID**: `100`
- **Subnet**: `10.200.10.0/24`
- **DHCP Pool**: `10.200.10.100 - 10.200.10.200`
  - **Reserved IPs**: `.1` to `.99` (for infrastructure)
  - `.10` to `.13` - Your Proxmox nodes
  - `.100` to `.200` - DHCP pool for Pulse and other services
- **Purpose**: Isolated network for Proxmox monitoring

**Steps in OVH Control Panel:**

1. **Access Private Networks**
   - Go to: OVH Manager → Public Cloud → Your Project → Network → Private Networks

2. **Create LAN Network** (if not exists)
   - Click "Create Private Network"
   - Name: `my-lan-network`
   - Region: Same as your Pulse instance (e.g., SBG5)
   - VLAN ID: Leave empty or use your existing LAN VLAN
   - Add to vRack: Select your vRack
   - Configure DHCP according to your LAN setup

3. **Create Monitoring Network**
   - Click "Create Private Network"
   - Name: `proxmox-monitoring`
   - Region: Same as your Pulse instance (e.g., SBG5)
   - **VLAN ID: 100** (IMPORTANT!)
   - Add to vRack: Select your vRack
   - Configure DHCP:
     - Enable DHCP: Yes
     - Subnet: `10.200.10.0/24`
     - DHCP Start: `10.200.10.100`
     - DHCP End: `10.200.10.200`
     - Gateway: `10.200.10.1`
     - DNS Servers: Your internal DNS (e.g., `10.200.10.1`)

4. **Verify Networks**
   - Both networks should appear in the Private Networks list
   - Both should be attached to your vRack
   - DHCP should be configured for the monitoring network
   - Note the **exact network names** to use in `terraform.tfvars`

5. **Ensure Proxmox Nodes are Connected**
   - Your Proxmox nodes should already be on VLAN 100
   - Static IPs: 10.200.10.10 to 10.200.10.13
   - They should be reachable from the vRack network

## Architecture

```
Internet
   |
   v
[OVH Public Cloud - Pulse Instance]
   |
   |-- Public IP (Ext-Net) - SSH access only
   |
   +-- vRack Network 1 (192.168.32.0/19)
   |   |-- Access Pulse GUI from your LAN
   |   |-- Pulse gets IP via DHCP
   |
   +-- vRack Network 2 (10.200.10.0/24 VLAN 100)
       |-- Monitor Proxmox nodes (.10 to .13)
       |-- Pulse gets IP from DHCP pool (.100-.200)
       |-- Isolated monitoring network
       |-- Auto-discovers Proxmox on this network
```

### Multi-Network Support

Pulse can be connected to **multiple private networks** simultaneously:

1. **LAN Network** (192.168.32.0/19) - For accessing Pulse web interface
2. **Monitoring Network** (10.200.10.0/24 VLAN 100) - For Proxmox monitoring
   - Proxmox nodes: `10.200.10.10` to `10.200.10.13` (static IPs)
   - Pulse instance: `10.200.10.100+` (from DHCP pool)
3. Additional networks as needed (storage, backup, etc.)

### IP Address Schema Example

```
Monitoring Network (10.200.10.0/24 VLAN 100):
├── 10.200.10.1       - Gateway/Router
├── 10.200.10.10      - Proxmox Node 1
├── 10.200.10.11      - Proxmox Node 2
├── 10.200.10.12      - Proxmox Node 3
├── 10.200.10.13      - Proxmox Node 4
├── 10.200.10.14-99   - Reserved for future infrastructure
└── 10.200.10.100-200 - DHCP Pool (Pulse gets IP from here)

LAN Network (192.168.32.0/19):
└── Your existing LAN DHCP pool (Pulse gets IP via DHCP)
```

## Setup Instructions

### 1. Upload SSH Keys to OVH (if not already done)

Before deploying, upload your SSH public keys to OVH:

1. Go to: **OVH Manager → Public Cloud → Your Project → SSH Keys**
2. Click **"Add an SSH Key"**
3. Paste your public key content and give it a name (e.g., "my-work-key", "my-personal-key")
4. Repeat for each key you want to use
5. Note the **exact names** you gave to the keys

**Tip**: You can have multiple SSH keys for different purposes (work laptop, personal laptop, etc.)

### 2. Navigate to This Directory

```bash
cd terraform/pulse/ovh
```

### 3. Configure Terraform Variables

Copy the example file and edit with your values:

```bash
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

**Important Configuration Options:**

- `ovh_endpoint`: Your OVH region endpoint (ovh-eu, ovh-ca, ovh-us)
- `ovh_application_key`, `ovh_application_secret`, `ovh_consumer_key`: OVH API credentials
- `ovh_service_name`: Your **existing** OVH Public Cloud project ID
- `project_name`: Prefix for resources (e.g., "pulse" → "pulse-instance")
- `region`: OVH datacenter region (SBG5, GRA11, DE1, UK1, WAW1)
- `flavor`: Instance size (s1-2, s1-4, b2-7, etc.)
- `use_existing_ssh_keys`: Use existing SSH keys from OVH (recommended)
- `existing_ssh_key_names`: List of SSH key names already uploaded to OVH (supports multiple keys)
- `ssh_public_key_paths`: List of local SSH public key files (if not using existing OVH keys)
- `enable_vrack`: Set to `true` to connect via vRack private networks (REQUIRED)
- `private_networks`: List of private networks to attach (supports multiple networks with VLANs)
- `enable_pulse_web_public`: Enable public internet access (default: `false` - RECOMMENDED)
- `pulse_web_whitelist_ips`: List of specific IPs allowed public access (e.g., VPN exit IP)

**SSH Keys Configuration:**

```hcl
# Multiple SSH keys from OVH (RECOMMENDED)
use_existing_ssh_keys   = true
existing_ssh_key_names  = ["my-work-key", "my-personal-key"]

# The first key is assigned during instance creation
# Additional keys are automatically added to authorized_keys via cloud-init
```

**Alternative - Local SSH keys:**

```hcl
# Upload multiple SSH keys from local files
use_existing_ssh_keys = false
ssh_public_key_paths  = [
  "~/.ssh/id_rsa.pub",
  "~/.ssh/id_ed25519.pub"
]
```

**Example configuration with two networks (RECOMMENDED):**

```hcl
project_name = "pulse"
region       = "SBG5"
flavor       = "s1-2"

# Multiple SSH keys
use_existing_ssh_keys   = true
existing_ssh_key_names  = ["my-ovh-key-1", "my-ovh-key-2"]

# Enable vRack private networks
enable_vrack = true

# Multiple Private Networks Configuration
# Network 1: Your LAN for GUI access
# Network 2: Proxmox monitoring network with VLAN
private_networks = [
  {
    network_name = "my-lan-network"       # LAN for Pulse GUI access
    vlan_id      = null                   # No VLAN tag
    subnet       = "192.168.32.0/19"      # Your LAN subnet
    use_dhcp     = true                   # Use DHCP
    fixed_ip     = null
  },
  {
    network_name = "proxmox-monitoring"   # Proxmox monitoring network
    vlan_id      = 100                    # VLAN 100
    subnet       = "10.200.10.0/24"       # Monitoring subnet
    use_dhcp     = true
    fixed_ip     = null                   # Or: "10.200.10.50" for fixed IP
  },
]

# Security - SSH access ONLY from LAN network (192.168.32.0/19)
# SSH is automatically restricted to your private LAN for maximum security
# No public SSH access - you must be on the LAN to connect

# Pulse Web Access - ONLY via private network (most secure)
enable_pulse_web_public = false  # No public internet access

# DNS for Proxmox name resolution (should be on monitoring network)
dns_server1 = "10.200.10.1"         # DNS server on monitoring network
dns_domain  = "yourdomain.local"
dns_search  = "yourdomain.local"

# Reference list of Proxmox nodes (optional - Pulse auto-discovers)
proxmox_nodes_info = [
  "proxmox1.yourdomain.local",
  "proxmox2.yourdomain.local",
]
```

**Example with emergency VPN access:**

```hcl
# Enable public access ONLY from your VPN exit IP
enable_pulse_web_public = true
pulse_web_whitelist_ips = [
  "203.0.113.50",  # Your VPN exit IP
]
```

### 4. Initialize Terraform

```bash
terraform init
```

### 5. Review the Deployment Plan

```bash
terraform plan
```

### 6. Deploy the Infrastructure

```bash
terraform apply
```

Type `yes` when prompted to confirm the deployment.

### 7. Get the Connection Information

After deployment completes:

```bash
terraform output
```

Example output:
```
public_ip = "203.0.113.10"
ssh_connection = "ssh -i ~/.ssh/id_rsa debian@192.168.32.50"  # SSH only via LAN IP

private_networks = {
  "my-lan-network"               = "192.168.32.50"
  "proxmox-monitoring (VLAN 100)" = "10.200.10.25"
}

pulse_web_url_public = "http://203.0.113.10:7655"        # Only if whitelisted
pulse_web_url_lan = "http://192.168.32.50:7655"          # Access from LAN
pulse_web_url_monitoring = "http://10.200.10.25:7655"    # Access from monitoring net

all_networks = {
  "Ext-Net"            = "203.0.113.10"
  "my-lan-network"     = "192.168.32.50"
  "proxmox-monitoring" = "10.200.10.25"
}
```

### 8. Access Pulse Dashboard

**RECOMMENDED - Via LAN Network:**

From any device connected to your LAN (192.168.32.0/19):

```
http://192.168.32.50:7655
```

**Alternative - Via Monitoring Network:**

From the monitoring network (10.200.10.0/24):

```
http://10.200.10.25:7655
```

**Via Public Internet (only if whitelisted):**

If you enabled `enable_pulse_web_public = true` and added your IP to the whitelist:

```
http://<public_ip>:7655
```

**Via SSH Tunnel (most secure for remote access):**

```bash
ssh -L 7655:localhost:7655 -i ~/.ssh/id_rsa debian@<public_ip>
```

Then access locally: `http://localhost:7655`

## Initial Setup

### First Time Access

1. Navigate to `http://<your-ip>:7655`
2. Complete the initial setup wizard
3. Pulse will automatically discover Proxmox nodes on your network
4. You can also manually add nodes through the web interface

### Adding Proxmox Nodes

**Option 1: Auto-Discovery (Recommended)**
- Pulse will automatically find Proxmox nodes on your vRack network
- No manual configuration needed if nodes are reachable

**Option 2: Manual Configuration**
- Click "Add Node" in the Pulse web interface
- Enter node hostname/IP, credentials, and API token
- Configure monitoring settings per node

### Configuring Alerts

1. Go to Settings → Notifications
2. Configure your preferred alert channels:
   - Discord webhook
   - Slack webhook
   - Telegram bot
   - Email (SMTP)
   - Generic webhooks

## Management

### SSH Access

SSH is only accessible from your LAN network (192.168.32.0/19) for security:

```bash
# Connect using the LAN IP (you must be on the LAN network)
ssh -i ~/.ssh/id_rsa debian@<lan_ip>
```

**Note**: SSH is NOT accessible from the public internet. You must be connected to your LAN (192.168.32.0/19) to SSH into the instance. This is a security feature.

### Management Scripts

```bash
/opt/pulse/start.sh       # Start Pulse
/opt/pulse/stop.sh        # Stop Pulse
/opt/pulse/restart.sh     # Restart Pulse
/opt/pulse/logs.sh        # View logs
```

### Systemd Service

```bash
sudo systemctl start pulse      # Start
sudo systemctl stop pulse       # Stop
sudo systemctl restart pulse    # Restart
sudo systemctl status pulse     # Status
```

### Updating Pulse

```bash
cd /opt/pulse
docker compose pull
docker compose up -d
```

## Troubleshooting

### Check Logs

```bash
docker logs pulse
/opt/pulse/logs.sh
cat /var/log/cloud-init-output.log
```

### Test Network Connectivity

```bash
# Test DNS resolution
nslookup proxmox1.yourdomain.local

# Test Proxmox API
curl -k https://proxmox1.yourdomain.local:8006
```

### Pulse Not Discovering Nodes

1. Check network connectivity from Pulse to Proxmox nodes
2. Verify DNS resolution of Proxmox hostnames
3. Check firewall rules on Proxmox (allow port 8006)
4. Manually add nodes through the web interface
5. Verify vRack configuration

## Security Recommendations

### Network Security (CRITICAL)

1. **Private Network Access Only (RECOMMENDED)**
   ```hcl
   enable_pulse_web_public = false  # Default - no public internet access
   ```
   Access Pulse ONLY from your vRack private network: `http://<private_ip>:7655`

2. **Emergency/VPN Access (If needed)**
   ```hcl
   enable_pulse_web_public = true
   pulse_web_whitelist_ips = [
     "203.0.113.50",  # Your VPN exit IP ONLY
   ]
   ```
   Only specific IPs can access Pulse from the internet.

3. **SSH Tunnel for Remote Access (Most Secure)**
   ```bash
   ssh -L 7655:localhost:7655 debian@<lan_ip>
   ```
   Access via `http://localhost:7655` - no firewall rules needed!
   Note: SSH is only accessible from your LAN network (192.168.32.0/19)

### Additional Security

4. **SSH Access Restricted to LAN**
   - SSH is automatically configured to ONLY work from LAN (192.168.32.0/19)
   - No public SSH access - you must be on the LAN to connect
   - This significantly improves security by eliminating internet-facing SSH

5. **Use vRack** - REQUIRED for private network communication with Proxmox

6. **Regular Updates**
   ```bash
   cd /opt/pulse && docker compose pull && docker compose up -d
   sudo apt update && sudo apt upgrade -y
   ```

7. **Enable Authentication** - Configure OIDC/SSO in Pulse settings

### Security Levels

| Level | Configuration | Use Case |
|-------|---------------|----------|
| **Maximum** | `enable_pulse_web_public = false` + SSH tunnel | Production environments |
| **High** | `enable_pulse_web_public = false` + vRack only | Secure internal access |
| **Medium** | `enable_pulse_web_public = true` + VPN IP whitelist | Need emergency access |
| **Not Recommended** | Public access with wide CIDR | Testing only, never production |

## Destroying the Infrastructure

```bash
terraform destroy
```

**Warning**: This will delete the instance and all data!

## Support and Resources

- **Pulse GitHub**: https://github.com/rcourtman/Pulse
- **OVH Docs**: https://docs.ovh.com/gb/en/public-cloud/
- **Terraform OVH Provider**: https://registry.terraform.io/providers/ovh/ovh/latest/docs

## License

This Terraform configuration is provided as-is for deploying Pulse on OVH Public Cloud.
Pulse itself is MIT licensed.
