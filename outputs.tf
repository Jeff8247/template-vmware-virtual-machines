output "vm_names" {
  description = "Names of all deployed virtual machines"
  value       = { for k, v in module.vm : k => v.name }
}

output "vm_ids" {
  description = "Managed object IDs (MOIDs) of all deployed virtual machines"
  value       = { for k, v in module.vm : k => v.id }
}

output "default_ip_addresses" {
  description = "Default IP address of each VM as reported by VMware Tools"
  value       = { for k, v in module.vm : k => v.default_ip_address }
}

output "ip_addresses" {
  description = "All IP addresses reported by VMware Tools, per VM"
  value       = { for k, v in module.vm : k => v.guest_ip_addresses }
}

output "vm_uuids" {
  description = "BIOS UUIDs of all deployed virtual machines"
  value       = { for k, v in module.vm : k => v.uuid }
}

output "power_states" {
  description = "Current power state of each VM"
  value       = { for k, v in module.vm : k => v.power_state }
}
