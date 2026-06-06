# onprem-infra Greenfield Restructure — Design

**Date:** 2026-06-06 · **Status:** APPROVED (brainstorm complete; scope locked) · **Repo:** `FusionCloudX Infrastructure` (the on-prem `onprem-infra` project) · **Engine:** OpenTofu

**Supersedes for execution:** the blueprint `09-Homelab/onprem-infra-greenfield-redesign.md`, the ADR `09-Homelab/Decisions/2026-06-05-onprem-state-topology.md` (A3 lock), `Apps-VM-vs-LXC-Substrate.md` (resolved: VMs now), `Backup-Strategy-3-2-1-1-0.md` (backup tools killed), and the network-layer spec `docs/superpowers/specs/2026-05-31-network-layer-greenfield-design.md` (thin-network scope). This doc is the single execution source of truth.

---

## 1. Frame

GREENFIELD rebuild of the on-prem IaC repo. **No precious data** (GitLab empty, PostgreSQL near-empty, Immich DB+originals decoupled on disk/UNAS). Destroying/recreating VMs/LXC is explicitly OK. **No `moved` blocks, no `terraform state mv`, no state-preservation gymnastics** — we rebuild clean so resources stick from now on via `prevent_destroy`. Execution is **iterative**: one branch per phase/feature → atomic commits → PR → `@claude` review + `/requesting-code-review` + `/receiving-code-review` → test → merge → ClickUp status move. Same cadence as PRs #41–#45. Operate **in place** (no GitLab migration, no remote change — that is separate later work).

## 2. Decisions (locked this brainstorm)

| # | Decision | Choice |
|---|---|---|
| D1 | Engine | **OpenTofu** (`tofu`, `required_version >= 1.8`, repo-root `.tofurc`, `tofu providers lock`) |
| D2 | State split | **3 states**: `tofu/network` · `tofu/opconnect` · `tofu/compute` |
| D3 | Compute granularity | **A3** — one shared `compute/` state, one bundled `.tf` per service, thin base modules, Ansible owns service identity |
| D4 | Backend | **S3 + CMK** (live, audited 2026-06-06), key-namespaced `onprem/proxmox/<stack>/terraform.tfstate`, `use_lockfile=true`, native AES-GCM client-side encryption layered on SSE-KMS — mirrors `aws-foundation/30-identity` |
| D5 | Apps substrate | **VMs now** (Docker), VMID `13xx`. LXC conversion = documented per-service growth path (A3 makes it a one-file swap later) |
| D6 | VMID scheme | **Scheme B `[T][R][SS]`** (T=1 VM/2 LXC; R=1 core-infra/2 platform/3 apps; templates 9xxx) |
| D7 | opconnect install | **Docker Compose** (1Password-official for single VM): `op connect server create` + `op connect token create`, SA-token authed, brought up by a dedicated `opconnect` Ansible role |
| D8 | opconnect sequencing | **Author now, cut over LAST + safe** (P4): build new → verify → repoint → decommission old VM 100 |
| D9 | network/ scope | **Thin** — stable `network_id` (`data "unifi_network"`) + internal DNS zone; per-VM `unifi_client` + A records live in `compute/`. Full UDM fabric authoring (VLANs/firewall/WiFi) is OUT OF SCOPE (separate Network-as-Code/UDM-reflash effort) |
| D10 | runitup | **Included** as the 4th disposable app |
| D11 | Secrets-in-state | `ephemeral "tls_private_key"` → `value_wo` to 1Password; static provenance (drop `timestamp()`) |
| D12 | Backup tools | backrest + duplicati + backup-client **REMOVED** (PBS replaces them, off-box); `enable_backup_stack` retired; wazuh + semaphore pruned |

## 3. Live ground truth (audited 2026-06-06)

