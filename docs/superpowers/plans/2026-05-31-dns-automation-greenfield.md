# UniFi DNS Automation (Greenfield, Reservation-as-Code) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans`. Steps use `- [ ]`.
> **For IaC, "test" = fresh evidence:** the Terraform Registry MCP validated the resource schema, `terraform validate` passed, `terraform plan` showed the intended change, `terraform apply` succeeded, and `dig`/the UniFi API confirmed the live result. NO step is "done" without that evidence (superpowers:verification-before-completion). **NEVER `terraform apply` without an explicit confirm** (Terraform MCP rule).

**Goal:** Automate internal DNS for the Proxmox fleet — each host gets a Terraform-managed `unifi_dns_record` (`<host>.fusioncloudx.home`) plus a `unifi_client` DHCP reservation that pins its IP — built greenfield on a cleaned UniFi slate, in the existing `terraform/` root.

**Architecture:** Per-instance networking lives with the VM (the AWS-validated boundary). In the EXISTING terraform root: `data "unifi_network"` reads Home Lab VLAN 40; `unifi_client.fcx` reserves each host's live IP (observe-then-pin; `allow_existing` → no import); `unifi_dns_record.fcx` publishes the name. **No state split, no foundational fabric, no firewall** — those are the documented roadmap (clickup backlog, task #3).

**Tech stack:** Terraform; `ubiquiti-community/unifi` 0.41.25; `bpg/proxmox` 0.93.0; UniFi UDM Pro API (`X-API-KEY` via `~/.zprofile` → `CLAUDE_UDM_PRO_API_TOKEN`); Terraform Registry MCP.

**Spec:** `docs/superpowers/specs/2026-05-31-network-layer-greenfield-design.md`

**Scope facts (grounded):** 8 VMs+LXC (gitlab, mealie, tandoor, immich, duplicati, backrest, postgresql; runitup is a state-orphan, disposable). MAC: VMs `proxmox_virtual_environment_vm.qemu-vm[k].mac_addresses[1]`, LXC `proxmox_virtual_environment_container.postgresql.network_interface[0].mac_address`. IP: VMs `ipv4_addresses[1][0]`, LXC `ipv4["eth0"]`. NEVER touch: physical devices, `pve` (.206), `ui.fusioncloudx.home` (.254.1).

---

### Task 1: Branch + session setup

**Files:** git only

- [ ] **Step 1 — Branch off main.**
```bash
cd "/Users/fcx/Developer/Personal/repos/FusionCloudX-Infrastructure"
git fetch origin && git checkout -b feat/dns-automation origin/main
git status -s   # expect only untracked scratch
```
- [ ] **Step 2 — Export the UniFi token** (provider reads `UNIFI_API_KEY`; clean-slate curls read the same):
```bash
source ~/.zprofile && export UNIFI_API_KEY="$CLAUDE_UDM_PRO_API_TOKEN"
[ -n "$UNIFI_API_KEY" ] && echo "token set"
```
- [ ] **Step 3 — Commit a plan-tracking marker** (the spec + this plan are already on `main` via docs; if not, `git add docs/superpowers && git commit -m "docs: dns-automation spec+plan"`).

---

## Phase 0 — Clean slate (scoped: VMs only; never physical/pve/ui)

> **Ordering (critical, grounded):** the clean must RELEASE the IPs, which requires the VMs DOWN — UniFi won't free an IP while the VM holds its lease. And observe-then-pin needs the VMs UP at the resource-apply (to read the live IP). So: **(a)** Task 2.5 sets the bpg `started = false` on all VMs+LXC and applies → graceful stop → leases release; **(b)** Tasks 3–5 do the scoped clean + verify; **(c)** Phase 1's apply sets `started = true` → VMs back up → fresh DHCP → observe-then-pin. Power-cycle stays IN Terraform (no manual `qm`). **Shutdown path chosen over `terraform destroy`** — preserves the VMs/apps, no full rebuild + ansible redeploy.

### Task 2: Scan the proxmox inventory = the cleanup scope

**Files:** none (read-only)

