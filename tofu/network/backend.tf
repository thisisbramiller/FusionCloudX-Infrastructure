terraform {
  backend "s3" {
    bucket       = "tmpx-tfstate-065094257518-use2"
    key          = "onprem/proxmox/network/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:us-east-2:065094257518:key/1d876310-c068-4204-aca3-d8585f477fda"
    use_lockfile = true
    # Base creds via the SSO profile in-config (not AWS_PROFILE env) so tofu + the
    # cloud.terraform inventory read state self-authenticated (#68 / #76).
    profile = "fcx-sso"
    assume_role = {
      role_arn = "arn:aws:iam::065094257518:role/OrganizationAccountAccessRole"
    }
  }
}
