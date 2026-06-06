# ==============================================================================
# Run It Up — disposable app (VM 1304, Scheme B)
# ==============================================================================
# DISPOSABLE: gated on var.disabled_workloads (see mealie.tf for the pattern).
# Runs a PRE-BUILT image (no on-VM build): 4GB = container runtime + NFS I/O
# headroom; 4 cores = general headroom (the image is built on the controller,
# not here). Profile matches the flat config.
# Module outputs referenced as module.runitup[0].x.
# ==============================================================================

module "runitup" {
  source = "../../modules/proxmox-vm"
  count  = contains(var.disabled_workloads, "runitup") ? 0 : 1

  vm_id        = 1304
  name         = "runitup"
  cores        = 4
  memory_mb    = 4096
  datastore_id = "local-zfs"
  tags         = ["opentofu", "ubuntu", "runitup"]

  user_data_file_id   = module.runitup_cloud_init[0].user_data_file_id
  vendor_data_file_id = module.runitup_cloud_init[0].vendor_data_file_id
}

module "runitup_cloud_init" {
  source = "../../modules/cloud-init"
  count  = contains(var.disabled_workloads, "runitup") ? 0 : 1

  name           = "runitup"
  ansible_pubkey = local.ansible_ssh_public_key
}

module "runitup_dns" {
  source = "../../modules/unifi-host"
  count  = contains(var.disabled_workloads, "runitup") ? 0 : 1

  name       = "runitup"
  mac        = module.runitup[0].mac_address
  ip         = module.runitup[0].ipv4_address
  network_id = null
}
