# ==============================================================================
# Tandoor — disposable app (VM 1302, Scheme B)
# ==============================================================================
# DISPOSABLE: gated on var.disabled_workloads (see mealie.tf for the pattern).
# Module outputs referenced as module.tandoor[0].x.
# ==============================================================================

module "tandoor" {
  source = "../../modules/proxmox-vm"
  count  = contains(var.disabled_workloads, "tandoor") ? 0 : 1

  vm_id        = 1302
  name         = "tandoor"
  cores        = 2
  memory_mb    = 2048
  datastore_id = "local-zfs"
  tags         = ["opentofu", "ubuntu", "tandoor"]

  user_data_file_id   = module.tandoor_cloud_init[0].user_data_file_id
  vendor_data_file_id = module.tandoor_cloud_init[0].vendor_data_file_id
}

module "tandoor_cloud_init" {
  source = "../../modules/cloud-init"
  count  = contains(var.disabled_workloads, "tandoor") ? 0 : 1

  name           = "tandoor"
  ansible_pubkey = local.ansible_ssh_public_key
}

module "tandoor_dns" {
  source = "../../modules/unifi-host"
  count  = contains(var.disabled_workloads, "tandoor") ? 0 : 1

  name       = "tandoor"
  mac        = module.tandoor[0].mac_address
  ip         = module.tandoor[0].ipv4_address
  network_id = null
}
