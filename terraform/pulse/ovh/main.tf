terraform {
  required_version = ">= 1.0"
  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 0.50"
    }
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 2.1"
    }
  }
}

provider "ovh" {
  endpoint           = var.ovh_endpoint
  application_key    = var.ovh_application_key
  application_secret = var.ovh_application_secret
  consumer_key       = var.ovh_consumer_key
}

provider "openstack" {
  auth_url    = var.openstack_auth_url
  region      = var.region
  tenant_id   = var.ovh_service_name
  tenant_name = var.ovh_service_name
  user_name   = var.openstack_user_name
  password    = var.openstack_password
}

# Get the latest Ubuntu/Debian image
data "openstack_images_image_v2" "os_image" {
  most_recent = true
  name        = var.os_image_name
  visibility  = "public"
}

# Get existing SSH keypairs if specified
data "openstack_compute_keypair_v2" "existing_keys" {
  count = var.use_existing_ssh_keys && length(var.existing_ssh_key_names) > 0 ? length(var.existing_ssh_key_names) : 0
  name  = var.existing_ssh_key_names[count.index]
}

# Create new SSH keypairs if not using existing ones
resource "openstack_compute_keypair_v2" "pulse_keypairs" {
  count      = var.use_existing_ssh_keys ? 0 : length(var.ssh_public_key_paths)
  name       = "${var.project_name}-keypair-${count.index + 1}"
  public_key = file(var.ssh_public_key_paths[count.index])
}

# Create security group
resource "openstack_networking_secgroup_v2" "pulse_secgroup" {
  name        = "${var.project_name}-secgroup"
  description = "Security group for Pulse instance"
}

# Allow SSH only from LAN private network (192.168.32.0/19)
# This is much more secure than public SSH access
resource "openstack_networking_secgroup_rule_v2" "ssh_lan" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.enable_vrack && length(var.private_networks) > 0 ? var.private_networks[0].subnet : "192.168.32.0/19"
  security_group_id = openstack_networking_secgroup_v2.pulse_secgroup.id
}

# Allow HTTP
resource "openstack_networking_secgroup_rule_v2" "http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.pulse_secgroup.id
}

# Allow HTTPS
resource "openstack_networking_secgroup_rule_v2" "https" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.pulse_secgroup.id
}

# Allow Pulse web interface (7655) from all private networks (vRack)
# Creates one rule per configured private network
resource "openstack_networking_secgroup_rule_v2" "pulse_web_private" {
  for_each          = var.enable_vrack ? { for idx, net in var.private_networks : idx => net if net.subnet != null } : {}
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = var.pulse_web_port
  port_range_max    = var.pulse_web_port
  remote_ip_prefix  = each.value.subnet
  security_group_id = openstack_networking_secgroup_v2.pulse_secgroup.id
}

# Allow Pulse web interface from whitelisted IPs only (if public access enabled)
# By default, Pulse is only accessible via private vRack network
resource "openstack_networking_secgroup_rule_v2" "pulse_web_whitelist" {
  count             = var.enable_pulse_web_public && length(var.pulse_web_whitelist_ips) > 0 ? length(var.pulse_web_whitelist_ips) : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = var.pulse_web_port
  port_range_max    = var.pulse_web_port
  remote_ip_prefix  = "${var.pulse_web_whitelist_ips[count.index]}/32"
  security_group_id = openstack_networking_secgroup_v2.pulse_secgroup.id
}

# Get private networks data sources
data "openstack_networking_network_v2" "private_networks" {
  count = var.enable_vrack && length(var.private_networks) > 0 ? length(var.private_networks) : 0
  name  = var.private_networks[count.index].network_name
}

# Generate Proxmox nodes information (for reference only)
locals {
  proxmox_nodes_env = join("\n", [
    for idx, node in var.proxmox_nodes_info :
    "      # PROXMOX_NODE${idx + 1}=${node}"
  ])

  # Generate network information for documentation
  private_networks_info = join("\n", [
    for idx, net in var.private_networks :
    "      # NETWORK${idx + 1}: ${net.network_name} (${net.subnet != null ? net.subnet : "DHCP"}) ${net.vlan_id != null ? "VLAN ${net.vlan_id}" : ""}"
  ])

  # Get additional SSH public keys
  # For existing OVH keys: fetch the public key from data source (keys beyond the first one)
  # For local files: read from local paths (keys beyond the first one)
  additional_ssh_keys = var.use_existing_ssh_keys ? (
    length(var.existing_ssh_key_names) > 1 ? [
      for i in range(1, length(var.existing_ssh_key_names)) :
      data.openstack_compute_keypair_v2.existing_keys[i].public_key
    ] : []
  ) : (
    length(var.ssh_public_key_paths) > 1 ? [
      for i in range(1, length(var.ssh_public_key_paths)) :
      trimspace(file(var.ssh_public_key_paths[i]))
    ] : []
  )

  # Format SSH keys for cloud-init (one per line, without YAML list markers)
  ssh_authorized_keys = length(local.additional_ssh_keys) > 0 ? join("\n", local.additional_ssh_keys) : ""
}

# Cloud-init configuration
data "template_file" "cloud_init" {
  template = file("${path.module}/cloud-init.yaml")
  vars = {
    docker_compose_config = base64encode(file("${path.module}/docker-compose.yml"))
    dns_server1           = var.dns_server1
    dns_server2           = var.dns_server2
    dns_domain            = var.dns_domain
    dns_search            = var.dns_search
    proxmox_nodes_env     = local.proxmox_nodes_env
    additional_ssh_keys   = local.ssh_authorized_keys
  }
}

# Create the Pulse instance
resource "openstack_compute_instance_v2" "pulse" {
  name            = "${var.project_name}-instance"
  flavor_name     = var.flavor
  image_id        = data.openstack_images_image_v2.os_image.id
  key_pair        = var.use_existing_ssh_keys && length(var.existing_ssh_key_names) > 0 ? var.existing_ssh_key_names[0] : openstack_compute_keypair_v2.pulse_keypairs[0].name
  security_groups = [openstack_networking_secgroup_v2.pulse_secgroup.name]
  user_data       = data.template_file.cloud_init.rendered

  # Public network (Ext-Net)
  network {
    name = "Ext-Net"
  }

  # Private networks (vRack)
  # Supports multiple networks with different VLANs
  # Example: Network 1 (192.168.32.0/19) for GUI access
  #          Network 2 (10.200.10.0/24 VLAN 200) for Proxmox monitoring
  dynamic "network" {
    for_each = var.enable_vrack && length(var.private_networks) > 0 ? var.private_networks : []
    content {
      name        = network.value.network_name
      fixed_ip_v4 = network.value.use_dhcp != false ? null : network.value.fixed_ip
    }
  }

  tags = var.instance_tags
}
