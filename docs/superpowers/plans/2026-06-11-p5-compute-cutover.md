# P5 — Compute Cutover + Full Bare-Command Hardening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` (inline) — this is a sequential live-infra runbook, not parallelizable code. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Cut the live fleet over from the legacy flat `terraform/` tree to the `tofu/compute` three-state tree, and make every `tofu`/`ansible-playbook` invocation work as a **bare command** (no `-var`, `-backend-config`, `-input`, `-i`, `TF_CLI_CONFIG_FILE=` prefix, `-chdir`, or `-parallelism`).

**Architecture:** The injection surface is already ~95% ambient via `~/.zprofile` + `~/.terraformrc`. The one missing piece is `AWS_PROFILE`. Cutover is forced **sequential** (destroy legacy → apply new) because both trees own the same UniFi DNS names + client reservations, even though VMIDs don't collide. Greenfield, no production data except opconnect (reproducible) — destroying is explicitly authorized.

**Tech stack:** OpenTofu 1.12 (S3 + SSE-KMS + native `aes_gcm` encryption), bpg/proxmox, patched ubiquiti-community/unifi fork (filesystem mirror), Ansible (cloud.terraform dynamic inventory), 1Password Connect (secrets root on VM 1101).

---

## Bare-command convention (the contract this plan enforces)

- **Working directory is context, not a parameter:** `cd tofu/compute && tofu apply` (never `tofu -chdir=…`).
- **Everything else is ambient:** all provider auth (`PROXMOX_VE_API_TOKEN`, `UNIFI_API_KEY`, `OP_CONNECT_HOST/TOKEN`, `TF_VAR_onepassword_vault_id`, `SSH_AUTH_SOCK`) is already exported in `~/.zprofile`; the UniFi fork mirror is auto-discovered via `~/.terraformrc`; S3 backend + KMS auth come from `AWS_PROFILE` (added in Task 1).
- **`tofu apply` stays interactive** (prompts for `yes`) — no `-auto-approve`. For automated execution the prompt is answered via stdin (`printf 'yes\n' | tofu apply`); the repo command itself stays bare.
- **Prerequisite each session:** `aws sso login --profile fcx-sso` (SSO token lasts ~12h). This is session bootstrap, not per-command injection.

## Verified facts (grounded 2026-06-11)

- `~/.terraformrc` already carries the fork `filesystem_mirror` → bare `tofu` resolves `tf.fusioncloudx.home/ubiquiti-community/unifi` locally with no `TF_CLI_CONFIG_FILE`. `~/.tofurc` does not exist; the repo-root `.tofurc` is **not** auto-discovered (CI-only).
- `~/.zprofile` exports everything **except** `AWS_PROFILE`. AWS SSO session is currently **expired**.
- AWS profile = `fcx-sso` (sso account 452424739751) → backend `assume_role` hops to `065094257518/OrganizationAccountAccessRole`.
- **Legacy VMIDs:** gitlab 1103, mealie 1104, tandoor 1105, immich 1106, runitup 1111, postgresql LXC 2001. **New VMIDs:** gitlab 1201, postgresql 2101, mealie 1301, tandoor 1302, immich 1303, runitup 1304. **Zero collision.**
- Both trees manage identical UniFi hostnames + client reservations → **destroy legacy before apply new** (sequential).
- Legacy `terraform/` tree has **no `prevent_destroy`** → clean teardown. New tree's `prevent_destroy` does not block first CREATE.
- The UniFi fork's logger-concurrency fix (v0.42.0-fcx1) is in the lockfile → **default parallelism is safe** (drop `-parallelism=1`).
- `tofu/compute/.terraform` has provider/module cache only — needs `tofu init` to bind the S3 backend.
- opconnect (1101) lives in a separate state — compute apply/destroy never touches it; it must stay **up** during the cutover (compute + ansible read secrets through Connect).

## File-structure map

| File | Change |
|------|--------|
| `~/.zprofile` | add `export AWS_PROFILE=fcx-sso` (the one param-free gap) |
| `tofu/opconnect/variables.tf` | (no change) `opconnect_dns_name` already `default = "opconnect"` → bare apply needs no `-var` |
| `tofu/opconnect/opconnect.tf` | explicit `on_boot = true` + snapshot-backup comment |
| `.tofurc` | fix the stale "use TF_CLI_CONFIG_FILE" comment (clarify local vs CI) |
| `ansible/inventory/terraform.yml` | `project_path: ../terraform` → `../tofu/compute` |
| (live infra) | `tofu destroy` legacy fleet → `tofu apply` compute → `ansible-playbook site.yml` |

---

## Task 1 — Param-free enablement (non-destructive, reversible)

**Files:** `~/.zprofile`, `tofu/opconnect/terraform.auto.tfvars` (create), `.tofurc`

