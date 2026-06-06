# FusionCloudX Network Layer — Foundational-Fabric State + Per-VM Networking With the VM (Design)

**Date:** 2026-05-31 · **Status:** FINAL — validated (Terraform MCP `hashicorp/aws` v6.47.0 + AWS SRA) and grounded (live UDM API + full repo rescan) · **Supersedes:** PR #37 (hardcoded-map proving step) and all earlier drafts of this spec.

## Goal

Split Terraform state at the AWS-validated boundary: **foundational/shared networking** (the fabric) → its own NETWORK state; **per-instance networking** (a VM's NIC, IP, and its own DNS record) → co-located with the VM in the COMPUTE state. Internal DNS via UniFi static records, **dynamic DHCP + kept reservations**, one **shared cloud-init template**, records **live-sourcing** each VM's IP.

## The boundary rule

> **FOUNDATIONAL** if its lifecycle is independent of any single workload and many VMs reference it upward by stable ID (the fabric VMs plug into). **PER-INSTANCE** if its lifecycle is 1:1 with one VM and it carries that VM's own address/identity.

Litmus: points AT the fabric (foundational ID inbound) but CARRIES the workload's address (IP/hostname outbound) → lives with the VM.

## Validation (verified)

`hashicorp/aws` v6.47.0 (Terraform MCP): `aws_route53_record` requires `zone_id` (foundational zone) but its value is `records=[<live workload attribute>]` → **zone foundational, record workload-scoped.** AWS SRA puts VPC/subnets/TGW/the hosted zone in the Network account; workload accounts create their own records. SGs/firewall split BOTH ways (shared baseline foundational; app-specific with the VM).

## Architecture (two states)

**NETWORK state — foundational fabric only** (`unifi` provider; later `aws`)
- The 9 VLANs (live UDM, all DHCP-server, UDM Pro router): Default `192.168.1.0/24`, Main(10) `.10`, Cameras(20) `.20`, **Home Lab(40) `192.168.40.0/24` = the VM subnet**, IoT(50) `.50`, Guest(99) `.99`, Management(254) `.254`, Client-Isolated(60) `.60`, Mobile(70) `.70`. Plus firewall rules, WiFi (PhaseZero / PhaseZeroCameras / PhaseZero_IoT), the internal DNS zone/forwarding.
- AWS later: VPC, subnets, route tables, IGW/NAT/TGW, `aws_route53_zone`, shared-SG.
- **Exports = stable IDs only** (VLAN IDs, subnet/gateway/CIDR, DNS zone name/id) — never live VM IPs.
- *Note:* the UDM exposes a per-VLAN gateway interface (`.1.1` / `.40.1` / `.254.1` …) — all the same router; `provider.tf`'s `192.168.40.1` is the homelab-side endpoint and is correct (this was a false-alarm "inconsistency").

**COMPUTE state — per-instance, with the VM** (`bpg/proxmox` + `unifi`)
- The 6 Proxmox VMs (shared `qemu-vm` for_each) + the postgres LXC. **Dynamic DHCP**, one **shared cloud-init template** (gitlab is the only fork).
- Each VM's per-host `unifi_dns_record` lives here, **live-sourcing the IP**: `ipv4_addresses[1][0]` for the 6 VMs (guest-agent), `ipv4["eth0"]` for the LXC.
- The `unifi` provider here is scoped to the per-host record only — normal provider hygiene, NOT a risk (compute already depends on `bpg/proxmox` / 1Password / tls the same way).

**Value-passing seam:** compute reads network via `terraform_remote_state` — **stable IDs only**, never live IPs. Live IPs are produced inside compute and consumed by the record in the same atomic apply.

**Ansible inventory seam — RESOLVED (one line).** Ansible resolves `ansible_host` via `cloud.terraform.terraform_provider` reading TF state live at runtime (`ansible/inventory/terraform.yml`, enabled `ansible.cfg:55`; no generated vars file). The `ansible_host`/`ansible_group` resources (`ansible-inventory.tf`) move to COMPUTE. Fix = repoint `project_path: ../terraform` → `../terraform/compute`; keep `search_child_modules: false`; clear the inventory cache (`ansible.cfg:57-60`) after the change. (NOT the `terraform_state` plugin — it doesn't surface `ansible_host`.)

## Identity — reservation-as-code via `unifi_client` (no MAC pin, no static IP, NO import)

Provider-validated (Terraform MCP, `unifi_client` resource, doc 11704916; this fork renamed legacy `unifi_user` → `unifi_client`). DHCP reservations are managed **in Terraform, not the UI** — eliminating the manual drift that orphaned the gitlab client and started this thread. Per VM/LXC in the COMPUTE state:

```hcl
resource "unifi_client" "fcx" {
  for_each       = <the 6 VMs + the postgres LXC>
  mac            = <LIVE MAC, BRANCHED by type — VMs: proxmox_virtual_environment_vm.qemu-vm[each.key].mac_addresses[1]  (index [0]=placeholder 00:00…/127, [2]+=docker bridges); LXC: proxmox_virtual_environment_container.postgresql.network_interface[0].mac_address>   # read, not declared → no MAC pin
  fixed_ip       = <each VM's LIVE DHCP IP: ipv4_addresses[1][0] for VMs, ipv4["eth0"] for the LXC>
  network_id     = data.terraform_remote_state.network.outputs.homelab_network_id  # stable ID from network state
  name           = each.key
  allow_existing = true   # DEFAULT true — ADOPTS the auto-created client, NO terraform import
  # skip_forget_on_destroy = true  # optional: keep the client object on destroy
  # DO NOT set local_dns_record here — it is the per-client Device DNS that 400-overlaps the static record
}
resource "unifi_dns_record" "fcx" {
  for_each    = <same set>
  name        = "${each.key}.fusioncloudx.home"
  value       = <the same live/pinned IP>
  record_type = "A"      # mandatory (UDM HTTP 500 otherwise, upstream #137)
  enabled     = true     # preserve current behavior (dns.tf:40 sets it today)
}
```

- **Observe-then-pin:** let DHCP assign, read the IP live, pin it as `fixed_ip`. The VM keeps the IP it already has (lease `.X` → reservation `.X`) → stable, **single apply, no convergence cycle** (corrects the earlier "one-DHCP-cycle" caveat — pinning the current IP changes nothing).
- **NO `terraform import`:** `allow_existing` defaults TRUE — provider doc: *"Clients are created in the controller when observed on the network, so the resource defaults to allowing itself to just take over management of a MAC address."* For the current fleet, Terraform **adopts** the existing manual reservations and re-asserts the same IP → no change, no import, no disruption.
- **Rebuild reconciliation:** MAC read live → on rebuild Terraform forgets the old client (unless `skip_forget_on_destroy`) and reserves the new MAC. The gitlab orphan failure mode is structurally gone.
- **Guest agent** (present fleet-wide) is used to read `ipv4_addresses` for the pin + the DNS value.
- **No static cloud-init, no IPAM map** — the IP is DHCP-chosen then frozen in code. **Float was rejected** (can drift on reboot — the operator's hard no).

## Greenfield freedom

Nothing real exists in any DB/storage yet → **everything (incl. `runitup`) is disposable.** No Phase-0 reconciliation, no migration ordering, no data-preservation care; we can destroy/recreate freely. Greenfield-no-`import` applies to the DNS records (recreate fresh; current state/UDM = reference for values only). The existing VMs stay (not recreated) but could be rebuilt freely if useful.

## The `.90` postgres fallback — fix to a NAME (it can fire)

Verified: the `.90` fallback is NOT a safely-dead default. Normally `cloud.terraform` injects the live LXC IP (`.251`), but the fallback fires whenever `hostvars['postgresql']` is absent (a `--limit` excluding postgresql, or stale state) → mealie/tandoor render a dead IP (`.90` is already wrong). Fixes:
- `ansible/roles/mealie/defaults/main.yml:33` + `ansible/roles/tandoor/defaults/main.yml:38`: `| default('192.168.40.90')` → `| default('postgresql.fusioncloudx.home')`.
- `ansible-inventory.tf:60-63` (postgres) + `:80-84` (vms): `try(..., "IP not available")` yields a **truthy** string on failure, which Jinja `default()` won't catch (renders the literal `IP not available`). Make the failure path null/empty. Same pattern across `outputs.tf` (`:21,33,58,63,68,73,79`, display-only) + the `dns.tf:43` `fcx_dns_records` output — fix consistently; decide whether `fcx_dns_records` is recreated in compute or dropped.
- UNAS NFS `192.168.40.137` (THREE files: `immich/defaults/main.yml:29`, `duplicati/…:30`, `backrest/…:38`) — **DEFERRED, NOT in this plan.** Non-TF appliance already stable via its own reservation (no float risk), AND a name COLLISION: `inventory/devices.yaml:34-37` maps `nas01`→`192.168.40.50` (stale — `.50` is `echo`'s reservation; the real NAS is `.137`). Naming `.137`→`nas01` today resolves to `.50` and breaks the NFS mounts. Separate follow-up: reconcile the stale `devices.yaml` mapping first; leave the three `.137` refs as-is.

## Phasing

> **THIS PR (DNS only):** Phase 0 (clean slate) → then add `unifi_client` reservations + `unifi_dns_record` to the **EXISTING** Terraform root (NOT a new `network/` state), `network_id` via `data "unifi_network"`, + the `.90` fix. **Phase 1 (NETWORK state / foundational fabric) below is ROADMAP-DEFERRED** — firewall/VLAN/WLAN authoring is future work. The Phase-2 resource wiring (`unifi_client` + `unifi_dns_record`, minus the state split) is what this PR actually builds, in the existing root.

- **Phase 0 — CLEAN SLATE (prerequisite).** Scan the proxmox VM/LXC inventory → the current VM+LXC MACs/names = the cleanup SCOPE. Then clear the UniFi side **for that scope only**: the VMs' DHCP reservations (Fixed-IP / `use_fixedip`), any per-client Device DNS (`local_dns_record`), stale/cruft clients (e.g. the old gitlab `.13` MAC), and the PR-#37 static `unifi_dns_record` set. The PR-#37 records (Terraform-managed) come out via `terraform destroy -target='unifi_dns_record.fcx'`; the manual reservations + Device-DNS via the UniFi API (scoped script: dry-run → confirm → delete) **OR** a one-time manual UI clean (checklist provided). **SCOPE GUARDRAIL — DO NOT touch:** physical devices (PlayStation/Sonos/UNAS/nas/printer/echo/zero/pi/opconnect), the `pve` host reservation (`.206`), or `ui.fusioncloudx.home`. **Verify-clean gate:** re-scan the UniFi API and assert zero reservations/static-DNS/Device-DNS for the VM scope (physical + `ui` intact) before Phase 1. (Post-clean, VMs may pull new pool IPs before Terraform re-pins — fine: disposable + DNS/name-addressing absorbs it; or sequence clean→apply within the lease window to preserve current IPs.)
- **Phase 1 — NETWORK state:** `terraform/network/` (own local state) — the foundational UniFi fabric (the 9 VLANs/DHCP/firewall/WiFi, authored from the live config) + the DNS zone/forwarding + stable-ID outputs; ephemeral `UNIFI_API_KEY`. Declares ZERO 1Password/proxmox vars (only the `unifi` provider). Own `.terraform.lock.hcl` (unifi only); fresh `terraform init`.
- **Phase 2 — COMPUTE state:** `terraform/compute/` — move the compute resources: VMs/LXC, cloud-init (`cloud-init.tf` + `cloud-init-gitlab.tf`), **the templates (`ubuntu-template.tf`, `lxc-debian-template.tf`)**, 1Password, ssh-keys (+ inert `ssh-keys.tf.disabled`), `ansible-inventory.tf`, `outputs.tf`. Add each host's `unifi_client` (observe-then-pin, `allow_existing=true`, MAC branched VM-vs-LXC) + `unifi_dns_record`. Repoint the ansible inventory `project_path → ../terraform/compute` (clear the cache). Fix the `.90` fallbacks + the truthy-string bug. **Repoint operator tooling hardcoding `cd terraform`:** `scripts/check-infrastructure.sh`, `README.md`, repo `CLAUDE.md`, `.github/copilot-instructions.md`, `COORDINATION-NOTE.md`. Own `.terraform.lock.hcl` (proxmox + onepassword + ansible + tls + unifi); fresh `terraform init` (do NOT copy old `.terraform/` — 3 fossil providers `null`/`external`/`restapi` drop on fresh init). **First apply DESTROYS the state-orphan `runitup`** (VM + cloud-init + ansible-host + DNS) — expected, disposable.
- **Throughout:** the Terraform Registry MCP validates each resource schema + provider version before HCL is written; `terraform validate` → `plan` → **confirm before `apply`**; the superpowers lifecycle drives it (writing-plans authoring, subagent-driven execution, verification-before-completion every step, requesting-code-review gate on the PR).

## Guardrails

`precondition record_type="A"` (UDM HTTP 500 otherwise, upstream #137); `prevent_destroy` on the postgres LXC; ephemeral `UNIFI_API_KEY` (closes the tfplan-leak finding); `removed` blocks / pre-clear for the PR-#37 records (dodge the name-overlap HTTP 400).

## Current-state map (rescan)

Single flat root module today, local backend. **Foundational → NETWORK** (mostly net-new): the `unifi` provider block (`provider.tf:72-76`); VLANs/DHCP/firewall/WiFi/DNS-zone (none in repo yet). **Per-instance → COMPUTE** (keep): `qemu-vm.tf`, `lxc-postgresql.tf`, `variables.tf` (`vm_configs`), `cloud-init.tf` + `cloud-init-gitlab.tf`, templates, `ansible-inventory.tf`, `outputs.tf`, `onepassword.tf`, `ssh-keys.tf`; the per-VM `unifi_dns_record` recreated here, live-sourced.

## Out of scope (deliberate)

Separate repo/pipeline (premature solo); remote encrypted backend (follow-up — the tfplan-leak finding wants it); AWS network layer (future); runitup container re-architecture (separate task).

## Provenance (verified against)

Terraform MCP `hashicorp/aws` v6.47.0 — `aws_route53_record` (12381581), `aws_subnet`, `aws_network_interface`, `aws_instance`, `aws_eip_association`; AWS SRA Network-account; live UDM API (`/rest/networkconf` + `/rest/user`, 2026-05-31 — VLANs + `use_fixedip`); repo rescan (guest-agent full coverage, `.90` fallback trace, ansible `cloud.terraform` inventory); `cloud.terraform.terraform_provider` inventory plugin docs (`project_path` raw/list, `search_child_modules`).
