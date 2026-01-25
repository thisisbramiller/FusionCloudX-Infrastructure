# ==============================================================================
# GitLab 1Password Items
# ==============================================================================
# Creates 1Password items for GitLab credentials
# ==============================================================================

# GitLab root user password
resource "onepassword_item" "gitlab_root_password" {
  vault    = var.onepassword_vault_id
  category = "login"
  title    = "GitLab Root User"
  tags     = ["terraform", "gitlab", "homelab"]

  username = "root"
  password_recipe {
    length  = 32
    symbols = true
  }
}

# GitLab runner registration token (for future CI/CD use)
resource "onepassword_item" "gitlab_runner_token" {
  vault    = var.onepassword_vault_id
  category = "password"
  title    = "GitLab Runner Registration Token"
  tags     = ["terraform", "gitlab", "homelab"]

  password_recipe {
    length  = 32
    symbols = false # Alphanumeric only for tokens
  }
}
