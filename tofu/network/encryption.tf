terraform {
  encryption {
    key_provider "aws_kms" "state" {
      kms_key_id = "arn:aws:kms:us-east-2:065094257518:key/1d876310-c068-4204-aca3-d8585f477fda"
      key_spec   = "AES_256"
      region     = "us-east-2"
      # Key provider assumes into shared-services itself (auth options == S3 backend);
      # base creds = fcx-sso, which can assume OrganizationAccountAccessRole.
      assume_role = {
        role_arn = "arn:aws:iam::065094257518:role/OrganizationAccountAccessRole"
      }
    }
    method "aes_gcm" "default" {
      keys = key_provider.aws_kms.state
    }
    # Fresh layer (no pre-existing plaintext state) -> enforce from t=0; no unencrypted fallback needed.
    state {
      method   = method.aes_gcm.default
      enforced = true
    }
    plan {
      method   = method.aes_gcm.default
      enforced = true
    }
  }
}