- **AWS backend (confirmed reachable as `fcx-sso` → assume `OrganizationAccountAccessRole` into `065094257518`):**
  - Bucket `tmpx-tfstate-065094257518-use2` (us-east-2), SSE-KMS, versioning on, blocks SSE-C.
  - CMK `arn:aws:kms:us-east-2:065094257518:key/1d876310-c068-4204-aca3-d8585f477fda` (alias `alias/tmpx/tfstate`, enabled, no `ViaService`).
  - Exec role `tmpx-TerraformExecutionRole` exists. Org `o-79iidr1xir`; accounts: shared-services `065094257518`, security `827444110075`, log-archive `561517126525`, mgmt `452424739751`.
  - **No `onprem/*` state keys exist yet** → all 3 on-prem states are clean creates.
- **Repo (`main`, HEAD `f26d126`):** flat `terraform/`, local backend, **no `prevent_destroy` anywhere**. Providers: bpg/proxmox `0.107.0`, onepassword `~3.0`, ansible `~1.3.0`, tls `~4.0`, unifi `0.42.0-fcx1` (fork via filesystem mirror — DONE, carries forward).
- **UniFi fork:** `thisisbramiller/terraform-provider-unifi` `patches` branch → filesystem mirror `~/.terraform.d/plugins/tf.fusioncloudx.home/ubiquiti-community/unifi/0.42.0-fcx1/darwin_arm64`, h1-locked, `~/.terraformrc` filesystem_mirror. `build-unifi-provider.sh` is current; only the `terraform providers lock` call swaps to `tofu`.
- **Live VMs:** gitlab 1103, mealie 1104, tandoor 1105, immich 1106 (local-zfs), runitup 1111, postgresql LXC 2001, ubuntu-template 1000, opconnect VM 100 (snowflake), open-archiver LXC 101 (snowflake, EXCLUDE). backrest/duplicati off in dev.

## 4. Backend pattern (verbatim shape per state)

`tofu/compute/backend.tf` (network/opconnect identical except `key`):
```hcl
terraform {
  backend "s3" {
    bucket       = "tmpx-tfstate-065094257518-use2"
    key          = "onprem/proxmox/compute/terraform.tfstate"   # network|opconnect|compute
    region       = "us-east-2"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:us-east-2:065094257518:key/1d876310-c068-4204-aca3-d8585f477fda"
    use_lockfile = true
    assume_role  = { role_arn = "arn:aws:iam::065094257518:role/OrganizationAccountAccessRole" }
  }
}
```
`tofu/compute/encryption.tf` (fresh-state enforced AES-GCM; key provider assumes into shared-services itself):
```hcl
terraform {
  encryption {
    key_provider "aws_kms" "state" {
      kms_key_id  = "arn:aws:kms:us-east-2:065094257518:key/1d876310-c068-4204-aca3-d8585f477fda"
      key_spec    = "AES_256"
      region      = "us-east-2"
      assume_role = { role_arn = "arn:aws:iam::065094257518:role/OrganizationAccountAccessRole" }
    }
    method "aes_gcm" "default" { keys = key_provider.aws_kms.state }
    state { method = method.aes_gcm.default  enforced = true }
    plan  { method = method.aes_gcm.default  enforced = true }
  }
}
```
**No `aws` provider in any config** — AWS is only the state backend + state-encryption key provider. Operator runs as `fcx-sso` (clear `~/.aws/cli/cache` after any SSO start-URL change). **Dependency note resolved:** S3 is up, so we wire it directly (no local-now-migrate-later interim).

## 5. Target tree (A3, apps=VM)

