# OVH vRack Network Setup Guide for Pulse

This guide explains how to configure the private networks in OVH **before** deploying Pulse with Terraform.

## Overview

Pulse requires **two private networks** in your OVH vRack:

1. **LAN Network** (192.168.32.0/19) - For accessing Pulse web interface
2. **Monitoring Network** (10.200.10.0/24 VLAN 100) - For Proxmox monitoring

## Network Configuration Details

### Network 1: LAN Network

This is your existing LAN network for accessing the Pulse web interface.

| Parameter | Value |
|-----------|-------|
| **Name** | `my-lan-network` |
| **Subnet** | `192.168.32.0/19` |
| **VLAN ID** | None (or your existing VLAN) |
| **Purpose** | Access Pulse GUI from your workstations |
| **DHCP** | According to your existing LAN setup |

### Network 2: Monitoring Network

This is a **dedicated isolated network** for Proxmox monitoring with VLAN tag 100.

| Parameter | Value |
|-----------|-------|
| **Name** | `proxmox-monitoring` |
| **Subnet** | `10.200.10.0/24` |
| **VLAN ID** | **100** |
| **Gateway** | `10.200.10.1` |
| **DNS** | `10.200.10.1` (or your DNS server) |
| **DHCP Pool** | `10.200.10.100 - 10.200.10.200` |
| **Reserved IPs** | `10.200.10.1 - 10.200.10.99` |
| **Purpose** | Isolated Proxmox monitoring traffic |

#### IP Address Allocation Plan

```
10.200.10.0/24 (VLAN 100 - Monitoring Network)

Gateway & Infrastructure:
├── 10.200.10.1       - Gateway/Router
├── 10.200.10.2-9     - Reserved for network services (DNS, NTP, etc.)

Proxmox Nodes (Static IPs):
├── 10.200.10.10      - Proxmox Node 1
├── 10.200.10.11      - Proxmox Node 2
├── 10.200.10.12      - Proxmox Node 3
├── 10.200.10.13      - Proxmox Node 4
├── 10.200.10.14-99   - Reserved for future Proxmox nodes or services

DHCP Pool (Dynamic allocation):
└── 10.200.10.100-200 - For Pulse instance and other monitoring tools
```

## Step-by-Step Setup in OVH Manager

### Step 1: Access Private Networks

1. Log into OVH Manager
2. Navigate to: **Public Cloud** → Select your project
3. Go to: **Network** → **Private Networks**

### Step 2: Create LAN Network (if doesn't exist)

1. Click **"Create Private Network"** or **"Add Private Network"**
2. Fill in the details:
   - **Name**: `my-lan-network`
   - **Region**: Same as where you'll deploy Pulse (e.g., SBG5, GRA11, etc.)
   - **VLAN ID**: Leave empty or specify your existing LAN VLAN
   - **Add to vRack**: Select your vRack from the dropdown
3. Configure according to your existing LAN setup
4. Click **Create**

### Step 3: Create Monitoring Network

1. Click **"Create Private Network"** or **"Add Private Network"**
2. Fill in the details:
   - **Name**: `proxmox-monitoring`
   - **Region**: **Same region as LAN network** (important!)
   - **VLAN ID**: **100** (must be exactly 100 for your Proxmox setup)
   - **Add to vRack**: Select the same vRack
3. Configure DHCP:
   - **Enable DHCP**: ✅ Yes
   - **Network**: `10.200.10.0`
   - **Subnet Mask**: `255.255.255.0` (or `/24`)
   - **DHCP Range Start**: `10.200.10.100`
   - **DHCP Range End**: `10.200.10.200`
   - **Default Gateway**: `10.200.10.1`
   - **DNS Servers**:
     - Primary: `10.200.10.1` (or your DNS server)
     - Secondary: (optional)
4. Click **Create**

### Step 4: Verify Configuration

1. Go back to **Private Networks** list
2. You should see both networks:
   ```
   ✓ my-lan-network (192.168.32.0/19)
   ✓ proxmox-monitoring (10.200.10.0/24) [VLAN 100]
   ```
