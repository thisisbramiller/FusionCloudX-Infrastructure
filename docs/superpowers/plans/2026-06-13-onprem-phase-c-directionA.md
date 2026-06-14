# onprem opconnect Phase C — Direction A (AWS-anchored, op-CLI-free consumer, native Connect TLS) Implementation Plan

> STATUS: EXECUTED + MERGED — PR #59 merged to main (fc1c43d, 2026-06-14). Direction A is live; the CREATE (clean-room first-seed) and ROTATE paths were validated end-to-end twice (2026-06-13/14); tofu plan no-op on onprem/opconnect AND aws-foundation/15 after seed and after rotate. The unchecked - [ ] steps below are the original plan, retained as the execution record.

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (or executing-plans). Steps use `- [ ]`. Every `tofu apply` / seed run / secret write / opconnect rebuild touches LIVE AWS or the secrets root — each is a **STOP-and-confirm with Branden** (CR9/CR10 are hard gates). **Never** run the seed at `-v`/`-vvv` (`no_log` bypass). **Never** print a secret value — only fingerprints / hashes / public keys. Shred temp files after secret handling. No `Co-Authored-By: Claude` trailer on commits (Branden's personal repo).

**Goal:** Complete the #68 opconnect consumer in **Direction A** — opconnect bootstraps entirely from the **AWS bundle** (dedicated SSH private key + `credentials.json` + Connect token via `amazon.aws.aws_secret`), the cloud-init **public** key from **SSM**, its Connect API served over **TLS using 1Password Connect's native TLS** (cert self-served on-box, no nginx), and **zero `op`-CLI / 1Password-account-mode in the consumer**. The 4 fleet VMs (1P-via-Connect, unchanged) are untouched.

**Architecture:** The **seed generates** the dedicated Ed25519 keypair locally (`community.crypto.openssh_keypair`), publishes the public half to an SSM String param, and writes the private half + `credentials.json` + token into the AWS Secrets Manager bundle. `tofu/opconnect` reads only the SSM public key → cloud-init `authorized_keys` (no private key in state, #8). At provision time the `ssh-key-loader` reads the **private** key from the bundle; the `opconnect` deploy role reads `credentials.json` from the bundle and brings Connect up on **loopback HTTP**; a post-deploy on-box step reads the server cert from opconnect's **own** Connect API, writes it locally, and flips connect-api to **native TLS** (`OP_TLS_CERT_FILE`/`OP_TLS_KEY_FILE`/`OP_HTTPS_PORT`). 1Password holds **nothing** for opconnect.

**Spec:** `…/specs/2026-06-13-onprem-bootstrap-trust-recovery-anchor-design.md` — **Revision 2** (D11′/D12/D13/D14; D9/D10 stand). **Supersedes** `…/plans/2026-06-13-onprem-phase-c-dedicated-key-directionB.md` (withdrawn). **Branch:** `feat/onprem-bootstrap-trust`.

**Native TLS facts (grounded — [1Password Connect server-configuration docs](https://www.1password.dev/connect/connect-server-configuration/), verified 2026-06-13):**
- `OP_TLS_CERT_FILE` = path to the **full-chain** PEM cert; `OP_TLS_KEY_FILE` = path to the PEM private key; `OP_HTTPS_PORT` (default **8443**); `OP_HTTP_PORT` (default **8080**). TLS env vars apply to the **connect-api** container ONLY (connect-sync does NOT take them).
- Cert files must be **readable by UID 999** (the `opuser` the containers run as).
- `OP_CONNECT_HOST` must carry the scheme — `https://…` once TLS is on.
- The docs do not state whether the HTTP listener stays active when TLS is on; we make this moot by **loopback-binding** the HTTP port in the compose port map so it is never LAN-reachable regardless.

**As-built starting point (Direction-B, committed — this plan reverts + extends it):**
- Seed (`opconnect_credentials/tasks/main.yml`): 1P generates the SSH-Key item, writes a 1P creds item + SSM pubkey + the AWS bundle. → seed generates **locally**, drops **both** 1P items.
- `ssh-key-loader/{tasks,defaults}`: Connect path + two `op` paths gated by `op_use_cli` (defaults carry `op_use_cli: false` + `op_ssh_key_ref: ""`). → replace `op` paths with an `aws_bundle` path; delete the boolean.
- opconnect deploy role: reads `credentials.json` from a 1P item via `op`; `defaults/main.yml` carries `opconnect_creds_1p_creds_item`. → read from the AWS bundle; drop the 1P default.
- opconnect compose (`roles/opconnect/templates/docker-compose.yml.j2`): connect-api `"{{ opconnect_api_port }}:8080"` = **`8080:8080` on 0.0.0.0** (LAN-plaintext), no TLS env. → loopback-bind HTTP + add native TLS + publish HTTPS.
- `certificates` role: PATH A (Connect, fleet) + PATH B (`op`, opconnect) gated by `op_use_cli` (`defaults/main.yml:28`). opconnect.yml runs it PRE-deploy. `nginx.yml` only drops an SSL **snippet** (no `server{}`/`listen 443`/`proxy_pass`); nothing installs nginx on opconnect. → remove PATH B + `op_use_cli` (fleet keeps PATH A); **opconnect stops using the certificates role entirely** (native Connect TLS instead).
- AWS layer `aws-foundation/15-opconnect-credentials`: bundle already holds creds.json+token+keypair; tofu reads only the SSM pubkey. **No aws-foundation changes.**
- `tofu/opconnect/ssh-keys.tf`: reads the SSM pubkey (D10, committed). `variables.tf` trailing comment still says the key "is now a 1Password SSH-Key item" (stale — fix in CR3).
- **Inventory reality (grounded):** `ansible.cfg` sets `inventory = ./inventory/`; group_vars live at `ansible/inventory/group_vars/all.yml` (a FILE). The seed playbook runs `-i 'localhost,'`; the opconnect consumer runs with TWO inventories (`-i inventory-bootstrap-localhost.yml -i opconnect.inventory.yml`) and NO `AWS_PROFILE` env — the cloud.terraform inventory + the tofu backend self-authenticate via the in-config `profile=fcx-sso` (bootstrap-localhost scopes the venv python to localhost; opconnect.inventory.yml is the `cloud.terraform` dynamic inventory, S3-backed). **Neither runner loads `inventory/group_vars/`** → the shared bundle contract must come via `vars_files`, NOT group_vars.

**Bundle JSON fields** (written by the seed): `connect_credentials_json` (b64), `connect_token`, `connect_host`, `ansible_public_key`, `ansible_private_key`, `token_expires`, `created`, `notes`.

---

## File structure (what each change owns)

| File | Responsibility | CR |
|---|---|---|
| `ansible/playbooks/vars/opconnect-bundle.yml` (**create**) | Shared AWS-bundle access contract (name/region/role/profile), loaded by both playbooks via `vars_files` (NOT group_vars — neither runner loads inventory/group_vars) | CR1 |
| `ansible/requirements.yml` | Declare `amazon.aws`, `community.aws`, `community.crypto` (used by seed + consumers; currently undeclared) | CR1 |
| `ansible/roles/opconnect_credentials/{tasks,defaults}/main.yml` | Seed **generates locally**; drops 1P generate/read-back + 1P creds item; empty-key assert; uses `opconnect_bundle_*` from the shared vars | CR1/CR2 |
| `ansible/playbooks/opconnect_credentials.yml` | Add `vars_files: vars/opconnect-bundle.yml` | CR1 |
| `tofu/opconnect/ssh-keys.tf` + `variables.tf` | SSM pubkey read (confirm); fix stale `variables.tf` comment to Direction A | CR3 |
| `ansible/roles/ssh-key-loader/{tasks,defaults}/main.yml` | Replace `op` paths with an `aws_bundle` source; **delete `op_use_cli` + `op_ssh_key_ref` from BOTH tasks and defaults** | CR4 |
| `ansible/playbooks/opconnect.yml` | `vars_files`; play 1 → `ssh_key_source: aws_bundle` (drop `op_use_cli`/`op_ssh_key_ref`/the pubkey assert); drop the pre-deploy certificates play; add the post-deploy native-TLS play; deploy play loses `op_use_cli` + the auth gate | CR4/CR5/CR6b/CR7 |
| `ansible/roles/opconnect/{tasks,defaults}/main.yml` | Read `credentials.json` from the AWS bundle; rewrite the fail-message (drop 1P string); drop `opconnect_creds_1p_creds_item` | CR5 |
| `ansible/roles/opconnect/templates/docker-compose.yml.j2` | Loopback-bind HTTP; conditional native-TLS env + cert mount + published HTTPS port | CR6b |
| `ansible/roles/opconnect/tasks/tls.yml` (**create**) | On-box: prime sync → poll → read cert from local Connect via `uri` → write locally → enable TLS → restart connect-api | CR6b |
| `ansible/roles/certificates/{tasks/retrieve-certs.yml,tasks/main.yml,tasks/deploy-cert.yml,defaults/main.yml}` | Remove PATH B (`op`) + `op_use_cli`; `no_log` the server-key copy (pre-existing fleet gap) | CR6a |

---

## CR1: Shared bundle contract (`vars_files`) + collections + seed defaults

**Files:** `ansible/playbooks/vars/opconnect-bundle.yml` (create), `ansible/requirements.yml`, `ansible/roles/opconnect_credentials/defaults/main.yml`, `ansible/playbooks/opconnect_credentials.yml`

- [ ] **Step 1 — create the shared contract** at `ansible/playbooks/vars/opconnect-bundle.yml` (a `vars_files` target — loads regardless of inventory, unlike `group_vars`):
```yaml
# ansible/playbooks/vars/opconnect-bundle.yml
# The AWS Secrets Manager bundle that bootstraps opconnect (Direction A, #68).
# Loaded via `vars_files` by BOTH playbooks/opconnect_credentials.yml (seed, runs
# `-i 'localhost,'`) and playbooks/opconnect.yml (consumer, runs `-i opconnect.inventory.yml`).
# group_vars is NOT used: neither runner loads ansible/inventory/group_vars/.
opconnect_bundle_secret_name: "tmpx/onprem/opconnect-credentials"
opconnect_bundle_region: "us-east-2"
opconnect_bundle_assume_role_arn: "arn:aws:iam::065094257518:role/OrganizationAccountAccessRole"
opconnect_bundle_sso_profile: "fcx-sso" # AWS CLI SSO profile (passed as a PARAM, never AWS_PROFILE env)
```

- [ ] **Step 2 — declare the collections** in `ansible/requirements.yml` (currently only `onepassword.connect` + `community.general`; a clean `ansible-galaxy collection install -r requirements.yml` must pull everything the seed + consumers + the opconnect rebuild use — incl. `community.docker` (the opconnect handler + docker role + `docker_compose_v2`) and `cloud.terraform` (the `opconnect.inventory.yml` dynamic inventory CR10 runs with), both currently undeclared):
```yaml
  - name: amazon.aws
  - name: community.aws
  - name: community.crypto
  - name: community.docker
  - name: cloud.terraform
```
Run `ansible-galaxy collection list | rg -i 'amazon.aws|community.aws|community.crypto|community.docker|cloud.terraform'` to confirm versions present in the venv; pin if the team pins elsewhere.

- [ ] **Step 3 — seed playbook loads the contract.** In `playbooks/opconnect_credentials.yml`, add to the play: `vars_files: [ vars/opconnect-bundle.yml ]` (path is playbook-relative).

- [ ] **Step 4 — seed defaults reference the shared names + drop 1P items.** In `opconnect_credentials/defaults/main.yml`: replace the four literals with references to the shared vars, and **delete** `opconnect_creds_1p_ssh_item` + `opconnect_creds_1p_creds_item`:
```yaml
opconnect_creds_secret_name: "{{ opconnect_bundle_secret_name }}"
opconnect_creds_region: "{{ opconnect_bundle_region }}"
opconnect_creds_assume_role_arn: "{{ opconnect_bundle_assume_role_arn }}"
opconnect_creds_sso_profile: "{{ opconnect_bundle_sso_profile }}"
# (unchanged) opconnect_creds_kms_alias / _vault / _server_name / _connect_host /
#             _token_ttl_days / _rotate_threshold_days / _ssm_pubkey_name
# REMOVED: opconnect_creds_1p_ssh_item, opconnect_creds_1p_creds_item (Direction A — no 1P items)
```
> These references resolve at use-time (lazy Jinja); the `vars_files` load (Step 3) makes `opconnect_bundle_*` available to the seed role. The seed tasks already use `opconnect_creds_*` — no task edits needed for the rename.

- [ ] **Step 5:** `cd ansible && .venv/bin/ansible-playbook playbooks/opconnect_credentials.yml -i 'localhost,' --syntax-check`. Commit.

## CR2: Seed — generate the keypair LOCALLY; drop both 1P items; empty-key assert

**File:** `ansible/roles/opconnect_credentials/tasks/main.yml`. The STS-assume, current-bundle read, seed/rotate/no-op decision, the `op connect server create` + `op connect token create` (Step 3), the SSM publish (Step 4), and the bundle write (Step 6) **stay**. Replace key generation; delete the 1P creds item (Step 5).

- [ ] **Step 1 — remove the 1P SSH-Key tasks** (`Check whether the dedicated 1P SSH-Key item exists`, `Generate the dedicated Ed25519 SSH key in 1Password if absent`, `Read dedicated public key from 1Password`, `Read dedicated private key from 1Password (OpenSSH)` — current lines ~75–148).

- [ ] **Step 2 — generate locally inside the `Distribute` block, after `Create a 0700 scratch dir`:**
```yaml
    - name: Generate the dedicated Ed25519 keypair locally (first seed / adoption)
      community.crypto.openssh_keypair:
        path: "{{ _tmp.path }}/opconnect_ed25519"
        type: ed25519
        comment: "opconnect-bootstrap"
      register: _keygen
      when: _need_seed | bool or (_cur.ansible_private_key | default('') | length == 0)
      no_log: true

    - name: Read the generated keypair back (first seed / adoption only)
      ansible.builtin.slurp:
        src: "{{ item }}"
      loop:
        - "{{ _tmp.path }}/opconnect_ed25519"
        - "{{ _tmp.path }}/opconnect_ed25519.pub"
      register: _keyfiles
      when: _keygen.changed | default(false)
      no_log: true

    - name: Compute effective keypair (generated this run, else current bundle)
      ansible.builtin.set_fact:
        _eff_priv: "{{ (_keyfiles.results[0].content | b64decode) if (_keygen.changed | default(false)) else _cur.ansible_private_key }}"
        _eff_pub: "{{ (_keyfiles.results[1].content | b64decode | trim) if (_keygen.changed | default(false)) else _cur.ansible_public_key }}"
      no_log: true

    - name: Assert the effective keypair is non-empty (never escrow an empty key)
      ansible.builtin.assert:
        that:
          - _eff_priv | length > 0
          - _eff_pub | length > 0
        fail_msg: "Refusing to write the bundle with an empty SSH key (would orphan the running opconnect VM)."
        quiet: true
```
> `_eff_priv`/`_eff_pub` are now **strings** (slurp+b64decode), not `.stdout`. Update Steps 4 + 6 references (next steps). The empty-key assert closes the silent-rotation footgun.

- [ ] **Step 3 — delete the 1P creds-item tasks** (`Build the Connect-creds item JSON`, `Check whether the 1P creds item exists`, `Create the 1P creds item if absent`, `Update the 1P creds item if present`). `credentials.json` + token live **only** in the AWS bundle now.

- [ ] **Step 4 — SSM publish reference:** `value: "{{ _eff_pub }}"` (was `_eff_pub.stdout | trim`).

- [ ] **Step 5 — bundle-write references** (`Assemble the bundle JSON`): `'ansible_public_key': _eff_pub`, `'ansible_private_key': _eff_priv` (were `.stdout` forms). Update `notes` to drop any "1P day-2" wording (Direction A: the bundle is the authoritative opconnect source).

- [ ] **Step 6:** `--syntax-check`. `rg -n 'op item|1p_ssh_item|1p_creds_item|creds-item.json' ansible/roles/opconnect_credentials` → only `op connect server`/`op connect token` survive. Commit.

## CR3: tofu/opconnect — SSM pubkey (confirm) + fix stale comment
**Files:** `tofu/opconnect/ssh-keys.tf` (confirm only), `tofu/opconnect/variables.tf` (one comment edit)
- [ ] Confirm `ssh-keys.tf` reads `/tmpx/onprem/opconnect/ansible_public_key` via `data "aws_ssm_parameter"`; `tofu -chdir=tofu/opconnect validate` clean (`TF_CLI_CONFIG_FILE="$PWD/.tofurc"`; tofu self-authenticates via the in-config `profile=fcx-sso`); no `onepassword` provider in `providers.tf`.
- [ ] Edit the trailing comment in `variables.tf` (the block ~line 41-47 that says the dedicated key "is now a 1Password SSH-Key item") to Direction A: the dedicated key is **generated locally by the seed**, the **private** half lives in the AWS bundle, the **public** half in SSM (read here); 1Password holds nothing for opconnect.
- [ ] Also fix the stale Direction-B comment in `ssh-keys.tf` (~line 8, "private key + creds read by ANSIBLE from 1Password (Direction B)") → Direction A: Ansible reads the private key + creds from the **AWS bundle** (`amazon.aws.aws_secret`); tofu reads only the non-secret SSM public key.
- [ ] `tofu -chdir=tofu/opconnect fmt`. Commit.

## CR4: ssh-key-loader — read the private key from the AWS bundle; delete `op_use_cli`
**Files:** `ansible/roles/ssh-key-loader/tasks/main.yml`, `ansible/roles/ssh-key-loader/defaults/main.yml`, `ansible/playbooks/opconnect.yml`

- [ ] **Step 1 — add the `aws_bundle` source path** (runs on `localhost`, opconnect.yml play 1 is `hosts: localhost`). Insert after the clean-workspace task:
```yaml
- name: Assume shared-services for the opconnect bundle read (aws_bundle source)
  amazon.aws.sts_assume_role:
    role_arn: "{{ opconnect_bundle_assume_role_arn }}"
    role_session_name: "opconnect-ssh-key-load"
    region: "{{ opconnect_bundle_region }}"
    profile: "{{ opconnect_bundle_sso_profile }}"
  delegate_to: localhost
  run_once: true
  no_log: true
  register: _sshload_assumed
  when: ssh_key_source | default('connect') == 'aws_bundle'
  tags: ['ssh-key', 'always']

- name: Read the dedicated private key from the AWS bundle
  ansible.builtin.set_fact:
    _bundle_priv: >-
      {{ (lookup('amazon.aws.aws_secret', opconnect_bundle_secret_name,
            region=opconnect_bundle_region,
            access_key=_sshload_assumed.sts_creds.access_key,
            secret_key=_sshload_assumed.sts_creds.secret_key,
            session_token=_sshload_assumed.sts_creds.session_token)
          | from_json).ansible_private_key }}
  delegate_to: localhost
  run_once: true
  no_log: true
  when: ssh_key_source | default('connect') == 'aws_bundle'
  tags: ['ssh-key', 'always']

- name: Write the bundle private key to the secure temp file (0600)
  ansible.builtin.copy:
    content: "{{ _bundle_priv if _bundle_priv.endswith('\n') else _bundle_priv + '\n' }}"
    dest: "{{ ssh_key_loader_temp_path }}"
    mode: '0600'
  delegate_to: localhost
  run_once: true
  no_log: true
  when: ssh_key_source | default('connect') == 'aws_bundle'
  tags: ['ssh-key', 'always']
```

- [ ] **Step 2 — delete the `op` paths + re-guard the Connect path.** Remove `Retrieve Ansible SSH private key via op (...)` + `Retrieve SSH private key via op read --out-file (full reference)`. Change the Connect retrieval `when:` → `ssh_key_source | default('connect') == 'connect'`; change the final `Write SSH key to secure temp file` `when:` → `ssh_key_source | default('connect') == 'connect'` and its `content:` → `_ssh_key_result.field.value` (drop the `op_use_cli` ternary). Status `debug` → `via {{ ssh_key_source | default('connect') }}`. Rewrite the role header (PATH A = Connect/fleet default; PATH B = AWS bundle/opconnect); drop all `op_use_cli`/`op_ssh_key_ref` prose.

- [ ] **Step 3 — delete the orphaned defaults.** In `ssh-key-loader/defaults/main.yml`, **delete** `op_use_cli: false` (line ~18) and `op_ssh_key_ref: ""` (line ~25) and their header prose. (Without this CR8's grep-zero gate fails.)

- [ ] **Step 4 — opconnect.yml play 1** (`Load SSH Key …`): replace `vars: { op_use_cli: true, op_ssh_key_ref: "op://..." }` with `vars: { ssh_key_source: aws_bundle }`. **Delete the entire `pre_tasks` `Assert TF_VAR_onepassword_vault_id is set` block** (the `op://` ref is gone). Add `vars_files: [ vars/opconnect-bundle.yml ]` **to this play**. Update the play header to Direction A (privkey from the AWS bundle; SSO+FIDO at the workstation; Connect-independent).
> **`vars_files` is a per-PLAY keyword in Ansible — there is no playbook-wide inheritance.** EVERY play in `opconnect.yml` that reads `opconnect_bundle_*` MUST declare `vars_files: [ vars/opconnect-bundle.yml ]` explicitly: **play 1** (here), the **Deploy 1Password Connect** play (CR5 Step 1), and the **TLS** play (CR6b Step 4, already declared). Verify all three carry it before CR8.

- [ ] **Step 5:** `--syntax-check`. Commit.

## CR5: opconnect deploy role — `credentials.json` from the AWS bundle
**Files:** `ansible/playbooks/opconnect.yml`, `ansible/roles/opconnect/tasks/main.yml`, `ansible/roles/opconnect/defaults/main.yml`

- [ ] **Step 0 — wire the bundle vars into the Deploy play.** In `opconnect.yml`, add `vars_files: [ vars/opconnect-bundle.yml ]` to the `Deploy 1Password Connect` play (it now reads `opconnect_bundle_*` — without this they are UNDEFINED at runtime; `vars_files` does not inherit across plays).
- [ ] **Step 1 — replace the 1P creds read** (`Read Connect credentials.json from 1Password (...)`, ~lines 40–57) with a bundle read delegated to localhost:
```yaml
- name: Assume shared-services for the opconnect bundle read (creds.json)
  amazon.aws.sts_assume_role:
    role_arn: "{{ opconnect_bundle_assume_role_arn }}"
    role_session_name: "opconnect-deploy-creds"
    region: "{{ opconnect_bundle_region }}"
    profile: "{{ opconnect_bundle_sso_profile }}"
  delegate_to: localhost
  become: false
  run_once: true
  register: _opc_deploy_assumed
  no_log: true
  tags: ['opconnect', 'deploy', 'secrets']

- name: Read Connect credentials.json (b64) from the AWS bundle
  ansible.builtin.set_fact:
    _opc_creds_b64: >-
      {{ (lookup('amazon.aws.aws_secret', opconnect_bundle_secret_name,
            region=opconnect_bundle_region,
            access_key=_opc_deploy_assumed.sts_creds.access_key,
            secret_key=_opc_deploy_assumed.sts_creds.secret_key,
            session_token=_opc_deploy_assumed.sts_creds.session_token)
          | from_json).connect_credentials_json }}
  delegate_to: localhost
  become: false
  run_once: true
  no_log: true
  tags: ['opconnect', 'deploy', 'secrets']
```
- [ ] **Step 2 — staging:** the `Stage 1Password Connect credentials …` copy task → change `_opc_creds_b64.stdout` to `_opc_creds_b64` (now a string fact). Keep the present-and-non-empty guards + `notify: restart opconnect`.
- [ ] **Step 3 — rewrite the fail-fast message** (`Fail fast if the credentials file is missing or empty`, ~lines 79–88): reference the **AWS bundle** field `connect_credentials_json` (secret `{{ opconnect_bundle_secret_name }}`) — **remove the `opconnect_creds_1p_creds_item` string** (else CR8's `opconnect Connect Credentials → 0` grep fails). Update the role header (~lines 9–21) to Direction A.
- [ ] **Step 4 — drop the 1P default.** In `opconnect/defaults/main.yml`, delete `opconnect_creds_1p_creds_item` (line ~43) and its comment; add `vars_files`-sourced `opconnect_bundle_*` is provided by the playbook, so no new defaults needed here.
- [ ] **Step 5:** `--syntax-check`. Commit.

## CR6a: certificates role — remove the `op` cert path + `op_use_cli` (fleet hygiene)
**Files:** `ansible/roles/certificates/tasks/retrieve-certs.yml`, `defaults/main.yml`, `tasks/deploy-cert.yml`
- [ ] Delete the entire `Retrieve certificates via op CLI (...)` PATH B block (`retrieve-certs.yml` ~lines 118–218). Change PATH A's guard from `when: not (op_use_cli | default(false) | bool)` to unconditional (the fleet always uses Connect via the controller). Delete `op_use_cli: false` from `certificates/defaults/main.yml` (line ~28). The fleet's PATH A (Connect, `delegate_to: localhost`) is unchanged.
- [ ] **`no_log` the server key copy** (pre-existing fleet gap): in `deploy-cert.yml`, add `no_log: true` to the `Deploy server private key` copy task (and defensively the cert/chain copies). Low effort, real exposure at `-v`.
- [ ] `--syntax-check` `site.yml`. Commit.

## CR6b: opconnect native Connect TLS (self-served on-box, no nginx)
**Files:** `ansible/roles/opconnect/templates/docker-compose.yml.j2`, `ansible/roles/opconnect/defaults/main.yml`, `ansible/roles/opconnect/tasks/tls.yml` (create), `ansible/playbooks/opconnect.yml`

- [ ] **Step 1 — defaults.** In `opconnect/defaults/main.yml` add:
```yaml
opconnect_tls_enabled: false              # phase flag — true on the 2nd render (TLS on)
opconnect_https_external_port: 443        # host port published for HTTPS (container OP_HTTPS_PORT=8443)
opconnect_tls_dir: "{{ opconnect_compose_dir }}/tls"   # holds fullchain.pem + server-key.pem (0600, UID 999)
```

- [ ] **Step 2 — compose template.** Edit `docker-compose.yml.j2` connect-api (and connect-sync) so the plaintext API is loopback-only and TLS is conditional:
```jinja
  connect-api:
    image: {{ opconnect_connect_api_image }}:{{ opconnect_connect_version }}
    container_name: connect-api
    restart: always
    ports:
      - "127.0.0.1:{{ opconnect_api_port }}:8080"        # loopback HTTP — on-box + health only, never LAN
{% if opconnect_tls_enabled %}
      - "{{ opconnect_https_external_port }}:8443"        # published HTTPS (container OP_HTTPS_PORT=8443)
{% endif %}
    environment:
      OP_LOG_LEVEL: "{{ opconnect_log_level }}"
{% if opconnect_tls_enabled %}
      OP_HTTPS_PORT: "8443"
      OP_TLS_CERT_FILE: "/home/opuser/.op/tls/fullchain.pem"
      OP_TLS_KEY_FILE: "/home/opuser/.op/tls/server-key.pem"
{% endif %}
    volumes:
      - "./1password-credentials.json:/home/opuser/.op/1password-credentials.json:ro"
      - "data:/home/opuser/.op/data"
{% if opconnect_tls_enabled %}
      - "./tls:/home/opuser/.op/tls:ro"
{% endif %}
```
Also loopback-bind connect-sync: `"127.0.0.1:{{ opconnect_sync_port }}:8080"`.

- [ ] **Step 3 — create `roles/opconnect/tasks/tls.yml`** (on-box, `uri`-only so the VM needs no extra collection). The token comes from the bundle (read on the controller, passed in); all reads hit `http://localhost:{{ opconnect_api_port }}`:
```yaml
---
# opconnect native TLS — phase 2. Runs ON opconnect. Reads the server cert from
# opconnect's OWN local Connect (loopback HTTP), writes it locally, flips connect-api
# to native TLS. No controller round-trip of the key; no AWS escrow of the cert.

# Sync-readiness gate FIRST (modeled on the proven P4.3 layered gate, cutover spec
# 2026-06-06-p4-opconnect-cutover-design.md): /heartbeat (liveness) is NOT enough —
# the cert item is only retrievable after connect-sync pulls the vault from
# 1password.com. The deploy role documents sync=TOKEN_NEEDED is EXPECTED at its end.
# Poll /health until sync LEAVES TOKEN_NEEDED *and* sqlite is ACTIVE, with a LOUD
# hard timeout, BEFORE the item read — so a wedged/slow sync (e.g. api/sync image
# mismatch, which /heartbeat won't catch) fails loudly instead of an opaque hang.
- name: Wait for connect-sync to prime the vault (/health, not just /heartbeat)
  ansible.builtin.uri:
    url: "http://localhost:{{ opconnect_api_port }}/health"
    headers: { Authorization: "Bearer {{ opconnect_tls_connect_token }}" }
    return_content: true
    status_code: 200
  register: _sync_health
  retries: 36          # 36 x 5s = 180s ceiling for the first vault sync; raise only with a documented vault-size reason
  delay: 5
  until:
    - _sync_health.status == 200
    - (_sync_health.json.dependencies | selectattr('service','equalto','sqlite') | map(attribute='status') | first | default('')) == 'ACTIVE'
    - (_sync_health.json.dependencies | selectattr('service','equalto','sync')   | map(attribute='status') | first | default('')) not in ['TOKEN_NEEDED','']
  no_log: true

- name: Find the FusionCloudX vault id (local Connect)
  ansible.builtin.uri:
    url: "http://localhost:{{ opconnect_api_port }}/v1/vaults"
    headers: { Authorization: "Bearer {{ opconnect_tls_connect_token }}" }
    return_content: true
  register: _vaults
  retries: 30
  delay: 5
  until: _vaults.status == 200 and (_vaults.json | selectattr('name','equalto', opconnect_creds_vault) | list | length > 0)
  no_log: true

- name: Resolve vault id
  ansible.builtin.set_fact:
    _vault_id: "{{ (_vaults.json | selectattr('name','equalto', opconnect_creds_vault) | first).id }}"
  no_log: true

# Poll the ITEM (not just /heartbeat) — connect-sync may still be priming the vault
# from 1password.com (the deploy role documents sync=TOKEN_NEEDED until a /v1 read
# primes it). Success = the cert item + its files are actually retrievable.
- name: Find the Intermediate CA Bundle item (retry until synced)
  ansible.builtin.uri:
    url: "http://localhost:{{ opconnect_api_port }}/v1/vaults/{{ _vault_id }}/items"
    headers: { Authorization: "Bearer {{ opconnect_tls_connect_token }}" }
    return_content: true
  register: _items
  retries: 60
  delay: 5
  until: _items.status == 200 and (_items.json | selectattr('title','equalto','FusionCloudX Intermediate CA Bundle') | list | length > 0)
  no_log: true

- name: Resolve item id
  ansible.builtin.set_fact:
    _item_id: "{{ (_items.json | selectattr('title','equalto','FusionCloudX Intermediate CA Bundle') | first).id }}"
  no_log: true

- name: Get the item detail (file content_paths)
  ansible.builtin.uri:
    url: "http://localhost:{{ opconnect_api_port }}/v1/vaults/{{ _vault_id }}/items/{{ _item_id }}"
    headers: { Authorization: "Bearer {{ opconnect_tls_connect_token }}" }
    return_content: true
  register: _item
  retries: 30
  delay: 5
  until: _item.status == 200 and (_item.json.files | selectattr('name','equalto','fullchain.pem') | list | length > 0) and (_item.json.files | selectattr('name','equalto','server-key.pem') | list | length > 0)
  no_log: true

- name: Ensure the TLS dir exists (0750, UID 999)
  ansible.builtin.file:
    path: "{{ opconnect_tls_dir }}"
    state: directory
    owner: "{{ opconnect_container_uid }}"
    group: "{{ opconnect_container_uid }}"
    mode: '0750'

- name: Download fullchain + server key from local Connect, write 0600 (UID 999)
  ansible.builtin.uri:
    url: "http://localhost:{{ opconnect_api_port }}{{ (_item.json.files | selectattr('name','equalto', item.fname) | first).content_path }}"
    headers: { Authorization: "Bearer {{ opconnect_tls_connect_token }}" }
    return_content: true
    dest: "{{ opconnect_tls_dir }}/{{ item.fname }}"
    mode: '0600'
    owner: "{{ opconnect_container_uid }}"
    group: "{{ opconnect_container_uid }}"
  loop:
    - { fname: "fullchain.pem" }
    - { fname: "server-key.pem" }
  no_log: true

- name: Re-render compose with TLS enabled
  ansible.builtin.template:
    src: docker-compose.yml.j2
    dest: "{{ opconnect_compose_dir }}/docker-compose.yml"
    owner: root
    group: root
    mode: '0640'
  vars:
    opconnect_tls_enabled: true
  notify: restart opconnect

- name: Apply (restart connect-api on TLS)
  ansible.builtin.meta: flush_handlers

- name: Verify HTTPS is serving (local)
  ansible.builtin.uri:
    url: "https://localhost:{{ opconnect_https_external_port }}/heartbeat"
    validate_certs: false   # local loopback check; SAN/issuer validated in CR10 against the hostname
    status_code: 200
  register: _https_hb
  retries: 12
  delay: 5
  until: _https_hb is succeeded
```
> The `uri` `dest:` writes the response body straight to the file (no `content` fact, no echo/argv) — the key never lands in a var or shell history. `validate_certs: false` here is a loopback liveness check only; CR10 does the real hostname/SAN validation.

- [ ] **Step 4 — opconnect.yml: drop the pre-deploy certificates play; add the post-deploy TLS play.** Remove play 2 (`Common Infrastructure Configuration (opconnect)` running `certificates`). Fold its apt-cache update into the deploy play `pre_tasks`. **After** the `Deploy 1Password Connect` play and **before** the `Cleanup SSH Key` play, add:
```yaml
- name: Configure opconnect native TLS (cert self-served on-box)
  hosts: opconnect
  become: yes
  gather_facts: yes
  vars_files: [ vars/opconnect-bundle.yml ]
  vars:
    ansible_ssh_private_key_file: "/tmp/.ansible_ssh_key"
  pre_tasks:
    - name: Assume shared-services for the bundle (Connect token)
      amazon.aws.sts_assume_role:
        role_arn: "{{ opconnect_bundle_assume_role_arn }}"
        role_session_name: "opconnect-tls-token"
        region: "{{ opconnect_bundle_region }}"
        profile: "{{ opconnect_bundle_sso_profile }}"
      delegate_to: localhost
      become: false
      run_once: true
      register: _tls_assumed
      no_log: true
    - name: Read the Connect token from the AWS bundle
      ansible.builtin.set_fact:
        opconnect_tls_connect_token: >-
          {{ (lookup('amazon.aws.aws_secret', opconnect_bundle_secret_name,
                region=opconnect_bundle_region,
                access_key=_tls_assumed.sts_creds.access_key,
                secret_key=_tls_assumed.sts_creds.secret_key,
                session_token=_tls_assumed.sts_creds.session_token)
              | from_json).connect_token }}
      delegate_to: localhost
      become: false
      run_once: true
      no_log: true
  tasks:
    - name: Include opconnect TLS tasks
      ansible.builtin.include_role:
        name: opconnect
        tasks_from: tls.yml
```
Must be inserted **between** the Deploy play and the Cleanup play (the TLS read needs `/tmp/.ansible_ssh_key`, which Cleanup shreds last).
> Note: `include_role: name=opconnect` in this separate play re-asserts the role's `docker` meta-dependency (per-play dep dedup resets). It is **idempotent** (the docker role no-ops) — accept it; the role defaults still load so `opconnect_api_port`/`opconnect_container_uid`/`opconnect_compose_dir`/`opconnect_tls_dir` resolve. (If the recap clutter ever matters, factor `tls.yml` into a thin wrapper role without the docker meta-dep — not now.)

- [ ] **Step 5 — repoint downstream to HTTPS.** Update `opconnect_creds_connect_host` (seed defaults + the bundle `connect_host`) and the deploy role's status message + `tofu/opconnect` `connect_host` output to `https://opconnect.fusioncloudx.home` (no `:8080`). Day-2 consumers set `OP_CONNECT_HOST=https://opconnect.fusioncloudx.home`. (Scheme is mandatory per the docs.)
- [ ] **Step 6:** `--syntax-check`. Commit.

## CR7: opconnect.yml deploy play — retire the `op_use_cli` auth gate
**File:** `ansible/playbooks/opconnect.yml`
- [ ] In the `Deploy 1Password Connect` play: delete the `op_use_cli: true` var (and any other `op_use_cli`), delete the `Ensure a 1Password auth path is available (Connect read path)` fail gate and the three-way `Display opconnect bootstrap auth status` debug; replace with a one-line debug confirming Direction A (SSH key + creds from the AWS bundle; Connect-independent). `--syntax-check`. Commit.

## CR8: Non-destructive validation (no live infra)
- [ ] `tofu -chdir=tofu/opconnect validate` clean.
- [ ] `--syntax-check` `opconnect.yml` (`-i 'localhost,'` won't resolve `opconnect` hosts but syntax-check is host-agnostic) + `site.yml`.
- [ ] **Grep-zero gates (scoped correctly — do NOT assert the vault-id var to zero estate-wide):**
  - `rg -n 'op_use_cli|op_ssh_key_ref' ansible/` → **0** (these are genuinely removed estate-wide).
  - `rg -n 'TF_VAR_onepassword_vault_id' ansible/playbooks/opconnect.yml` → **0** ONLY (the opconnect bootstrap surface). **Estate-wide this var has 14+ legitimate fleet uses** — the fleet ssh-key-loader Connect path keeps `_op_vault_id` (ssh-key-loader/tasks/main.yml:45) + the app playbooks/roles use it; asserting it to 0 across `ansible/` is impossible and would block a correct implementation.
  - `rg -n 'opconnect Bootstrap SSH Key|opconnect Connect Credentials' ansible/` → **0** (1P items gone, incl. any surviving comment/fail-message strings — run AFTER the CR11 comment cleanup, or enumerate the comment blocks here so the gate is honest).
  - `rg -n 'op item|op read' ansible/roles/opconnect_credentials` → only `op connect server`/`op connect token`.
  - `rg -n 'Infrastructure Ansible SSH Key' ansible/` → only the fleet Connect path.
- [ ] **SAN pre-flight (PULL FORWARD — before the destructive CR10 rebuild):** read the current server cert from the live fleet Connect (or the `FusionCloudX Intermediate CA Bundle` 1P item) and `openssl x509 -noout -ext subjectAltName` confirms it covers `opconnect.fusioncloudx.home` (or `*.fusioncloudx.home`). If the SAN omits the host, **reissue/mint the cert with the SAN FIRST** — otherwise the entire TLS phase is dead-on-arrival after an expensive rebuild. (Re-checked as a hard gate in CR10.)
- [ ] **Fleet non-regression (convert from inference to a check):** `ansible-playbook site.yml --syntax-check`; `ansible-playbook site.yml --check --limit <one app host> --tags certificates,ssh-key` (or `--list-tasks`) confirms the Connect ssh-key + cert paths resolve with `ssh_key_source` defaulting to `connect` and the certificates role unconditional PATH A.

## CR9 (GATED — first Direction-A seed: generates the key locally, writes the bundle + SSM)
- [ ] Preconditions: 1P desktop **unlocked** (for `op connect server/token create`); `aws sso login --sso-session fcx-sso`.
- [ ] **GATED** (NO `-v`; use the documented inline inventory): `cd ansible && env -u AWS_PROFILE OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES no_proxy='*' .venv/bin/ansible-playbook playbooks/opconnect_credentials.yml -i 'localhost,' -e "ansible_python_interpreter=$PWD/.venv/bin/python"`. **NOTE:** a first-seed when a live Connect server already exists requires `-e recreate_connect_server=true` (deletes + re-mints the server; `credentials.json` is emitted ONLY at server create). A token-only rotation uses `-e force=true` instead (key/server/creds preserved).
- [ ] **Verify (no secret values printed):**
  - Bundle keys: `aws secretsmanager get-secret-value --secret-id tmpx/onprem/opconnect-credentials --region us-east-2 --query SecretString --output text | jq 'keys'` (AWS_PROFILE=fcx-sso) → includes `ansible_private_key`, `ansible_public_key`, `connect_credentials_json`, `connect_token`, `token_expires`.
  - SSM == bundle pubkey (compare strings, no key bytes echoed beyond the pubkey).
  - Round-trip (pinned, redirected — never echo/here-string the key): `umask 077; aws secretsmanager get-secret-value --secret-id tmpx/onprem/opconnect-credentials --region us-east-2 --query SecretString --output text | jq -r .ansible_private_key > /tmp/_k && ssh-keygen -y -f /tmp/_k > /tmp/_kp; shred -u /tmp/_k` → `/tmp/_kp` == the SSM pubkey; `shred -u /tmp/_kp`. **GATE on mismatch.**
  - **No 1P items:** `op item get "opconnect Bootstrap SSH Key" --vault FusionCloudX` and `op item get "opconnect Connect Credentials" --vault FusionCloudX` both → not found.
  - **Idempotency:** the FIRST Direction-A seed legitimately CHANGES the SSM pubkey + escrow (it regenerates the key locally via `openssh_keypair` — the pubkey now carries the `opconnect-bootstrap` comment vs the old `op read` shape; adoption replaces the old bundle key). That one-time change is EXPECTED. Assert idempotency on run **N vs N+1 post-transition**: a second Direction-A run → "re-asserted", escrow `changed=false`, SSM pubkey **byte-identical** (no silent re-generation); the empty-key assert never trips.

## CR10 (GATED — opconnect-only rebuild + verify, incl. native TLS)
- [ ] `tofu -chdir=tofu/opconnect plan` — `data.aws_ssm_parameter.ansible_pubkey` read; cloud-init authorizes the **dedicated** pubkey; any legacy `tls_private_key`/`null_resource` destroyed (#8). Confirm dedicated key, not fleet.
- [ ] **GATED:** lift `prevent_destroy` on VM 1101 → `tofu apply` → restore `prevent_destroy`.
- [ ] **GATED (use the TWO-inventory form — else `hosts: opconnect` plays match 0 hosts and silently skip):** `cd ansible && env -u AWS_PROFILE OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES no_proxy='*' .venv/bin/ansible-playbook -i inventory-bootstrap-localhost.yml -i opconnect.inventory.yml playbooks/opconnect.yml`. Before claiming the gate, confirm the play recap shows a non-zero host count for the deploy + TLS plays.
- [ ] **Verify:**
  - Ansible authenticated with the **dedicated** key (from the AWS bundle); fleet pubkey **absent** from opconnect `authorized_keys` (grep → 0).
  - **Native TLS up:** `openssl s_client -connect opconnect.fusioncloudx.home:{{ opconnect_https_external_port }} </dev/null 2>/dev/null | openssl x509 -noout -issuer -subject -ext subjectAltName` → FusionCloudX intermediate issuer **and** SAN covers `opconnect.fusioncloudx.home` (**KEY RISK** — if the shared server cert's SAN omits the host, reissue/mint before claiming the gate). Connect serves a test secret over `https://`.
  - **Plaintext closed:** from another host, `curl --max-time 5 http://opconnect.fusioncloudx.home:8080/heartbeat` → connection refused/timeout (HTTP is loopback-bound, not LAN-reachable). On-box `curl http://localhost:8080/heartbeat` → 200.
  - **No `op` in the run:** the play log shows AWS bundle reads + local-Connect `uri` reads, **no** `op read`/`op item`.
  - **#8:** `tofu -chdir=tofu/opconnect state list | rg 'tls_private_key|null_resource'` → empty.
- [ ] **Repoint downstream consumers (modeled on the P4.4 cutover runbook) — BEFORE declaring the gate done.** The HTTPS flip changes `OP_CONNECT_HOST` on BOTH scheme (`http`→`https`) AND port (`8080`→ the canonical external HTTPS port, **443** per `opconnect_https_external_port`). Any long-lived consumer still on `http://opconnect.fusioncloudx.home:8080` strands the instant the port flips. Repoint `OP_CONNECT_HOST=https://opconnect.fusioncloudx.home` everywhere it lives (operator `.zprofile`/Keychain, `TF_VAR_*`, launchd/cron/CI, `tofu/compute`), open a fresh shell, and restart long-lived consumers; confirm a day-2 fleet secret read succeeds over HTTPS. (CR6b Step 5 already updated the COMMITTED `connect_host` strings; this step covers the LIVE env + running processes.)
- [ ] Commit → PR → @claude review → merge (no Claude co-author trailer).

## CR11: Docs + memory + close-out + orthogonal hardening
- [ ] Rewrite the opconnect runbook for Direction A + native TLS: seed generates locally → bundle + SSM; consumer reads privkey + creds from the bundle; **native Connect TLS** self-served on-box (two-phase: HTTP-loopback → read cert from local Connect → flip `OP_TLS_*` → restart); fleet uses `https://`; 90-day token rotation re-mints the token only (key unchanged). Also correct the `opconnect_credentials` role header/defaults comments so docs don't drift post-merge.
- [ ] `enhance-harden-later.md` #8 SSH-key half → RESOLVED (privkey AWS-bundle-served, never in state).
- [ ] Update memory + `09-Homelab` docs + Nexus session note.
- [ ] **Orthogonal (task #81):** extract `intermediate-ca-key.pem` from the `FusionCloudX Intermediate CA Bundle` 1P item to offline/HSM custody (CAT-1). **Note:** the on-box TLS read pulls only `fullchain.pem` + `server-key.pem` from that item — it does NOT touch the CA private key — but the CA key being co-located makes its extraction more urgent (it is now reachable by anything with Connect access). Track separately; not gated on Phase C.
- [ ] **Orthogonal checkbox (link #60):** produce + store the offline 3-2-1 leg of the AWS bundle (encrypted USB / printed), openable with FIDO/passphrase alone.
- [ ] Mark `op_use_cli` fully retired estate-wide; specialized bootstrap roles (C4) noted as the future refactor trigger (3rd source / collaborator).

---

## Self-Review

**Spec coverage (Revision 2):** D9 dedicated key (CR2 keygen; CR10 fleet-key-absent) · D10 SSM pubkey (CR3) · D11′ Direction-A consume — privkey + creds + token from the AWS bundle, no `op` in the consumer (CR4/CR5; CR8/CR10 greps) · D12 seed generates locally, no 1P items, empty-key assert (CR2; CR9 not-found) · D13 native Connect TLS self-served on-box, loopback-bind HTTP, no nginx, no AWS cert escrow (CR6b; CR10 TLS verify + plaintext-closed) · D14 no `op_use_cli`, explicit `ssh_key_source` (CR4) + structural opconnect TLS (CR6b); auto-detection rejected · #8 (CR10) · fleet untouched + **verified** (CR6a unconditional PATH A; CR8 fleet --check) · gated (CR9/CR10) · idempotent/adoption-safe (CR2 guard + empty-key assert). ✅

**Blockers from review (all addressed):** (1) TLS termination — replaced the missing-nginx approach with **native Connect TLS** (CR6b), grounded in the 1P docs. (2) Plain-HTTP on 0.0.0.0 — compose now **loopback-binds** 8080 and publishes only HTTPS (CR6b Step 2; CR10 plaintext-closed check). (3) CR1 contract — moved from a non-loading `group_vars` to `vars_files` on both playbooks (CR1). (4) CR8 greps — `op_use_cli`/`op_ssh_key_ref` enumerated for deletion estate-wide (CR4 Step 3, CR6a) → grep `→ 0`; `TF_VAR_onepassword_vault_id` is removed ONLY from `opconnect.yml` (CR4 Step 4) and the gate is scoped to that file (the var has 14+ legitimate fleet uses + the retained fleet Connect path — NOT asserted to 0 estate-wide); 1P-item strings removed (CR5 Step 3) → grep `→ 0`.

**Important from review (addressed):** connect-sync timing (CR6b `tls.yml` polls the ITEM, not `/heartbeat`); `uri`-only on-box read, no collection on the VM (CR6b); CR10 `-i opconnect.inventory.yml` + `AWS_PROFILE` + non-zero-host check; CR9 `-i 'localhost,'`; ssh-key-loader defaults deletion (CR4 Step 3); the full `TF_VAR_onepassword_vault_id` assert + `op_ssh_key_ref` removal (CR4 Step 4); stale spec Acceptance/Risk/Issue-#8 (spec Revision-2 addendum); requirements.yml collections (CR1 Step 2); fleet non-regression now a CR8 check.

**Minor from review (addressed):** empty-key assert before escrow (CR2 Step 2); adoption→rebuild note (CR2 implies CR10; runbook CR11); `no_log` on the server-key copy (CR6a); pinned/redirected privkey extraction (CR9); stale spec Risk/Issue-#8 + Direction-B banner (spec edits done); offline 3-2-1 checkbox (CR11); TLS-play-between-deploy-and-cleanup ordering (CR6b Step 4); stale `variables.tf`/role comments (CR3, CR11).

**Live-verify key risks (carried to CR9/CR10):** server-cert SAN covers `opconnect.fusioncloudx.home` (CR10); connect-sync vault populated before the cert read (CR6b polls); `uri`-only read needs no VM collection (CR6b); no silent key regeneration (CR9 byte-identical pubkey + empty-key assert); #8 clean state (CR10); fleet regression (CR8 `--check`).

*Plan 2026-06-13 (late, rev 2): Direction A — AWS-anchored, `op`-CLI-free consumer, native Connect TLS self-served on-box. Grounded in the 1Password Connect server-configuration docs + the as-built compose/inventory. Supersedes the Direction-B plan. Wave 2 (CI OIDC, Roles Anywhere, SSH-CA, step-ca ACME) out of scope.*