```
onprem-infra/
├── .tofurc                       # committed: filesystem_mirror + direct exclude for the unifi fork
├── .gitignore                    # *.tfstate* *.tfplan* *.auto.tfvars *.tfvars .terraform/
├── modules/
│   ├── proxmox-vm/   (main/variables/outputs.tf)
│   ├── proxmox-lxc/
│   ├── cloud-init/
│   ├── unifi-host/               # unifi_client reservation + unifi_dns_record (reads network_id)
│   └── op-secret/                # ephemeral key/password -> 1Password write-only (value_wo)
├── tofu/
│   ├── network/                  # STATE onprem/proxmox/network — THIN
│   │   ├── backend.tf providers.tf encryption.tf
│   │   ├── network.tf            # data "unifi_network" homelab (stable id) ; dns-zone records
│   │   └── outputs.tf            # homelab_network_id (+ zone), STABLE IDs only
│   ├── opconnect/                # STATE onprem/proxmox/opconnect — secrets root
│   │   ├── backend.tf providers.tf encryption.tf
│   │   ├── opconnect.tf          # proxmox-vm module (VMID 1101) + op-secret ; prevent_destroy
│   │   └── outputs.tf
│   └── compute/                  # STATE onprem/proxmox/compute — A3 one state
│       ├── backend.tf providers.tf encryption.tf
│       ├── remote-state.tf       # data.terraform_remote_state.network (stable IDs)
│       ├── locals.tf             # enabled_app_configs + disabled_workloads toggle
│       ├── templates.tf          # ubuntu (9001) + debian-lxc (9101)        ┐ SHARED ROOT
│       ├── ssh-keys.tf           # ephemeral tls_private_key -> value_wo 1P  │
│       ├── ansible-inventory.tf  # for_each ALL compute -> 1 inventory       ┘
│       ├── gitlab.tf             # proxmox-vm (1201) ; prevent_destroy
│       ├── postgresql.tf         # proxmox-lxc (2101) ; prevent_destroy
│       ├── mealie.tf             # proxmox-vm (1301) ; disposable
│       ├── tandoor.tf            # proxmox-vm (1302) ; disposable
│       ├── immich.tf             # proxmox-vm (1303, local-zfs) ; disposable
│       └── runitup.tf            # proxmox-vm (1304) ; disposable
└── ansible/                      # SERVICE IDENTITY lives here
    ├── roles/{docker,certificates,postgresql,gitlab,immich,mealie,tandoor,runitup,opconnect,nfs_mount,ssh-key-loader,common}/
    ├── playbooks/{site,gitlab,postgresql,opconnect,...}.yml
    └── inventory/                # cloud.terraform plugin -> project_path ../tofu/compute
```

**Seam:** `compute` reads `network` via `terraform_remote_state` — stable IDs only (`homelab_network_id`), never live IPs. Each service `.tf` calls `proxmox-vm`/`proxmox-lxc` + `cloud-init` + `unifi-host` (per-VM reservation+DNS, live-sourced IP) + `op-secret`. `ansible-inventory.tf` aggregates ALL compute via `for_each`. `prevent_destroy` is a static literal on the named gitlab/postgresql resources (extracted OUT of the disposable for_each).

**VMID map (Scheme B):** ubuntu-template `9001`, debian-lxc-template `9101`, opconnect `1101`(VM core-infra), postgresql `2101`(LXC core-infra), gitlab `1201`(VM platform), mealie `1301` / tandoor `1302` / immich `1303` / runitup `1304` (VM apps).

**Storage:** all OS/app/DB disks → `local-zfs`; immich photo library → UNAS NFS (in-guest mount via `nfs_mount`). Databases never on NFS.

## 6. opconnect stack (D7/D8)

`tofu/opconnect/` (SA-token auth — `OP_SERVICE_ACCOUNT_TOKEN`, NOT Connect; you cannot make Connect with Connect):
- `proxmox-vm` module → VM 1101, cloud-init (ansible user + key), `lifecycle { prevent_destroy = true }`.
- Ansible `opconnect` role: install Docker (shared `docker` role), bring up `1password/connect-api` + `1password/connect-sync` via Docker Compose (port 8080), mount `1password-credentials.json`, persist sync data volume. Credentials + token generated out-of-band via `op connect server create` / `op connect token create` (SA-token), delivered to the VM (1Password item or operator-staged file).
- **Cutover (P4, late):** stand up 1101 + fresh Connect server/token → verify it serves a test secret → repoint `OP_CONNECT_HOST`/`OP_CONNECT_TOKEN` (the on-prem 1Password provider + the `ssh-key-loader` role) → decommission old VM 100. Old 100 stays as fallback until the new one is proven.

## 7. Ansible restructure

