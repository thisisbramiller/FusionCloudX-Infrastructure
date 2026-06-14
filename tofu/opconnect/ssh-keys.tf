# ==============================================================================
# opconnect bootstrap pubkey — read from SSM (spec D10)
# ==============================================================================
# tofu reads ONLY the non-secret DEDICATED ansible PUBLIC key, published to SSM
# by the seed (opconnect_credentials role). Replaces the ephemeral Secrets
# Manager read (rejected at plan: an ephemeral value cannot feed persisted
# cloud-init user_data). The private key + Connect creds are read by ANSIBLE from
# the AWS bundle (amazon.aws.aws_secret, Direction A) — never by tofu -> never in state (#8).
# ==============================================================================
data "aws_ssm_parameter" "ansible_pubkey" {
  name = "/tmpx/onprem/opconnect/ansible_public_key"
}

locals {
  ansible_ssh_public_key = trimspace(data.aws_ssm_parameter.ansible_pubkey.value)
}
