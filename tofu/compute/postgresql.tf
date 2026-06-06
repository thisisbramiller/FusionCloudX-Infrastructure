# ==============================================================================
# PostgreSQL — core-infra singleton LXC (VM 2101, Scheme B)
# ==============================================================================
# PROTECTED SINGLETON: always built (NO count guard, NOT in disabled_workloads).
# One unprivileged Debian LXC hosting MULTIPLE databases; PostgreSQL itself is
# installed/configured by Ansible (the module only builds the substrate).
#
# prevent_destroy SEATBELT: applied automatically — the proxmox-lxc module is
# only ever consumed by this protected singleton, so its container resource
# carries an unconditional lifecycle.prevent_destroy = true literal. No call-site
# flag needed.
# ==============================================================================

module "postgresql" {
  source = "../../modules/proxmox-lxc"

  vm_id        = 2101
  hostname     = "postgresql"
  cores        = 2
  memory_mb    = 4096
  disk_gb      = 64
  datastore_id = "local-zfs"

  template_file_id = proxmox_virtual_environment_download_file.debian12_lxc_template.id
  ssh_pubkey       = local.ansible_ssh_public_key

  tags = ["database", "postgresql", "homelab"]
}

# Per-host UniFi DHCP reservation + A record. MAC/IP passed explicitly from the
# LXC module. network_id = null — the proven dns path OMITS it.
module "postgresql_dns" {
  source = "../../modules/unifi-host"

  name       = "postgresql"
  mac        = module.postgresql.mac_address
  ip         = module.postgresql.ipv4
  network_id = null
}
