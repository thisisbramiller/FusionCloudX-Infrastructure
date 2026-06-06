output "user_data_file_id" {
  value       = proxmox_virtual_environment_file.user_data.id
  description = "Proxmox file ID of the cloud-init user-data snippet."
}

output "vendor_data_file_id" {
  value       = proxmox_virtual_environment_file.vendor_data.id
  description = "Proxmox file ID of the cloud-init vendor-data snippet."
}