- **Extract shared `docker` role** (Docker CE install duplicated in mealie/tandoor/immich/backrest/duplicati + runitup variant) → app roles depend on it via `meta/main.yml`.
- **certificates role — VERIFY FIRST.** The live fleet serves a valid `*.fusioncloudx.home` cert today, so before "fixing" the `server-cert.pem`/`server-key.pem` loop over `intermediate_ca_files`, inspect the live 1Password Int-CA-Bundle item (does it contain `server-cert.pem`/`server-key.pem`?). Fix the loop only if genuinely broken; otherwise leave + document. Do not break a working cert path.
- **Remove** roles `backrest`, `duplicati`, `backup-client`; `host_vars/backrest.yml`; the site.yml backup-client/backrest/duplicati plays; `duplicati.yml`.
- **Delete dead cruft:** `group_vars/vault.yml` (plaintext `ChangeMe_*`), `setup-vault.sh`, `.vault_pass.template`, `update-inventory.*.legacy`, `1PASSWORD_MIGRATION.md`, `test-1password-connect.*`.
- **Harden:** `ssh-key-loader` `/tmp` key → `mktemp` 0600; reconsider `host_key_checking=False` → `accept-new`; `bootstrap.yml hosts: postgresql` stays (only the LXC needs the raw python3/sudo bootstrap; apps are VMs with cloud-init).
- **Inventory:** `cloud.terraform.terraform_provider` `project_path: ../terraform` → `../tofu/compute`; keep `search_child_modules: false`; clear the inventory cache.
- **Inventory truthy-string fix:** `ansible-inventory.tf` `try(…, "IP not available")` → null/omit so Jinja `default()` engages (the `.90` role-default is already name-based + correct).

## 8. Footgun catalog (apply in the rebuild)

1. Private keys in state → `ephemeral` + `value_wo` + S3+CMK encrypted state.
2. `.gitignore` hardening **before** any `tofu/**` could leak state (currently only `tfplan`).
3. Inventory truthy-`try()` → null failure path (§7).
4. `mac_addresses[1]` single-NIC assumption → pass MAC explicitly at the `unifi-host` module call.
5. proxmox `insecure=false` is already set; Day-0 PKI delivers the node cert (bootstrap repo phases 04/13) — keep `insecure=false`.
6. Guest-agent IP race → settle/`wait_for_agent` before DNS resources read `ipv4_addresses`.
7. Fresh `tofu init` (do NOT copy fossil `.terraform/` providers).
8. `timestamp()` in 1P `note_value` → static provenance string.
9. `dev.auto.tfvars` gitignored (already covered once `*.tfvars` lands in `.gitignore`).
10. `devices.yaml` NAS `.50`→`.137` reconcile (the three `.137` NFS refs) — DEFERRED with the broader NFS work, not this restructure.

## 9. Phased rollout

Each phase: branch → atomic commits → `/requesting-code-review` (3-dim Workflow) → push → `@claude` PR review → `/receiving-code-review` (triage/fix) → test gate → merge → its ClickUp story `to do`→`in progress`→`complete`. **Confirm before any destructive `apply`.**

