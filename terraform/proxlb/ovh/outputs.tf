output "instance_id" {
  description = "ID of the ProxLB instance"
  value       = openstack_compute_instance_v2.proxlb.id
}

output "instance_name" {
  description = "Name of the ProxLB instance"
  value       = openstack_compute_instance_v2.proxlb.name
}

output "public_ip" {
  description = "Public IP address of the ProxLB instance"
  value       = openstack_compute_instance_v2.proxlb.access_ip_v4
}

output "ssh_connection" {
  description = "SSH connection string"
  value       = "ssh -i ~/.ssh/id_rsa debian@${openstack_compute_instance_v2.proxlb.access_ip_v4}"
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
  value       = openstack_networking_secgroup_v2.proxlb_secgroup.id
}

output "private_ip" {
  description = "Private IP address (vRack) of the ProxLB instance"
  value       = var.enable_vrack && var.vrack_network_name != "" ? try(openstack_compute_instance_v2.proxlb.network[1].fixed_ip_v4, "N/A") : "vRack not enabled"
}

output "all_networks" {
  description = "All network interfaces and IPs"
  value = {
    for idx, net in openstack_compute_instance_v2.proxlb.network :
    net.name => net.fixed_ip_v4
  }
}