- [ ] **Step 1 — List the TF-managed VM/LXC MACs + IPs from live Terraform state** (the authoritative scope):
```bash
cd "/Users/fcx/Developer/Personal/repos/FusionCloudX-Infrastructure/terraform"
terraform show -json | python3 -c '
import json,sys
d=json.load(sys.stdin)
res=d.get("values",{}).get("root_module",{}).get("resources",[])
for r in res:
    t=r.get("type"); v=r.get("values",{})
    if t=="proxmox_virtual_environment_vm":
        print("VM ", v.get("name"), "mac=", (v.get("mac_addresses") or [None,None])[1], "ip=", (v.get("ipv4_addresses") or [[],[None]])[1][0] if len(v.get("ipv4_addresses") or [])>1 else None)
    if t=="proxmox_virtual_environment_container":
        print("LXC", v.get("vm_id"), "mac=", (v.get("network_interface") or [{}])[0].get("mac_address"), "ip=", (v.get("ipv4") or {}).get("eth0"))'
```
Expected: 6 VM lines + 1 LXC line, each with a `bc:24:11:*` MAC + a `192.168.40.x` IP. **Record these MACs** — they are the clean-slate scope.
- [ ] **Step 2 — Capture the UniFi client + DNS state for diffing** (read-only):
```bash
B1="https://192.168.40.1/proxy/network/api/s/default"; B2="https://192.168.40.1/proxy/network/v2/api/site/default"
curl -sk -H "X-API-KEY: $UNIFI_API_KEY" "$B1/rest/user" > /tmp/u-clients-before.json
curl -sk -H "X-API-KEY: $UNIFI_API_KEY" "$B2/static-dns" > /tmp/u-dns-before.json
```

### Task 2.5: Shut down the fleet via Terraform (`started=false`) — release the IPs

**Files:** `terraform/variables.tf` `vm_configs` + `postgresql_lxc_config` (set `started=false`), or a `-var` override

- [ ] **Step 1 — MCP-verify** the `started` attribute on `proxmox_virtual_environment_vm` + `proxmox_virtual_environment_container` (bpg exposes it; confirm graceful-shutdown semantics, not hard-stop).
- [ ] **Step 2 — Set `started = false`** on all 6 VMs + the LXC (temporary).
- [ ] **Step 3 — `terraform plan`** → expect only the VMs+LXC to stop (no other changes). **CONFIRM the plan.**
- [ ] **Step 4 — `terraform apply`** (type `yes`) → graceful stop → DHCP leases release → UniFi frees the IPs.
- [ ] **Step 5 — SSH into Proxmox and verify ALL TF-managed VMs are DOWN (hard gate):** `ssh root@192.168.40.206 'qm list; pct list'` → assert the 6 VMs (1103–1108) + the LXC (2001) show `stopped`, and `runitup` is gone. **Do not proceed to the clean (Task 3) until every one is confirmed down** — verification-before-completion, not "terraform said it applied."

### Task 3: Dry-run the scoped clean

**Files:** none

- [ ] **Step 1 — Compute exactly what will be cleared** (VM-MAC reservations + their Device-DNS + the VM static-DNS records), and what is EXCLUDED:
```bash
python3 - <<'PY'
import json
vm_macs = {  # paste the MACs from Task 2 Step 1 (lower-case)
 "bc:24:11:...gitlab","bc:24:11:...mealie","bc:24:11:...tandoor","bc:24:11:...immich",
 "bc:24:11:...duplicati","bc:24:11:...backrest","bc:24:11:...postgresql"}
clients=json.load(open("/tmp/u-clients-before.json")).get("data",[])
print("WILL CLEAR (reservation/Device-DNS):")
for c in clients:
    if c.get("mac","").lower() in vm_macs and (c.get("use_fixedip") or c.get("local_dns_record_enabled")):
        print("  ", c.get("name") or c.get("hostname"), c.get("mac"), "fixed_ip=",c.get("fixed_ip"))
print("WILL NEVER TOUCH (sample physical/pve):")
for c in clients:
    nm=(c.get("name") or "").lower()
    if c.get("use_fixedip") and any(p in nm for p in ["playstation","sonos","unas","nas","printer","echo","zero","pi","opconnect","nzxt"]):
        print("  KEEP", c.get("name"), c.get("fixed_ip"))
dns=json.load(open("/tmp/u-dns-before.json"))
dns=dns if isinstance(dns,list) else dns.get("data",[])
print("DNS to clear (VM scope) / KEEP ui:")
for r in dns:
    keep = r.get("key")=="ui.fusioncloudx.home"
    print("  ", "KEEP" if keep else "CLEAR", r.get("key"), r.get("value"))
PY
```
Expected: lists the 7–8 VM reservations/records to clear; `ui.fusioncloudx.home` and all physical devices show KEEP.
- [ ] **Step 2 — STOP and get explicit confirmation** of the dry-run output before any deletion (destructive-op gate). *(Manual-UI alternative: instead of Steps in Task 4, clear those exact toggles/records in the UniFi UI; then skip to Task 5.)*

### Task 4: Execute the scoped clean (API)

**Files:** none

