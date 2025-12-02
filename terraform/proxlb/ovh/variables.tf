variable "ovh_endpoint" {
  description = "OVH API endpoint (ovh-eu, ovh-ca, ovh-us)"
  type        = string
  default     = "ovh-eu"
}

variable "ovh_application_key" {
  description = "OVH application key"
  type        = string
  sensitive   = true
}

variable "ovh_application_secret" {
  description = "OVH application secret"
  type        = string
  sensitive   = true
}

variable "ovh_consumer_key" {
  description = "OVH consumer key"
  type        = string
  sensitive   = true
}

variable "ovh_service_name" {
  description = "OVH Public Cloud project ID (UUID format, e.g., 1a2b3c4d5e6f7g8h) - Your EXISTING project ID from OVH API"
  type        = string
}

variable "openstack_auth_url" {
  description = "OpenStack authentication URL"
  type        = string
  default     = "https://auth.cloud.ovh.net/v3"
}

variable "openstack_user_name" {
  description = "OpenStack username"
  type        = string
  sensitive   = true
}

variable "openstack_password" {
  description = "OpenStack password"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "OVH region (e.g., GRA11, SBG5, DE1, UK1, WAW1)"
  type        = string
  default     = "SBG5"
}

variable "project_name" {
  description = "Prefix for naming Terraform-created resources (e.g., proxlb-instance, proxlb-secgroup)"
  type        = string
  default     = "proxlb"
}

variable "flavor" {
  description = "Instance flavor (e.g., s1-2, s1-4, b2-7)"
  type        = string
  default     = "s1-2"
}

variable "os_image_name" {
  description = "OS image name pattern"
  type        = string
  default     = "Debian 13"
}

variable "use_existing_ssh_key" {
  description = "Use an existing SSH key already uploaded to OVH (recommended)"
  type        = bool
  default     = true
}

variable "existing_ssh_key_name" {
  description = "Name of existing SSH key in OVH (if use_existing_ssh_key is true)"
  type        = string
  default     = ""
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file (only used if use_existing_ssh_key is false)"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH (recommended: your IP/32)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "allowed_api_cidr" {
  description = "CIDR block allowed to access ProxLB API"
  type        = string
  default     = "0.0.0.0/0"
}

variable "enable_proxlb_api" {
  description = "Enable ProxLB API port in security group"
  type        = bool
  default     = false
}

variable "instance_tags" {
  description = "Tags to apply to the instance"
  type        = list(string)
  default     = ["proxlb", "load-balancer"]
}

# vRack Configuration
variable "vrack_id" {
  description = "vRack ID (e.g., pn-xxxxx) - Optional, only needed if you want to manage vRack via Terraform"
  type        = string
  default     = ""
}

variable "vrack_network_name" {
  description = "Name of the vRack private network (must already exist in your OVH account and region)"
  type        = string
  default     = ""
}

variable "enable_vrack" {
  description = "Enable vRack private network connection"
  type        = bool
  default     = true
}

variable "vrack_dhcp" {
  description = "Use DHCP for vRack network (recommended)"
  type        = bool
  default     = true
}

# DNS Configuration
variable "dns_server1" {
  description = "Primary DNS server for internal name resolution"
  type        = string
  default     = "8.8.8.8"
}

variable "dns_server2" {
  description = "Secondary DNS server (leave empty if only using one DNS server)"
  type        = string
  default     = ""
}

variable "dns_domain" {
  description = "Internal DNS domain"
  type        = string
  default     = "yourdomain.local"
}

variable "dns_search" {
  description = "DNS search domain"
  type        = string
  default     = "yourdomain.local"
}

# Proxmox Configuration
variable "proxmox_user" {
  description = "Proxmox user (e.g., root@pam)"
  type        = string
  default     = "root@pam"
}

variable "proxmox_token_name" {
  description = "Proxmox API token name"
  type        = string
  default     = "proxlb"
}

variable "proxmox_nodes" {
  description = "List of Proxmox nodes with their hostnames and tokens"
  type = list(object({
    host  = string
    token = string
  }))
  default = []
}