- [ ] **1.1 — Add `AWS_PROFILE` to `~/.zprofile`.** Append after the existing exports:
  ```bash
  # AWS profile for the on-prem-infra S3+KMS state backend (assume-role to 065094257518).
  # fcx-personal-project specific. Run `aws sso login --profile fcx-sso` once per ~12h session.
  export AWS_PROFILE=fcx-sso
  ```
- [ ] **1.2 — No change needed for `opconnect_dns_name`.** `tofu/opconnect/variables.tf:37` already `default = "opconnect"` (canonical). Bare `tofu apply` uses it with no `-var` — the P4 `-var opconnect_dns_name=opconnect-new` was a one-time cutover override, and `opconnect-new` is now retired. (An `*.auto.tfvars` would be gitignored by the tfvars-hygiene rule anyway, so don't add one.)
- [ ] **1.3 — Fix the stale `.tofurc` comment.** Replace the "Use explicitly with: TF_CLI_CONFIG_FILE=…" line with: local runs auto-discover `~/.terraformrc` (no flag); `TF_CLI_CONFIG_FILE=$PWD/.tofurc` is only for CI / fresh machines without `~/.terraformrc`.
- [ ] **1.4 — Commit** (repo files only; `~/.zprofile` is not in-repo):
  ```bash
  git add tofu/opconnect/terraform.auto.tfvars .tofurc
  git commit -m "feat(p5): bare-command enablement — opconnect auto.tfvars + .tofurc comment"
  ```
- [ ] **1.5 — Operator step:** open a fresh shell and run `aws sso login --profile fcx-sso` (browser auth). Verify: `aws sts get-caller-identity` returns account `452424739751`.

## Task 2 — opconnect 1101 availability hardening (P5.0 gate, harness #46)

**Files:** `tofu/opconnect/opconnect.tf`

- [ ] **2.1 — Make `on_boot` explicit** in the `module "opconnect"` call (module default is already `true`; make the intent explicit + document backup mode):
  ```hcl
  on_boot = true # secrets-root MUST auto-start after a node reboot
  # DR note: back up 1101 with snapshot-mode (vzdump default), NEVER --mode stop
  # (the opconnect-cutover runbook's --mode stop was for decommissioning old VM 100 only).
  ```
- [ ] **2.2 — Plan (bare) and confirm in-place update, not replace:**
  ```bash
  cd "$REPO/tofu/opconnect" && tofu init && tofu plan
  ```
  **Expected:** `0 to add, 1 to change, 0 to destroy` (in-place `on_boot` update on VM 1101). If it shows `1 to destroy`/replace, STOP — do not apply.
- [ ] **2.3 — Apply** (interactive `yes`): `tofu apply`. **Expected:** `Apply complete! Resources: 0 added, 1 changed, 0 destroyed.`
- [ ] **2.4 — Verify 1101 is up + Connect serving:** `curl -fsS "$OP_CONNECT_HOST/heartbeat"` returns `.`; the onepassword provider can read a secret. Commit:
  ```bash
  cd "$REPO" && git add tofu/opconnect/opconnect.tf
  git commit -m "feat(p5): explicit on_boot=true on opconnect 1101 + snapshot-backup note"
  ```

## Task 3 — Repoint Ansible inventory (P5.1, harness #47)

**Files:** `ansible/inventory/terraform.yml:12`

- [ ] **3.1 — Edit line 12:** `project_path: ../terraform` → `project_path: ../tofu/compute`. (`binary_path: tofu` already correct.)
- [ ] **3.2 — Commit** (graph verification deferred to Task 7, after compute state has resources):
  ```bash
  git add ansible/inventory/terraform.yml
  git commit -m "feat(p5): repoint ansible dynamic inventory to tofu/compute"
  ```

## Task 4 — Pre-flight + legacy state backup (P5.1)

**Files:** none (read-only + backup)

- [ ] **4.1 — Back up the legacy local state** (greenfield safety):
  ```bash
  cp "$REPO/terraform/terraform.tfstate" "$HOME/onprem-flat-state-backup-$(date +%Y%m%d-%H%M%S).tfstate"
  ```
- [ ] **4.2 — Pre-flight checks (all must pass):**
  - Legacy template VMID ≠ 9001: `grep -n vm_id "$REPO/terraform/ubuntu-template.tf"` — confirm it is NOT 9001 (so legacy destroy can't remove the network-owned template). If it IS 9001, STOP and reassess.
  - opconnect 1101 up (Task 2.4 passed).
  - `aws sts get-caller-identity` OK (Task 1.5).
- [ ] **4.3 — Init + plan the new compute tree (bare):**
  ```bash
  cd "$REPO/tofu/compute" && tofu init && tofu plan
  ```
  **Expected:** init binds the S3 backend from the filesystem mirror (no registry/dev_overrides warning); plan = `N to add, 0 to change, 0 to destroy` (empty state → all creates: 6 VMs/LXC + cloud-init + unifi clients/records + ansible inventory). Capture as evidence.

## Task 5 — Destroy the legacy fleet (destructive — authorized)

**Files:** none (live infra; legacy uses LOCAL state, no AWS needed — Proxmox/UniFi auth is ambient)

- [ ] **5.1 — Show the destroy plan:**
  ```bash
  cd "$REPO/terraform" && tofu init && tofu plan -destroy
  ```
  **Expected:** destroys gitlab(1103)/mealie(1104)/tandoor(1105)/immich(1106)/runitup(1111) VMs + postgresql(2001) LXC + their `unifi_client`/`unifi_dns_record` entries + cloud-init snippets + `tls_private_key`. No `prevent_destroy` blocks.
- [ ] **5.2 — Destroy** (answer `yes`): `tofu destroy`. **Expected:** `Destroy complete! Resources: N destroyed.` This frees the UniFi hostnames + client reservations for the new tree.

## Task 6 — Apply the new compute fleet (destructive-create — authorized)

**Files:** none (live infra; `tofu/compute` S3 state — needs `AWS_PROFILE` + SSO session)

- [ ] **6.1 — Apply** (default parallelism; answer `yes`):
  ```bash
  cd "$REPO/tofu/compute" && tofu apply
  ```
  **Expected:** creates VMs 1201/1301/1302/1303/1304 + LXC 2101 + cloud-init + `unifi_client` reservations + `unifi_dns_record` A records (now pointing at the new IPs) + the ansible inventory resource. `prevent_destroy` on gitlab(1201)/postgresql(2101) engages for future destroys. `Apply complete!`
- [ ] **6.2 — Settle check:** each VM/LXC reports a guest-agent IP; UniFi DNS A records resolve: `for h in gitlab postgresql mealie tandoor immich runitup; do dig +short $h.fusioncloudx.home; done` returns the new IPs.

## Task 7 — Provision the rebuilt fleet (Ansible, bare)

**Files:** none (live infra)

- [ ] **7.1 — Verify the repointed inventory resolves the NEW fleet:**
  ```bash
  cd "$REPO/ansible" && ansible-inventory --graph
  ```
  **Expected:** all six hosts listed with the new IPs from `tofu/compute` state (no `../terraform` references).
- [ ] **7.2 — Run the site playbook (bare — no `-i`, no `-e`):**
  ```bash
  cd "$REPO/ansible" && ansible-playbook playbooks/site.yml
  ```
  **Expected:** docker role, certificates (via Connect), per-service deploys all green. ⚠️ **Watch the immich UNAS NFS mount** (`.137`) — known reconcile-hang risk (harness #18); if it hangs, halt and diagnose (do not force).

## Task 8 — Verify / test (P5.3 + P5.5, harness #49)

**Files:** none (verification)

- [ ] **8.1 — Idempotency proof:** `cd "$REPO/tofu/compute" && tofu plan` → **`No changes`**. Same for `tofu/network` and `tofu/opconnect`.
- [ ] **8.2 — Per-service reachability:** each of gitlab/mealie/tandoor/immich/runitup loads over HTTPS by hostname with a valid cert (Playwright desktop + mobile viewport); a write/persist smoke where applicable.
- [ ] **8.3 — Secrets path:** confirm a service that reads a generated secret (e.g. postgres-backed app) came up → proves Connect served secrets during the cutover.
- [ ] **8.4 — Bare-command acceptance:** in a fresh shell (only `aws sso login` run), confirm `cd tofu/network && tofu plan`, `cd tofu/opconnect && tofu plan`, `cd tofu/compute && tofu plan`, and `cd ansible && ansible-playbook playbooks/site.yml --check` all run with **zero flags**. This is the param-free acceptance gate (closes harness #62).
- [ ] **8.5 — Mark complete:** harness #46/#47/#48/#49/#62 done. Legacy `terraform/` deletion stays for P6 (#56) — do NOT delete here.

---

## Self-review

- **Spec coverage:** Task 1 = param-free enablement (AWS_PROFILE + opconnect auto.tfvars + .tofurc) ✓; Task 2 = opconnect hardening (#46) ✓; Task 3 = inventory repoint (#47) ✓; Tasks 5–6 = destroy/apply (#48) ✓; Tasks 7–8 = provision + verify (#49) ✓; Task 8.4 = bare-command acceptance (#62) ✓. Full param-free scope: network (8.4), opconnect (1.2, 8.4), compute (4.3, 8.4) all covered.
- **Sequencing:** destroy (Task 5) strictly before apply (Task 6) — DNS/client collision honored. opconnect untouched by compute. Legacy backup (4.1) before destroy.
- **Param leakage scan:** every `tofu`/`ansible-playbook` command in the plan is bare (`cd <stack> && tofu <verb>`); no `-var`/`-chdir`/`-input`/`-backend-config`/`-i`/`-e`/`-parallelism`. The only `-destroy` is on `tofu plan -destroy` (a read-only preview flag, not a mutation parameter) — the mutation is bare `tofu destroy`.
- **Rollback:** if Task 6 apply fails midway → `tofu destroy` compute, then `cd terraform && tofu apply` restores legacy from the backed-up state (Task 4.1).
