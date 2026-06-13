# onprem Bootstrap-Trust + Recovery-Anchor — Implementation Plan (Wave 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Relocate the on-prem secret-zero into AWS as a FIDO-gated, human-orchestrated break-glass anchor — so opconnect/1Password Connect bootstraps DR-portably (no Mac `op`-CLI dependency) — while day-2 secrets stay local and no secrets land in tofu state.

**Architecture:** A new `aws-foundation/15-recovery-anchor` layer owns a dedicated CMK (`alias/tmpx/onprem-bootstrap`) + an AWS Secrets Manager break-glass bundle (key policy grants `kms:Decrypt` to the IdC AdministratorAccess SSO role only). `onprem-infra/tofu/opconnect` consumes the CMK **by alias** (data source, not remote_state); the bundle's public material wires cloud-init at build time and the Ansible `opconnect`/`ssh-key-loader` roles read the private material from Secrets Manager at provision time. The Ansible SSH key becomes Connect-served, retiring the Option-D `op`-CLI write-back and clearing #8.

**Tech Stack:** OpenTofu ≥1.10 (aws ~>6.0; ephemeral resources), AWS KMS + Secrets Manager + IAM Identity Center, Ansible (`amazon.aws` collection), 1Password Connect.

**Spec:** `docs/superpowers/specs/2026-06-13-onprem-bootstrap-trust-recovery-anchor-design.md` (decisions D1–D7 locked).

**Repos:** `aws-foundation` (Phase A/B) + `FusionCloudX Infrastructure` / onprem-infra (Phase C/D). Branch suggestion: `feat/recovery-anchor` in each.

**Apply gating:** every `tofu apply` / `ansible-playbook` here touches LIVE AWS or the secrets root — each apply step is a STOP-and-confirm with Branden (SSO `fcx-sso` + FIDO active). "Tests" for IaC = `tofu validate` → `tofu plan` (assert exact change) → gated `apply` → live verify.

---

## File Structure

