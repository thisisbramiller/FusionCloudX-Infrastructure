# ==============================================================================
# Remote state — read the THIN network state (onprem/proxmox/network)
# ==============================================================================
# Seam: compute reads network via terraform_remote_state — STABLE IDs ONLY
# (homelab_network_id), never live IPs. The unifi-host module accepts a
# network_id but the proven-working dns path OMITS it (the fork cannot
# round-trip network_id on unifi_client); the per-service *_dns module calls
# therefore pass network_id = null. The remote-state read is wired here so the
# stable id is AVAILABLE if/when a future opt-in needs it without re-plumbing.
#
# Backend config mirrors tofu/network/backend.tf exactly except the key.
# NOTE: terraform_remote_state needs S3 reachable; offline `validate
# -backend=false` cannot resolve it (real plan runs at P5 / with S3).
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
