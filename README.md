# Proxmox Utils

A collection of utilities and scripts for Proxmox that automate and simplify common deployment and infrastructure tasks.

## Description

This repository contains a collection of tools, scripts, and configurations designed to save time in managing and administering Proxmox VE environments. All scripts are production-ready and can be downloaded directly to your Proxmox nodes for immediate use.

## Purpose

Provide reusable scripts that facilitate:
- Automated deployments
- Infrastructure configuration
- Maintenance tasks
- Resource optimization
- VM and container management
- System backups and recovery

## Repository Structure

```
proxmox-utils/
├── scripts/           # Automation scripts for Proxmox administration
│   ├── backup_files_before_upgrade.sh
│   ├── proxmox-drop-cache.sh
│   ├── zfs-pool-r0.sh
│   ├── zfs-limit-arc.sh
│   ├── apache_optimizer.sh
│   ├── php_installer.sh
│   ├── nginx_installer.sh
│   └── README.md     # Detailed documentation for all scripts
│
└── terraform/        # Infrastructure as Code deployments
    └── proxlb-ovh-public-cloud/
        └── README.md # ProxLB deployment guide
```

## Quick Start

All scripts can be downloaded and executed directly from this repository:

```bash
# Download any script directly to your Proxmox node
wget https://raw.githubusercontent.com/sysamu/proxmox-utils/main/scripts/SCRIPT_NAME.sh
chmod +x SCRIPT_NAME.sh
sudo ./SCRIPT_NAME.sh
```

## Available Tools

### System Administration Scripts
- **Backup Tools** - Configuration backup before upgrades
- **Cache Management** - ZFS ARC and system cache optimization
- **Storage Configuration** - ZFS pool setup and management

### Web Server Tools
- **Apache Optimizer** - Auto-configuration for Apache + PHP-FPM
- **Nginx Installer** - Optimized Nginx setup for static content
- **PHP Installer** - Version-specific PHP installation with module management

### Infrastructure as Code
- **Terraform Deployments** - Complete ProxLB setup on OVH Public Cloud

## Documentation

For detailed documentation, usage examples, and installation instructions for each tool, please refer to:

- **[Scripts Documentation](scripts/README.md)** - Complete guide for all automation scripts
- **[Terraform Deployments](terraform/)** - Infrastructure as Code examples

## Usage

Each script includes:
- Specific documentation about its use and purpose
- Safety checks and confirmations
- Optimized defaults based on system resources
- Clear error messages and logging

## Safety Tips

1. Always backup important data before running storage configuration scripts
2. Review scripts before executing in production environments
3. Test in non-production environments when possible
4. Scripts include built-in safety checks and confirmations

## Contributions

This is a personal utilities repository, but suggestions and improvements are welcome.

## License

Free-to-use scripts for Proxmox environments.
