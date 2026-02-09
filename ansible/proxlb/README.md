# ProxLB Ansible Deployment

Deploy ProxLB (Proxmox Load Balancer) to an existing server using Ansible.

## Prerequisites

- Ansible 2.10+
- Target server with Ubuntu/Debian
- SSH access to the target server
- Python 3 on the target server

### Install Ansible Collections

```bash
ansible-galaxy collection install community.docker
```

## Quick Start

1. **Create inventory file:**

```bash
cp inventory.example.yml inventory.yml
```

Edit `inventory.yml` with your server details:

```yaml
all:
  hosts:
    proxlb_server:
      ansible_host: "192.168.1.100"
      ansible_user: "ubuntu"
      ansible_ssh_private_key_file: "~/.ssh/id_rsa"
```

2. **Configure variables:**

```bash
cp vars/main.example.yml vars/main.yml
```

Edit `vars/main.yml` with your Proxmox cluster details:

```yaml
proxmox_hosts:
  - "proxmox1.example.com"
  - "proxmox2.example.com"

proxmox_token_id: "proxlb"
proxmox_token_secret: "your-api-token-secret"
```

3. **Run the playbook:**

```bash
ansible-playbook -i inventory.yml deploy.yml
```

## Usage Examples

### Full deployment
```bash
ansible-playbook -i inventory.yml deploy.yml
```

### Update configuration only
```bash
ansible-playbook -i inventory.yml deploy.yml --tags "config"
```

### Force container restart
```bash
ansible-playbook -i inventory.yml deploy.yml -e "proxlb_restart=true"
```

### Force pull latest image
```bash
ansible-playbook -i inventory.yml deploy.yml -e "proxlb_force_pull=true"
```

### Dry run (check mode)
```bash
ansible-playbook -i inventory.yml deploy.yml --check
```

## Configuration Options

All configuration is done in `vars/main.yml`. Key options:

| Variable | Default | Description |
|----------|---------|-------------|
| `proxlb_image` | `gyptazy/proxlb:latest` | Docker image |
| `proxlb_base_dir` | `/opt/proxlb` | Installation directory |
| `proxlb_timezone` | `Europe/Madrid` | Container timezone |
| `balancing_method` | `memory` | Balancing method (memory/cpu/disk) |
| `balancing_mode` | `used` | Resource mode (assigned/used/psi) |
| `balancing_enforce_affinity` | `true` | Enforce pool affinity/anti-affinity rules |
| `balancing_enforce_pinning` | `true` | Enforce plb_pin_* tags for VM pinning |
| `service_schedule_interval` | `12` | Check interval |
| `service_schedule_format` | `hours` | Interval format (hours/minutes) |

See `vars/main.example.yml` for all available options.

## Pool Affinity/Anti-Affinity Rules

ProxLB supports pool-based affinity rules to control VM placement.

### Setup in Proxmox

1. Create a pool: **Datacenter -> Pools -> Create**
2. Add VMs to the pool
3. Configure the pool in `vars/main.yml`

### Pool Types

| Type | Description | Use Case |
|------|-------------|----------|
| `affinity` | Keep VMs together on the same node | App + local cache |
| `anti-affinity` | Spread VMs across different nodes | HA pairs, replicas |

### Pinning VMs to Specific Nodes

ProxLB supports pinning VMs to specific nodes using Proxmox tags:

1. In Proxmox, add tag `plb_pin_<nodename>` to the VM
2. Example: `plb_pin_pve-node01` pins the VM to `pve-node01`

**Critical limitation:**
- **Pinning has absolute priority over `maintenance_nodes`** - pinned VMs will NOT be evacuated during maintenance mode
- This behavior occurs even with `balancing_enforce_pinning: false`
- For planned maintenance, you MUST manually remove pin tags first, then restore them after

**Why we don't recommend pinning for HA services:**

Pinning adds complexity and manual steps for maintenance:
- ❌ More manual work: Remove tags → maintenance → restore tags
- ❌ Error-prone: Easy to forget which VMs were pinned to which nodes
- ❌ No evacuation: VMs stay on node even in maintenance mode

**Better alternative:** Use Proxmox HA Node Affinity instead:
- ✅ VMs automatically return to preferred nodes after maintenance (failback)
- ✅ Only 1 click to disable/enable during maintenance
- ✅ Works seamlessly with ProxLB anti-affinity pools
- ✅ Simpler workflow (see "Planned Maintenance" section below)

### Recommended Strategy for HA Services

For critical services like HA firewalls that need to:
- Stay on specific nodes during normal operation
- Be separated across different nodes (HA)
- Failover automatically during crashes
- NOT move during normal ProxLB balancing operations

**⚠️ CRITICAL: ProxLB + HA Node Affinity = Migration Loop Risk**

When a VM is managed by both ProxLB pools/balancing AND Proxmox HA Node Affinity:

**Loop during automatic balancing:**
1. Cluster becomes unbalanced (node reaches 75% memory/CPU)
2. ProxLB moves VM to balance the cluster
3. HA Node Affinity migrates VM back to preferred node
4. ProxLB detects unbalance again and moves VM
5. **Infinite loop → max reallocations → max restarts → VM shutdown** 💥

**Loop during maintenance mode:**
1. ProxLB evacuates VM from maintenance node
2. HA Node Affinity migrates VM back to preferred node (failback)
3. ProxLB evacuates again
4. Loop continues indefinitely

**RECOMMENDED: Use `plb_ignore` tag**

For VMs with Proxmox HA Node Affinity configured:

1. **Add `plb_ignore` tag** to VMs in Proxmox UI
   - ProxLB will completely ignore these VMs
   - No risk of migration loops under any circumstance

2. **Configure Proxmox HA with Node Affinity**
   - VMs stay on preferred nodes
   - Automatic failover during node crashes
   - Automatic failback after node recovery

3. **Manual migration during planned maintenance**
   - Before node maintenance: migrate VMs manually from Proxmox UI (2 clicks)
   - After maintenance: HA Node Affinity returns VMs to preferred nodes automatically

**Why this is better:**
- ✅ Zero risk of migration loops
- ✅ Critical VMs never move during balancing
- ✅ Predictable behavior
- ✅ HA works perfectly for crashes
- ✅ Simple maintenance workflow

**Don't use:**
- ❌ `plb_pin_*` tags - prevent maintenance evacuation
- ❌ ProxLB pools for VMs with HA Node Affinity - risk of loops

### Example Configuration

```yaml
balancing_pools:
  # Database replicas - spread across nodes
  # Use this when VMs do NOT have Proxmox HA Node Affinity
  ha-databases:
    type: anti-affinity
    strict: true          # Never allow on same node

  # App + Cache - keep together
  webapp-stack:
    type: affinity
    strict: false
```

**For VMs with Proxmox HA Node Affinity (firewalls, domain controllers):**
- Do NOT add them to ProxLB pools
- Add `plb_ignore` tag in Proxmox UI instead
- See "Recommended Strategy for HA Services" above

## Maintenance Mode

To evacuate VMs from a node before maintenance:

1. Edit `vars/main.yml`:
```yaml
proxmox_maintenance_nodes: ["pve-node01"]
```

2. Apply the configuration:
```bash
ansible-playbook -i inventory.yml deploy.yml --tags "config"
```

3. ProxLB will migrate VMs off the node

4. After maintenance, remove from the list and re-apply

**Note:** VMs with `plb_pin_*` tags pointing to the maintenance node will NOT be evacuated automatically. You must remove the pin tag first or migrate manually.

## File Structure

```
ansible/proxlb/
├── deploy.yml                  # Main playbook
├── inventory.example.yml       # Example inventory
├── README.md                   # This file
├── templates/
│   ├── docker-compose.yml.j2   # Docker Compose template
│   └── proxlb.yaml.j2          # ProxLB config template
└── vars/
    └── main.example.yml        # Example variables (copy to main.yml)
```

## Post-Deployment

After deployment, ProxLB will be running at `/opt/proxlb`.

### Check container status
```bash
ssh user@server "docker ps | grep proxlb"
```

### View logs
```bash
ssh user@server "docker logs -f proxlb"
```

### Manual restart
```bash
ssh user@server "cd /opt/proxlb && docker compose restart"
```

## Planned Maintenance with VMs Using plb_ignore Tag

For VMs with `plb_ignore` tag (critical VMs managed by Proxmox HA with Node Affinity):

### Step-by-Step Maintenance Workflow

**Example scenario:** Maintaining `pve-node-a1` which hosts firewall VM 102 and VM 103 (both tagged `plb_ignore` with HA Node Affinity to `pve-node-a1`).

#### 1. Manually Migrate Critical VMs (Proxmox UI)

Navigate to each VM and migrate to another node:

**VM 102:**
1. Right-click VM → **Migrate**
2. Select target node (e.g., `pve-node-b1`)
3. Check **Online migration** if VM is running
4. Click **Migrate**

**VM 103:**
1. Repeat for each critical VM on the maintenance node

**Why:** VMs with `plb_ignore` are not managed by ProxLB, so you must migrate them manually.

#### 2. Perform Maintenance

Once all critical VMs are migrated:
- Update packages
- Reboot `pve-node-a1`
- Perform any necessary work

Verify the node is back online and healthy.

#### 3. Re-enable HA Node Affinity (Proxmox UI)

Navigate to: **Datacenter → HA → Affinity Rules**

For each VM's HA Node Affinity rule:
1. Click **Edit**
2. Ensure **Enable** is checked
3. Click **OK**

**Proxmox HA will automatically migrate VMs back to `pve-node-a1` (failback).**

![HA Node Affinity Configuration](docs/images/ha-node-affinity-disable.png)

### Quick Reference

```bash
# For VMs with plb_ignore tag:
# 1. Manually migrate VMs from Proxmox UI
# 2. Perform maintenance
# 3. HA Node Affinity handles automatic failback

# For other VMs (managed by ProxLB):
# Use maintenance_nodes to evacuate automatically
# Edit vars/main.yml:
proxmox_maintenance_nodes: ["pve-node-a1"]
service_schedule_interval: 10  # Optional: faster evacuation
service_schedule_format: "minutes"

# Then deploy:
ansible-playbook -i inventory.yml deploy.yml --tags config
```

### Summary: When to Use What

| VM Type | Management | Maintenance Approach |
|---------|-----------|---------------------|
| Critical VMs with HA Node Affinity (firewalls, DCs) | `plb_ignore` tag | Manual migration from Proxmox UI |
| Regular VMs with anti-affinity needs (databases) | ProxLB pools | ProxLB maintenance mode |
| Standard VMs | ProxLB balancing | ProxLB maintenance mode |

## References

- [ProxLB Documentation](https://github.com/gyptazy/ProxLB)
- [ProxLB Example Config](https://github.com/credativ/ProxLB/blob/main/config/proxlb_example.yaml)
- [Maintenance Mode Guide](MAINTENANCE.md) - Detailed guide for HA integration
