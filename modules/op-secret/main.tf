# Thin 1Password generated-password item. Extracted from the flat
# terraform/onepassword.tf password_recipe items. note_value is STATIC (no
# timestamp()) so apply stays a no-op — provenance, not a moving target.
resource "onepassword_item" "this" {
  vault      = var.vault
  title      = var.title
  category   = var.category
  note_value = var.note_value
  tags       = var.tags
  username   = var.username

  password_recipe {
    length  = var.length
    symbols = var.symbols
  }
}
