# ==============================================================================
# GitLab — platform singleton (VM 1201, Scheme B)
# ==============================================================================
# PROTECTED SINGLETON: always built (NO count guard, NOT in disabled_workloads).
#
# prevent_destroy SEATBELT: applied via protected = true below, which selects the
# proxmox-vm module's "protected" resource variant (lifecycle.prevent_destroy =
# true, a literal). The disposable apps (mealie/tandoor/immich/runitup) omit
# protected (default false) and get the destroyable variant — disabled_workloads
# toggle preserved.
# ==============================================================================

module "gitlab" {
  source = "../../modules/proxmox-vm"

  vm_id        = 1201
  name         = "gitlab"
  cores        = 8
  memory_mb    = 16384
  datastore_id = "local-zfs"
  tags         = ["opentofu", "ubuntu", "gitlab"]
  protected    = true # protected singleton — prevent_destroy seatbelt

  # Foundation ubuntu template (9001) lives in the network/ state (P3, applied first).
  template_vm_id = data.terraform_remote_state.network.outputs.ubuntu_template_vm_id

  user_data_file_id   = module.gitlab_cloud_init.user_data_file_id
  vendor_data_file_id = module.gitlab_cloud_init.vendor_data_file_id
}

module "gitlab_cloud_init" {
  source = "../../modules/cloud-init"

  name           = "gitlab"
  ansible_pubkey = local.ansible_ssh_public_key

  fqdn            = "gitlab.fusioncloudx.home"
  package_upgrade = true

  # GitLab prerequisites layered on the module base set
  # (qemu-guest-agent, net-tools, curl, python3, python3-pip).
  extra_packages = [
    "perl",
    "openssh-server",
    "postfix",
    "ufw",
    "ca-certificates",
    "tzdata",
  ]

  # Non-interactive postfix config (Internet Site, mailname = fqdn).
  debconf_selections = <<-EOT
    postfix postfix/main_mailer_type select 'Internet Site'
    postfix postfix/mailname string gitlab.fusioncloudx.home
  EOT
}

# Per-host UniFi DHCP reservation + A record. MAC/IP passed explicitly from the
# VM module (footgun #4: no [1]-index single-NIC assumption leaks into the
# unifi-host module). network_id = null — the proven dns path OMITS it.
module "gitlab_dns" {
  source = "../../modules/unifi-host"

  name       = "gitlab"
  mac        = module.gitlab.mac_address
  ip         = module.gitlab.ipv4_address
  network_id = null
}
