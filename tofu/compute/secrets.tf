# ==============================================================================
# 1Password Items — surviving credentials (created fresh by compute)
# ==============================================================================
# Ported from the flat terraform/onepassword.tf, EXCLUDING the P1-removed items
# (NO wazuh/duplicati/backrest items) and EXCLUDING the ansible_ssh_key item
# (now a bootstrap-seeded credential READ via ssh-keys.tf, never written here —
# footgun #1: no private key in state).
#
# Ansible references these by item TITLE (not resource name). note_value is a
# STATIC provenance string (footgun #8: NO timestamp() — keep apply a no-op).
#
# The database-category items (postgresql_admin / mealie / tandoor) carry
# category=database + type=postgresql + hostname/port/database/username, which
# the op-secret module (password-only) cannot express — so they use
# onepassword_item directly. The plain password/login items COULD ride the
# op-secret module, but are kept as direct resources here for one consistent
# secrets file.
# ==============================================================================

locals {
  # Provenance stamp applied to every Tofu-managed 1Password item so anyone
  # browsing the vault sees what created it and that hand-edits are overwritten.
  op_managed_by = <<-EOT
    Managed by OpenTofu — thisisbramiller/FusionCloudX-Infrastructure (tofu/compute/secrets.tf).
    Do not edit by hand; manual changes are overwritten on `tofu apply`.
  EOT

  # The PostgreSQL LXC FQDN. Matches the proxmox-lxc hostname ("postgresql") +
  # the internal DNS zone. Hardcoded (no vm_configs var in the compute state).
  postgresql_fqdn = "postgresql.fusioncloudx.home"
}

# ------------------------------------------------------------------------------
# PostgreSQL Credentials (category=database / type=postgresql)
# ------------------------------------------------------------------------------

resource "onepassword_item" "postgresql_admin" {
  vault      = var.onepassword_vault_id
  category   = "database"
  title      = "PostgreSQL Admin (postgres)"
  note_value = local.op_managed_by
  tags       = ["opentofu", "postgresql", "homelab", "admin"]

  type     = "postgresql"
  hostname = local.postgresql_fqdn
  port     = "5432"
  database = "postgres"
  username = "postgres"

  password_recipe {
    length  = 32
    symbols = true
  }
}

resource "onepassword_item" "mealie_db_user" {
  vault      = var.onepassword_vault_id
  category   = "database"
  title      = "PostgreSQL - Mealie Database User"
  note_value = local.op_managed_by
  tags       = ["opentofu", "postgresql", "mealie", "homelab"]

  type     = "postgresql"
  hostname = local.postgresql_fqdn
  port     = "5432"
  database = "mealie"
  username = "mealie"

  password_recipe {
    length  = 32
    symbols = true
  }
}

resource "onepassword_item" "tandoor_db_user" {
  vault      = var.onepassword_vault_id
  category   = "database"
  title      = "PostgreSQL - Tandoor Database User"
  note_value = local.op_managed_by
  tags       = ["opentofu", "postgresql", "tandoor", "homelab"]

  type     = "postgresql"
  hostname = local.postgresql_fqdn
  port     = "5432"
  database = "tandoor"
  username = "tandoor"

  password_recipe {
    length  = 32
    symbols = true
  }
}

# ------------------------------------------------------------------------------
# GitLab Credentials
# ------------------------------------------------------------------------------

resource "onepassword_item" "gitlab_root_password" {
  vault      = var.onepassword_vault_id
  category   = "login"
  title      = "GitLab Root User"
  note_value = local.op_managed_by
  tags       = ["opentofu", "gitlab", "homelab"]

  username = "root"
  password_recipe {
    length  = 32
    symbols = true
  }
}

resource "onepassword_item" "gitlab_runner_token" {
  vault      = var.onepassword_vault_id
  category   = "password"
  title      = "GitLab Runner Registration Token"
  note_value = local.op_managed_by
  tags       = ["opentofu", "gitlab", "homelab"]

  password_recipe {
    length  = 32
    symbols = false # Alphanumeric only for tokens
  }
}

# ------------------------------------------------------------------------------
# Tandoor Application Secret
# ------------------------------------------------------------------------------

resource "onepassword_item" "tandoor_secret_key" {
  vault      = var.onepassword_vault_id
  category   = "password"
  title      = "Tandoor Secret Key"
  note_value = local.op_managed_by
  tags       = ["opentofu", "tandoor", "homelab"]

  password_recipe {
    length  = 50
    symbols = false # Django SECRET_KEY typically alphanumeric
  }
}

# ------------------------------------------------------------------------------
# Immich Credentials
# ------------------------------------------------------------------------------

resource "onepassword_item" "immich_db_password" {
  vault      = var.onepassword_vault_id
  category   = "password"
  title      = "Immich Database Password"
  note_value = local.op_managed_by
  tags       = ["opentofu", "immich", "homelab"]

  password_recipe {
    length  = 32
    symbols = false # Immich DB_PASSWORD must be alphanumeric
  }
}
