# ProxLB Deployment on OVH Public Cloud

Automated deployment of [ProxLB](https://github.com/gyptazy/ProxLB) load balancer for Proxmox clusters on OVH Public Cloud using Terraform.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- OVH Public Cloud account
- OVH API credentials
- SSH key pair
- Proxmox cluster (target for load balancing)
- Proxmox API tokens (see below for creation steps)

## Creating Proxmox API Tokens

Before deploying ProxLB, you need to create API tokens in Proxmox for authentication:

### 1. Create API Token User

```bash
# SSH to one of your Proxmox nodes
ssh root@proxmox1.yourdomain.local

# Create a dedicated user for ProxLB (recommended)
pveum user add proxlb@pam

# OR use root@pam (less secure but simpler)
```

### 2. Create API Token

In Proxmox Web UI:

1. Navigate to **Datacenter** → **Permissions** → **API Tokens**
2. Click **Add**
3. Configure:
   - **User**: `root@pam` (or `proxlb@pam` if you created dedicated user)
   - **Token ID**: `proxlb`
   - **Privilege Separation**: **Uncheck** (token needs same permissions as user)
4. Click **Add**
5. **Copy the token secret** (format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)
   - ⚠️ You can only see this once! Save it securely.

### 3. Set Permissions (if using dedicated user)

If you created a dedicated `proxlb@pam` user, grant necessary permissions:

```bash
# Grant PVEAuditor role for read access
pveum acl modify / -user proxlb@pam -role PVEAuditor

# Grant VM migration permissions
pveum acl modify / -user proxlb@pam -role PVEVMAdmin
```

### 4. Use in terraform.tfvars

```hcl
proxmox_user       = "root@pam"           # or "proxlb@pam"
proxmox_token_name = "proxlb"             # The Token ID
proxmox_nodes = [
  {
    host  = "https://proxmox1.yourdomain.local:8006"
    token = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # The token secret you copied
  },
  # ... more nodes with the same token if they're in the same cluster
]
```

**Note**: If all nodes are in the same Proxmox cluster, they can share the same API token.

## Getting OVH API Credentials

1. Go to [OVH API Token Creation](https://www.ovh.com/auth/api/createToken)
2. Log in with your OVH account
3. Fill in the form:
   - **Application name**: `terraform-proxlb`
   - **Application description**: `Terraform ProxLB deployment`
   - **Validity**: `Unlimited` or set an expiration date
   - **Rights**:
     - `GET /cloud/*`
     - `POST /cloud/*`
     - `PUT /cloud/*`
     - `DELETE /cloud/*`
4. Click **Create keys**
5. Save the **Application Key**, **Application Secret**, and **Consumer Key**

## Getting Your OVH Project ID

Your **Project ID** (also called `service_name`) is a UUID that identifies your existing OVH Public Cloud project.

### Option 1: Via OVH Control Panel
1. Go to [OVH Control Panel](https://www.ovh.com/manager/public-cloud/)
2. Select your Public Cloud project
3. Go to **Project Management** → **Project Settings**
4. Copy the **Project ID** (format: `1a2b3c4d5e6f7g8h...`)

### Option 2: Via OVH API
```bash
# List all your projects
curl -X GET "https://eu.api.ovh.com/1.0/cloud/project" \
  -H "X-Ovh-Application: YOUR_APP_KEY" \
  -H "X-Ovh-Consumer: YOUR_CONSUMER_KEY"

# Get project details
curl -X GET "https://eu.api.ovh.com/1.0/cloud/project/YOUR_PROJECT_ID" \
  -H "X-Ovh-Application: YOUR_APP_KEY" \
  -H "X-Ovh-Consumer: YOUR_CONSUMER_KEY"
```

**Important:** The `project_name` variable in Terraform is just a **naming prefix** for resources created (like `proxlb-instance`). It's NOT related to your OVH project name or description.

## Getting OpenStack Credentials

1. Go to [OVH Control Panel](https://www.ovh.com/manager/public-cloud/)
2. Select your Public Cloud project
3. Go to **Users & Roles** → **OpenStack users**
4. Create a new user or use existing credentials
5. Download the RC file or note the username and password

## SSH Key Configuration

### Using an Existing SSH Key (Recommended)

If you already have an SSH key uploaded to OVH:

1. Go to [OVH Control Panel](https://www.ovh.com/manager/public-cloud/)
2. Select your Public Cloud project
3. Go to **Project Management** → **SSH Keys**
4. Note the **exact name** of your SSH key
5. In `terraform.tfvars`, set:
   ```hcl
   use_existing_ssh_key  = true
   existing_ssh_key_name = "your-key-name"  # Exact name from OVH
   ```

**Benefits:**
- No need to upload the key again
- Key is already available in OVH
- Simpler configuration

### Creating a New SSH Key

If you want Terraform to upload a new SSH key:

1. Ensure you have an SSH key pair locally
2. In `terraform.tfvars`, set:
   ```hcl
   use_existing_ssh_key = false
   ssh_public_key_path  = "~/.ssh/id_rsa.pub"  # Path to your public key
   ```

**Note:** If you don't have an SSH key, create one:
```bash
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

## Setting Up vRack (Private Network)

vRack allows your ProxLB instance to communicate with Proxmox dedicated servers over a private network, avoiding public internet traffic.

### Prerequisites

**IMPORTANT**: This Terraform configuration assumes you already have:
1. ✅ An **existing vRack** service in OVH
2. ✅ Your **Public Cloud project** already attached to the vRack
3. ✅ Your **dedicated Proxmox servers** already attached to the vRack
4. ✅ A **private network** created in your Public Cloud project (in the same region you'll deploy to)

If you don't have these set up yet, follow the configuration steps below.

### Configuration Steps (if not already done)

1. **Get your vRack ID**:
   - Go to [OVH Control Panel](https://www.ovh.com/manager/)
   - Go to **Network** → **vRack**
   - Note your vRack ID (format: `pn-xxxxx`)

2. **Verify Services are Attached to vRack**:
   - In your vRack dashboard
   - Ensure your Public Cloud project is listed
   - Ensure your dedicated Proxmox servers are listed
   - If not, click "Add" and attach them

3. **Create Private Network in Public Cloud** (if not exists):
   - Go to **Public Cloud** → Your Project
   - Click **Private Network** → **Add Private Network**
   - Name: `my-vrack-network` (use this exact name in terraform.tfvars)
   - Select your region (e.g., SBG5) - **must match where you'll deploy ProxLB**
   - Enable DHCP and configure IP range (e.g., `10.0.0.0/24`)
   - Click **Create**

4. **Get Private Network Name**:
   - In **Public Cloud** → **Private Network**
   - Note the exact name of your private network
   - Use this name in `vrack_network_name` variable

5. **Verify Proxmox Servers Configuration**:
   - Ensure your Proxmox dedicated servers have network interfaces in the vRack
   - Verify they have IPs in the same subnet as your DHCP range (e.g., `10.0.0.10`, `10.0.0.11`)
   - Test connectivity between Proxmox nodes via private IPs

## ProxLB Balancing Configuration

This deployment uses an **optimized balancing configuration** for ProxLB:

### Key Features

- **Balancing Method**: Memory-based (monitors RAM usage across nodes)
- **Threshold**: 75% - triggers rebalancing when a node exceeds this memory usage
- **Balanciness**: 5 (moderate) - balances significant imbalances without being overly aggressive
  - Scale: 1 (conservative) to 10 (aggressive)
  - 5 is recommended for most production clusters
- **Live Migration**: Enabled - no VM downtime during rebalancing
- **Schedule**: Every 12 hours automatic check
- **Guest Types**: Both VMs and containers (LXC)
- **Local Disks**: Supports migration of VMs with local disks
- **Connection State**: Preserves network connection state during migration

### Advanced Features

- **Overprovisioning**: Allowed (can allocate more resources than physically available)
- **Maintenance Mode**: Can exclude specific nodes from receiving migrations
- **Pool-based Rules**: Support for affinity/anti-affinity rules (commented in template)

### Customization

To adjust balancing behavior, edit `proxlb.yaml.template` before deployment:

- **More aggressive balancing**: Increase `balanciness` to 7-10
- **More conservative**: Decrease `balanciness` to 1-3
- **Different method**: Change `method` to `cpu` for CPU-based balancing
- **Faster checks**: Reduce `interval` to 6 or 4 hours

All changes must be made before running `terraform apply`.

## Project Structure

```
terraform/proxlb/ovh/
├── main.tf                      # Main Terraform configuration
├── variables.tf                 # Variable definitions
├── outputs.tf                   # Output definitions
├── terraform.tfvars.example     # Example variables file (copy to terraform.tfvars)
├── docker-compose.yml           # ProxLB Docker Compose config
├── proxlb.yaml.template         # ProxLB configuration template (auto-generated)
├── cloud-init.yaml              # Cloud-init setup script
└── README.md                    # This file
```

## Quick Start

### 1. Clone and Navigate

```bash
cd terraform/proxlb/ovh
```

### 2. Configure Variables

Copy the example file and edit with your credentials:

```bash
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
```

**Important fields to configure:**

```hcl
# OVH API Credentials
ovh_application_key    = "your_application_key"
ovh_application_secret = "your_application_secret"
ovh_consumer_key       = "your_consumer_key"

# YOUR EXISTING PROJECT ID (UUID format)
# Get it from: OVH API /cloud/project or Control Panel → Project Settings
ovh_service_name = "1a2b3c4d5e6f7g8h9i0j"  # Your existing project ID

# OpenStack Credentials (for your existing project)
openstack_user_name = "your_openstack_username"
openstack_password  = "your_openstack_password"

# Resource Naming Prefix (not related to your OVH project name)
project_name = "proxlb"  # Prefix for resources: proxlb-instance, proxlb-secgroup, etc.

# Deployment Settings
region = "SBG5"  # Must match your vRack network region
flavor = "s1-2"  # Adjust based on your needs

# SSH Key Configuration (IMPORTANT)
# Option 1: Use existing SSH key from OVH (RECOMMENDED)
use_existing_ssh_key  = true
existing_ssh_key_name = "my-ovh-ssh-key"  # Name from OVH panel

# vRack Configuration (IMPORTANT for private network with Proxmox)
enable_vrack       = true
vrack_id           = ""                  # Optional: leave empty
vrack_network_name = "my-vrack-network"  # EXACT name of your existing private network
vrack_dhcp         = true
```

> **Critical Notes**:
> 1. **SSH Key**: If you already have an SSH key in OVH, use `use_existing_ssh_key = true` and specify the key name. Find it in: **Public Cloud** → **SSH Keys**
> 2. The `vrack_network_name` must **exactly match** the name of your private network in OVH Public Cloud
> 3. The private network must exist in the **same region** as your deployment (e.g., SBG5)
> 4. To find your network name: Go to **Public Cloud** → Your Project → **Private Network**
> 5. If you want to restrict public access and use only vRack for Proxmox communication:
>    - Set `allowed_ssh_cidr` to your admin IP only
>    - Configure ProxLB to use private IPs in `proxlb.yaml`
>    - Consider disabling HTTP/HTTPS rules in security group if not needed

### 3. Configure DNS and Proxmox Nodes

**Important**: All ProxLB configuration is managed through `terraform.tfvars`. You don't need to edit `proxlb.yaml` manually - it's generated automatically from the template.

Configure your Proxmox nodes and DNS settings in `terraform.tfvars`:

```hcl
# DNS Configuration (for internal Proxmox name resolution)
dns_server1 = "192.168.1.1"        # Your internal DNS server
dns_server2 = ""                   # Secondary DNS (leave empty if only using one)
dns_domain  = "yourdomain.local"   # Your internal domain
dns_search  = "yourdomain.local"   # DNS search domain

# Proxmox Cluster Configuration
# IMPORTANT: Create API tokens in Proxmox first: Datacenter → Permissions → API Tokens
proxmox_user       = "root@pam"
proxmox_token_name = "proxlb"

proxmox_nodes = [
  {
    host  = "https://proxmox1.yourdomain.local:8006"
    token = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # API token secret for node 1
  },
  {
    host  = "https://proxmox2.yourdomain.local:8006"
    token = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # API token secret for node 2
  },
  # Add more nodes as needed
]
```

**Key configuration details:**

The generated `proxlb.yaml` will include:
- **Proxmox API**: Token-based authentication (more secure than passwords)
- **Balancing method**: Memory-based with 75% threshold
- **Balanciness**: 5 (moderate - balances significant imbalances)
- **Live migration**: Enabled (no VM downtime)
- **Schedule**: Checks balance every 12 hours
- **Balance types**: Both VMs and containers

> **Security Best Practice**:
> - Use internal DNS for Proxmox name resolution
> - Use hostnames from your internal domain instead of IPs for easier management
> - API tokens are automatically configured from `terraform.tfvars`
> - All Proxmox API communication goes through the vRack private network

### 4. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy
terraform apply
```

### 5. Access Your Instance

After deployment, Terraform will output the connection details:

```bash
# Get all outputs including private IP
terraform output

# View specific outputs
terraform output public_ip       # Public IP for SSH access
terraform output private_ip      # Private IP (vRack) for Proxmox communication
terraform output all_networks    # All network interfaces

# Connect via SSH
terraform output -raw ssh_connection | sh
# or
ssh -i ~/.ssh/id_rsa ubuntu@<public_ip>
```

**Output Example:**
```
public_ip = "51.210.xxx.xxx"
private_ip = "10.0.0.50"
all_networks = {
  "Ext-Net" = "51.210.xxx.xxx"
  "my-vrack-network" = "10.0.0.50"
}
```

## Available Regions

OVH Public Cloud regions:

- `GRA11` - Gravelines, France
- `SBG5` - Strasbourg, France (recommended for EU)
- `DE1` - Frankfurt, Germany
- `UK1` - London, United Kingdom
- `WAW1` - Warsaw, Poland

## Available Flavors

Common instance flavors:

- `s1-2` - 1 vCore, 2GB RAM (minimum recommended)
- `s1-4` - 2 vCore, 4GB RAM
- `s1-8` - 4 vCore, 8GB RAM
- `b2-7` - 2 vCore, 7GB RAM
- `b2-15` - 4 vCore, 15GB RAM

## Managing ProxLB

### On the Instance

```bash
# View logs
/opt/proxlb/logs.sh
# or
docker logs -f proxlb

# Restart ProxLB
/opt/proxlb/restart.sh
# or
systemctl restart proxlb

# Stop ProxLB
/opt/proxlb/stop.sh
# or
systemctl stop proxlb

# Start ProxLB
/opt/proxlb/start.sh
# or
systemctl start proxlb

# Check status
systemctl status proxlb
docker ps
```

### Update Configuration

**Option 1: Update via Terraform (Recommended)**

To change ProxLB configuration (nodes, DNS, balancing settings):

1. Edit `terraform.tfvars` with your changes
2. Apply the changes:
   ```bash
   terraform apply
   ```
3. The instance will be recreated with the new configuration

**Option 2: Manual Edit on Instance**

For quick changes without recreating the instance:

1. SSH to the instance
2. Edit the environment file:
   ```bash
   sudo vim /opt/proxlb/.env
   ```
3. Regenerate configuration and restart:
   ```bash
   sudo /opt/proxlb/generate-config.sh
   sudo /opt/proxlb/restart.sh
   ```

**Note**: Manual changes will be lost if you run `terraform apply` again. For permanent changes, always update `terraform.tfvars`.

### Update ProxLB Image

```bash
cd /opt/proxlb
docker-compose pull
docker-compose up -d
```

## Security Recommendations

### Network Security with vRack

1. **Use vRack for Proxmox Communication**:
   - Configure ProxLB to connect to Proxmox nodes via **private IPs** (vRack)
   - This keeps all API communication off the public internet
   - Example in `proxlb.yaml`: `host: "https://10.0.0.10:8006"`

2. **Restrict Public Access**:
   ```hcl
   # In terraform.tfvars
   allowed_ssh_cidr = "203.0.113.0/32"  # Your IP only
   ```

3. **Verify Network Configuration**:
   ```bash
   # After deployment, SSH to instance and check interfaces
   ip addr show
   # You should see both public (Ext-Net) and private (vRack) interfaces

   # Test connectivity to Proxmox via private network
   ping 10.0.0.10  # Your Proxmox private IP
   curl -k https://10.0.0.10:8006/api2/json/version
   ```

### Application Security

4. **Use Proxmox API tokens**: Instead of passwords, use token authentication in `proxlb.yaml`

5. **Enable SSL verification**: Set `verify_ssl: true` in `proxlb.yaml` when using valid certificates

6. **Firewall**: The security group allows only SSH, HTTP, and HTTPS by default
   - HTTP/HTTPS rules can be removed if ProxLB doesn't need to be publicly accessible
   - ProxLB API port (8000) is disabled by default

### Proxmox Server Configuration

7. **Configure Proxmox Firewall**: On your dedicated servers, restrict API access to vRack subnet
   ```bash
   # On Proxmox server
   iptables -A INPUT -s 10.0.0.0/24 -p tcp --dport 8006 -j ACCEPT
   iptables -A INPUT -p tcp --dport 8006 -j DROP
   ```

## Troubleshooting

### Check cloud-init logs

```bash
ssh ubuntu@<public_ip>
sudo cat /var/log/cloud-init-output.log
sudo cat /var/log/cloud-init-complete.log
```

### Check Docker status

```bash
sudo systemctl status docker
docker ps -a
```

### Check ProxLB logs

```bash
docker logs proxlb
# or
cat /var/log/proxlb/proxlb.log
```

### Test Proxmox connectivity

```bash
# Test from the instance
ping 10.0.0.10  # Private IP of your Proxmox server
curl -k https://10.0.0.10:8006/api2/json/version

# Test from ProxLB container
docker exec -it proxlb sh
# Inside container
curl -k https://10.0.0.10:8006/api2/json/version
```

### vRack Network Issues

If ProxLB cannot reach Proxmox servers via vRack:

1. **Check network interfaces**:
   ```bash
   ip addr show
   # Look for the vRack interface (usually ens4 or eth1)
   ```

2. **Verify vRack network is attached**:
   ```bash
   # Check routing
   ip route show
   # You should see routes to 10.0.0.0/24 (or your vRack subnet)
   ```

3. **Test from Public Cloud console**:
   - Go to OVH Control Panel
   - Navigate to your instance
   - Check that both networks are attached (Ext-Net and your vRack network)

4. **Verify DHCP is working**:
   ```bash
   sudo dhclient -v  # Request DHCP lease
   ip addr show      # Check if vRack interface has an IP
   ```

5. **Check Proxmox server connectivity**:
   - Ensure Proxmox servers are in the same vRack
   - Test from Proxmox: `ping 10.0.0.50` (ProxLB private IP)

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

## Cost Estimation

Approximate monthly costs for OVH Public Cloud (as of 2025):

- `s1-2` (1 vCore, 2GB): ~€4-5/month
- `s1-4` (2 vCore, 4GB): ~€8-10/month
- `b2-7` (2 vCore, 7GB): ~€10-12/month

Plus bandwidth and snapshot costs if applicable.

## Additional Resources

- [ProxLB Documentation](https://github.com/gyptazy/ProxLB)
- [OVH Public Cloud Documentation](https://docs.ovh.com/gb/en/public-cloud/)
- [Terraform OVH Provider](https://registry.terraform.io/providers/ovh/ovh/latest/docs)
- [Proxmox API Documentation](https://pve.proxmox.com/wiki/Proxmox_VE_API)

## Support

For issues related to:
- **ProxLB**: https://github.com/gyptazy/ProxLB/issues
- **This deployment**: Create an issue in this repository
- **OVH Cloud**: https://help.ovhcloud.com/

## License

This deployment configuration is provided as-is for use with Proxmox environments.
