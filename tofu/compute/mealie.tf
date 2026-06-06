# ==============================================================================
# Mealie — disposable app (VM 1301, Scheme B)
# ==============================================================================
# DISPOSABLE: gated on var.disabled_workloads. disabled_workloads=["mealie"]
# sets count=0 on these modules and destroys ONLY mealie (the protected
# singletons gitlab/postgresql are unaffected). Module outputs are referenced
# as module.mealie[0].x.
# ==============================================================================

module "mealie" {
  source = "../../modules/proxmox-vm"
  count  = contains(var.disabled_workloads, "mealie") ? 0 : 1

  vm_id        = 1301
  name         = "mealie"
  cores        = 2
  memory_mb    = 2048
  datastore_id = "local-zfs"
  tags         = ["opentofu", "ubuntu", "mealie"]

  user_data_file_id   = module.mealie_cloud_init[0].user_data_file_id
  vendor_data_file_id = module.mealie_cloud_init[0].vendor_data_file_id
}

module "mealie_cloud_init" {
  source = "../../modules/cloud-init"
  count  = contains(var.disabled_workloads, "mealie") ? 0 : 1

  name           = "mealie"
  ansible_pubkey = local.ansible_ssh_public_key
}

module "mealie_dns" {
  source = "../../modules/unifi-host"
  count  = contains(var.disabled_workloads, "mealie") ? 0 : 1

  name       = "mealie"
  mac        = module.mealie[0].mac_address
  ip         = module.mealie[0].ipv4_address
  network_id = null
}
