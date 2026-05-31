# UniFi DNS Automation — Implementation Plan

> Spec: `docs/superpowers/specs/2026-05-31-unifi-dns-automation-design.md`
> Scope: Phase 1 (runitup-first). "Test" for IaC = `plan` shows the intended create, `apply`
> succeeds, `dig` resolves the name. Branch: `add-unifi-dns`.

**Goal:** Add the `ubiquiti-community/unifi` provider + one static DNS record
(`runitup.fusioncloudx.home → 192.168.40.25`) to the Terraform root module, proven against the
live UDM, via PR + GitHub Claude review.

---

### Task 1: Add the provider — `terraform/provider.tf`
- [ ] Add `unifi = { source = "ubiquiti-community/unifi", version = "0.41.25" }` to `required_providers`.
- [ ] Add a `provider "unifi"` block: `api_url = "https://192.168.40.1"`, `allow_insecure = true`
      (api_key via `UNIFI_API_KEY` env — not inlined).

### Task 2: Add the record — `terraform/dns.tf` (new)
- [ ] `for_each` over a `local.fcx_dns_records` map (runitup only; fleet entries commented).
- [ ] `unifi_dns_record` with `name`, `value`, `record_type = "A"`, `enabled = true`.

### Task 3: Init + validate
- [ ] `export UNIFI_API_KEY="$CLAUDE_UDM_PRO_API_TOKEN"`
- [ ] `terraform init` — expect `ubiquiti-community/unifi v0.41.25` installed, lock updated.
- [ ] `terraform validate` — expect success.

### Task 4: Plan (the red→green check)
- [ ] `terraform plan -target='unifi_dns_record.fcx["runitup"]'`
- [ ] Expect: **1 to add** — `runitup.fusioncloudx.home / A / 192.168.40.25 / enabled`. No proxmox/OP changes.

### Task 5: Apply + verify (the test)
- [ ] `terraform apply -target='unifi_dns_record.fcx["runitup"]'` — expect `Apply complete! 1 added`.
- [ ] `dig +short runitup.fusioncloudx.home @192.168.40.1` — expect `192.168.40.25`.

### Task 6: Commit + PR + review
- [ ] Commit `provider.tf`, `dns.tf`, the lock file, and these docs.
- [ ] Push `add-unifi-dns`; open PR → `main`; wait for GitHub Claude code review; address; merge.

### Follow-up (Phase 2, separate)
- [ ] Per VM: clear `local_dns_record` (keep `fixed_ip`), add its static record sourced from the
      proxmox VM resource. Then retire the device-DNS records for the fleet.
