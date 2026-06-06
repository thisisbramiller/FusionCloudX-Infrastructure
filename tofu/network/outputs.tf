output "homelab_network_id" {
  value       = data.unifi_network.homelab.id
  description = "Stable UniFi network id of the VLAN-40 'Home Lab' network. Consumed by the compute state via terraform_remote_state (stable id only, never live IPs)."
}

# ------------------------------------------------------------------------------
# Foundation templates — consumed by opconnect (P4) + compute (P5) via remote
# state. Cross-state clone-by-vm_id is safe because network/ applies first (P3)
# and physically creates these on the pve node before P4/P5 run.
# ------------------------------------------------------------------------------

output "ubuntu_template_vm_id" {
  value       = proxmox_virtual_environment_vm.ubuntu_template.vm_id
  description = "VMID (9001) of the ubuntu-template full-clone source. Passed to the proxmox-vm module's template_vm_id by opconnect + compute service calls."
}

output "debian_lxc_template_file_id" {
  value       = proxmox_virtual_environment_download_file.debian12_lxc_template.id
  description = "Proxmox file ID of the downloaded Debian 12 LXC vztmpl. Passed to the proxmox-lxc module's template_file_id by compute/postgresql."
}