3. Both should show as **attached to your vRack**
4. Click on `proxmox-monitoring` to verify:
   - DHCP is enabled
   - DHCP pool is `10.200.10.100 - 10.200.10.200`
   - VLAN ID is `100`

### Step 5: Verify Proxmox Connectivity

Before deploying Pulse, ensure your Proxmox nodes are properly configured:

1. **Check Proxmox Network Config** on each node:
   ```bash
   # SSH into Proxmox node
   ip addr show
   # Should see interface with 10.200.10.10-13
   ```

2. **Test connectivity between Proxmox nodes**:
   ```bash
   # From Proxmox node 1
   ping 10.200.10.11
   ping 10.200.10.12
   ping 10.200.10.13
   ```

3. **Verify VLAN tag** on Proxmox (in `/etc/network/interfaces`):
   ```
   auto vmbr1.100
   iface vmbr1.100 inet static
       address 10.200.10.10/24
       gateway 10.200.10.1
   ```

## Troubleshooting

### DHCP Not Working

If Pulse doesn't get an IP from DHCP pool:

1. Check DHCP is enabled in OVH for `proxmox-monitoring`
2. Verify DHCP range: `10.200.10.100 - 10.200.10.200`
3. Ensure the network is attached to the same vRack as your project
4. Check if DHCP pool is exhausted (100 IPs should be plenty)

### Cannot Reach Proxmox Nodes

If Pulse cannot discover Proxmox nodes:

1. Verify VLAN 100 is configured on Proxmox nodes
2. Test ping from OVH instance to Proxmox IPs (after deployment)
3. Check firewall on Proxmox nodes (allow port 8006)
4. Verify DNS resolution for Proxmox hostnames

### Wrong Network Attached

If Pulse gets IP from wrong network:

1. Check network order in `terraform.tfvars` (order matters!)
2. Verify network names exactly match OVH configuration
3. Check that both networks are in the same region

### VLAN Tag Issues

If VLAN 100 traffic doesn't work:

1. Confirm VLAN 100 is created in OVH with proper subnet
2. Verify Proxmox switches/routers support VLAN 100
3. Check if VLAN 100 is properly trunked to Proxmox hosts
4. Test with simple ping between known-good VLAN 100 device

## Network Names Reference

When filling `terraform.tfvars`, use the **exact names** from OVH:

```hcl
private_networks = [
  {
    network_name = "my-lan-network"       # Must match OVH exactly!
    vlan_id      = null
    subnet       = "192.168.32.0/19"
    use_dhcp     = true
    fixed_ip     = null
  },
  {
    network_name = "proxmox-monitoring"   # Must match OVH exactly!
    vlan_id      = 100
    subnet       = "10.200.10.0/24"
    use_dhcp     = true
    fixed_ip     = null
  },
]
```

## Common OVH Manager Paths

- **Private Networks**: Public Cloud → Project → Network → Private Networks
- **vRack**: Public Cloud → Project → Network → vRack
- **DHCP Config**: Private Networks → Select Network → DHCP Configuration
- **Region Check**: Private Networks → Network Details → Region

## After Network Setup

Once both networks are created and configured:

1. ✅ Note the exact network names
2. ✅ Verify VLAN 100 is configured
3. ✅ Check DHCP pool is `10.200.10.100-200`
4. ✅ Proceed to [README.md](README.md) for Terraform deployment
5. ✅ Use the exact network names in your `terraform.tfvars`

## Security Notes

- The monitoring network (VLAN 100) is **isolated** from your LAN
- Only Pulse and Proxmox nodes should be on this network
- No direct internet access on monitoring network (security by design)
- All Proxmox management traffic stays on this isolated network
- Access Pulse GUI from LAN network, monitor Proxmox via dedicated network

## Next Steps

After completing this setup:
→ Continue with [README.md](README.md) for Terraform deployment
→ Configure `terraform.tfvars` with your network names
→ Run `terraform apply` to deploy Pulse
