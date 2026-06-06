# Provider requirements only — NO provider config blocks. The root module that
# consumes this module supplies the configured `onepassword` provider.
terraform {
  required_version = ">= 1.8"

  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 3.0"
    }
  }
}