**aws-foundation/15-recovery-anchor/** (new layer, own state `15-recovery-anchor/terraform.tfstate`)
- `versions.tf` — required_version + aws provider (copy 10-bootstrap)
- `backend.tf` — S3 backend (copy 10-bootstrap, change `key`)
- `encryption.tf` — native AES-GCM block (copy verbatim from a sibling layer)
- `variables.tf` — `shared_services_account_id`, `idc_admin_permission_set_arn_like`
- `kms.tf` — the `alias/tmpx/onprem-bootstrap` CMK + key policy
- `secret.tf` — the Secrets Manager break-glass bundle (write-only)
- `outputs.tf` — `bootstrap_cmk_arn`, `bootstrap_cmk_alias`, `breakglass_secret_arn`
- `README.md` — layer purpose + the "no reverse dependency" rule

**onprem-infra/tofu/opconnect/** (modify)
- `recovery.tf` (new) — `data "aws_kms_alias"` + the build-time public-key read
- `ssh-keys.tf` (rewrite) — drop the Option-D `tls_private_key` + `null_resource` write-back; source the ansible pubkey from the bundle
- `providers.tf` (modify) — add the `aws` provider (read-only, assume-role); drop `tls`

**onprem-infra/ansible/roles/opconnect/** + **ssh-key-loader/** (modify)
- read the Connect `credentials.json` + token (and the ansible private key) from Secrets Manager via `amazon.aws.aws_secret`, instead of the Option-D / local-file path

**Runbooks/docs**
- `docs/runbooks/recovery-anchor-bootstrap.md` (new) — the DR drill + offline 3-2-1 export procedure

---

## Phase A — aws-foundation/15-recovery-anchor (the primitive)

### Task A0: Spike — confirm the ephemeral-read vs ansible-read mechanism
**Files:** none (investigation, write findings into the layer README)
- [ ] **Step 1:** In a scratch dir, confirm OpenTofu 1.12 `ephemeral "aws_secretsmanager_secret_version"` works under the `assume_role` backend, AND confirm an ephemeral value CANNOT be an `output` (it can't — by design). Decision criterion: because the Ansible `opconnect` role (not tofu) deploys Connect, the **Connect credentials.json + token + ansible private key are read by ANSIBLE** via `amazon.aws.aws_secret`; tofu only reads the **public** key (non-secret) for cloud-init. Record this split in the layer README.
- [ ] **Step 2:** Confirm the `amazon.aws` collection is installed for the control node: `ansible-galaxy collection list | grep amazon.aws` (install `ansible-galaxy collection install amazon.aws` if absent).
- [ ] **Step 3: Commit** the README note. `git commit -m "docs(recovery): record bundle read-split (tofu=pubkey, ansible=secrets)"`

### Task A1: Scaffold the layer (boilerplate, copied from 10-bootstrap)
**Files:** Create `aws-foundation/15-recovery-anchor/{versions.tf,backend.tf,encryption.tf,variables.tf}`
- [ ] **Step 1:** `versions.tf` — identical to `10-bootstrap/versions.tf`:
```hcl
terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
```
- [ ] **Step 2:** `backend.tf` — copy `10-bootstrap/backend.tf`, change ONLY the key:
```hcl
terraform {
  backend "s3" {
    bucket       = "tmpx-tfstate-065094257518-use2"
    key          = "15-recovery-anchor/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:us-east-2:065094257518:key/1d876310-c068-4204-aca3-d8585f477fda"
    use_lockfile = true
    assume_role  = { role_arn = "arn:aws:iam::065094257518:role/OrganizationAccountAccessRole" }
  }
}
```
- [ ] **Step 3:** `encryption.tf` — copy verbatim from a sibling layer (e.g. `10-bootstrap/encryption.tf` if present, else `20-log-archive/`): the `terraform { encryption { key_provider "aws_kms" "state" { kms_key_id = <tfstate CMK arn>, key_spec = "AES_256" } method "aes_gcm" "state" { keys = key_provider.aws_kms.state } state { method = method.aes_gcm.state, enforced = true } plan { method = method.aes_gcm.state, enforced = true } } }` block. It is identical across layers — copy, do not author from scratch.
- [ ] **Step 4:** `variables.tf`:
```hcl
variable "shared_services_account_id" {
  type        = string
  default     = "065094257518"
  description = "Account that owns the recovery anchor (where tfstate + tmpx CMKs live)."
}
variable "idc_admin_role_arn_like" {
  type        = string
  default     = "arn:aws:iam::065094257518:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_AdministratorAccess_*"
  description = "ArnLike pattern for the IdC AdministratorAccess SSO role (the FIDO-gated human bootstrap identity)."
}
```
- [ ] **Step 5:** `tofu -chdir=15-recovery-anchor init` → expect success (providers download, backend init). **Commit.**

### Task A2: The dedicated CMK + key policy
**Files:** Create `aws-foundation/15-recovery-anchor/kms.tf`
- [ ] **Step 1:** Author `kms.tf`, mirroring `10-bootstrap/kms.tf` but granting `kms:Decrypt` to the SSO Admin role (NO `kms:ViaService`, the documented hook):
```hcl
resource "aws_kms_key" "bootstrap" {
  description             = "onprem bootstrap/recovery break-glass - tmpx shared-services"
  enable_key_rotation     = true
  rotation_period_in_days = 365
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.bootstrap_key.json
  lifecycle { prevent_destroy = true }
}

resource "aws_kms_alias" "bootstrap" {
  name          = "alias/tmpx/onprem-bootstrap"
  target_key_id = aws_kms_key.bootstrap.key_id
}

data "aws_iam_policy_document" "bootstrap_key" {
  statement {
    sid       = "EnableIAMRootPermissions"
    effect    = "Allow"
    principals { type = "AWS", identifiers = ["arn:aws:iam::${var.shared_services_account_id}:root"] }
    actions   = ["kms:*"]
    resources = ["*"]
  }
  statement {
    sid       = "AllowSSOAdminDecrypt"
    effect    = "Allow"
    principals { type = "AWS", identifiers = ["arn:aws:iam::${var.shared_services_account_id}:root"] }
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = [var.idc_admin_role_arn_like]
    }
  }
}
```
- [ ] **Step 2:** `tofu -chdir=15-recovery-anchor validate` → Success. `tofu plan` → expect **2 to add** (key + alias) + the data source. Assert no other changes.
- [ ] **Step 3 (GATED APPLY — confirm with Branden):** `tofu -chdir=15-recovery-anchor apply` → key + alias created.
- [ ] **Step 4: Verify:** `aws kms describe-key --key-id alias/tmpx/onprem-bootstrap` (via `fcx-sso`) returns the key; `aws kms get-key-policy` shows the two statements. **Commit.**

### Task A3: The Secrets Manager break-glass bundle (write-only, empty shell)
**Files:** Create `aws-foundation/15-recovery-anchor/secret.tf` + `outputs.tf`
- [ ] **Step 1:** `secret.tf` — create the secret container encrypted under the CMK; the VALUE is written write-only (no plaintext in state). Initial value is an empty JSON shell (populated in Phase B by the operator, out-of-band, so the real material never transits tofu):
```hcl
resource "aws_secretsmanager_secret" "breakglass" {
  name                    = "tmpx/onprem/breakglass-bundle"
  description             = "onprem recovery seed: 1P Connect credentials.json + token + ansible keypair. FIDO-gated."
  kms_key_id              = aws_kms_key.bootstrap.arn
  recovery_window_in_days = 30
}
# Value is populated OUT-OF-BAND (Phase B) via the CLI with the orchestrator's SSO
# session — NOT through tofu — so the recovery material never transits tofu state.
# (If a managed seed is later wanted, use aws_secretsmanager_secret_version with
#  secret_string_wo / secret_string_wo_version to keep it write-only.)
```
- [ ] **Step 2:** `outputs.tf`:
```hcl
output "bootstrap_cmk_arn"     { value = aws_kms_key.bootstrap.arn }
output "bootstrap_cmk_alias"   { value = aws_kms_alias.bootstrap.name }
output "breakglass_secret_arn" { value = aws_secretsmanager_secret.breakglass.arn }
output "breakglass_secret_id"  { value = aws_secretsmanager_secret.breakglass.id }
```
- [ ] **Step 3:** `validate` → `plan` (expect +1 secret) → **GATED APPLY** → verify `aws secretsmanager describe-secret --secret-id tmpx/onprem/breakglass-bundle` shows `KmsKeyId` = the bootstrap CMK. **Commit.**
- [ ] **Step 4:** Add a `README.md` for the layer: purpose, the "anchor must NOT depend on onprem-infra or 1Password Connect" rule, the alias contract (`alias/tmpx/onprem-bootstrap`), and the apply-order note (15 sits above 10, below 30). **Commit.** Open PR `aws-foundation: 15-recovery-anchor` → @claude review → merge.

---

## Phase B — populate the break-glass bundle + offline copy (operator, out-of-band)

### Task B1: Assemble + store the bundle
**Files:** none in-repo (operator action; documented in the runbook)
- [ ] **Step 1:** Generate the ansible bootstrap keypair locally (ED25519): `ssh-keygen -t ed25519 -N "" -f /tmp/ansible_bootstrap -C "ansible@fusioncloudx"`.
- [ ] **Step 2:** Obtain the 1Password Connect seed: `1password-credentials.json` + a Connect token (`op connect server create` / existing). (These exist today from the live opconnect — capture them, do not regenerate unless rotating.)
- [ ] **Step 3:** Build the bundle JSON (in a 0600 tmpfile, shredded after): `{ "ansible_private_key": "...", "ansible_public_key": "...", "connect_credentials_json": <base64>, "connect_token": "...", "notes": "proxmox/gitlab restore pointers; NOT AWS-root break-glass (offline)" }`.
- [ ] **Step 4 (GATED — confirm with Branden):** Put the value with the SSO session: `aws secretsmanager put-secret-value --secret-id tmpx/onprem/breakglass-bundle --secret-string file:///tmp/bundle.json` then `shred -u /tmp/bundle.json /tmp/ansible_bootstrap*`.
- [ ] **Step 5: Verify:** a different shell, `fcx-sso`, `aws secretsmanager get-secret-value --secret-id tmpx/onprem/breakglass-bundle` returns the bundle (proves the SSO-Admin grant works). **No commit** (no repo change).

### Task B2: Offline 3-2-1 copy (closes #60 too)
- [ ] **Step 1:** Export the same bundle, encrypt offline: `age -p < bundle.json > breakglass.age` (or `gpg -c`), store on an encrypted USB / fireproof location. Document the passphrase custody (memorized / FIDO-protected, NOT in 1Password — circular).
- [ ] **Step 2:** Record in the runbook that this offline copy covers the AWS-unreachable cold-start. Cross-link task #60 (1password-credentials.json as a DR document). **Commit** the runbook.

---

## Phase C — onprem-infra opconnect consumer

### Task C1: Read-only AWS provider + the CMK alias data source
**Files:** Modify `tofu/opconnect/providers.tf`; Create `tofu/opconnect/recovery.tf`
- [ ] **Step 1:** In `providers.tf`, add the `aws` provider to `required_providers` (`source = "hashicorp/aws", version = "~> 6.0"`) and a `provider "aws" { region = "us-east-2"; assume_role { role_arn = "arn:aws:iam::065094257518:role/OrganizationAccountAccessRole" } }` (read-only use: kms alias + secrets read). Keep proxmox/unifi/ansible. (Drop `tls` only after C3.)
- [ ] **Step 2:** `recovery.tf`:
```hcl
# The recovery anchor's CMK, referenced by its STABLE ALIAS (no remote_state -
# zero coupling to aws-foundation's state). Spec D6.
data "aws_kms_alias" "bootstrap" {
  name = "alias/tmpx/onprem-bootstrap"
}
# Ansible PUBLIC key for cloud-init is read at build time from the bundle.
# Public key is non-secret -> a normal (non-ephemeral) read is fine; it lands in
# state but it is PUBLIC. The PRIVATE key + Connect creds are read by ANSIBLE
# (amazon.aws.aws_secret), never by tofu -> never in state (Task C4, #8).
ephemeral "aws_secretsmanager_secret_version" "breakglass" {
  secret_id = "tmpx/onprem/breakglass-bundle"
}
```
- [ ] **Step 3:** `tofu -chdir=tofu/opconnect validate` → Success. **Commit** (`feat(opconnect): read recovery CMK by alias + ephemeral bundle`).

### Task C2: Wire the cloud-init pubkey from the bundle
**Files:** Modify `tofu/opconnect/recovery.tf` + `opconnect.tf`
- [ ] **Step 1:** In `recovery.tf` add a local for the public key from the ephemeral bundle JSON:
```hcl
locals {
  ansible_ssh_public_key = jsondecode(ephemeral.aws_secretsmanager_secret_version.breakglass.secret_string)["ansible_public_key"]
}
```
- [ ] **Step 2:** Confirm `opconnect.tf:45` already uses `ansible_pubkey = local.ansible_ssh_public_key` — no change needed there; this local now SOURCES from AWS instead of `tls_private_key`. (NOTE: a local fed by an ephemeral value is only valid where consumed at apply — cloud-init `write_files`/snippet is fine; verify `tofu plan` does not error "ephemeral in persistent context". If it does, fall back to reading the public key from a non-ephemeral SSM SecureString published alongside the bundle.)
- [ ] **Step 3:** `validate` + `plan` → expect the opconnect cloud-init snippet to show the bundle's pubkey. **Commit.**

### Task C3: Retire the Option-D key-in-state (`tls_private_key` + `null_resource`)
**Files:** Rewrite `tofu/opconnect/ssh-keys.tf`; remove `scripts/op-write-ssh-key.sh` usage
- [ ] **Step 1:** Delete the `resource "tls_private_key" "ansible"` + `resource "null_resource" "ansible_ssh_key_writeback"` blocks (the Option-D path). The `local.ansible_ssh_public_key` now lives in `recovery.tf` (C2), so `ssh-keys.tf` becomes empty or is deleted.
- [ ] **Step 2:** Remove the `tls` provider from `providers.tf` (no longer used). Keep `scripts/op-write-ssh-key.sh` in git history but unreferenced (or delete + note in commit).
- [ ] **Step 3:** `validate` → `plan`. Expect: `tls_private_key.ansible` + `null_resource.ansible_ssh_key_writeback` **to be destroyed** (they leave state); opconnect VM cloud-init now sourced from the bundle pubkey. Assert NO opconnect VM replacement (the pubkey value is the same key, so cloud-init is stable — confirm the bundle pubkey == the current key; if different, the VM cloud-init changes → acceptable on a deliberate rebuild, flag to Branden). **GATED APPLY.**
- [ ] **Step 4: Verify:** `grep -c tls_private_key tofu/opconnect/*.tf` = 0; `tofu state list | grep -E 'tls_private_key|ansible_ssh_key_writeback'` = empty (closes the SSH-key half of #8). **Commit.** 

### Task C4: Ansible reads Connect creds + private key from Secrets Manager
**Files:** Modify `ansible/roles/opconnect/tasks/main.yml`, `ansible/roles/ssh-key-loader/tasks/main.yml`
- [ ] **Step 1:** In `ssh-key-loader`, replace the current key-source with the Secrets Manager lookup (orchestrator's SSO creds):
```yaml
- name: Load ansible private key from the AWS break-glass bundle
  ansible.builtin.set_fact:
    _bundle: "{{ lookup('amazon.aws.aws_secret', 'tmpx/onprem/breakglass-bundle', region='us-east-2') | from_json }}"
  no_log: true
- name: Write the ansible private key (0600, transient)
  ansible.builtin.copy:
    content: "{{ _bundle.ansible_private_key }}"
    dest: "{{ ansible_private_key_path }}"
    mode: "0600"
  no_log: true
```
- [ ] **Step 2:** In `opconnect` role, source `1password-credentials.json` + the Connect token from `_bundle.connect_credentials_json` (base64-decode) + `_bundle.connect_token` instead of the prior path; deploy the Connect compose stack as today. `no_log: true` on the secret tasks.
- [ ] **Step 3 (GATED):** Run `cd ansible && ansible-playbook playbooks/opconnect.yml` (or `site.yml --limit opconnect`) with `fcx-sso` active. Expect the opconnect role to fetch creds from AWS + bring Connect up.
- [ ] **Step 4: Verify:** `curl -sk https://opconnect.fusioncloudx.home:8080/heartbeat` OK; Connect serves a test secret to compute. **Commit.** Open PR `onprem-infra: recovery-anchor consumer` → @claude review → merge.

---

## Phase D — DR drill + acceptance verification

### Task D1: Clean-room bootstrap drill (the real acceptance test)
- [ ] **Step 1 (GATED):** Destroy opconnect: `tofu -chdir=tofu/opconnect destroy` (lift prevent_destroy deliberately for the drill, then restore).
- [ ] **Step 2:** Re-bootstrap from SCRATCH using ONLY: `aws sso login --sso-session fcx-sso` (+ FIDO) → `tofu -chdir=tofu/opconnect apply` → `cd ansible && ansible-playbook playbooks/opconnect.yml`. **Do NOT** use the Mac `op` CLI account-mode path. Expect Connect up + serving.
- [ ] **Step 3: Verify acceptance criteria:**
  - opconnect bootstrapped with no Mac `op` account-mode step ✅
  - `tofu state list` (both `15-recovery-anchor` and `opconnect`) → grep: zero `tls_private_key`, zero plaintext key/password (#8) ✅
  - Negative auth: from a role WITHOUT the IdC Admin grant, `aws secretsmanager get-secret-value --secret-id tmpx/onprem/breakglass-bundle` → AccessDenied ✅
  - `15-recovery-anchor` has no dependency on onprem-infra / Connect (grep its `.tf` for `remote_state`/`onprem`/`1password` → none) ✅
- [ ] **Step 4:** Update `docs/runbooks/recovery-anchor-bootstrap.md` with the verified drill steps. **Commit.**

### Task D2: Docs + memory + close-out
- [ ] **Step 1:** Update `docs/enhance-harden-later.md` §A/B: mark the secret-zero bootstrap + #8 (SSH-key half) RESOLVED via this design; note the residual DB-password `password_wo` migration if not yet done.
- [ ] **Step 2:** Update the vault `project_onprem_tofu_migration` memory + `09-Homelab` onprem docs: opconnect now AWS-anchored (Wave 1 complete); machine-identity Wave 2 deferred (triggers).
- [ ] **Step 3:** Nexus session note. **Commit.**

---

## Self-Review

**Spec coverage:** D1 two-tier (Phase C keeps 1P Connect local; A/B put the anchor in AWS) ✅ · D2 human-SSO bootstrap (all applies gated, SSO+FIDO; no CI) ✅ · D3 AWS anchor / secret-zero collapse (A2 key policy → IdC Admin only) ✅ · D4 bundle whole in foundation (A3 secret + B1 populate, in 15-recovery-anchor) ✅ · D5 new layer not 10-bootstrap, no new repo (Phase A) ✅ · D6 alias not remote_state (C1 `data aws_kms_alias`) ✅ · D7 1P stays day-2 (untouched) ✅ · #8 (SSH key out of state) C3+D1 ✅ · offline 3-2-1 (B2) ✅.
**Placeholder scan:** boilerplate "copy sibling" steps name the exact source file (10-bootstrap/{versions,backend,encryption}); the one genuine unknown (ephemeral-in-persistent-context behavior) is a defined spike (A0) + a stated fallback (C2 Step 2: non-ephemeral SSM pubkey). No bare TODOs.
**Type consistency:** `alias/tmpx/onprem-bootstrap`, `tmpx/onprem/breakglass-bundle`, `local.ansible_ssh_public_key`, bundle JSON keys (`ansible_public_key`/`ansible_private_key`/`connect_credentials_json`/`connect_token`) used consistently across A2/A3/C1/C2/C4/B1.

**Known risk to validate during execution:** OpenTofu ephemeral value feeding a cloud-init snippet local (C2) — if rejected as "ephemeral in persistent context," switch the PUBLIC key to a normal `aws_ssm_parameter` (public, non-secret) published by 15-recovery-anchor and read via `data "aws_ssm_parameter"`; the private key + Connect creds stay ansible-read. This does not change the architecture.

---

*Plan generated 2026-06-13 from the approved spec. Wave 2 (CI OIDC, Roles Anywhere) is out of scope per the spec.*
