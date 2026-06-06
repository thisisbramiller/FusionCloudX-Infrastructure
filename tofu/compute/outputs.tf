# ==============================================================================
# compute state — outputs
# ==============================================================================
# Failure paths are NULL (footgun #3), never the truthy "IP not available"
# string the flat config used. one(module.<svc>[*].x) yields null when a
# disposable is disabled (count=0); module.gitlab/postgresql are always built.
# ==============================================================================

# ------------------------------------------------------------------------------
# Infrastructure summary — built VMs + the postgresql LXC
# ------------------------------------------------------------------------------

output "infrastructure_summary" {
  description = "Compute deployment summary (built hosts only; disabled disposables omitted)."
  value = {
    vms = merge(
      {
        gitlab = {
          vm_id = module.gitlab.vm_id
          name  = module.gitlab.name
          ip    = module.gitlab.ipv4_address # null until guest-agent lease
        }
      },
      # Disposable apps: present only when built (count=1).
      { for name, m in {
        mealie  = module.mealie
        tandoor = module.tandoor
        immich  = module.immich
        runitup = module.runitup
        } : name => {
        vm_id = one(m[*].vm_id)
        name  = one(m[*].name)
        ip    = one(m[*].ipv4_address)
        } if length(m) > 0
      },
    )

    postgresql = {
      vm_id    = module.postgresql.vm_id
      hostname = module.postgresql.hostname
      ip       = module.postgresql.ipv4 # null until container leased
    }
  }
}

# ------------------------------------------------------------------------------
# Quick access — per-app URLs (null when not built / no lease)
# ------------------------------------------------------------------------------

output "gitlab_url" {
  description = "GitLab web interface URL (null until gitlab has a lease)."
  value       = try("http://${module.gitlab.ipv4_address}", null)
}

output "immich_url" {
  description = "Immich web interface URL (null when immich is disabled or unleased)."
  value       = try("https://${one(module.immich[*].ipv4_address)}:9926", null)
}

output "runitup_url" {
  description = "Run It Up web interface URL (null when runitup is disabled or unleased)."
  value       = try("https://${one(module.runitup[*].ipv4_address)}:9929", null)
}

# ------------------------------------------------------------------------------
# PostgreSQL connection
# ------------------------------------------------------------------------------

output "postgresql_connection" {
  description = "PostgreSQL connection details."
  value = {
    host     = module.postgresql.ipv4 # null until leased
    port     = 5432
    hostname = module.postgresql.hostname
  }
}

# ------------------------------------------------------------------------------
# 1Password credential references (surviving items only)
# ------------------------------------------------------------------------------

output "onepassword_items" {
  description = "1Password item IDs for credential retrieval (surviving items only)."
  value = {
    gitlab = {
      root_password = onepassword_item.gitlab_root_password.id
      runner_token  = onepassword_item.gitlab_runner_token.id
    }
    postgresql = {
      admin_password   = onepassword_item.postgresql_admin.id
      mealie_password  = onepassword_item.mealie_db_user.id
      tandoor_password = onepassword_item.tandoor_db_user.id
    }
    tandoor = {
      secret_key = onepassword_item.tandoor_secret_key.id
    }
    immich = {
      db_password = onepassword_item.immich_db_password.id
    }
  }
}

# ------------------------------------------------------------------------------
# Ansible SSH public key (READ from 1Password — see ssh-keys.tf)
# ------------------------------------------------------------------------------

output "ansible_ssh_public_key" {
  description = "Ansible SSH public key (read from the bootstrap-seeded 1Password item; private key never in state)."
  value       = local.ansible_ssh_public_key
}
