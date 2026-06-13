# ==============================================================================
# opconnect off-site credentials — CONSUMER reads (spec #68, D6)
# ==============================================================================
# The bundle lives off-site in aws-foundation/15-opconnect-credentials. This state
# references it BY STABLE ALIAS / NAME (no terraform_remote_state -> zero coupling
# to that layer's state).
#
# SPLIT (spec D6): tofu reads ONLY the NON-SECRET ansible PUBLIC key (for the
# opconnect VM's own cloud-init authorized_keys). The PRIVATE key + Connect
# credentials.json + token are read by ANSIBLE (amazon.aws.aws_secret) at provision
# time -> they NEVER enter tofu state (#8).
#
# Bootstrap order (DR): seed the bundle (ansible playbooks/opconnect_credentials.yml)
# BEFORE applying this state, so the public key exists to read here.
# ==============================================================================

# The off-site-credentials CMK, by its stable alias. Documents the contract; the
# ephemeral read below decrypts via this key transparently through Secrets Manager.
data "aws_kms_alias" "opconnect" {
  name = "alias/tmpx/onprem-opconnect"
}

# EPHEMERAL read of the bundle: an ephemeral resource NEVER persists to state, so
# although the bundle JSON also contains the private key, nothing here lands in
# state. We extract ONLY the public key below.
ephemeral "aws_secretsmanager_secret_version" "opconnect_credentials" {
  secret_id = "tmpx/onprem/opconnect-credentials"
}

locals {
  # The ansible PUBLIC key for the opconnect VM's cloud-init (consumed by
  # opconnect.tf: `ansible_pubkey = local.ansible_ssh_public_key`).
  #
  # KNOWN RISK — validate at `tofu plan` (spec/plan C2): an ephemeral value may be
  # REJECTED where it flows into a PERSISTENT attribute (the VM's cloud-init
  # user_data is stored in state). If `tofu plan` errors "ephemeral value not
  # allowed here", apply the documented FALLBACK:
  #   - have the seed playbook publish the NON-SECRET public key to an SSM String
  #     parameter (e.g. /tmpx/onprem/opconnect/ansible-public-key), and
  #   - read it here via `data "aws_ssm_parameter"` (persistent is fine — it is
  #     public), replacing the ephemeral read for the pubkey only.
  # The private key + Connect creds stay ANSIBLE-only either way.
  ansible_ssh_public_key = trimspace(jsondecode(ephemeral.aws_secretsmanager_secret_version.opconnect_credentials.secret_string)["ansible_public_key"])
}
