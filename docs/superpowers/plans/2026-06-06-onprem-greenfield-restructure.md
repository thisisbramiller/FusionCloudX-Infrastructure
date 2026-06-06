# onprem-infra Greenfield Restructure — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development` (P3+) or inline execution (P0–P2) to implement this plan phase-by-phase. Steps use checkbox (`- [ ]`) syntax. Spec: `docs/superpowers/specs/2026-06-06-onprem-greenfield-restructure-design.md`.

**Goal:** Restructure the on-prem `onprem-infra` repo into the locked target architecture — OpenTofu, 3-state split (network/opconnect/compute), A3 per-service modules, S3+CMK backend, VMID Scheme B (apps=VM), ephemeral secrets, backup-stack removed — executed as iterative phased PRs that each leave the fleet working.

**Architecture:** OpenTofu against Proxmox (bpg) + UniFi (maintained fork via filesystem mirror) + 1Password + Ansible. State in S3 (`tmpx-tfstate-065094257518-use2`, `onprem/proxmox/<stack>`) with native AES-GCM encryption, assuming `OrganizationAccountAccessRole` into shared-services as `fcx-sso`. Greenfield: destroy/recreate freely; `prevent_destroy` is the going-forward seatbelt.

**Tech Stack:** OpenTofu ≥1.8, bpg/proxmox 0.107.0, ubiquiti-community/unifi 0.42.0-fcx1 (fork), 1Password/onepassword ~3.0, ansible/ansible ~1.3.0, hashicorp/tls ~4.0 (ephemeral), Ansible + 1Password Connect, S3+KMS backend.

---

## Per-phase ritual (every phase P0–P6 follows this)

1. `git checkout main && git pull --ff-only` → `git checkout -b <phase-branch>`.
2. Move the phase's ClickUp story (board `901417076449`) `to do` → `in progress`.
3. Implement the phase's tasks as **atomic commits** (no `Co-Authored-By: Claude` trailer — personal repo).
4. **In-cycle test gate — read-only, BEFORE merge:** `tofu fmt -check -recursive` + `tofu validate` + `tofu plan` (against the live fleet, matching the deployed profile via `-var`). App phases also: `ansible-playbook --syntax-check` / `--check`. Post the results to the PR — **testing is part of every PR cycle.**
5. `/requesting-code-review` (3-dimension Workflow: correctness/security/conventions) → fix Critical/Important.
6. `git push -u origin <branch>` → `gh pr create` → comment `@claude` for the bot review → wait → `/receiving-code-review` (triage; fix or push back with reasoning).
7. Re-run the in-cycle gate if changes were made → merge when green (`gh pr merge --merge --delete-branch`) → `git checkout main && git pull --ff-only`.
8. **Post-merge apply — mutating, from `main`, BEFORE the next phase:** `tofu apply` (matching the deployed profile via `-var`) + (app phases) `ansible-playbook site.yml` + Playwright verify (desktop+mobile). Applies MERGED code to the live fleet → live always equals `main`, and each phase branches off a freshly-applied baseline. **Confirm before any destructive apply (esp. P5).** ⚠️ `dev.auto.tfvars` may carry a stale `disabled_workloads` — always apply with an explicit profile that matches the live fleet.
9. Move the ClickUp story → `complete`. Mark the harness task done.

**Plan-expansion rule:** P0–P2 tasks below are complete + executable now. P3–P6 are task lists with files + actions + gates; expand each to bite-sized steps (full HCL/YAML) **at the start of that phase** via `superpowers:writing-plans`, because later-phase content depends on the modules + state shape produced earlier.

---

## Phase P0 — Hygiene + OpenTofu engine swap

**Branch:** `chore/p0-hygiene-opentofu` · **ClickUp:** P0 story · **No infra topology change.**

