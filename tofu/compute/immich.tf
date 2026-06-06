# ==============================================================================
# Immich — disposable app (VM 1303, Scheme B)
# ==============================================================================
# DISPOSABLE: gated on var.disabled_workloads (see mealie.tf for the pattern).
# Heavier profile (8GB / 4 cores) for ML processing (face recognition, CLIP).
# datastore_id local-zfs (NVMe) for DB + Docker I/O; the photo library mounts
# UNAS NFS in-guest via Ansible (nfs_mount) — out of scope for this module.
# Module outputs referenced as module.immich[0].x.
# ==============================================================================

module "immich" {
  source = "../../modules/proxmox-vm"
  count  = contains(var.disabled_workloads, "immich") ? 0 : 1

  vm_id        = 1303
  name         = "immich"
  cores        = 4
  memory_mb    = 8192
  datastore_id = "local-zfs"
  tags         = ["opentofu", "ubuntu", "immich"]

  user_data_file_id   = module.immich_cloud_init[0].user_data_file_id
  vendor_data_file_id = module.immich_cloud_init[0].vendor_data_file_id
}

module "immich_cloud_init" {
  source = "../../modules/cloud-init"
  count  = contains(var.disabled_workloads, "immich") ? 0 : 1

  name           = "immich"
  ansible_pubkey = local.ansible_ssh_public_key
}

module "immich_dns" {
  source = "../../modules/unifi-host"
  count  = contains(var.disabled_workloads, "immich") ? 0 : 1

  name       = "immich"
  mac        = module.immich[0].mac_address
  ip         = module.immich[0].ipv4_address
  network_id = null
}
