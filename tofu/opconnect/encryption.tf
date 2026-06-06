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
    # Decrypt the FOUNDATION network state read via data.terraform_remote_state.
    # network/ is AES-GCM encrypted with this SAME CMK + key_provider name
    # ("state") + method, so one default decryptor reads it. Without this block
    # the cross-state read fails "Unsupported state file format" — encrypted
    # remote state is opaque to a consumer with no remote-state decryptor.
    # Pattern mirrors aws-foundation/{21-detective-controls,24-alerting}.
    remote_state_data_sources {
      default {
        method = method.aes_gcm.default
      }
    }
  }
}
