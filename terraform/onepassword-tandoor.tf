# ==============================================================================
# Tandoor 1Password Items
# ==============================================================================
# Creates 1Password items for Tandoor credentials
# ==============================================================================

resource "onepassword_item" "tandoor_secret_key" {
  vault    = var.onepassword_vault_id
  category = "password"
  title    = "Tandoor Secret Key"
  tags     = ["terraform", "tandoor", "homelab"]

  password_recipe {
    length  = 50
    symbols = false # Django SECRET_KEY typically alphanumeric
  }
}
