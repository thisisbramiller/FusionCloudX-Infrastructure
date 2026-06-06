# ==============================================================================
# Ansible inventory (cloud.terraform.terraform_provider)
# ==============================================================================
# Aggregates EVERY built compute host into one inventory. Groups ported from the
# flat ansible-inventory.tf. The cloud.terraform plugin reads these resources
# (project_path -> ../tofu/compute).
#
# STATIC for_each KEYS (P3 review fix): the for_each map's KEYS must be known at
# plan time. The keys here are gated ONLY by the STATIC var.disabled_workloads
# (a plan-time-known input), never by computed IPs. The IP is carried as a
# (nullable) attribute VALUE, never a filter key — so a host whose guest-agent
# lease has not landed is STILL keyed into the map (with ansible_host = null),
# and `tofu plan` never fails on "for_each over computed values".
#
# Footgun #3 (truthy-string failure path): the failure path is NULL, not the
# truthy "IP not available" string the flat config used. ansible_host is either
# a real lease IP or null; null lets Jinja default() (the name-based .90
# role-default) engage. The value is never a truthy string.
#
# Count-guard aggregation: disposable services use count, so a disabled service
# is an EMPTY module list. one(module.<svc>[*].x) yields the single element when
# built and NULL when count=0 — no module.<svc>[0] index error. Disposables are
# merged in conditionally on the STATIC var.disabled_workloads, so a disabled
# service contributes NO map key at all (not a null-valued key).
# ==============================================================================

locals {
  # STATIC keys: gitlab + postgresql always present; disposables gated by the
  # static var.disabled_workloads (merge of conditional maps). Only the `ip`
  # VALUE is computed (nullable) — never a key, never a filter.
  inventory_hosts = merge(
    {
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
    },
    contains(var.disabled_workloads, "mealie") ? {} : { mealie = {
      ip    = one(module.mealie[*].ipv4_address)
      group = "application_servers"
      vm_id = one(module.mealie[*].vm_id)
      type  = "qemu"
    } },
    contains(var.disabled_workloads, "tandoor") ? {} : { tandoor = {
      ip    = one(module.tandoor[*].ipv4_address)
      group = "application_servers"
      vm_id = one(module.tandoor[*].vm_id)
      type  = "qemu"
    } },
    contains(var.disabled_workloads, "immich") ? {} : { immich = {
      ip    = one(module.immich[*].ipv4_address)
      group = "application_servers"
      vm_id = one(module.immich[*].vm_id)
      type  = "qemu"
    } },
    contains(var.disabled_workloads, "runitup") ? {} : { runitup = {
      ip    = one(module.runitup[*].ipv4_address)
      group = "application_servers"
      vm_id = one(module.runitup[*].vm_id)
      type  = "qemu"
    } },
  )
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
# Hosts — one ansible_host per BUILT compute host (static for_each keys)
# ------------------------------------------------------------------------------
# for_each keys are STATIC (gitlab/postgresql always, disposables gated by the
# plan-time var.disabled_workloads). ansible_host is the nullable IP VALUE — a
# host with no lease yet keys in with ansible_host = null (NULL failure path),
# letting Jinja default() engage. The IP is never a key or a filter.

resource "ansible_host" "compute" {
  for_each = local.inventory_hosts

  name   = each.key
  groups = [each.value.group]

  variables = {
    ansible_host = each.value.ip
    vm_id        = each.value.vm_id
    type         = each.value.type
  }
}
