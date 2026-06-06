terraform {
  required_version = ">= 1.8"

  required_providers {
    unifi = {
      # Patched fork consumed via an OpenTofu filesystem mirror — see the
      # repo-root .tofurc and terraform/PATCHED-PROVIDER.md. Synthetic host +
      # pinned version; binary installed by scripts/build-unifi-provider.sh.
      source  = "tf.fusioncloudx.home/ubiquiti-community/unifi"
      version = "0.42.0-fcx1"
    }
  }
}

# AWS is only the state backend + state-encryption key provider — NO aws
# provider block here (this state authors only UniFi network data lookups).

provider "unifi" {
  # Bare controller URL ONLY — do NOT append /proxy/network or /api. The SDK
  # auto-discovers the UDM Pro /proxy/network path.
  api_url = "https://192.168.40.1"

  # The UDM Pro presents a self-signed certificate; skip TLS verification.
  allow_insecure = true

  # api_key is intentionally omitted — the provider reads it from the
  # UNIFI_API_KEY environment variable, keeping the secret out of HCL/state.
}
