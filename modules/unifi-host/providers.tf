# Provider requirements only — NO provider config blocks. The root module that
# consumes this module supplies the configured `unifi` provider.
#
# Patched fork consumed via a Terraform/OpenTofu filesystem mirror — see
# terraform/PATCHED-PROVIDER.md and the repo-root .tofurc. Synthetic host +
# pinned version; binary installed by scripts/build-unifi-provider.sh.
terraform {
  required_version = ">= 1.8"

  required_providers {
    unifi = {
      source  = "tf.fusioncloudx.home/ubiquiti-community/unifi"
      version = "0.42.0-fcx1"
    }
  }
}
