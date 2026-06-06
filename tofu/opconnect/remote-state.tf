# ==============================================================================
# Remote state — read the FOUNDATION network state (onprem/proxmox/network)
# ==============================================================================
# opconnect (P4) clones the ubuntu template authored by the network/ state (P3).
# It reads the template VMID (9001) here so the proxmox-vm module clones the
# foundation template by id. Cross-state clone-by-vm_id is safe because network/
# (P3) applies BEFORE opconnect (P4), so 9001 physically exists on the pve node
# first.
#
# STABLE IDs ONLY — never live IPs. Backend config mirrors
# tofu/network/backend.tf exactly except this is a read (same bucket/key/region/
# kms/role as compute's remote-state read).
# NOTE: terraform_remote_state needs S3 reachable; offline `validate
# -backend=false` cannot resolve it (real plan runs at P4 / with S3).
# ==============================================================================

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket       = "tmpx-tfstate-065094257518-use2"
    key          = "onprem/proxmox/network/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:us-east-2:065094257518:key/1d876310-c068-4204-aca3-d8585f477fda"
    use_lockfile = true
    assume_role = {
      role_arn = "arn:aws:iam::065094257518:role/OrganizationAccountAccessRole"
    }
  }
}