- [ ] **Step 1 — Clear each VM client's fixed-IP + Device-DNS** (PUT merge per client `_id`, scoped to the recorded VM MACs):
```bash
# For each VM client _id from /tmp/u-clients-before.json (VM scope only):
curl -sk -X PUT -H "X-API-KEY: $UNIFI_API_KEY" -H "Content-Type: application/json" \
  -d '{"use_fixedip":false,"fixed_ip":"","local_dns_record_enabled":false,"local_dns_record":""}' \
  "https://192.168.40.1/proxy/network/api/s/default/rest/user/<CLIENT_ID>"
```
- [ ] **Step 2 — Delete the VM static-DNS records** (DELETE each VM record `_id` from `/tmp/u-dns-before.json`; **skip `ui.fusioncloudx.home`**):
```bash
curl -sk -X DELETE -H "X-API-KEY: $UNIFI_API_KEY" \
  "https://192.168.40.1/proxy/network/v2/api/site/default/static-dns/<RECORD_ID>"
```
- [ ] **Step 3 — Handle the local Terraform state orphans** (the PR-#37 `unifi_dns_record.fcx` may be in the shared local `terraform.tfstate`):
```bash
cd "/Users/fcx/Developer/Personal/repos/FusionCloudX-Infrastructure/terraform"
terraform state list | grep unifi_dns_record || echo "none in state"
# if present:  terraform state rm 'unifi_dns_record.fcx'
```
- [ ] **Step 4 — Close PR #37** (superseded): `gh pr close 37 --comment "Superseded by feat/dns-automation (greenfield reservation-as-code)."`

### Task 5: Verify-clean gate

**Files:** none

- [ ] **Step 1 — Re-scan and assert clean for the VM scope, physical+ui intact:**
```bash
curl -sk -H "X-API-KEY: $UNIFI_API_KEY" "https://192.168.40.1/proxy/network/v2/api/site/default/static-dns" | python3 -c '
import json,sys; d=json.load(sys.stdin); rows=d if isinstance(d,list) else d.get("data",[])
keys=[r.get("key") for r in rows]; print("remaining DNS:",keys)
assert keys==["ui.fusioncloudx.home"] or all("fusioncloudx.home" not in k or k=="ui.fusioncloudx.home" for k in keys), "VM DNS not clean"'
```
Expected: only `ui.fusioncloudx.home` remains among `*.fusioncloudx.home`. **If not clean, do not proceed.**

---

## Phase 1 — DNS automation (existing `terraform/` root)

### Task 6: `data "unifi_network"` for Home Lab VLAN 40

**Files:** Create `terraform/dns.tf` (replaces the old hardcoded-map dns.tf)

- [ ] **Step 1 — MCP-validate the data source schema FIRST.** Via the Terraform Registry MCP: `search_providers(ubiquiti-community/unifi, "network", data-sources)` → `get_provider_details(<network data-source doc_id>)`. Confirm the attribute that returns the network/VLAN `id` for a lookup by `name = "Home Lab"`. Record the exact field names.
- [ ] **Step 2 — Write the data source** (use the field names from Step 1; example assumes `name`):
```hcl
data "unifi_network" "homelab" {
  name = "Home Lab"   # VLAN 40, 192.168.40.0/24
}
```
- [ ] **Step 3 — `terraform validate`:**
```bash
cd "/Users/fcx/Developer/Personal/repos/FusionCloudX-Infrastructure/terraform"
terraform init -upgrade && terraform validate
```
Expected: `Success! The configuration is valid.`

### Task 7: `unifi_client` reservations (observe-then-pin)

**Files:** Modify `terraform/dns.tf`

- [ ] **Step 1 — MCP-validate `unifi_client`** (doc 11704916 already confirmed): `fixed_ip`, `mac`, `network_id`, `allow_existing`. Confirm no schema drift in 0.41.25.
- [ ] **Step 2 — Write the reservation, branched VM-vs-LXC:**
```hcl
locals {
  fcx_vms = toset(keys(var.vm_configs))   # the 6 QEMU VMs
}
resource "unifi_client" "vm" {
  for_each       = local.fcx_vms
  mac            = proxmox_virtual_environment_vm.qemu-vm[each.key].mac_addresses[1]
  fixed_ip       = proxmox_virtual_environment_vm.qemu-vm[each.key].ipv4_addresses[1][0]
  network_id     = data.unifi_network.homelab.id
  name           = each.key
  allow_existing = true
}
resource "unifi_client" "lxc" {
  mac            = proxmox_virtual_environment_container.postgresql.network_interface[0].mac_address
  fixed_ip       = proxmox_virtual_environment_container.postgresql.ipv4["eth0"]
  network_id     = data.unifi_network.homelab.id
  name           = "postgresql"
  allow_existing = true
}
```
- [ ] **Step 3 — `terraform validate`** → expect valid.
- [ ] **Step 4 — `terraform plan`** → expect **7 `unifi_client` to add** (6 VM + 1 LXC), `fixed_ip` = the current live IPs, 0 changes to VMs/LXC. Read the plan; confirm no VM/LXC replacement.

### Task 8: `unifi_dns_record` per host

**Files:** Modify `terraform/dns.tf`

- [ ] **Step 1 — Write the records** (value = the same live IP the reservation pins):
```hcl
resource "unifi_dns_record" "vm" {
  for_each    = local.fcx_vms
  name        = "${each.key}.fusioncloudx.home"
  value       = proxmox_virtual_environment_vm.qemu-vm[each.key].ipv4_addresses[1][0]
  record_type = "A"
  enabled     = true
}
resource "unifi_dns_record" "lxc" {
  name        = "postgresql.fusioncloudx.home"
  value       = proxmox_virtual_environment_container.postgresql.ipv4["eth0"]
  record_type = "A"
  enabled     = true
}
```
- [ ] **Step 2 — `terraform validate`** → valid.
- [ ] **Step 3 — `terraform plan`** → expect **7 `unifi_dns_record` to add**, values = the live IPs. Confirm. **Do NOT add `ui` or `runitup`.**

### Task 9: Apply + verify (the IaC test)

**Files:** none

- [ ] **Step 1 — Set `started = true`** back on all VMs+LXC, then **Apply (CONFIRM first):** `terraform apply` → review → type `yes`. Expected: the VMs+LXC start back up; once each guest agent reports its IP, `14 added` (7 `unifi_client` + 7 `unifi_dns_record`), VMs/LXC changed (started true), 0 destroyed.
- [ ] **Step 2 — Verify DNS resolves (fresh evidence):**
```bash
for h in gitlab mealie tandoor immich duplicati backrest postgresql; do
  printf "  %-12s -> %s\n" "$h" "$(dig +short $h.fusioncloudx.home @192.168.40.1)"
done
```
Expected: all 7 resolve to their `192.168.40.x` IPs.
- [ ] **Step 3 — Verify reservations live** via the UniFi API: re-GET `/rest/user`, assert each VM client `use_fixedip=true` + `fixed_ip` matches. Assert `ui` + physical devices untouched.

### Task 10: Fix the `.90` ansible fallbacks → name

**Files:** Modify `ansible/roles/mealie/defaults/main.yml:33`, `ansible/roles/tandoor/defaults/main.yml:38`

- [ ] **Step 1 — Change both fallbacks** from `| default('192.168.40.90')` to `| default('postgresql.fusioncloudx.home')`.
- [ ] **Step 2 — Verify** no other `192.168.40.90` consumer remains: `grep -rn "192.168.40.90" ansible/` → expect 0.

### Task 11: Commit, PR, code-review gate

**Files:** git

- [ ] **Step 1 — Commit:**
```bash
git add terraform/dns.tf ansible/roles/mealie/defaults/main.yml ansible/roles/tandoor/defaults/main.yml
git commit -m "feat(dns): greenfield UniFi DNS automation — per-host unifi_client reservation + unifi_dns_record"
```
- [ ] **Step 2 — Push + open PR** to `main` (the auto-review now posts; `@claude` is the fallback).
- [ ] **Step 3 — Code-review gate:** wait for the Claude review to post; address findings; merge only when green + reviewed (never trust a green run without a posted review).

---

## Self-Review

- **Spec coverage:** Phase 0 clean-slate (scoped, verify-gated) ✓; reservation-as-code `unifi_client` (observe-then-pin, allow_existing, MAC branched) ✓; `unifi_dns_record` (record_type=A, enabled) ✓; `network_id` via data source ✓; `.90` fix ✓; `ui` never-touch ✓; runitup disposable (state-rm/close PR#37) ✓. Firewall/fabric/split correctly OUT (roadmap).
- **Placeholders:** Task 2/3 require pasting the actual MACs from the live scan — flagged as explicit steps, not TODOs. Task 6 Step 1 MCP-validates the data-source field names before use (the one unverified attribute).
- **Type consistency:** `local.fcx_vms` used in Tasks 7+8; `data.unifi_network.homelab.id` consistent; MAC/IP attribute paths identical across reservation + record.

## Execution Handoff

Two options:
1. **Subagent-Driven (recommended)** — fresh subagent per task, review between, MCP-validate + plan-confirm gates enforced per task.
2. **Inline Execution** — batch with checkpoints at each `terraform plan` / `apply` confirm.
