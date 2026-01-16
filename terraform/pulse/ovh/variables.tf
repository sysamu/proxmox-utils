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
  description = "Prefix for naming Terraform-created resources (e.g., pulse-instance, pulse-secgroup)"
  type        = string
  default     = "pulse"
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

variable "use_existing_ssh_keys" {
  description = "Use existing SSH keys already uploaded to OVH (recommended)"
  type        = bool
  default     = true
}

variable "existing_ssh_key_names" {
  description = "List of existing SSH key names in OVH (if use_existing_ssh_keys is true)"
  type        = list(string)
  default     = []
}

variable "ssh_public_key_paths" {
  description = "List of paths to SSH public key files (only used if use_existing_ssh_keys is false)"
  type        = list(string)
  default     = ["~/.ssh/id_rsa.pub"]
}

variable "enable_pulse_web_public" {
  description = "Enable PUBLIC access to Pulse web interface (RECOMMENDED: false, access only via vRack)"
  type        = bool
  default     = false
}

variable "pulse_web_whitelist_ips" {
  description = "List of public IPs allowed to access Pulse web interface (e.g., your VPN exit IP). Only used if enable_pulse_web_public = true"
  type        = list(string)
  default     = []
}

variable "pulse_web_port" {
  description = "Port for Pulse web interface access"
  type        = number
  default     = 7655
}

variable "instance_tags" {
  description = "Tags to apply to the instance"
  type        = list(string)
  default     = ["pulse", "monitoring"]
}

# vRack Configuration
variable "vrack_id" {
  description = "vRack ID (e.g., pn-xxxxx) - Optional, only needed if you want to manage vRack via Terraform"
  type        = string
  default     = ""
}

variable "enable_vrack" {
  description = "Enable vRack private network connections"
  type        = bool
  default     = true
}

# Private Networks Configuration
# Supports multiple private networks with different VLANs
variable "private_networks" {
  description = "List of private networks to attach to the instance"
  type = list(object({
    network_name = string           # Name of the vRack network in OVH
    vlan_id      = optional(number) # VLAN tag (e.g., 200)
    subnet       = optional(string) # Subnet CIDR (e.g., "10.200.10.0/24")
    use_dhcp     = optional(bool)   # Use DHCP (default: true)
    fixed_ip     = optional(string) # Fixed IP address (if not using DHCP)
  }))
  default = []
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

# Proxmox Configuration (for reference in .env file)
# Pulse will auto-discover nodes or you can configure them through the web interface
variable "proxmox_nodes_info" {
  description = "List of Proxmox nodes for reference (hostname/IP only, configured in Pulse web UI)"
  type        = list(string)
  default     = []
}
