# ==============================================================================
# Ansible SSH key — GENERATED + OWNED here (opconnect = secrets root)
# ==============================================================================
# opconnect applies BEFORE compute, so it is the right place to own the Ansible
# SSH keypair: it generates the key and writes both halves to the
# "Infrastructure Ansible SSH Key" 1Password secure_note. tofu/compute and the
# ansible ssh-key-loader role READ it (data source / op); this state OWNS it.
#
# WHY a resource (not a data source): the greenfield redesign briefly moved this
# to a read-only data source on the assumption that the bootstrap FusionCloudX
# repo seeds it — but bootstrap phase 05-ssh-key-bootstrap is an unimplemented
# 0-byte stub (commented out in bootstrap.sh), so NOTHING seeded it. The legacy
# terraform tree was the sole creator. We restore IaC ownership here.
#
# WHY private-key-in-state is acceptable: this state is S3 + SSE-KMS + OpenTofu
# native aes_gcm encryption (enforced) — the same posture under which the
# generated DB passwords in tofu/compute/secrets.tf already live. Write-only /
# ephemeral was deliberately NOT used (YAGNI: it dodges a risk already accepted
# one file over, at the cost of ephemeral regeneration fragility).
# ==============================================================================

resource "tls_private_key" "ansible" {
  algorithm = "ED25519"
}

resource "onepassword_item" "ansible_ssh_key" {
  vault    = var.onepassword_vault_id
  category = "secure_note"
  title    = var.ansible_ssh_key_item_title
  tags     = ["opentofu", "ansible", "ssh", "infrastructure"]

  # STATIC provenance (footgun #8: NO timestamp() — keep apply a no-op).
  note_value = <<-EOT
    Ansible SSH keypair — generated + owned by OpenTofu (tofu/opconnect/ssh-keys.tf).
    Public key is auto-deployed to VMs/LXC via cloud-init; the private key is read
    at runtime by the ansible ssh-key-loader role. Do not edit by hand.
  EOT

  # Read by the ssh-key-loader role:
  #   op://<vault>/Infrastructure Ansible SSH Key/Private Key/private_key
  section {
    label = "Private Key"

    field {
      label = "private_key"
      type  = "CONCEALED"
      value = tls_private_key.ansible.private_key_openssh
    }

    field {
      label = "key_type"
      type  = "STRING"
      value = "ED25519"
    }
  }

  # Read by tofu/compute + tofu/opconnect (field label "public_key") for cloud-init.
  section {
    label = "Public Key"

    field {
      label = "public_key"
      type  = "STRING"
      value = tls_private_key.ansible.public_key_openssh
    }

    field {
      label = "public_key_fingerprint_sha256"
      type  = "STRING"
      value = tls_private_key.ansible.public_key_fingerprint_sha256
    }
  }
}

locals {
  # This state OWNS the key, so use the generated public key directly (reading a
  # data source for an item we create in the same apply would be a dependency cycle).
  ansible_ssh_public_key = trimspace(tls_private_key.ansible.public_key_openssh)
}
