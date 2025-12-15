# Proxmox Utils

A collection of utilities and scripts for Proxmox that automate and simplify common deployment and infrastructure tasks.

## Description

This repository contains a collection of tools, scripts, and configurations designed to save time in managing and administering Proxmox VE environments.

## Purpose

Provide reusable scripts that facilitate:
- Automated deployments
- Infrastructure configuration
- Maintenance tasks
- Resource optimization
- VM and container management

## Content

The repository includes scripts and tools for various Proxmox administration tasks, organized in a way that can be easily integrated into Infrastructure as Code (IaC) workflows.

## Scripts

### proxmox-drop-cache.sh

Interactive script to safely clear Proxmox system cache (pagecache, dentries, and inodes).

**Features:**
- Displays current cache size before cleanup
- Recommends whether cleanup is worthwhile (threshold: 256 MB)
- Interactive confirmation before proceeding
- Shows before/after comparison and freed memory
- Includes safety measures (sync before dropping cache)

**Usage:**
```bash
sudo ./scripts/proxmox-drop-cache.sh
```

**When to use:**
- When you need to free up memory occupied by cache
- Before performing memory-intensive operations
- To test actual memory usage without cache
- As part of maintenance routines

**Note:** Requires root privileges to modify `/proc/sys/vm/drop_caches`.

## Usage

Each script includes specific documentation about its use and purpose. Check the comments in each file for more details.

## Contributions

This is a personal utilities repository, but suggestions and improvements are welcome.

## License

Free-to-use scripts for Proxmox environments.
