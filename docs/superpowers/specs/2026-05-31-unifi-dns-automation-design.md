# UniFi DNS Automation — Design

**Date:** 2026-05-31 · **Status:** approved (runitup-first scope) · **Branch:** `add-unifi-dns`

## Goal

Bring the FusionCloudX VM fleet's internal DNS (`*.fusioncloudx.home`) into Terraform so a
record follows its VM instead of being hand-clicked in the UniFi UI and going stale on rebuild
(the failure that broke the GitLab deploy when its VM was recreated). **DNS records only — no
network service module, no firewall/VLAN/VPN.** That broader work is the post-project backlog.

## Provider

`ubiquiti-community/unifi` pinned **exactly** to `0.41.25` (the maintained successor to the
archived `paultyng` provider; it added `unifi_dns_record`). Validated firsthand against this
controller (UDM Pro, UniFi OS 5.1.12 / Network 10.3.58) in a throwaway `/tmp` trial:
auth ✓ (X-API-KEY via `UNIFI_API_KEY`), schema ✓, `plan` ✓. The only `apply` failure was a
device-DNS overlap rule — see Migration.

- `api_url = https://192.168.40.1` (no trailing `/api`), `allow_insecure = true` (self-signed UDM cert).
- `api_key` supplied via the **`UNIFI_API_KEY` env var**, sourced from Keychain/`.zprofile`
  (same posture as the proxmox SSH agent + 1Password token). **Never committed.**

## Decision: static DNS table, not per-client Device DNS

The fleet today resolves via per-client **Device DNS** (`local_dns_record` on each client object)
+ fixed-IP reservations. Device DNS is **MAC-keyed**, so a VM rebuild (new MAC) orphans it — the
GitLab break. Static `unifi_dns_record` is **name-keyed** and survives rebuilds. Physical/stable
devices (nzxt, nas, printer, pi, echo, zero, opconnect) stay on Device DNS — that's their sweet spot.

- `record_type = "A"` is **mandatory** even though the schema marks it optional — omitting it
  returns HTTP 500 (issue #137).
- `value` is the VM's IP. Fleet rollout will source it from the proxmox VM resource
  (`ipv4_addresses`); the runitup POC hardcodes it (the runitup VM resource lives on the
  unmerged `add-runitup-vm` branch).

## Scope

**Phase 1 — runitup-first (this branch):** one record, `runitup.fusioncloudx.home → 192.168.40.25`.
runitup is the only fleet VM with **no** existing Device DNS record, so the static create has **no
overlap** — it proves the write-path end-to-end against the live UDM at near-zero blast radius.

**Phase 2 — fleet (follow-up):** the other 7 (gitlab, mealie, tandoor, immich, duplicati, backrest,
postgresql). Each requires a one-time **migration**: clear `local_dns_record` on the client but
**keep `fixed_ip`** (so IPs don't move and inter-app refs like postgres `.251` don't break), then
add its static record sourced from the VM resource.

**Out of scope (backlog):** MAC-pinning + reservation-as-code, Device DNS for physical hosts,
and every other UniFi resource (network/firewall/wlan/vpn). See the UniFi possibility-map.

## Risk & ops (GREEN tier)

- Pin the provider exactly; it rides an undocumented v2 API — re-validate after UniFi OS bumps.
- Back up the UDM controller config before applies; the UI stays a viable fallback.
- Same Terraform root module is fine for DNS (low blast radius); network-state isolation is a
  RUN-phase concern, not now.
