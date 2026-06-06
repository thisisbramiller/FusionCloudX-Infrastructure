# ==============================================================================
# Ansible inventory (cloud.terraform.terraform_provider)
# ==============================================================================
# Aggregates EVERY built compute host into one inventory. Groups ported from the
# flat ansible-inventory.tf. The cloud.terraform plugin reads these resources
# (project_path -> ../tofu/compute).
#
# Footgun #3 (truthy-string failure path): the flat config used
# try(<ip>, "IP not available") — a TRUTHY string that defeats Jinja's
# default(). Here the failure path is NULL: the host is built into the map only
# when its ip is non-null, so a host with no lease is OMITTED entirely (no
# ansible_host) and Jinja default() (the name-based .90 role-default) engages.
#
# Count-guard aggregation: disposable services use count, so a disabled service
# is an EMPTY module list. one(module.<svc>[*].x) yields the single element when
# built and NULL when count=0 — no module.<svc>[0] index error. local.app_hosts
# enumerates every disposable; the compact/for filter drops the count=0 (null)
# and the no-lease (null ip) entries before for_each.
# ==============================================================================

locals {
  # Protected singletons — always built.
  singleton_hosts = {
    gitlab = {
      ip    = module.gitlab.ipv4_address # null until guest-agent lease
      group = "application_servers"
      vm_id = module.gitlab.vm_id
      type  = "qemu"
    }
    postgresql = {
      ip    = module.postgresql.ipv4 # null until container leased
      group = "postgresql"
      vm_id = module.postgresql.vm_id
      type  = "lxc"
    }
  }

  # Disposable apps — one(module[*].x) = element when built, null when count=0.
  app_hosts = {
    mealie = {
      ip    = one(module.mealie[*].ipv4_address)
      group = "application_servers"
      vm_id = one(module.mealie[*].vm_id)
      type  = "qemu"
    }
    tandoor = {
      ip    = one(module.tandoor[*].ipv4_address)
      group = "application_servers"
      vm_id = one(module.tandoor[*].vm_id)
      type  = "qemu"
    }
    immich = {
      ip    = one(module.immich[*].ipv4_address)
      group = "application_servers"
      vm_id = one(module.immich[*].vm_id)
      type  = "qemu"
    }
    runitup = {
      ip    = one(module.runitup[*].ipv4_address)
      group = "application_servers"
      vm_id = one(module.runitup[*].vm_id)
      type  = "qemu"
    }
  }

  # Merge singletons + apps, then DROP any host that is not-built (vm_id null)
  # or has no lease yet (ip null). NULL failure path — not a truthy string.
  compute_hosts = {
    for name, h in merge(local.singleton_hosts, local.app_hosts) :
    name => h
    if h.vm_id != null && h.ip != null
  }
}

# ------------------------------------------------------------------------------
# Groups
# ------------------------------------------------------------------------------

resource "ansible_group" "postgresql" {
  name = "postgresql"
  variables = {
    ansible_user               = "root"
    ansible_python_interpreter = "/usr/bin/python3"
    ansible_ssh_common_args    = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  }
}

resource "ansible_group" "application_servers" {
  name = "application_servers"
  variables = {
    ansible_user               = "ansible"
    ansible_python_interpreter = "/usr/bin/python3"
    ansible_ssh_common_args    = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  }
}

resource "ansible_group" "monitoring" {
  name = "monitoring"
  variables = {
    ansible_user               = "ansible"
    ansible_python_interpreter = "/usr/bin/python3"
    ansible_ssh_common_args    = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  }
}

resource "ansible_group" "homelab" {
  name = "homelab"
  children = [
    ansible_group.postgresql.name,
    ansible_group.application_servers.name,
    ansible_group.monitoring.name,
  ]
  variables = {
    ansible_connection = "ssh"
  }
}

# ------------------------------------------------------------------------------
# Hosts — one ansible_host per BUILT, LEASED compute host
# ------------------------------------------------------------------------------

resource "ansible_host" "compute" {
  for_each = local.compute_hosts

  name   = each.key
  groups = [each.value.group]

  variables = {
    ansible_host = each.value.ip
    vm_id        = each.value.vm_id
    type         = each.value.type
  }
}