**Files:**
- Modify: `.gitignore`, `terraform/.gitignore`
- Delete: `ansible/group_vars/vault.yml`, `ansible/setup-vault.sh`, `ansible/.vault_pass.template`, `ansible/update-inventory.ps1.legacy`, `ansible/update-inventory.sh.legacy`, `ansible/1PASSWORD_MIGRATION.md`, `ansible/test-1password-connect.ps1`, `ansible/test-1password-connect.sh`
- Move: `docs/CONTROL-PLANE.md`, `docs/QUICK-START-CONTROL-PLANE.md`, `docs/E2E-TEST-PLAN.md` → `docs/archive/`
- Modify: `README.md` (merge-conflict marker ~L319), `scripts/build-unifi-provider.sh`, `check-infrastructure.sh`, `scripts/setup-infrastructure-ssh-key.sh`, `scripts/lxc-post-start-setup.sh`
- Create: `.tofurc`

- [ ] **P0.1 — Verify dead-cruft is unreferenced before deleting.** `grep -rn "vault.yml\|vault_pass\|setup-vault\|update-inventory\|test-1password-connect\|1PASSWORD_MIGRATION" ansible/ *.md docs/ .github/`. Confirm `group_vars/vault.yml` is NOT in any `vars_files`/`group_vars/all/` auto-load path (it's a bare `group_vars/vault.yml`, no `vault` group exists → dead). If any live reference, stop + reassess. Expected: only self-references.
- [ ] **P0.2 — Harden `.gitignore`.** Ensure (root and/or `terraform/`) excludes: `*.tfstate*`, `*.tfplan*`, `*.tfvars`, `*.auto.tfvars`, `.terraform/`, `*.tar`. Keep a tracked example: rename/keep `terraform/terraform.auto.tfvars` → `terraform/terraform.auto.tfvars.example` (vault_id is commented anyway) and add `!*.example`. Commit. Verify `git status` shows no `*.tfstate`/`*.tfvars` tracked.
- [ ] **P0.3 — Delete dead cruft** (the 8 files in P0.1, once confirmed unreferenced). Commit `chore(ansible): remove dead vault/1Password-migration/legacy cruft`.
- [ ] **P0.4 — Archive stale Semaphore docs.** `mkdir -p docs/archive`; `git mv` the 3 control-plane/E2E docs into it; prepend a one-line "ARCHIVED (Semaphore removed; GitLab CI/CD)" note. Commit.
- [ ] **P0.5 — Fix README merge-conflict.** Open `README.md` ~L307–319; remove the `>>>>>>> origin/main` marker + dedupe the two footer blocks (keep the 2026-02-02 block). Commit.
- [ ] **P0.6 — Create repo-root `.tofurc`** mirroring `~/.terraformrc`:
  ```hcl
  provider_installation {
    filesystem_mirror {
      path    = "/Users/fcx/.terraform.d/plugins"
      include = ["tf.fusioncloudx.home/ubiquiti-community/unifi"]
    }
    direct {
      exclude = ["tf.fusioncloudx.home/ubiquiti-community/unifi"]
    }
  }
  ```
  Note in a comment: consumed via `TF_CLI_CONFIG_FILE=$PWD/.tofurc` (CI portability); the global `~/.terraformrc` continues to work locally. Commit.
- [ ] **P0.7 — `terraform`→`tofu` in scripts.** `scripts/build-unifi-provider.sh`: `terraform providers lock` → `tofu providers lock`. `check-infrastructure.sh`: `terraform`→`tofu` (binary + messages), keep `cd terraform` for now (path changes in P6). `scripts/setup-infrastructure-ssh-key.sh` + `scripts/lxc-post-start-setup.sh`: swap any `terraform` refs. Commit `chore(scripts): swap terraform CLI -> tofu`.
- [ ] **P0.8 — Regenerate the lockfile multi-platform.** In `terraform/`: `TF_CLI_CONFIG_FILE=../.tofurc tofu providers lock -fs-mirror="$HOME/.terraform.d/plugins" -platform=darwin_arm64 -platform=linux_amd64` (writes `darwin_arm64`+`linux_amd64` h1: for all providers incl. the unifi fork). Commit `chore(tofu): multi-platform provider lock`.
- [ ] **P0.9 — TEST GATE.** `cd terraform && TF_CLI_CONFIG_FILE=../.tofurc tofu init && tofu validate && tofu plan`. **Expected:** init OK from the filesystem mirror (no dev_overrides warning), validate clean, **`plan` = No changes** (P0 touched no resources). Capture output as evidence.
- [ ] **P0.10 — Review lifecycle + merge** (per-phase ritual steps 5–8).

## Phase P1 — Kill backup stack + prune vestigial

**Branch:** `refactor/p1-kill-backup-stack` · Subtractive; flat config stays working.

**Tasks (files → action → gate):**
- [ ] **P1.1 TF:** `variables.tf` — remove `backrest`+`duplicati` from `vm_configs`; retire `enable_backup_stack` var + the `backup_stack_members` local + the `effective_disabled_workloads` backup branch (keep `disabled_workloads`). Remove the wazuh database from `postgresql_databases`.
- [ ] **P1.2 TF:** `ssh-keys.tf` — remove `tls_private_key.backrest`. `onepassword.tf` — remove `backrest_ssh_key`, `backrest_web_password`, `backrest_restic_password`, `duplicati_web_password`, `wazuh_db_user`. `outputs.tf` — drop the backrest/duplicati URL outputs + the removed 1P item refs.
- [ ] **P1.3 Ansible:** delete roles `backrest/`, `duplicati/`, `backup-client/`; delete `host_vars/backrest.yml`, `host_vars/duplicati.yml`; remove the backup-client + backrest + duplicati plays from `playbooks/site.yml`; delete `playbooks/duplicati.yml` (+ backrest/duplicati standalone playbooks if present). Remove `wazuh`/`semaphore` references from `group_vars/postgresql.yml`.
- [ ] **P1.4 GATE:** `tofu plan` shows only backrest/duplicati/wazuh removals (and they're already off in dev). Confirm → `tofu apply`. `ansible-playbook site.yml` green on the reduced fleet. Playwright spot-check one surviving app (e.g. mealie) loads over HTTPS.
- [ ] **P1.5** Review lifecycle + merge. ClickUp P1 → complete; close harness #4 (#4 backrest pg_dump obsoleted) + note #29 (vault.yml deleted in P0).

## Phase P2 — Ansible structural cleanups

**Branch:** `refactor/p2-ansible-cleanups` · Ansible-only; no rebuild.

**Tasks:**
- [ ] **P2.1** Create shared `roles/docker/` (the canonical Docker CE install: keyrings, repo, docker-ce + compose plugin, service enable). Add `dependencies: [{role: docker}]` to `mealie`, `tandoor`, `immich`, `runitup` `meta/main.yml`; delete the duplicated Docker blocks from each role's `tasks/main.yml`.
- [ ] **P2.2** certificates role — **VERIFY FIRST** (systematic-debugging): inspect the live 1Password Int-CA-Bundle item (does it carry files named `server-cert.pem`/`server-key.pem`? what are the actual filenames?). If the `loop: intermediate_ca_files` + `when: item.name == "server-cert.pem"` genuinely yields empty, fix the loop/source; if the live fleet's valid cert proves it works, leave it + add a clarifying comment. Document the finding in the PR.
- [ ] **P2.3** `roles/ssh-key-loader/`: write the temp key via `mktemp` (0600) instead of a fixed `/tmp/.ansible_ssh_key`; update `cleanup.yml`. `ansible.cfg`: evaluate `host_key_checking` → `accept-new` (vs `False`); leave `IdentitiesOnly=yes`.
- [ ] **P2.4 GATE:** `ansible-playbook site.yml --check` clean, then live `ansible-playbook site.yml` green (re-provision, no rebuild). Playwright spot-check.
- [ ] **P2.5** Review lifecycle + merge. ClickUp P2 → complete.

## Phase P3 — Author the new tofu tree (no cutover)

**Branch:** `feat/p3-tofu-tree` (split P3a/P3b/P3c if review prefers) · Old flat `terraform/` still governs the live fleet. **Use subagent-driven-development.**

**Tasks (expand to bite-sized at phase start):**
- [ ] **P3.1 `modules/`** — author thin reusable modules with clean interfaces:
  - `proxmox-vm` (inputs: vm_id, name, cores, memory_mb, datastore_id, cloud-init file ids, template id, MAC passthrough; outputs: id, ipv4, mac, name).
  - `proxmox-lxc` (inputs: vm_id, hostname, cores, memory_mb, disk_gb, template id, key; outputs: id, ipv4, mac, hostname).
  - `cloud-init` (inputs: hostname, ansible pubkey, extra packages; outputs: user_data + vendor_data file ids).
  - `unifi-host` (inputs: name, mac, fixed_ip, network_id; resources: `unifi_client` observe-then-pin `allow_existing=true` + `unifi_dns_record` A record `record_type="A"`; pass MAC explicitly).
  - `op-secret` (inputs: title/vault/fields; ephemeral key/password → `value_wo` to 1Password; outputs: item id, public key).
- [ ] **P3.2 `tofu/network/`** — `backend.tf`+`encryption.tf` (key `onprem/proxmox/network`), `providers.tf` (unifi only + default_tags), `network.tf` (`data "unifi_network"` homelab + DNS-zone records), `outputs.tf` (`homelab_network_id` + zone — stable IDs only). **Apply this state** (thin/near-no-op) so its outputs exist in S3.
- [ ] **P3.3 `tofu/compute/`** — `backend.tf`+`encryption.tf` (key `onprem/proxmox/compute`), `providers.tf` (proxmox+unifi+onepassword+ansible+tls, `insecure=false`), `remote-state.tf` (read network outputs), `locals.tf` (`enabled_app_configs` + `disabled_workloads`), `templates.tf` (9001/9101), `ssh-keys.tf` (ephemeral tls→value_wo), `ansible-inventory.tf` (for_each ALL compute → 1 inventory; **null failure-path** fix), per-service files `gitlab.tf`(1201, prevent_destroy), `postgresql.tf`(2101, prevent_destroy), `mealie.tf`(1301), `tandoor.tf`(1302), `immich.tf`(1303, local-zfs), `runitup.tf`(1304). Static provenance (no `timestamp()`). `wait_for_agent`/settle before unifi-host DNS. **Plan only** (fresh S3 state shows "N to add"; do NOT apply — flat root still owns the live fleet).
- [ ] **P3.4 `tofu/opconnect/`** — `backend.tf`+`encryption.tf` (key `onprem/proxmox/opconnect`), `providers.tf` (proxmox+onepassword via **SA token**+ansible+tls), `opconnect.tf` (proxmox-vm 1101 + cloud-init + `prevent_destroy` + op-secret), `outputs.tf`. **Plan only.**
- [ ] **P3.5 Ansible:** add `roles/opconnect/` (docker dep + Connect docker-compose: connect-api+connect-sync, port 8080, mount `1password-credentials.json`, sync volume); add `playbooks/opconnect.yml`. Repoint `inventory/terraform.yml` `project_path → ../tofu/compute`; `search_child_modules: false`; clear inventory cache.
- [ ] **P3.6 GATE:** per state, `TF_CLI_CONFIG_FILE` set, `tofu init`(S3)+`validate`+`plan` clean; network/ applied + outputs present in S3; compute/ + opconnect/ plans reviewed (expected creates, no errors). Per-task spec + code-quality review (subagent-driven).
- [ ] **P3.7** Review lifecycle + merge.

## Phase P4 — opconnect cutover (careful, late)

**Branch:** `feat/p4-opconnect-cutover` · Replace the live secrets root safely.

**Tasks:**
- [ ] **P4.1** `op connect server create` + `op connect token create` (SA token) → stage `1password-credentials.json` + token (1P item / operator file).
- [ ] **P4.2** Confirm → `tofu apply` `tofu/opconnect/` → VM 1101 up; `ansible-playbook opconnect.yml` brings up Connect (port 8080).
- [ ] **P4.3 GATE:** new Connect serves a test secret (`curl` /v1/vaults with the new token) **before** touching the old one.
- [ ] **P4.4** Repoint `OP_CONNECT_HOST`/`OP_CONNECT_TOKEN` (the on-prem 1Password provider env + `ssh-key-loader` role) to 1101; re-run a no-op `ansible-playbook site.yml` to confirm the fleet authenticates via the new Connect.
- [ ] **P4.5** Decommission old VM 100 (snowflake) only after the new path is proven. Review lifecycle + merge.

## Phase P5 — compute cutover (destructive, controlled)

**Branch:** `feat/p5-compute-cutover` · The one destructive rebuild. **Confirm before destroy.**

**Tasks:**
- [ ] **P5.1** Back up the flat local state (`cp terraform/terraform.tfstate ~/onprem-flat-state-backup-<stamp>.tfstate`).
- [ ] **P5.2** Confirm → `cd terraform && tofu destroy` the flat fleet (gitlab/mealie/tandoor/immich/runitup VMs + postgres LXC + their unifi clients/records). Greenfield: expected + fine.
- [ ] **P5.3** `cd tofu/compute && tofu apply` (network already applied; remote_state read OK) → new fleet at renumbered VMIDs with `prevent_destroy` on gitlab/postgresql.
- [ ] **P5.4** `cd ansible && ansible-playbook playbooks/site.yml` (inventory → `../tofu/compute`) → provision the rebuilt fleet. ⚠️ Watch the NFS reconcile (#18) on immich's UNAS mount — known hang risk; halt + diagnose if it hangs.
- [ ] **P5.5 GATE:** full Playwright verify — every service (gitlab, mealie, tandoor, immich, runitup) loads over HTTPS by hostname, **desktop + mobile viewport**, valid cert, write/persist smoke where applicable.
- [ ] **P5.6** Remove the flat `terraform/` files (now superseded); `prevent_destroy` locks are live. Review lifecycle + merge.

## Phase P6 — Operator/doc finalize

**Branch:** `chore/p6-operator-docs`

**Tasks:**
- [ ] **P6.1** `check-infrastructure.sh` — rewrite for remote (S3) state + `cd tofu/compute`.
- [ ] **P6.2** `README.md` + repo `CLAUDE.md` (+ `.github/` instructions if present) — every `cd terraform` → `cd tofu/compute`; document the 3-state layout + the `TF_CLI_CONFIG_FILE=$PWD/.tofurc` operator note + the `fcx-sso` backend auth.
- [ ] **P6.3** Archive any remaining stale docs; add the network spec's NEVER-touch guardrail list as a comment block where appropriate.
- [ ] **P6.4 GATE:** docs coherent; a fresh `cd tofu/compute && tofu init && tofu plan` from the README instructions works. Review lifecycle + merge. Update memory + write a Nexus session note.

---

## Out of scope (do NOT do here)
Author the UDM fabric (VLANs/firewall/WiFi — separate Network-as-Code/UDM-reflash effort); migrate the repo to GitLab / change remote; wire the bootstrap-repo conductor seam; touch AWS (consume the backend only); the NFS-reconcile-hang deep fix (#18 — surfaced at P5, fixed separately); `devices.yaml .50→.137` reconcile; open-archiver LXC 101; A1 per-service-state carve-out (growth path).

## Definition of done (whole project)
All §12 spec acceptance criteria met; P0–P6 merged via the full review lifecycle; ClickUp board reflects every phase complete; `tofu validate`+`plan` clean across all 3 states; the rebuilt fleet verified live (desktop+mobile); no private keys in state; `prevent_destroy` live on gitlab/postgresql/opconnect.
