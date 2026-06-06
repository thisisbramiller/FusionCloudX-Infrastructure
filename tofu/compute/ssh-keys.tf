# ==============================================================================
# Ansible SSH key — READ from 1Password (data source, NEVER a resource)
# ==============================================================================
# Footgun #1 (private keys in state): this is a DATA SOURCE, not a resource.
# The flat config GENERATED the key with tls_private_key and wrote BOTH halves
# into 1Password — which lands the private key in TF state. Here we only READ
# the public key; the private key never enters compute state.
#
# The ansible ssh-key-loader role fetches the PRIVATE key from 1Password Connect
# at runtime (not from TF). This item is a BOOTSTRAP-SEEDED credential: it MUST
# already exist in the vault before `compute` apply (P5 dependency note — the
# opconnect/secrets seam seeds it; it is not created by this state).
#
# The flat onepassword.tf stored the public key in a section labelled
# "Public Key" with a STRING field labelled "public_key". The 1Password data
# source also surfaces a top-level read-only `public_key` attribute for
# ssh_key-category items, but this item is a secure_note, so we pull the value
# out of the section/field block list by matching the field label.
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
