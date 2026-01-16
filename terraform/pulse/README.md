# Pulse - Proxmox Monitoring Deployment

This directory contains Terraform configurations for deploying Pulse monitoring instances across different cloud providers.

Pulse is designed to collect metrics, monitor performance, and provide insights into your Proxmox VE infrastructure.

## Key Features

- **Monitoring and Metrics Collection**: Track CPU, memory, disk, and network usage across your Proxmox cluster
- **Per-Node Network Configuration**: Each Proxmox node can have its own VLAN ID and internal network port
- **Multi-Provider Support**: Deploy on different cloud platforms (currently OVH, more providers coming)
- **Docker-Based**: Easy deployment and management with Docker Compose
- **API Access**: Optional REST API for programmatic access to metrics

## Difference from ProxLB

While ProxLB focuses on **load balancing** VMs across Proxmox nodes, Pulse focuses on **monitoring and observability**:

| Feature | ProxLB | Pulse |
|---------|--------|-------|
| Purpose | Load balancing & VM distribution | Monitoring & metrics collection |
| VLAN Support | Uniform network config | Per-node VLAN & port config |
| Main Function | Migrate VMs to balance load | Collect and report metrics |
| API | Resource management | Metrics & monitoring data |

## Available Providers

### [OVH Public Cloud](ovh/)

Deploy Pulse on OVH Public Cloud with vRack integration for secure private networking.

**Features:**
- vRack support for private network communication
- Per-node VLAN ID configuration (e.g., node1: VLAN 100, node2: VLAN 200)
- Per-node internal port configuration (e.g., vmbr1, vmbr2, vmbr3)
- Flexible instance sizing
- Automated cloud-init deployment

**[→ Get started with OVH deployment](ovh/)**

### Coming Soon

- **AWS** - Amazon Web Services deployment
- **Azure** - Microsoft Azure deployment
- **Hetzner Cloud** - Hetzner deployment
- **On-Premises** - Bare metal/VM deployment guide

## Network Configuration Flexibility

Pulse supports **multiple private networks** for different purposes:

### Multi-Network Setup Example (OVH)

```hcl
private_networks = [
  {
    network_name = "my-lan-network"       # LAN for GUI access
    vlan_id      = null                   # No VLAN tag
    subnet       = "192.168.32.0/19"      # Your LAN
    use_dhcp     = true
  },
  {
    network_name = "proxmox-monitoring"   # Isolated monitoring network
    vlan_id      = 100                    # VLAN tag
    subnet       = "10.200.10.0/24"       # Monitoring subnet
    use_dhcp     = true
  },
]
```

This architecture allows:
- **Separated networks**: GUI access on LAN, monitoring on isolated VLAN
- **Security**: Monitoring traffic isolated from general network
- **Flexibility**: Each network can have different VLAN tags and subnets
- **Auto-discovery**: Pulse discovers Proxmox nodes on monitoring network
- **Reserved IPs**: Infrastructure uses static IPs (.10-.99), services use DHCP pool (.100-.200)

## Quick Start

1. Choose your cloud provider (start with [OVH](ovh/))
2. Navigate to the provider directory
3. Follow the provider-specific README
4. Configure your Proxmox nodes with VLAN/port settings
5. Deploy with Terraform

## Architecture Overview

```
┌─────────────────────────────────┐
│   Cloud Provider (OVH/AWS/etc)  │
│                                 │
│  ┌───────────────────────────┐ │
│  │   Pulse Instance          │ │
│  │   - Docker Container      │ │
│  │   - Metrics Collector     │ │
│  │   - API Server (optional) │ │
│  └───────────┬───────────────┘ │
│              │                  │
└──────────────┼──────────────────┘
               │
          vRack/VPN
               │
    ┌──────────┴──────────┐
    │                     │
┌───▼───┐             ┌───▼───┐
│ PVE 1 │             │ PVE 2 │
│VLAN100│             │VLAN200│
│ vmbr1 │             │ vmbr2 │
└───────┘             └───────┘
```

## Requirements

- Terraform >= 1.0
- Access to a cloud provider account
- Proxmox VE cluster (version 7.0+)
- API tokens created in Proxmox
- Private network connectivity (vRack, VPN, etc.)

## Support

For provider-specific issues, see the README in each provider directory:
- [OVH Documentation](ovh/README.md)

For general Pulse configuration questions, check the configuration templates in each provider folder.

## License

This Terraform configuration is provided as-is for deploying Pulse monitoring on various cloud providers.
