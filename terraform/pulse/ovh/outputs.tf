output "instance_id" {
  description = "ID of the Pulse instance"
  value       = openstack_compute_instance_v2.pulse.id
}

output "instance_name" {
  description = "Name of the Pulse instance"
  value       = openstack_compute_instance_v2.pulse.name
}

output "public_ip" {
  description = "Public IP address of the Pulse instance"
  value       = openstack_compute_instance_v2.pulse.access_ip_v4
}

output "ssh_connection" {
  description = "SSH connection string (via LAN network only)"
  value = var.enable_vrack && length(var.private_networks) > 0 ? "ssh -i ~/.ssh/id_rsa debian@${try(
    openstack_compute_instance_v2.pulse.network[1].fixed_ip_v4,
    "N/A"
  )} # SSH only works from LAN (${var.private_networks[0].subnet})" : "No private networks configured"
}

output "region" {
  description = "OVH region where instance was deployed"
  value       = var.region
}

output "flavor" {
  description = "Instance flavor used"
  value       = var.flavor
}

output "security_group_id" {
  description = "Security group ID"
  value       = openstack_networking_secgroup_v2.pulse_secgroup.id
}

output "private_networks" {
  description = "Private network IPs (vRack networks)"
  value = var.enable_vrack && length(var.private_networks) > 0 ? {
    for idx, net in var.private_networks :
    "${net.network_name}${net.vlan_id != null ? " (VLAN ${net.vlan_id})" : ""}" => try(
      openstack_compute_instance_v2.pulse.network[idx + 1].fixed_ip_v4,
      "N/A"
    )
  } : {}
}

output "all_networks" {
  description = "All network interfaces and IPs (including public)"
  value = {
    for idx, net in openstack_compute_instance_v2.pulse.network :
    net.name => net.fixed_ip_v4
  }
}

output "pulse_web_url_public" {
  description = "URL to access Pulse web interface (public IP - only if whitelisted)"
  value       = "http://${openstack_compute_instance_v2.pulse.access_ip_v4}:${var.pulse_web_port}"
}

output "pulse_web_url_lan" {
  description = "URL to access Pulse via LAN (first private network)"
  value = var.enable_vrack && length(var.private_networks) > 0 ? "http://${try(
    openstack_compute_instance_v2.pulse.network[1].fixed_ip_v4,
    "N/A"
  )}:${var.pulse_web_port}" : "No private networks configured"
}

output "pulse_web_url_monitoring" {
  description = "URL to access Pulse via monitoring network (second private network, if exists)"
  value = var.enable_vrack && length(var.private_networks) > 1 ? "http://${try(
    openstack_compute_instance_v2.pulse.network[2].fixed_ip_v4,
    "N/A"
  )}:${var.pulse_web_port}" : "No second private network configured"
}

output "pulse_bootstrap_token_command" {
  description = "Command to get the Pulse bootstrap token (run on the instance)"
  value       = "docker exec pulse cat /data/.bootstrap_token"
}

output "pulse_get_token_ssh" {
  description = "Full SSH command to retrieve bootstrap token from LAN"
  value = var.enable_vrack && length(var.private_networks) > 0 ? "ssh debian@${try(
    openstack_compute_instance_v2.pulse.network[1].fixed_ip_v4,
    "N/A"
  )} 'docker exec pulse cat /data/.bootstrap_token'" : "No private networks configured"
}