- **P0 — Hygiene + OpenTofu swap** (`chore/p0-hygiene-opentofu`). gitignore harden; delete dead cruft; archive Semaphore docs (`docs/CONTROL-PLANE.md`, `QUICK-START-CONTROL-PLANE.md`, `E2E-TEST-PLAN.md`) → `docs/archive/`; fix README merge-conflict (line 319); `terraform`→`tofu` in `build-unifi-provider.sh`/`check-infrastructure.sh`/`setup-infrastructure-ssh-key.sh`/`lxc-post-start-setup.sh`; `required_version >= 1.8`; committed repo-root `.tofurc`; regenerate `.terraform.lock.hcl` multi-platform (`darwin_arm64` + `linux_amd64`). **Gate:** `tofu init` + `validate` + `plan` = no-op on the existing flat config. No apply.
- **P1 — Kill backup stack + prune vestigial** (`refactor/p1-kill-backup-stack`). Remove backrest+duplicati (vm_configs/for_each, 4 1P items, `tls_private_key.backrest`); retire `enable_backup_stack` + `backup_stack_members`; prune wazuh DB user + wazuh database + semaphore; delete the Ansible backup roles/host_vars/plays. **Gate:** `tofu apply` (flat) + `ansible-playbook site.yml` green + Playwright spot-check a surviving app.
- **P2 — Ansible structural cleanups** (`refactor/p2-ansible-cleanups`). Shared `docker` role; certificates verify-then-fix; ssh-key-loader `mktemp`; `host_key_checking` reconsider. **Gate:** `ansible-playbook site.yml` green + Playwright.
- **P3 — Author the new tofu tree (no cutover)** (`feat/p3-tofu-tree`; may split P3a modules+network / P3b compute / P3c opconnect). Author `modules/` + `tofu/network` (thin) + `tofu/compute` (per-service, VMID renumber, ephemeral tls, prevent_destroy gitlab+postgresql, static provenance, inventory fix, S3 backend+encryption) + `tofu/opconnect`. Old flat `terraform/` still governs the live fleet. **Gate:** `tofu init`(S3)+`validate`+`plan` clean for each state; apply **network/** only (thin/near-no-op so its outputs exist in S3 for compute's remote_state).
- **P4 — opconnect cutover** (`feat/p4-opconnect-cutover`). Stand up new opconnect 1101 + Connect; verify a test secret; repoint `OP_CONNECT_HOST`/`OP_CONNECT_TOKEN`; decommission old VM 100. **Gate:** new Connect serves a secret before old 100 retired.
- **P5 — compute cutover (destructive, controlled)** (`feat/p5-compute-cutover`). Back up flat state → `tofu destroy` the flat fleet → `tofu apply` network→compute → `ansible-playbook site.yml` → full Playwright verify (desktop + mobile, every service) → remove the flat `terraform/` files → `prevent_destroy` locks now live. **Gate:** full e2e green; **confirm before destroy**. ⚠️ NFS reconcile hang (#18) is re-exercised here — watch it.
- **P6 — Operator/doc finalize** (`chore/p6-operator-docs`). `check-infrastructure.sh` remote-state; `README.md`/`CLAUDE.md` `cd terraform`→`cd tofu/compute`; residual stale-doc archival; `.tofurc`/CI-portability note; carry-forward guardrail comment block.

A1 per-service-state carve-out (via `tofu state mv` + the `community.general.proxmox` dynamic-inventory plugin) is the documented GROWTH PATH — NOT built now.

## 10. ClickUp integration

Board: **`🧱 onprem-infra · OpenTofu Greenfield Restructure`** (list `901417076449`, Infrastructure & Operations space). 11 completed + 6 open backlog stories already reflected. Each phase P0–P6 gets a story; status moves `to do`→`in progress`→`complete` as the phase progresses. New work discovered mid-flight → new stories.

## 11. Guardrails / out of scope

- **GREENFIELD:** destroy/recreate freely; no `moved` blocks. Plan→review→apply; never leave the fleet half-broken.
- **Do NOT** touch AWS (consume the backend only), migrate the repo to GitLab / change the remote, wire the bootstrap-repo conductor seam, or author the UDM fabric (VLANs/firewall/WiFi — separate Network-as-Code/UDM-reflash effort).
- **No `Co-Authored-By: Claude` trailer** on commits (Branden's personal repo).
- open-archiver LXC 101 + the `devices.yaml .50→.137` reconcile + the NFS-reconcile-hang deep fix (#18) = out of scope (noted, not fixed here).

## 12. Acceptance criteria

- `tofu/network` + `tofu/opconnect` + `tofu/compute` + `modules/` exist; `tofu validate` + `tofu plan` clean.
- Engine = OpenTofu; UniFi fork resolves via `.tofurc` filesystem mirror + h1 lock.
- `backend "s3"` + `encryption.tf` wired to the live bucket/CMK; state lands at `onprem/proxmox/{network,opconnect,compute}`.
- VMID Scheme B applied; `prevent_destroy` on gitlab + postgresql + opconnect.
- opconnect stack creates Connect via the SA token; Day-2 consumes via Connect; old VM 100 decommissioned only after the new one is verified.
- `ephemeral tls_private_key` → no private keys in state.
- `disabled_workloads=["mealie"]` destroys only mealie (disposable toggle intact); backup-stack toggle retired.
- Ansible cleanups + the §8 footgun catalog applied.
- Each phase merged via the full review lifecycle; ClickUp stories tracked.
