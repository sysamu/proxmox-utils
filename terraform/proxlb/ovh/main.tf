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

# Get existing SSH keypair if specified
data "openstack_compute_keypair_v2" "existing_key" {
  count = var.use_existing_ssh_key && var.existing_ssh_key_name != "" ? 1 : 0
  name  = var.existing_ssh_key_name
}

# Create new SSH keypair if not using existing one
resource "openstack_compute_keypair_v2" "proxlb_keypair" {
  count      = var.use_existing_ssh_key ? 0 : 1
  name       = "${var.project_name}-keypair"
  public_key = file(var.ssh_public_key_path)
}

# Create security group
resource "openstack_networking_secgroup_v2" "proxlb_secgroup" {
  name        = "${var.project_name}-secgroup"
  description = "Security group for ProxLB instance"
}

# Allow SSH
resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.allowed_ssh_cidr
  security_group_id = openstack_networking_secgroup_v2.proxlb_secgroup.id
}

# Allow HTTP
resource "openstack_networking_secgroup_rule_v2" "http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.proxlb_secgroup.id
}

# Allow HTTPS
resource "openstack_networking_secgroup_rule_v2" "https" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.proxlb_secgroup.id
}

# Allow ProxLB API port (if needed)
resource "openstack_networking_secgroup_rule_v2" "proxlb_api" {
  count             = var.enable_proxlb_api ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8000
  port_range_max    = 8000
  remote_ip_prefix  = var.allowed_api_cidr
  security_group_id = openstack_networking_secgroup_v2.proxlb_secgroup.id
}

# Get vRack private network if enabled
data "openstack_networking_network_v2" "vrack_network" {
  count = var.enable_vrack && var.vrack_network_name != "" ? 1 : 0
  name  = var.vrack_network_name
}

# Generate Proxmox nodes environment variables
locals {
  # Extract hostnames from URLs (remove https:// and :port)
  proxmox_hostnames = [
    for node in var.proxmox_nodes :
    replace(replace(node.host, "https://", ""), ":8006", "")
  ]

  proxmox_nodes_env = join("\n", [
    for idx, node in var.proxmox_nodes :
    "      PROXMOX_NODE${idx + 1}_HOST=${local.proxmox_hostnames[idx]}\n      PROXMOX_NODE${idx + 1}_TOKEN=${node.token}"
  ])
}

# Cloud-init configuration
data "template_file" "cloud_init" {
  template = file("${path.module}/cloud-init.yaml")
  vars = {
    docker_compose_config = base64encode(file("${path.module}/docker-compose.yml"))
    proxlb_config         = base64encode(file("${path.module}/proxlb.yaml.template"))
    dns_server1           = var.dns_server1
    dns_server2           = var.dns_server2
    dns_domain            = var.dns_domain
    dns_search            = var.dns_search
    proxmox_user          = var.proxmox_user
    proxmox_token_name    = var.proxmox_token_name
    proxmox_nodes_env     = local.proxmox_nodes_env
  }
}

# Create the ProxLB instance
resource "openstack_compute_instance_v2" "proxlb" {
  name            = "${var.project_name}-instance"
  flavor_name     = var.flavor
  image_id        = data.openstack_images_image_v2.os_image.id
  key_pair        = var.use_existing_ssh_key ? var.existing_ssh_key_name : openstack_compute_keypair_v2.proxlb_keypair[0].name
  security_groups = [openstack_networking_secgroup_v2.proxlb_secgroup.name]
  user_data       = data.template_file.cloud_init.rendered

  # Public network (Ext-Net)
  network {
    name = "Ext-Net"
  }

  # vRack private network (optional, for communication with Proxmox dedicated servers)
  dynamic "network" {
    for_each = var.enable_vrack && var.vrack_network_name != "" ? [1] : []
    content {
      name        = var.vrack_network_name
      fixed_ip_v4 = var.vrack_dhcp ? null : ""
    }
  }

  tags = var.instance_tags
}
