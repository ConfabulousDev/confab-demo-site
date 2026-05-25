output "vm_ip" {
  description = "Public IPv4 of the demo VM."
  value       = linode_instance.demo.ip_address
}

output "ssh_command" {
  description = "SSH into the VM as root (use this for initial admin / scrub work)."
  value       = "ssh root@${linode_instance.demo.ip_address}"
}

output "ssh_deploy_command" {
  description = "SSH into the VM as the deploy user (used by scripts/deploy.sh)."
  value       = "ssh deploy@${linode_instance.demo.ip_address}"
}
