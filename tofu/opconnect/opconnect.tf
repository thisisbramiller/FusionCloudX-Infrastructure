# ==============================================================================
# opconnect — secrets-root platform singleton (VM 1101, Scheme B)
# ==============================================================================
# This VM RUNS 1Password Connect (connect-api + connect-sync) on Docker. It is
# the secrets root of the on-prem estate: every other state/role that reads
# 1Password via Connect depends on this host being up.
#
# PROTECTED SINGLETON: always built (NO count guard, NOT in any disabled set).
# protected = true selects the proxmox-vm module's "protected" resource variant
# (lifecycle.prevent_destroy = true, a literal) — destroying the secrets root by
# accident would dark-out Connect for the whole fleet, so the seatbelt is on.
#
# Docker + the Connect compose stack are NOT provisioned here — that is the P4
# ansible `opconnect` role. cloud-init only lays down the base image + the
# ansible user/key (Docker prereqs handled by the shared `docker` role at P4).
# ==============================================================================

module "opconnect" {
  source = "../../modules/proxmox-vm"

  vm_id        = 1101
  name         = "opconnect"
  cores        = var.opconnect_cores
  memory_mb    = var.opconnect_memory_mb
  datastore_id = "local-zfs"
  tags         = ["opentofu", "ubuntu", "opconnect"]
  protected    = true # secrets-root singleton — prevent_destroy seatbelt
  # on_boot: 1101 MUST auto-start after a Proxmox node reboot (it is the secrets
  # root — the fleet reads 1Password through Connect here). DR backups of this VM
  # must be snapshot-mode (vzdump default) — NEVER --mode stop, which would stop
  # the guest and dark-out Connect for every downstream apply/playbook.
  on_boot      = true

  # Foundation ubuntu template (9001) lives in the network/ state (P3, applied first).
  template_vm_id = data.terraform_remote_state.network.outputs.ubuntu_template_vm_id

  user_data_file_id   = module.opconnect_cloud_init.user_data_file_id
  vendor_data_file_id = module.opconnect_cloud_init.vendor_data_file_id
}

module "opconnect_cloud_init" {
  source = "../../modules/cloud-init"

  name           = "opconnect"
  ansible_pubkey = local.ansible_ssh_public_key

  fqdn = "opconnect.fusioncloudx.home"

  # Docker CE + the Compose plugin are installed by the shared `docker` role
  # (an opconnect-role meta dependency) at P4 — NOT layered into cloud-init.
  # Base packages (qemu-guest-agent, net-tools, curl, python3, python3-pip) are
  # the cloud-init module default and are sufficient for Ansible to take over.
}

# Per-host UniFi DHCP reservation + A record. MAC/IP passed explicitly from the
# VM module (footgun #4: no [1]-index single-NIC assumption leaks into the
# unifi-host module). network_id = null — the proven dns path OMITS it.
# name = var.opconnect_dns_name: "opconnect" (canonical). The old snowflake Connect
# (VM 100, opconnect->.44) is destroyed and the namespace is open — 1101 owns it
# outright, so there is no collision and no temp-subdomain machinery.
module "opconnect_dns" {
  source = "../../modules/unifi-host"

  name       = var.opconnect_dns_name
  mac        = module.opconnect.mac_address
  ip         = module.opconnect.ipv4_address
  network_id = null
}

# ------------------------------------------------------------------------------
# Ansible targeting — group + host so the P4 opconnect role can reach this VM
# ------------------------------------------------------------------------------
# opconnect is ALWAYS built (protected singleton), so the ansible_host is
# UNCONDITIONAL — no count over a computed IP (that would make `tofu plan` fail
# on "count depends on computed values"). The IP is carried as a nullable
# attribute VALUE: ansible_host is the live lease IP or null. Footgun #3 (NULL
# failure path, never the truthy "IP not available" string) is satisfied by the
# nullable value — null lets Jinja default() engage; the value is never a
# truthy string.
# ------------------------------------------------------------------------------

resource "ansible_group" "opconnect" {
  name = "opconnect"
  variables = {
    ansible_user               = "ansible"
    ansible_python_interpreter = "/usr/bin/python3"
    ansible_ssh_common_args    = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  }
}

resource "ansible_host" "opconnect" {
  name   = "opconnect"
  groups = [ansible_group.opconnect.name]

  variables = {
    ansible_host = module.opconnect.ipv4_address # null until guest-agent lease
    vm_id        = module.opconnect.vm_id
    type         = "qemu"
  }
}
