# ==============================================================================
# Ansible SSH key — READ from 1Password (data source, NEVER a resource)
# ==============================================================================
# Footgun #1 (private keys in state): this is a DATA SOURCE, not a resource.
# We only READ the public key here; the private key never enters opconnect
# state. The onepassword provider AUTO-DETECTS auth from the environment (see
# providers.tf): the P4 cutover supplies the OLD Connect (OP_CONNECT_HOST +
# OP_CONNECT_TOKEN) for this one read; a from-scratch rebuild instead supplies
# OP_SERVICE_ACCOUNT_TOKEN or an operator `op signin`.
#
# The Connect server credentials + token are generated out-of-band at P4.1 via
# `op signin` + `op connect server/token create` (NOT by this state). The Ansible
# SSH key item is a BOOTSTRAP-SEEDED credential: it MUST already exist in the
# vault before `opconnect` apply.
#
# The item stores the public key in a section field labelled "public_key"
# (secure_note category), so the top-level data-source `public_key` attribute
# (ssh_key-category only) does not populate — pull the value from the
# section/field block list by matching the field label. Mirrors tofu/compute.
# ==============================================================================

data "onepassword_item" "ansible_ssh_key" {
  count = var.ansible_pubkey == "" ? 1 : 0
  vault = var.onepassword_vault_id
  title = var.ansible_ssh_key_item_title
}

locals {
  # Flatten every section's fields and select the "public_key" STRING field.
  # The item is a secure_note (the top-level data-source `public_key` attribute
  # only populates for ssh_key-category items), so read it from the section.
  # When ansible_pubkey is supplied directly (Connect-less rebuild), count=0 so
  # the data source is skipped entirely and we use the var value instead.
  _ansible_ssh_key_fields = var.ansible_pubkey == "" ? flatten([
    for s in data.onepassword_item.ansible_ssh_key[0].section : [
      for f in s.field : f
    ]
  ]) : []

  ansible_ssh_public_key = var.ansible_pubkey != "" ? trimspace(var.ansible_pubkey) : trimspace(one([
    for f in local._ansible_ssh_key_fields : f.value if f.label == "public_key"
  ]))
}
