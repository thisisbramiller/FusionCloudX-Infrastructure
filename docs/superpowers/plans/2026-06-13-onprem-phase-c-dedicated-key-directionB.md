# onprem opconnect Phase C — REVISED (dedicated key + Direction B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (or subagent-driven-development). Steps use `- [ ]`. Every `tofu apply` / seed run / secret write touches LIVE AWS, 1Password, or the secrets root — each is a STOP-and-confirm with Branden. Never run the seed at `-v`/`-vvv` (`no_log` bypass).

**Goal:** Complete the #68 opconnect consumer with a **dedicated opconnect bootstrap keypair** (D9) stored as a **native 1Password SSH-Key item**, the cloud-init pubkey read from **SSM** (D10, replacing the impossible ephemeral read), and **full Direction-B consume** (D11) — opconnect reads its key + Connect creds from 1Password day-2 (account-mode `op`), AWS escrow = break-glass. The 4 fleet VMs are untouched.

**Architecture:** **1Password generates** the dedicated key (native SSH-Key item — the `op` CLI generates but cannot import, so 1P is the canonical generator). The seed (`opconnect_credentials` role) **reads the keypair back** and mirrors it to the AWS escrow bundle + an SSM String param (pubkey only); it mints/stores Connect `creds.json`/token in a 1P Secure Note (+ escrow). `tofu/opconnect` reads only the SSM pubkey → cloud-init `authorized_keys`. No private key ever enters tofu state (#8).

**Spec:** `…/specs/2026-06-13-onprem-bootstrap-trust-recovery-anchor-design.md` (D9/D10/D11). **Supersedes** Phase C of `…/plans/2026-06-13-onprem-bootstrap-trust-recovery-anchor.md`. **Branch:** `feat/onprem-bootstrap-trust`.

**Verified `op` facts (live sweep, v2.34.0):**
- Generate: `op item create --category ssh --ssh-generate-key=ed25519 --title T --vault V` (Ed25519 default; `--dry-run` previews). **Import is GUI-only** → 1P generates.
- **Key-type control:** `--ssh-generate-key` accepts `ed25519` | `rsa` | `rsa2048` | `rsa3072` | `rsa4096` (default Ed25519). We use **ed25519** (matches the fleet key; no passphrase/custom-curve knobs exist). No `op ssh` command group — `op item` + `op read` is the entire SSH surface.
- **SSH-Key item schema CONFIRMED** (`op item template get "SSH Key"`): one `SSHKEY`-typed field, label **`private key`**, **no section**; public key + fingerprint are 1P-**derived**. So the references are field-direct: `op read "op://V/ITEM/private key?ssh-format=openssh"` (OpenSSH private key) and `op read "op://V/ITEM/public key"`. `op read --out-file F --file-mode 0600` writes straight to a 0600 file.
- **LIVE-VALIDATED 2026-06-13** (real create→read→delete in FusionCloudX): `op item create --category ssh --ssh-generate-key=ed25519 --vault FusionCloudX` landed in `FusionCloudX (ve6jgmyk77ssj7aqpeodt2uhyi)` (by name **and** by UUID); `op read --out-file --file-mode 0600 "op://FusionCloudX/<item>/private key?ssh-format=openssh"` produced a valid OpenSSH key whose derived pubkey matched `op read ".../public key"`; item deleted + confirmed gone. Field-path + vault-targeting + the loader mechanism are confirmed, not assumed.
- **No passphrase at generation** — 1P has no such option (`op item create` has no passphrase flag); 1P's stance: keys are "protected by your Master Password and Secret Key" (vault encryption), and `op read …?ssh-format=openssh` returns plaintext. CLI can't import a passphrased key (GUI-only). For this **unattended automation/bootstrap key a passphrase is undesirable** (non-interactive-supply friction + DR fragility); protection = 1P vault encryption + AWS KMS+FIDO + ephemeral 0600 temp + dedicated-key isolation (D9).
- **Sensitive values:** `op item create`/`edit` warn that assignment-statement args are visible to other processes → **use a JSON template** (`op item template get "Secure Note"`; `op item create --template F` / piped stdin). SSH-key gen passes no secret arg (safe); the creds item uses a template.
- Connect (already validated): `op connect server create <name> --vaults V`; `op connect token create <name> --server <name> --vaults V --expires-in=Nd`.

**As-built:** `ssh-keys.tf` (renamed from `recovery.tf` — purged metaphor) has the broken `ephemeral` read (UNAPPLIED; live still has `tls_private_key`+`null_resource`). Seed generates via `community.crypto.openssh_keypair` + writes escrow in-block (this plan moves gen→1P and distribution→always-run). opconnect role copies `creds.json` from `opconnect_credentials_local`. ssh-key-loader has an `op_use_cli` path. Live escrow key `6dV2…` is REPLACED on adoption by the new native 1P key; creds/token preserved. Fleet key `VrLco8…` untouched.

**Shared names (`opconnect_credentials/defaults/main.yml`):** `opconnect_creds_1p_ssh_item: "opconnect Bootstrap SSH Key"` · `opconnect_creds_1p_creds_item: "opconnect Connect Credentials"` · `opconnect_creds_ssm_pubkey_name: "/tmpx/onprem/opconnect/ansible_public_key"`.

---

## CR1: Seed defaults
**File:** `ansible/roles/opconnect_credentials/defaults/main.yml`
- [ ] Append the three `opconnect_creds_1p_ssh_item` / `_1p_creds_item` / `_ssm_pubkey_name` defaults above. Commit.

## CR2: Seed — 1P generates the SSH-Key item; seed reads + distributes (escrow + SSM + 1P creds)
**File:** `ansible/roles/opconnect_credentials/tasks/main.yml`. All `op` tasks account-mode (`env -u OP_CONNECT_HOST -u OP_CONNECT_TOKEN`); secret tasks `no_log: true`. Distribution is **always-run + idempotent**. **Remove** the `community.crypto.openssh_keypair` task.

- [ ] **Step 1 — ensure the native SSH-Key item (1P generates; idempotent):**
```yaml
- name: Check whether the dedicated 1P SSH-Key item exists
  ansible.builtin.command:
    argv: [env,-u,OP_CONNECT_HOST,-u,OP_CONNECT_TOKEN, op,item,get,
           "{{ opconnect_creds_1p_ssh_item }}","--vault","{{ opconnect_creds_vault }}","--format","json"]
  register: _ssh_item_check
  changed_when: false
  failed_when: false
  no_log: true

- name: Generate the dedicated Ed25519 SSH key in 1Password if absent
  ansible.builtin.command:
    argv: [env,-u,OP_CONNECT_HOST,-u,OP_CONNECT_TOKEN, op,item,create,
           "--category","ssh","--ssh-generate-key=ed25519",
           "--title","{{ opconnect_creds_1p_ssh_item }}","--vault","{{ opconnect_creds_vault }}"]
  when: _ssh_item_check.rc != 0
  no_log: true
```
> ✅ Confirmed live 2026-06-13: `--category ssh --ssh-generate-key=ed25519 --vault FusionCloudX` creates an Ed25519 `SSH_KEY` item in FusionCloudX (the flags coexist; verified by a real create + dry-run, by vault name and UUID).

- [ ] **Step 2 — read the keypair back (always-run; `op read` formats correctly, no escaping):**
```yaml
- name: Read dedicated public key from 1Password
  ansible.builtin.command:
    argv: [env,-u,OP_CONNECT_HOST,-u,OP_CONNECT_TOKEN, op,read,
           "op://{{ opconnect_creds_vault }}/{{ opconnect_creds_1p_ssh_item }}/public key"]
  register: _eff_pub
  changed_when: false
  no_log: true

- name: Read dedicated private key from 1Password (OpenSSH)
  ansible.builtin.command:
    argv: [env,-u,OP_CONNECT_HOST,-u,OP_CONNECT_TOKEN, op,read,
           "op://{{ opconnect_creds_vault }}/{{ opconnect_creds_1p_ssh_item }}/private key?ssh-format=openssh"]
  register: _eff_priv
  changed_when: false
  no_log: true
```
> ✅ Confirmed live 2026-06-13: the `SSH_KEY` item exposes `private key` + `public key` **field-direct (no section)**; both `op read` references resolve against a real item. These references are final.

- [ ] **Step 3 — token/creds (existing block, TOKEN-scoped):** keep `_need_seed` (bundle absent → `op connect server create … --vaults` → `creds.json`) / `_need_rotate` (token near `rotate_threshold_days` or `force`) → `op connect token create … --server … --vaults … --expires-in=…d`. Then:
```yaml
- name: Compute effective creds/token (minted this run, else current bundle)
  ansible.builtin.set_fact:
    _eff_creds_b64: "{{ (lookup('file', _tmp.path ~ '/1password-credentials.json') | b64encode) if (_need_seed | bool) else _cur.connect_credentials_json }}"
    _eff_token:     "{{ (_tok.stdout | trim) if (_need_seed or _need_rotate) else _cur.connect_token }}"
    _eff_token_expires: "{{ _token_expires if (_need_seed or _need_rotate) else _cur.token_expires }}"
  no_log: true
```

- [ ] **Step 4 — publish pubkey to SSM (always-run; non-secret):**
```yaml
- name: Publish dedicated ansible public key to SSM
  community.aws.ssm_parameter:
    name: "{{ opconnect_creds_ssm_pubkey_name }}"
    value: "{{ _eff_pub.stdout | trim }}"
    string_type: String
    region: "{{ opconnect_creds_region }}"
    access_key: "{{ _assumed.sts_creds.access_key }}"
    secret_key: "{{ _assumed.sts_creds.secret_key }}"
    session_token: "{{ _assumed.sts_creds.session_token }}"
```

- [ ] **Step 5 — ensure the 1P creds item via JSON TEMPLATE (NOT CLI-arg assignments — they leak to process lists):** build the item JSON, write to the 0600 scratch (`_tmp`), create-or-edit via `--template`, shredded by the existing `always:`.
```yaml
- name: Build the Connect-creds item JSON (Secure Note, concealed fields)
  ansible.builtin.copy:
    dest: "{{ _tmp.path }}/creds-item.json"
    mode: '0600'
    content: "{{ { 'title': opconnect_creds_1p_creds_item, 'category': 'SECURE_NOTE',
                   'vault': {'id': opconnect_creds_vault},
                   'fields': [ {'label':'credentials_json','type':'CONCEALED','value': _eff_creds_b64},
                               {'label':'connect_token','type':'CONCEALED','value': _eff_token} ] } | to_json }}"
  no_log: true

- name: Create the 1P creds item if absent
  ansible.builtin.command:
    argv: [env,-u,OP_CONNECT_HOST,-u,OP_CONNECT_TOKEN, op,item,create,
           "--vault","{{ opconnect_creds_vault }}","--template","{{ _tmp.path }}/creds-item.json"]
  when: _creds_item_check.rc != 0     # _creds_item_check = an `op item get … --format json` probe (mirror Step 1)
  no_log: true

- name: Update the 1P creds item if present (token rotated / creds changed)
  ansible.builtin.shell:
    cmd: "env -u OP_CONNECT_HOST -u OP_CONNECT_TOKEN op item edit '{{ opconnect_creds_1p_creds_item }}' --vault '{{ opconnect_creds_vault }}' < '{{ _tmp.path }}/creds-item.json'"
  when: _creds_item_check.rc == 0 and (_need_seed or _need_rotate | default(false) | bool)
  no_log: true
```
> Verify at implementation: `op item edit` accepts a piped JSON template (per `op item edit --help` "edit using piped input"); if the schema differs, fall back to `op item template get "Secure Note"` as the base + inject the two fields.

- [ ] **Step 6 — assemble + write the escrow bundle (always-run; idempotent; keypair from 1P):** move the `community.aws.secretsmanager_secret` write OUT of the seed/rotate block to here; `ansible_public_key = _eff_pub.stdout|trim`, `ansible_private_key = _eff_priv.stdout`, creds/token/expires from `_eff_*`. (Existing `_tmp` + `always:` shred/rm stay.)
- [ ] **Step 7:** `--syntax-check`. Commit.

## CR3: tofu/opconnect — pubkey from SSM
**File:** `tofu/opconnect/ssh-keys.tf` (renamed from `recovery.tf`) — replace body with `data "aws_ssm_parameter" "ansible_pubkey" { name = "/tmpx/onprem/opconnect/ansible_public_key" }` + `local.ansible_ssh_public_key = trimspace(data.aws_ssm_parameter.ansible_pubkey.value)`. Drop the `aws_kms_alias` data source. `opconnect.tf:45` reference unchanged. `fmt`+`validate` (`TF_CLI_CONFIG_FILE="$PWD/.tofurc" AWS_PROFILE=fcx-sso`). Commit.

## CR4: ssh-key-loader — opconnect reads the native key via `op read --out-file`
**Files:** `ansible/roles/ssh-key-loader/tasks/main.yml`, `ansible/playbooks/opconnect.yml`
- [ ] **Step 1:** Add an optional full-reference path to the loader: when `op_ssh_key_ref` is set (and `op_use_cli`), write the key directly — sidesteps the item/section/field template and carries the `?ssh-format=` query:
```yaml
- name: Retrieve SSH private key via op read --out-file (full reference)
  ansible.builtin.command:
    argv: [env,-u,OP_CONNECT_HOST,-u,OP_CONNECT_TOKEN, op,read,
           "--out-file","{{ ssh_key_loader_temp_path }}","--file-mode","0600","--force","{{ op_ssh_key_ref }}"]
  delegate_to: localhost
  run_once: true
  when: op_use_cli | default(false) | bool and (op_ssh_key_ref | default('') | length > 0)
  no_log: true
  tags: ['ssh-key','always']
```
Guard the existing op-CLI `op read`+copy tasks with `... and (op_ssh_key_ref | default('') | length == 0)` so exactly one path runs.
- [ ] **Step 2:** In `opconnect.yml`, on the SSH-key-load play:
```yaml
  vars:
    op_use_cli: true
    op_ssh_key_ref: "op://{{ lookup('env','TF_VAR_onepassword_vault_id') }}/opconnect Bootstrap SSH Key/private key?ssh-format=openssh"
```
> ✅ Field-direct (no section) confirmed live 2026-06-13 — this reference is final. `op read --out-file --file-mode 0600 --force` carries the `?ssh-format=openssh` query and writes a valid OpenSSH key (validated).
- [ ] **Step 3:** `--syntax-check`. Commit.

## CR5: opconnect deploy role — creds.json from 1P (retire local file)
**Files:** `ansible/roles/opconnect/tasks/main.yml`, `defaults/main.yml`
- [ ] Replace the `opconnect_credentials_local` copy with: `op read "op://{{vault}}/{{ opconnect_creds_1p_creds_item }}/credentials_json"` (account-mode, delegate localhost, `no_log`) → `copy: content: "{{ _opc_creds_b64.stdout | b64decode }}"` to the compose dir (0600, container uid), `notify: restart opconnect`. Keep the present-and-non-empty guards. Remove `opconnect_credentials_local` + update the `opconnect.yml` header. `--syntax-check`. Commit.

## CR6: Non-destructive validation
- [ ] `tofu -chdir=tofu/opconnect validate`; `--syntax-check` both playbooks; fleet-untouched greps (`Infrastructure Ansible SSH Key` only in fleet paths; `opconnect Bootstrap SSH Key`/`opconnect Connect Credentials` only in opconnect paths).

## CR7 (GATED — first seed; 1P generates the key, writes AWS + 1P)
- [ ] Preconditions: 1P desktop **unlocked**; `aws sso login --sso-session fcx-sso`.
- [ ] **GATED** run the seed (NO `-v`): `cd ansible && OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES no_proxy='*' .venv/bin/ansible-playbook playbooks/opconnect_credentials.yml -e "ansible_python_interpreter=$PWD/.venv/bin/python"`.
- [ ] **Verify:**
  - Field path is **pre-validated** (field-direct `private key`/`public key`, no section — live create→read→delete 2026-06-13); no longer a gate. Sanity-check: `op read "op://FusionCloudX/opconnect Bootstrap SSH Key/public key"` returns the key.
  - SSM == 1P pubkey: `aws ssm get-parameter --name /tmpx/onprem/opconnect/ansible_public_key --region us-east-2 --query Parameter.Value --output text` (AWS_PROFILE=fcx-sso) == `op read "op://FusionCloudX/opconnect Bootstrap SSH Key/public key"`.
  - Round-trip (use `--out-file`, NOT `ssh-keygen -y -f /dev/stdin` — it rejects stdin on a permissions guard): `op read --out-file /tmp/_k --file-mode 0600 --force "op://FusionCloudX/opconnect Bootstrap SSH Key/private key?ssh-format=openssh" && ssh-keygen -y -f /tmp/_k; shred -u /tmp/_k` → derived pubkey == the SSM pubkey. **GATE on mismatch.**
  - 1P items exist: `opconnect Bootstrap SSH Key` (SSH Key) + `opconnect Connect Credentials` (Secure Note).

## CR8 (GATED — opconnect-only rebuild + verify)
- [ ] `tofu -chdir=tofu/opconnect plan` — assert `tls_private_key`+`null_resource` destroyed; `data.aws_ssm_parameter.ansible_pubkey` read; cloud-init `user_data` authorizes the **dedicated** pubkey (VM recreate expected). Confirm dedicated key, not fleet.
- [ ] **GATED:** lift `prevent_destroy` on VM 1101 → `tofu apply` → restore `prevent_destroy`.
- [ ] **GATED:** `cd ansible && .venv/bin/ansible-playbook playbooks/opconnect.yml -e "ansible_python_interpreter=$PWD/.venv/bin/python"`.
- [ ] **Verify:** `/heartbeat` 200; `/health` pinned version + sqlite ACTIVE; serves a test secret; Ansible logged in with the **dedicated** key; **fleet pubkey NOT** in opconnect `authorized_keys` (grep → 0); no local-file creds; `tofu state list | grep -E 'tls_private_key|null_resource'` empty (#8). Commit → PR → @claude review → merge.

## CR9: Docs + memory + close-out
- [ ] Runbook (native 1P SSH-Key item, 1P-generates/can't-import, 1P homes + SSM, 1P day-2 / escrow DR); `enhance-harden-later.md` #8 SSH-key half RESOLVED; memory + `09-Homelab` docs; Nexus note.

---

## Self-Review
**Spec coverage:** D9 (native 1P SSH-Key item; CR1/CR2.1–2/CR4; CR8 fleet-key-absent) · D10 (SSM publish CR2.4 / read CR3) · D11 (1P writes CR2.5–6 + CR5; retire local file) · Direction B (1P day-2, escrow break-glass, SSM the one forced AWS read) · #8 (CR8) · fleet untouched (CR6) · gated (CR7/CR8) · idempotent/adoption-safe (always-run + `_eff_*`). ✅

**Sweep + live validation (v2.34.0, 2026-06-13):** `--category ssh --ssh-generate-key=ed25519 --vault FusionCloudX` creates an Ed25519 `SSH_KEY` item in the right vault (live create→read→delete, by name + UUID); `op read` field-direct refs `…/private key?ssh-format=openssh` + `…/public key` resolve (no section); loader via `op read --out-file --file-mode 0600` carries the query param + writes 0600 (avoids the `ssh-keygen -y -f /dev/stdin` permissions trap). Creds item via **JSON template** (CLI-arg secrets leak per `op item create --help`). **No passphrase at generation** (1P vault-encryption model). Import is GUI-only → 1P generates.

**Resolved live 2026-06-13** (no longer gates): SSH field path (field-direct, no section) · `--category ssh`+`--ssh-generate-key` coexistence · vault targeting · the `op read --out-file` loader mechanism · no-passphrase.

**Still open (named, not TODO):** (1) `op item create --template` + `op item edit` piped-template for the Secure-Note creds item (CR2.5 — confirm the hand-built JSON schema is accepted; fallback `op item template get "Secure Note"` as the base). (2) `community.aws.ssm_parameter` arg names (`string_type`/`overwrite_value`) vs the installed collection (CR2.4). (3) the SSM write + `data aws_ssm_parameter` read round-trip (live, CR7→CR8). (4) ordering: seed (CR7) before `tofu apply` (CR8). (5) adoption: escrow key `6dV2…`→new 1P key while creds/token preserved — expected.

*Plan 2026-06-13 (PM): A1 (SSM) + B1 (full consume) + D9 (dedicated, native 1P SSH-Key). Grounded in a live `op` v2.34.0 `--help` sweep. Wave 2 (CI OIDC, Roles Anywhere, SSH-CA) out of scope.*
