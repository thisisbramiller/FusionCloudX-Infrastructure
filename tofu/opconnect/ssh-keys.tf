# ==============================================================================
# Ansible SSH key — READ from 1Password (data source, NEVER a resource)
# ==============================================================================
# Footgun #1 (private keys in state): this is a DATA SOURCE, not a resource.
# We only READ the public key here; the private key never enters opconnect
# state. Read via the SA token (OP_SERVICE_ACCOUNT_TOKEN) — the secrets-root
# bootstrap auth path, NOT Connect (Connect does not exist yet at this layer).
#
# The ansible opconnect role authenticates to 1Password out-of-band at P4 (the
# SA token / op CLI is also what generates the Connect credentials + token). The
# Ansible SSH key item is a BOOTSTRAP-SEEDED credential: it MUST already exist
# in the vault before `opconnect` apply.
#
# The item stores the public key in a section field labelled "public_key"
# (secure_note category), so the top-level data-source `public_key` attribute
# (ssh_key-category only) does not populate — pull the value from the
# section/field block list by matching the field label. Mirrors tofu/compute.
# ==============================================================================

data "onepassword_item" "ansible_ssh_key" {
  vault = var.onepassword_vault_id
  title = var.ansible_ssh_key_item_title
}

locals {
  # Flatten every section's fields and select the "public_key" STRING field.
  # The item is a secure_note (the top-level data-source `public_key` attribute
  # only populates for ssh_key-category items), so read it from the section.
  _ansible_ssh_key_fields = flatten([
    for s in data.onepassword_item.ansible_ssh_key.section : [
      for f in s.field : f
    ]
  ])

  ansible_ssh_public_key = trimspace(one([
    for f in local._ansible_ssh_key_fields : f.value if f.label == "public_key"
  ]))
}
