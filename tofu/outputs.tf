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

# Rendered /opt/confab/.env. scripts/deploy.sh reads this (`tofu output -raw
# env_file`) and ships it to the VM each deploy, so tfvars stays the single
# source of truth instead of the live .env drifting from first-boot values.
output "env_file" {
  description = "Rendered contents of /opt/confab/.env, kept in sync by scripts/deploy.sh."
  value       = local.env_content
  sensitive   = true
}
