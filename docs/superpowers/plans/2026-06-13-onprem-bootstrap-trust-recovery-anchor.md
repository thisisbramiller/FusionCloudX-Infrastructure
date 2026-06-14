> ⚠️ **SUPERSEDED — HISTORICAL.** This Wave 1 "recovery-anchor" plan is not the as-built design. It was
> superseded 2026-06-13/14 by **Direction A** (dedicated key, AWS-bundle bootstrap, native Connect TLS). The
> ephemeral pubkey read proposed here was rejected (an ephemeral value cannot feed persisted cloud-init) and
> replaced by an SSM `aws_ssm_parameter` data source. As-built:
> `docs/superpowers/plans/2026-06-13-onprem-phase-c-directionA.md` (PR #59 merged fc1c43d) +
> runbook `docs/runbooks/opconnect-credentials.md`.

# onprem opconnect off-site credentials — Implementation Plan (Wave 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or subagent-driven-development) to implement task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Store an off-site copy of opconnect's credentials in AWS as a FIDO-gated, human-orchestrated anchor — so opconnect/1Password Connect bootstraps DR-portably (no Mac `op`-CLI dependency) — while day-2 secrets stay local and no secrets land in tofu state. Seed/rotate is a pure-Ansible playbook (idempotent + expiry-aware), not a script, not in `site.yml`.

**Architecture:** `aws-foundation/15-opconnect-credentials` owns a dedicated CMK (`alias/tmpx/onprem-opconnect`, **root-enable-only** policy) + an empty Secrets Manager secret (`tmpx/onprem/opconnect-credentials`). `onprem-infra/tofu/opconnect` consumes the CMK **by alias** + reads only the **public** key (ephemeral) for cloud-init; the Ansible `opconnect`/`ssh-key-loader` roles read the secret material via `amazon.aws.aws_secret`. The seed playbook `opconnect_credentials.yml` mints/rotates the bundle.

**Tech Stack:** OpenTofu ≥1.10 (aws ~>6.0; ephemeral resources), AWS KMS + Secrets Manager + IAM Identity Center, Ansible (`amazon.aws` + `community.aws` collections), 1Password Connect (`op` CLI account mode).

**Spec:** `docs/superpowers/specs/2026-06-13-onprem-bootstrap-trust-recovery-anchor-design.md` (D1–D8 locked).

**Repos:** `aws-foundation` (Phase A) + `FusionCloudX Infrastructure` / onprem-infra (Phase B/C/D). Branches: `feat/opconnect-credentials` in each.

**Apply gating:** every `tofu apply` / `ansible-playbook` here touches LIVE AWS or the secrets root — each is a STOP-and-confirm with Branden (SSO `fcx-sso` + FIDO active; 1Password desktop app unlocked for the seed). "Tests" for IaC = `tofu validate`/`fmt` → `plan` (assert exact change) → gated `apply` → live verify.

---

## File Structure

**aws-foundation/15-opconnect-credentials/** (own state `15-opconnect-credentials/terraform.tfstate`) — **DONE/APPLIED as `15-recovery-anchor`; renamed to literal naming (commit `ca16628`), rename-apply deferred (gated).**
- `versions.tf` `backend.tf` `encryption.tf` `variables.tf` — scaffold
- `kms.tf` — `alias/tmpx/onprem-opconnect` CMK + **root-enable-only** policy + `moved{}` (re-address from `…bootstrap`)
- `secret.tf` — empty `tmpx/onprem/opconnect-credentials` secret (value out-of-band)
- `outputs.tf` — `opconnect_cmk_arn/alias`, `opconnect_credentials_secret_arn/id`
- `README.md` — purpose, no-reverse-dependency rule, rename/deferred-apply note

**onprem-infra/ansible/** (seed + consume)
- `playbooks/opconnect_credentials.yml` (new) — the seed/rotate entry point (localhost; NOT in site.yml)
- `roles/opconnect/tasks/seed.yml` (new) — idempotent + expiry-aware mint/rotate/write
- `roles/opconnect/defaults/main.yml` (modify) — add the shared bundle schema vars (`opconnect_creds_*`)
- `roles/opconnect/tasks/main.yml` (modify, Phase C) — read creds from the bundle via `amazon.aws.aws_secret`
- `roles/ssh-key-loader/tasks/main.yml` (modify, Phase C) — load the ansible private key from the bundle

**onprem-infra/tofu/opconnect/** (consume, Phase C)
- `recovery.tf` (new) — `data "aws_kms_alias" "opconnect"` + ephemeral read of the **public** key
- `ssh-keys.tf` (rewrite) — drop the Option-D `tls_private_key` + `null_resource` write-back
- `providers.tf` (modify) — add read-only `aws` provider; drop `tls` (after C3)

**Runbooks/docs**
- `docs/runbooks/opconnect-credentials.md` (new) — seed/rotate procedure + offline 3-2-1 export + clean-room DR drill

---

## Phase A — aws-foundation/15-opconnect-credentials  ✅ DONE (applied; rename-apply deferred)

CMK `62a22d52-…` + alias + empty secret applied (as `15-recovery-anchor`, commit `d2eb248`); verified live via OrganizationAccountAccessRole. Key policy corrected to **root-enable-only** during authoring (SSO-admin-only would have denied the OAAR read path). Renamed to `15-opconnect-credentials` (commit `ca16628`).

- [x] A1 scaffold · A2 CMK + alias + root-enable policy · A3 empty secret + outputs + README
- [ ] **A4 (GATED, deferred — needs `fcx-sso` + FIDO):** apply the rename. `tofu -chdir=15-opconnect-credentials init -migrate-state` (state key `15-recovery-anchor/` → `15-opconnect-credentials/`) → `plan` (assert: CMK **moved** no-op, old alias destroyed + `onprem-opconnect` created, old empty secret destroyed [30-day window] + `opconnect-credentials` created; **no key replacement**) → gated `apply` → verify `aws kms describe-key --key-id alias/tmpx/onprem-opconnect` + `aws secretsmanager describe-secret --secret-id tmpx/onprem/opconnect-credentials`.

---

## Phase B — the Ansible seed/rotate playbook (D8)

### Task B1: Shared bundle-schema defaults + the seed task file
**Files:** Modify `ansible/roles/opconnect/defaults/main.yml`; Create `ansible/roles/opconnect/tasks/seed.yml`

- [ ] **Step 1:** Append the shared schema vars to `roles/opconnect/defaults/main.yml` (one source of truth — produce + consume both reference these, so the bundle schema can't drift):
```yaml
# --- off-site credentials (the AWS opconnect-credentials secret) ---
opconnect_creds_secret_name:    "tmpx/onprem/opconnect-credentials"
opconnect_creds_region:         "us-east-2"
opconnect_creds_assume_role_arn: "arn:aws:iam::065094257518:role/OrganizationAccountAccessRole"
opconnect_creds_vault:          "FusionCloudX"            # 1Password vault the Connect server is scoped to
opconnect_creds_server_name:    "opconnect"               # `op connect server` name
opconnect_creds_connect_host:   "http://opconnect.fusioncloudx.home:8080"
opconnect_creds_rotate_threshold_days: 14                 # rotate when token_expires is within this window
```
- [ ] **Step 2:** Author `roles/opconnect/tasks/seed.yml` (full content below — idempotent + expiry-aware; `no_log` on every secret task; account-mode `op` with `OP_CONNECT_*` unset). See **Appendix: seed.yml** at the end of this plan for the exact file.
- [ ] **Step 3:** `ansible-galaxy collection list | grep -E 'amazon.aws|community.aws'` — confirm both installed (the write module `community.aws.secretsmanager_secret` + `amazon.aws.sts_assume_role`/`aws_secret`). Install if absent. **Commit** (`feat(opconnect): seed.yml + shared bundle schema (no apply)`).

### Task B2: The seed playbook entry point (NOT in site.yml)
**Files:** Create `ansible/playbooks/opconnect_credentials.yml`
- [ ] **Step 1:** Author the playbook (full content in **Appendix: opconnect_credentials.yml**). `hosts: localhost`, `connection: local`, `gather_facts: false`, imports the `opconnect` role `tasks_from: seed`.
- [ ] **Step 2:** Confirm `site.yml` does **not** import it (`grep -n opconnect_credentials site.yml` → empty). Document the "never `-vvv`" rule in the playbook header.
- [ ] **Step 3:** `ansible-playbook --syntax-check playbooks/opconnect_credentials.yml`. **Commit.**

### Task B3 (GATED — first real seed): run it
- [ ] **Step 1:** Preconditions: 1Password desktop app **unlocked**; `aws sso login --sso-session fcx-sso`; Phase A4 rename applied (secret exists under the new name).
- [ ] **Step 2 (GATED — confirm with Branden):** `cd ansible && ansible-playbook playbooks/opconnect_credentials.yml` (NO `-v`). First run: secret empty → `need_seed` → `op connect server create` (or reuse existing creds.json) + `op connect token create` → assemble → write. Expect the play to report the written bundle's `token_expires`.
- [ ] **Step 3: Verify idempotency:** run it again immediately → expect `need_rotate=false`, `need_seed=false`, write task `changed=false`, "valid, expires … nothing to do."
- [ ] **Step 4: Verify rotation:** `ansible-playbook playbooks/opconnect_credentials.yml -e force=true` → new token minted, `token_expires` advances, server identity + ansible keypair unchanged (compare the public key before/after). **No repo commit** (no repo change; it writes AWS).

### Task B4: Offline 3-2-1 copy (closes #60)
- [ ] **Step 1:** Export + encrypt the bundle offline (`age -p` / `gpg -c`), store on encrypted USB / fireproof. Passphrase custody: memorized / FIDO-protected, **NOT** in 1Password (circular).
- [ ] **Step 2:** Record in `docs/runbooks/opconnect-credentials.md` that this covers the AWS-unreachable cold-start; cross-link #60. **Commit** the runbook.

---

## Phase C — onprem-infra opconnect consumer

### Task C1: Read-only AWS provider + the CMK alias data source
**Files:** Modify `tofu/opconnect/providers.tf`; Create `tofu/opconnect/recovery.tf`
- [ ] **Step 1:** In `providers.tf`, add `aws = { source = "hashicorp/aws", version = "~> 6.0" }` to `required_providers` + `provider "aws" { region = "us-east-2"; assume_role { role_arn = "arn:aws:iam::065094257518:role/OrganizationAccountAccessRole" } }`. Keep proxmox/unifi/ansible. (Drop `tls` after C3.)
- [ ] **Step 2:** `recovery.tf`:
```hcl
# The off-site opconnect-credentials CMK, referenced by its STABLE ALIAS (no
# remote_state — zero coupling to aws-foundation state). Spec D6.
data "aws_kms_alias" "opconnect" {
  name = "alias/tmpx/onprem-opconnect"
}
# Ansible PUBLIC key for cloud-init, read at build time from the bundle. Public key
# is non-secret. The PRIVATE key + Connect creds are read by ANSIBLE
# (amazon.aws.aws_secret), never by tofu -> never in state (Task C4, #8).
ephemeral "aws_secretsmanager_secret_version" "opconnect_credentials" {
  secret_id = "tmpx/onprem/opconnect-credentials"
}
```
- [ ] **Step 3:** `tofu -chdir=tofu/opconnect validate` → Success. **Commit** (`feat(opconnect): read CMK by alias + ephemeral bundle pubkey`).

### Task C2: Wire the cloud-init pubkey from the bundle
**Files:** Modify `tofu/opconnect/recovery.tf` + confirm `opconnect.tf`
- [ ] **Step 1:** Add the local:
```hcl
locals {
  ansible_ssh_public_key = jsondecode(ephemeral.aws_secretsmanager_secret_version.opconnect_credentials.secret_string)["ansible_public_key"]
}
```
- [ ] **Step 2:** Confirm `opconnect.tf` already uses `ansible_pubkey = local.ansible_ssh_public_key` — this local now SOURCES from AWS. If `tofu plan` errors "ephemeral in persistent context," fall back to a non-secret `aws_ssm_parameter` for the public key (published by `15-opconnect-credentials`). 
- [ ] **Step 3:** `validate` + `plan`. **Commit.**

### Task C3: Retire the Option-D key-in-state (`tls_private_key` + `null_resource`)
**Files:** Rewrite `tofu/opconnect/ssh-keys.tf`; `providers.tf`
- [ ] **Step 1:** Delete `resource "tls_private_key" "ansible"` + `resource "null_resource" "ansible_ssh_key_writeback"`. The pubkey local now lives in `recovery.tf`.
- [ ] **Step 2:** Remove the `tls` provider from `providers.tf`.
- [ ] **Step 3:** `validate` → `plan`: expect `tls_private_key.ansible` + the `null_resource` **destroyed**; assert NO opconnect VM replacement (confirm the bundle pubkey == the current key; if different, cloud-init changes → acceptable on a deliberate rebuild, flag to Branden). **GATED APPLY.**
- [ ] **Step 4: Verify:** `grep -c tls_private_key tofu/opconnect/*.tf` = 0; `tofu state list | grep -E 'tls_private_key|ansible_ssh_key_writeback'` = empty (closes the SSH-key half of #8). **Commit.**

### Task C4: Ansible reads Connect creds + private key from the bundle
**Files:** Modify `ansible/roles/opconnect/tasks/main.yml`, `ansible/roles/ssh-key-loader/tasks/main.yml`
- [ ] **Step 1:** A shared `tasks/_read_bundle.yml` (or a block) used by both: assume role → `amazon.aws.aws_secret` lookup of `opconnect_creds_secret_name` → `set_fact: _bundle` (`no_log: true`). Reuse the same `opconnect_creds_*` defaults (no schema drift vs seed.yml).
- [ ] **Step 2:** `ssh-key-loader`: write `_bundle.ansible_private_key` to the key path (`mode: 0600`, `no_log: true`).
- [ ] **Step 3:** `opconnect`: base64-decode `_bundle.connect_credentials_json` → `1password-credentials.json`; use `_bundle.connect_token`; deploy the Connect compose stack as today. `no_log: true` on secret tasks.
- [ ] **Step 4 (GATED):** `cd ansible && ansible-playbook playbooks/opconnect.yml` (`fcx-sso` active). Expect Connect up from AWS-delivered creds.
- [ ] **Step 5: Verify:** Connect `/heartbeat` OK; serves a test secret. **Commit.** Open PR `onprem-infra: opconnect-credentials consumer` → @claude review → merge.

---

## Phase D — DR drill + acceptance

### Task D1: Clean-room bootstrap drill
- [ ] **Step 1 (GATED):** Destroy opconnect (lift prevent_destroy for the drill, then restore).
- [ ] **Step 2:** Re-bootstrap from SCRATCH using ONLY: `aws sso login --sso-session fcx-sso` (+ FIDO) → `tofu -chdir=tofu/opconnect apply` → `cd ansible && ansible-playbook playbooks/opconnect.yml`. **Do NOT** use the Mac `op` CLI account-mode path. Expect Connect up + serving.
- [ ] **Step 3: Verify acceptance:** no Mac `op` account-mode step ✅ · `tofu state list` (both layers) grep zero `tls_private_key`/plaintext (#8) ✅ · negative auth (a role without SSO/OAAR → `get-secret-value` AccessDenied) ✅ · `15-opconnect-credentials` grep `.tf` for `remote_state|onprem|1password` → none ✅ · seed playbook idempotent + not in site.yml ✅.
- [ ] **Step 4:** Update `docs/runbooks/opconnect-credentials.md` with verified steps. **Commit.**

### Task D2: Docs + memory + close-out
- [ ] **Step 1:** `docs/enhance-harden-later.md` §A/B: mark secret-zero bootstrap + #8 (SSH-key half) RESOLVED; note residual DB-password `password_wo` migration if pending.
- [ ] **Step 2:** Vault `project_onprem_tofu_migration` memory + `09-Homelab` onprem docs: opconnect AWS-anchored (Wave 1 complete); Wave 2 deferred (triggers).
- [ ] **Step 3:** Nexus session note. **Commit.**

---

## Self-Review

**Spec coverage:** D1 two-tier ✅ · D2 human-SSO (all applies gated) ✅ · D3 AWS anchor / root-enable policy (A2) ✅ · D4/D5 CMK+secret in new layer 15, no new repo ✅ · D6 alias + name, not remote_state (C1 + C4) ✅ · D7 1P day-2 untouched ✅ · **D8 seed = idempotent/expiry Ansible playbook, not site.yml, not a script (Phase B)** ✅ · #8 SSH key out of state (C3+D1) ✅ · offline 3-2-1 (B4) ✅ · root-enable-only key policy (A2, as-built) ✅.
**Placeholder scan:** the two new files have their full content in the Appendix (no "TODO"). The one genuine unknown (ephemeral-in-persistent-context, C2) has a stated fallback (non-secret SSM pubkey).
**Type consistency:** `alias/tmpx/onprem-opconnect`, `tmpx/onprem/opconnect-credentials`, `opconnect_creds_*` defaults, bundle JSON keys (`connect_credentials_json`/`connect_token`/`ansible_public_key`/`ansible_private_key`/`token_expires`/`created`/`notes`) used consistently across A/B/C, seed.yml, and the consumer.

**Known risks to validate during execution:** (1) the Jinja expiry compare in seed.yml (`now()` + `strftime` + ISO string compare) — validate on the first idempotency run (B3 Step 3). (2) OpenTofu ephemeral pubkey feeding a cloud-init local (C2) — fallback to SSM. (3) `community.aws.secretsmanager_secret` `overwrite`/version semantics — assert `changed=false` on the no-op run.

---

## Appendix: `ansible/roles/opconnect/tasks/seed.yml`

> Imported ONLY by `playbooks/opconnect_credentials.yml` (localhost, account-mode `op`). NOT part of the role's `main.yml` deploy path. NEVER run the playbook with `-vvv` (`no_log` bypass). The exact file the implementer writes:

```yaml
---
- name: Assert localhost (biometric op + AWS FIDO are workstation-bound)
  ansible.builtin.assert:
    that: inventory_hostname == 'localhost'
    fail_msg: "Run via playbooks/opconnect_credentials.yml on the operator workstation only."

- name: Assume shared-services for Secrets Manager
  amazon.aws.sts_assume_role:
    role_arn: "{{ opconnect_creds_assume_role_arn }}"
    role_session_name: "opconnect-credentials-seed"
    region: "{{ opconnect_creds_region }}"
  register: _assumed
  no_log: true

- name: Read the current secret (absent on first seed)
  ansible.builtin.set_fact:
    _current: >-
      {{ lookup('amazon.aws.aws_secret', opconnect_creds_secret_name,
                region=opconnect_creds_region,
                aws_access_key=_assumed.sts_creds.access_key,
                aws_secret_key=_assumed.sts_creds.secret_key,
                aws_security_token=_assumed.sts_creds.session_token,
                on_missing='skip') | default('') }}
  no_log: true

- name: Compute seed/rotate/no-op decision
  vars:
    _threshold_iso: "{{ '%Y-%m-%dT%H:%M:%SZ' | strftime((now(utc=true).timestamp() | int) + (opconnect_creds_rotate_threshold_days | int * 86400)) }}"
    _cur: "{{ (_current | from_json) if (_current | length > 0) else {} }}"
  ansible.builtin.set_fact:
    _need_seed: "{{ _current | length == 0 }}"
    _need_rotate: "{{ (_current | length > 0) and (force | bool or (_cur.token_expires | default('1970-01-01T00:00:00Z')) < _threshold_iso) }}"
    _cur: "{{ _cur }}"

- name: No-op (bundle valid)
  ansible.builtin.debug:
    msg: "opconnect-credentials valid; token_expires {{ _cur.token_expires | default('?') }} — nothing to do."
  when: not (_need_seed | bool) and not (_need_rotate | bool)

- name: Seed / rotate
  when: _need_seed | bool or _need_rotate | bool
  environment:        # force account mode: Connect env vars otherwise lock op to Connect API mode
    OP_CONNECT_HOST: ""
    OP_CONNECT_TOKEN: ""
  block:
    - name: Create the Connect server (FIRST SEED ONLY — not idempotent)
      ansible.builtin.command:
        cmd: "op connect server create {{ opconnect_creds_server_name }} --vaults {{ opconnect_creds_vault }}"
        chdir: "{{ _seed_tmp.path }}"          # writes 1password-credentials.json here
      when: _need_seed | bool
      no_log: true
      vars:
        _seed_tmp: "{{ _tmp }}"

    - name: Mint a Connect token (seed OR rotate)
      ansible.builtin.command:
        cmd: "op connect token create breakglass-{{ '%Y%m%d' | strftime }} --server {{ opconnect_creds_server_name }} --vaults {{ opconnect_creds_vault }}"
      register: _tok
      no_log: true

    # credentials.json: fresh file on seed; reuse the stored value on rotate.
    - name: Load credentials.json (seed = freshly created file; rotate = from current bundle)
      ansible.builtin.set_fact:
        _creds_b64: >-
          {{ (lookup('file', _tmp.path ~ '/1password-credentials.json') | b64encode)
             if (_need_seed | bool) else _cur.connect_credentials_json }}
      no_log: true

    - name: Decode the minted token's expiry (JWT exp; non-secret timestamp)
      ansible.builtin.set_fact:
        _token_expires: "{{ '%Y-%m-%dT%H:%M:%SZ' | strftime( (_tok.stdout | split('.') | community.general.json_query('[1]') | b64decode | from_json).exp ) }}"
      no_log: true     # _tok.stdout is the token; keep it out of logs

    - name: Reuse existing keypair on rotate; generate on seed
      community.crypto.openssh_keypair:
        path: "{{ _tmp.path }}/ansible_key"
        type: ed25519
        comment: "ansible@fusioncloudx-bootstrap"
      when: _need_seed | bool
      no_log: true

    - name: Assemble the bundle
      ansible.builtin.set_fact:
        _bundle_json: >-
          {{ {
            'connect_credentials_json': _creds_b64,
            'connect_token': _tok.stdout,
            'connect_host': opconnect_creds_connect_host,
            'ansible_public_key':  (lookup('file', _tmp.path ~ '/ansible_key.pub') if (_need_seed|bool) else _cur.ansible_public_key),
            'ansible_private_key': (lookup('file', _tmp.path ~ '/ansible_key')     if (_need_seed|bool) else _cur.ansible_private_key),
            'token_expires': _token_expires,
            'created': ('%Y-%m-%dT%H:%M:%SZ' | strftime),
            'notes': 'off-site opconnect credentials. proxmox/gitlab restore pointers in runbook. NO AWS-root break-glass (offline).'
          } | to_json }}
      no_log: true

    - name: Write the bundle to Secrets Manager (idempotent; no churn if unchanged)
      community.aws.secretsmanager_secret:
        name: "{{ opconnect_creds_secret_name }}"
        state: present
        json_secret: "{{ _bundle_json }}"
        kms_key_id: "alias/tmpx/onprem-opconnect"
        overwrite: true
        region: "{{ opconnect_creds_region }}"
        access_key: "{{ _assumed.sts_creds.access_key }}"
        secret_key: "{{ _assumed.sts_creds.secret_key }}"
        session_token: "{{ _assumed.sts_creds.session_token }}"
      no_log: true

    - name: Report
      ansible.builtin.debug:
        msg: "opconnect-credentials {{ 'seeded' if _need_seed|bool else 'rotated' }}; token_expires {{ _token_expires }}."
```
*(A `tempfile` block creates `_tmp` (a 0700 dir) before the block and a shred/remove runs in an `always:` — the implementer wraps the block accordingly. The `community.general.json_query`/`community.crypto.openssh_keypair` deps are confirmed present or installed in B1 Step 3. The JWT-exp decode is best-effort; validate at B3.)*

## Appendix: `ansible/playbooks/opconnect_credentials.yml`

```yaml
---
# Seed/rotate the OFF-SITE copy of opconnect's credentials (AWS Secrets Manager).
# RUN BY HAND on the operator workstation: 1Password desktop app UNLOCKED +
# `aws sso login --sso-session fcx-sso`. Idempotent + expiry-aware. NOT in site.yml.
# NEVER run with -v/-vvv (no_log bypass). Spec D8.
#   ansible-playbook playbooks/opconnect_credentials.yml            # seed/rotate as needed
#   ansible-playbook playbooks/opconnect_credentials.yml -e force=true   # force a rotation now
- name: Seed/rotate opconnect off-site credentials
  hosts: localhost
  connection: local
  gather_facts: false
  vars:
    force: false
  tasks:
    - name: Seed/rotate
      ansible.builtin.import_role:
        name: opconnect
        tasks_from: seed
```

---

*Plan generated 2026-06-13 from the approved+refined spec. Wave 2 (CI OIDC, Roles Anywhere) is out of scope per the spec.*
