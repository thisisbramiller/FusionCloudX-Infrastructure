# P4 — opconnect cutover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the snowflake 1Password Connect (VM 100 @ `192.168.40.44`) with the IaC-managed `opconnect` VM 1101, with zero unplanned secret-access outage: build-new → real authenticated verify → repoint → hardened clean-cut retire.

**Architecture:** `tofu/opconnect` (merged P3) authors VM 1101 + DNS + ansible targeting. This phase adds the thin ansible/role/doc changes, then executes the live cutover. Build-time auth = the old Connect; new Connect is granted the infra vault (UUID `ve6jgmyk77ssj7aqpeodt2uhyi`) with a 90-day token; old snowflake is clean-cut after a real authenticated `/v1` gate + verified DNS flip + broad `site.yml` verify.

**Tech Stack:** OpenTofu 1.12 (S3+SSE-KMS backend, `AWS_PROFILE=fcx-sso`), bpg/proxmox, the UniFi fork, the 1Password `op` CLI + `onepassword.connect` Ansible collection, Docker Compose (`community.docker.docker_compose_v2`), 1Password Connect (connect-api/connect-sync).

**Source spec:** `docs/superpowers/specs/2026-06-06-p4-opconnect-cutover-design.md`

**Step legend:** **[BUILD]** additive/non-destructive · **[OP]** operator-gated (needs your 1Password account / `op signin` / Keychain) · **[CUT]** mutates live state · **[CONFIRM]** STOP for explicit user confirmation before running.

---

## File Structure

**Phase A — code/doc changes (branch `feat/p4-opconnect-cutover`):**
- Modify: `ansible/playbooks/opconnect.yml` — relax the SA-token-only assertion to SA **or** Connect.
- Modify: `ansible/roles/opconnect/templates/docker-compose.yml.j2` — drop the redundant `OP_HTTP_PORT` env.
- Modify: `ansible/roles/opconnect/tasks/main.yml` — non-empty creds validation + layered readiness gate (`/heartbeat` + `/health` `sqlite ACTIVE`); keep the authenticated `/v1` proof in the runbook (the role does not hold the new token).
- Modify: `tofu/opconnect/providers.tf` — comment accuracy (old-Connect build auth).
- Create: `docs/runbooks/opconnect-cutover.md` — the P4.0–P4.6 operator runbook.
- Create: `docs/runbooks/opconnect-token-rotation.md` — the 90-day overlap rotation runbook.

**Phase B — PR review + merge.**

**Phase C — live cutover execution (post-merge, from `main`).** No repo files; executes the runbook against live infra with `[CONFIRM]` gates.

---

## Phase A — Code & doc changes

### Task A1: Relax the opconnect playbook SA-token assertion

**Files:**
- Modify: `ansible/playbooks/opconnect.yml`

- [ ] **Step 1: Establish the failing check (assertion currently rejects the chosen old-Connect path)**

Run: `cd "ansible" && ansible-playbook --syntax-check playbooks/opconnect.yml`
Expected: syntax OK. Then confirm the *current* assertion logic at the `pre_tasks` `fail` block requires `OP_SERVICE_ACCOUNT_TOKEN` only (read the block). This is what must change — with our build auth (`OP_CONNECT_*`, no SA token) the play would abort.

- [ ] **Step 2: Replace the assertion to accept SA token OR Connect env**

In `ansible/playbooks/opconnect.yml`, replace the `Ensure 1Password Service Account token is set` pre-task with:

```yaml
    - name: Ensure a 1Password auth path is available (SA token OR Connect)
      ansible.builtin.fail:
        msg: >-
          Provide a 1Password auth path: either OP_SERVICE_ACCOUNT_TOKEN (pure
          secrets-root bootstrap) OR OP_CONNECT_HOST + OP_CONNECT_TOKEN (the P4
          cutover bootstraps the NEW Connect via the EXISTING old Connect — the
          one item read is the Ansible SSH key). A from-scratch rebuild (no prior
          Connect) uses OP_SERVICE_ACCOUNT_TOKEN or an operator `op signin` to
          restage 1password-credentials.json from the DR document.
      when: >-
        lookup('env', 'OP_SERVICE_ACCOUNT_TOKEN') == '' and
        (lookup('env', 'OP_CONNECT_HOST') == '' or lookup('env', 'OP_CONNECT_TOKEN') == '')
```

Update the play's top "OLD CONNECT VM 100 MUST STAY UP" header comment to note this is the deliberate, design-approved build path (not a temporary hack), and that the steady state after P4.4 is the new Connect.

- [ ] **Step 3: Verify syntax + assertion logic**

Run: `cd "ansible" && ansible-playbook --syntax-check playbooks/opconnect.yml`
Expected: `playbook: playbooks/opconnect.yml` (no error).

- [ ] **Step 4: Commit**

```bash
git add ansible/playbooks/opconnect.yml
git commit -m "fix(p4): opconnect playbook accepts SA token OR Connect for build auth"
```

### Task A2: Drop the redundant OP_HTTP_PORT env from the compose template

**Files:**
- Modify: `ansible/roles/opconnect/templates/docker-compose.yml.j2`

- [ ] **Step 1: Remove the no-op env**

In `ansible/roles/opconnect/templates/docker-compose.yml.j2`, delete the `OP_HTTP_PORT: "8080"` line from **both** `connect-api` and `connect-sync` `environment:` blocks (it re-asserts the image default container port — a tautology). Keep `OP_LOG_LEVEL`. Leave `restart: always`, the `:ro` creds bind, and the `rw` shared `data` volume unchanged. Add a one-line comment that `OP_LOG_LEVEL` is an operability extension beyond the official compose shape.

- [ ] **Step 2: Verify template renders (no syntax break)**

Run: `cd "ansible" && ansible-playbook --syntax-check playbooks/opconnect.yml`
Expected: syntax OK (template is rendered at run time; this confirms the play still parses).

- [ ] **Step 3: Commit**

```bash
git add ansible/roles/opconnect/templates/docker-compose.yml.j2
git commit -m "fix(p4): drop redundant OP_HTTP_PORT from opconnect compose"
```

### Task A3: Add creds non-empty validation + layered readiness gate to the role

**Files:**
- Modify: `ansible/roles/opconnect/tasks/main.yml`

- [ ] **Step 1: Validate the staged creds file is present and non-empty before compose up**

In `ansible/roles/opconnect/tasks/main.yml`, immediately AFTER the `Stage 1Password Connect credentials into the compose directory` copy task, add:

```yaml
- name: Assert staged credentials file is present and non-empty
  ansible.builtin.stat:
    path: "{{ opconnect_compose_dir }}/1password-credentials.json"
  register: _opconnect_creds_stat
  tags: ['opconnect', 'deploy', 'secrets']

- name: Fail fast if the credentials file is missing or empty
  ansible.builtin.fail:
    msg: >-
      {{ opconnect_compose_dir }}/1password-credentials.json is missing or empty.
      The controller-side source ({{ opconnect_credentials_local }}) must be the
      non-empty file emitted by `op connect server create` (P4.1) — the relative
      ./ bind in docker-compose would otherwise create an empty mount and
      connect-sync cannot authenticate.
  when: not _opconnect_creds_stat.stat.exists or _opconnect_creds_stat.stat.size == 0
  tags: ['opconnect', 'deploy', 'secrets']
```

- [ ] **Step 2: Replace the bare `/heartbeat` verify with a layered readiness gate**

In `ansible/roles/opconnect/tasks/main.yml`, keep the existing `Wait for 1Password Connect API to be ready` (`/heartbeat`) task (container liveness), and ADD after it:

```yaml
# /health (unauthenticated) returns {name, version, dependencies[]}. On a fresh
# server BEFORE the first authenticated request, the `sync` dependency reports
# TOKEN_NEEDED (expected — primed by the P4.3 authenticated /v1 read in the
# runbook, NOT here). The role gate therefore asserts ONLY: api is live
# (/heartbeat, above), the pinned version is what deployed, and sqlite is ACTIVE.
- name: Fetch 1Password Connect /health
  ansible.builtin.uri:
    url: "http://localhost:{{ opconnect_api_port }}/health"
    return_content: true
    status_code: 200
  register: _opconnect_healthz
  retries: 12
  delay: 5
  until: _opconnect_healthz is succeeded
  tags: ['opconnect', 'verify']

- name: Assert deployed version matches the pinned tag and sqlite is ACTIVE
  ansible.builtin.assert:
    that:
      - _opconnect_healthz.json.version == opconnect_connect_version
      - >-
        (_opconnect_healthz.json.dependencies
         | selectattr('service', 'equalto', 'sqlite') | map(attribute='status') | first | default('')) == 'ACTIVE'
    fail_msg: >-
      /health did not confirm a clean deploy. version_seen={{ _opconnect_healthz.json.version | default('?') }}
      expected={{ opconnect_connect_version }}; dependencies={{ _opconnect_healthz.json.dependencies | default([]) }}.
      (sync=TOKEN_NEEDED here is EXPECTED — it is primed by the authenticated /v1 read in P4.3.)
    success_msg: "Connect {{ _opconnect_healthz.json.version }} live; sqlite ACTIVE; sync will prime on the P4.3 authenticated read."
  tags: ['opconnect', 'verify']
```

> Note: the `sqlite` dependency `service` key name + the `version` field are per the official `/health` Server-Health object. If a live `/health` shows a different `service` label for the local store, adjust the `equalto` selector to match the observed key (verify at P4.3).

- [ ] **Step 3: Verify syntax**

Run: `cd "ansible" && ansible-playbook --syntax-check playbooks/opconnect.yml`
Expected: syntax OK.

- [ ] **Step 4: Commit**

```bash
git add ansible/roles/opconnect/tasks/main.yml
git commit -m "feat(p4): opconnect role validates creds + layered /health readiness gate"
```

### Task A4: Correct the tofu/opconnect provider comment

**Files:**
- Modify: `tofu/opconnect/providers.tf`

- [ ] **Step 1: Update the onepassword provider comment**

In `tofu/opconnect/providers.tf`, replace the `# 1Password provider — SA-TOKEN auth ONLY ...` comment block above `provider "onepassword" {}` with one stating: the provider auto-detects auth from the environment; for the P4 cutover it reads the single Ansible-SSH-key item via the **old Connect** (`OP_CONNECT_HOST`/`OP_CONNECT_TOKEN`); a from-scratch rebuild would instead use `OP_SERVICE_ACCOUNT_TOKEN` or an operator `op signin`. No secrets in HCL/state. (HCL unchanged — comment only.)

- [ ] **Step 2: Verify formatting**

Run: `cd "/Users/fcx/Developer/Personal/repos/FusionCloudX Infrastructure" && tofu fmt -check tofu/opconnect/`
Expected: no output (clean). If it reprints a filename, run `tofu fmt tofu/opconnect/`.

- [ ] **Step 3: Commit**

```bash
git add tofu/opconnect/providers.tf
git commit -m "docs(p4): correct opconnect onepassword provider auth comment"
```

### Task A5: Write the cutover runbook

**Files:**
- Create: `docs/runbooks/opconnect-cutover.md`

- [ ] **Step 1: Author the runbook**

Create `docs/runbooks/opconnect-cutover.md` containing the full Phase C sequence below (P4.0–P4.6) verbatim — exact commands, expected outputs, the `[OP]`/`[BUILD]`/`[CUT]`/`[CONFIRM]` markers, the rollback/abort section, and the `prevent_destroy` escape hatch. This is the operator-facing copy of Phase C so the live run is followable without the plan.

- [ ] **Step 2: Commit**

```bash
git add docs/runbooks/opconnect-cutover.md
git commit -m "docs(p4): add opconnect cutover runbook"
```

### Task A6: Write the token-rotation runbook

**Files:**
- Create: `docs/runbooks/opconnect-token-rotation.md`

- [ ] **Step 1: Author the rotation runbook**

Create `docs/runbooks/opconnect-token-rotation.md` documenting the 90-day overlap rotation (from the spec's "Token rotation runbook" section): the monitored T-14d/T-3d alert, the create-new → verify → repoint (Keychain `opconnectfcxtoken` + `TF_VAR_onepassword_connect_token` + DR doc) → restart consumers → verify → delete-old overlap, and that token vault-set + expiry are immutable (rotation = revoke+reissue).

- [ ] **Step 2: Commit**

```bash
git add docs/runbooks/opconnect-token-rotation.md
git commit -m "docs(p4): add opconnect 90-day token rotation runbook"
```

---

## Phase B — Review & merge the code PR

### Task B1: PR through the full review lifecycle

- [ ] **Step 1: Push + open PR**

```bash
git push -u origin feat/p4-opconnect-cutover
gh pr create --title "P4: opconnect cutover — code + runbooks (live cutover follows)" --body "$(cat <<'EOF'
## Summary
- Relax opconnect.yml auth assertion to accept SA token OR Connect (P4 build auth = old Connect).
- Harden the opconnect role: non-empty creds validation + layered /health readiness gate; drop redundant OP_HTTP_PORT.
- Provider comment accuracy; add cutover + 90-day token-rotation runbooks.

## Test plan
- [ ] ansible --syntax-check clean
- [ ] tofu fmt clean
- [ ] Live cutover executes from the runbook (Phase C) post-merge
EOF
)"
```

- [ ] **Step 2: Local code review** — dispatch a code-reviewer subagent (superpowers:requesting-code-review) for `main..feat/p4-opconnect-cutover`. Fix Critical/Important before merge.

- [ ] **Step 3: `@claude` review** — `gh pr comment <#> --body "@claude review"`. Address findings (superpowers:receiving-code-review).

- [ ] **Step 4: Merge when green**

```bash
gh pr merge <#> --merge --delete-branch
git checkout main && git pull --ff-only
```

---

## Phase C — Live cutover execution (post-merge, from `main`)

> Shell prereqs each session: `export AWS_PROFILE=fcx-sso` and `export UNIFI_API_KEY="$(security find-generic-password -a "$USER" -s claudeudmproapikey -w)"`. The old-Connect env (`OP_CONNECT_HOST`/`OP_CONNECT_TOKEN`) stays set until P4.4.

### Task C0 (P4.0): Pre-flight — verification only, no mutation

- [ ] **Step 1: [OP] Verify the pinned image pair exists** — confirm `1password/connect-api:1.7.3` AND `1password/connect-sync:1.7.3` exist on Docker Hub as a matched pair; capture both digests. Record them in a comment next to `opconnect_connect_version` in `ansible/roles/opconnect/defaults/main.yml` (a follow-up commit on a small branch). If 1.7.3 is not a valid matched pair, pick the latest matched pair and update the default.

- [ ] **Step 2: DNS — temp subdomain (no pre-apply deletion needed)** — confirm current state:
  Run: `dig +short opconnect.fusioncloudx.home @192.168.40.1`
  Expected: `192.168.40.44` (old). Leave this record alone — the P4.2 apply passes
  `-var opconnect_dns_name=opconnect-new`, so `module.opconnect_dns` creates
  `opconnect-new.fusioncloudx.home → 1101` with no collision. The old Connect remains reachable
  by IP (`192.168.40.44`) throughout, so all consumers are unaffected. The canonical name is
  reclaimed at the new Task C6 (P4.6) after VM 100 is retired. **No pre-apply deletion or import
  required before C2.**
  **Token-scope good news (verified):** the old token sees exactly ONE vault —
  `ve6jgmyk77ssj7aqpeodt2uhyi` ("FusionCloudX"). The new 90d token scoped to that single vault
  gives exact parity with no darkout. Device-cert items in `ansible/inventory/devices.yaml` target
  LOCAL DESKTOP 1Password (not Connect) — out of scope.

- [ ] **Step 3: Enumerate every `op://` consumer → confirm one vault**
  Run: `grep -rnoE 'op://[^ "'\'']+' "/Users/fcx/Developer/Personal/repos/FusionCloudX Infrastructure/ansible" "/Users/fcx/Developer/Personal/repos/FusionCloudX Infrastructure/tofu" 2>/dev/null | sort -u`
  Plus the items read by the `onepassword.connect`/`onepassword_item` lookups (Ansible SSH Key, GitLab Root, GitLab Runner Token, PostgreSQL Admin, PostgreSQL Wazuh DB User, TLS certs). Confirm all live in vault `ve6jgmyk77ssj7aqpeodt2uhyi`; if any live elsewhere, collect the full vault set for the `--vaults`/`--vault` flags.

- [ ] **Step 4: [OP] Verify the live `op` CLI flag form** — confirm `op connect token create` accepts `--vault` (or `--vaults`) + `--expires-in 90d` on the installed `op` version: `op connect token create --help`.

- [ ] **Step 5: Confirm backend reachable** — `aws sts get-caller-identity` (with `AWS_PROFILE=fcx-sso`) returns the mgmt account; `tofu -chdir=tofu/opconnect init -input=false` succeeds.

### Task C1 (P4.1): [OP] Bootstrap the new Connect identity — old Connect untouched

- [ ] **Step 1: [OP][CONFIRM] Create the server + token (run in YOUR terminal / via `!`)**

```bash
op signin
op connect server create opconnect --vaults ve6jgmyk77ssj7aqpeodt2uhyi   # emits ./1password-credentials.json
op connect token create opconnect-fleet --server opconnect \
    --vault ve6jgmyk77ssj7aqpeodt2uhyi --expires-in 90d                   # capture the printed token
```
Record the token issuance date (compute T+90d). Keep the new token OUT of the build shell.

- [ ] **Step 2: [OP] Store the DR copy** — save `1password-credentials.json` as a 1P **document** in the infra vault (`op document create ./1password-credentials.json --title "opconnect 1101 credentials" --vault ve6jgmyk77ssj7aqpeodt2uhyi`) AND an encrypted off-Connect backup. Document out-of-band retrieval (`op signin` + `op document get`, never via Connect).

### Task C2 (P4.2): [BUILD] Build VM 1101 + bring up Connect

- [ ] **Step 1: Apply the opconnect state** (after the C0 pre-flight; no DNS pre-deletion needed)

```bash
cd "/Users/fcx/Developer/Personal/repos/FusionCloudX Infrastructure"
tofu -chdir=tofu/opconnect plan -input=false -var opconnect_dns_name=opconnect-new   # expect 7 add / 0 change / 0 destroy
tofu -chdir=tofu/opconnect apply -input=false -var opconnect_dns_name=opconnect-new  # [CONFIRM] before apply
```
Expected: VM 1101 created; `opconnect-new.fusioncloudx.home → 1101` DNS record created;
`opconnect_ip` output populated once the guest agent leases. The canonical
`opconnect.fusioncloudx.home → .44` record is untouched.

- [ ] **Step 2: Place credentials on the Ansible controller**

Place `1password-credentials.json` on the **Ansible controller** at
`~/opconnect-cutover/1password-credentials.json` (or override with
`-e opconnect_credentials_local=<path>`). The `opconnect.yml` run copies it to the VM
automatically — no manual scp required. The file is chowned to the container opuser
UID (999) so connect-sync can read it.

- [ ] **Step 3: Run the opconnect play** (build auth = old Connect, already in env)

```bash
cd "ansible" && ansible-playbook playbooks/opconnect.yml
```
Expected: `connect-api` + `connect-sync` up; `/heartbeat` 200; `/health` `sqlite ACTIVE`, version == pinned tag (the new A3 gate). `sync=TOKEN_NEEDED` here is expected.

### Task C3 (P4.3): [BUILD] GATE — authenticated proof against 1101's IP

- [ ] **Step 1: Prime sync + prove the token reads the vault** (retry loop handles sync latency)

```bash
NEWTOK='<new token from C1>'; IP='<1101-IP>'
# (a) vault visible
curl -fsS -H "Authorization: Bearer $NEWTOK" -H 'Content-type: application/json' "http://$IP:8080/v1/vaults"
# (b) items listed (the real gate) — retry until non-empty or timeout
curl -fsS -H "Authorization: Bearer $NEWTOK" -H 'Content-type: application/json' "http://$IP:8080/v1/vaults/ve6jgmyk77ssj7aqpeodt2uhyi/items"
```
Expected: (a) 200 with the infra vault present; (b) 200 listing the Ansible SSH key + representative app secrets. Empty/partial → wait + retry (sync priming); hard timeout → **ABORT** (VM 100 fully intact; leave 1101 running, fix forward).

- [ ] **Step 2: [CONFIRM]** Gate passed (vault + items confirmed via the NEW token). Both Connects still running; nothing on VM 100 touched. Confirm before proceeding to the cutover.

### Task C4 (P4.4): [CUT, reversible] Repoint to temp subdomain + broad verify

- [ ] **Step 1: Verify the temp DNS record** — the P4.2 apply created `opconnect-new → 1101`; confirm:
  Run: `dig +short opconnect-new.fusioncloudx.home @192.168.40.1`
  Expected: `<1101-IP>`. Do not trust the temp hostname until this passes. The canonical
  `opconnect.fusioncloudx.home → .44` is NOT touched.

- [ ] **Step 2: [OP] Repoint the fleet env to the temp subdomain** — update Keychain + profile together:
```bash
security add-generic-password -U -a "$USER" -s opconnectfcxtoken -w '<new token>'
# edit ~/.zprofile: OP_CONNECT_HOST -> http://opconnect-new.fusioncloudx.home:8080
```
Update the DR 1P-document note. Open a FRESH shell (re-sources `.zprofile` → new `OP_CONNECT_TOKEN`/`OP_CONNECT_HOST`/`TF_VAR_onepassword_connect_token`). Restart long-lived consumers (launchd/cron/CI).

- [ ] **Step 3: Broad verify via the NEW Connect** (not a single no-op)
```bash
cd "/Users/fcx/Developer/Personal/repos/FusionCloudX Infrastructure"
tofu -chdir=tofu/compute plan -input=false          # clean, reads secrets via new Connect
cd "ansible" && ansible-playbook playbooks/site.yml  # 0 failed; non-empty asserts on each secret class
```
Expected: compute plan clean (0 errors); `site.yml` 0 failed. Prove traffic hits 1101 (server-side log on 1101 / `/health` served-from), not `.44`.

- [ ] **Step 4: Rollback window note** — until C5, rollback = revert Keychain/`.zprofile` env back to
  the old `.44`; the canonical `opconnect.fusioncloudx.home → .44` record was never touched, old
  token + server + VM 100 still live.

### Task C5 (P4.5): [CUT, irreversible] Hardened clean-cut retire

- [ ] **Step 1: [CONFIRM]** Broad verify clean + traffic confirmed on 1101. **This step is irreversible — explicit user confirmation required before any destruction.**

- [ ] **Step 2: [OP] Cold off-box backup** — `vzdump` VM 100 to off-box storage (offline insurance, not a running fallback).

- [ ] **Step 3: [OP][CUT] Retire the old identity**
```bash
op connect token  delete <old-token> --server <old-server>
op connect server delete <old-server>           # CLI-only, irreversible; safe for cloud vault data
op connect server list                          # confirm old server absent; new present with infra vault
```

- [ ] **Step 4: [OP][CUT] Decommission VM 100** — stop + delete the snowflake VM 100 in Proxmox.

- [ ] **Step 5: [OP][CUT] Delete the old `opconnect → .44` UDM A record** (UniFi DNS UI). VM 100 is
  gone; the canonical name is now free to be reclaimed at C6.

- [ ] **Step 6: Finalize** — update `docs/.../1Password-Connect.md` (host = 1101, correct `/health` expectation, out-of-band DR retrieval); record the T+90d rotation deadline + set the T-14d/T-3d alerts; `prevent_destroy` on 1101 stays on (escape hatch documented in the runbook).

- [ ] **Step 7: Verify done** — `op connect server list` lacks the old server; old token revoked; VM 100 absent in Proxmox; off-box `vzdump` exists; `tofu -chdir=tofu/compute plan` + `tofu -chdir=tofu/opconnect plan` clean via the new Connect.

### Task C6 (P4.6): [CUT] Finalize — reclaim the canonical name

Only after C5 is fully complete (VM 100 gone, old token/server revoked, old `opconnect → .44`
UDM record deleted).

- [ ] **Step 1: Apply with the default var (canonical name)**

```bash
cd "/Users/fcx/Developer/Personal/repos/FusionCloudX Infrastructure"
tofu -chdir=tofu/opconnect apply -input=false      # default opconnect_dns_name=opconnect
```
Expected: `opconnect.fusioncloudx.home → 1101` created; `opconnect-new.fusioncloudx.home` record
destroyed in the same apply.

- [ ] **Step 2: Verify canonical DNS**

```bash
dig +short opconnect.fusioncloudx.home @192.168.40.1    # must equal <1101-IP>
dig +short opconnect-new.fusioncloudx.home @192.168.40.1 # must be empty (record gone)
```

- [ ] **Step 3: [OP] Repoint fleet env to canonical hostname**

```bash
# edit ~/.zprofile: OP_CONNECT_HOST -> http://opconnect.fusioncloudx.home:8080
```
Token is unchanged. Open a fresh shell; restart long-lived consumers (launchd/cron/CI).

- [ ] **Step 4: Final broad verify**

```bash
cd "/Users/fcx/Developer/Personal/repos/FusionCloudX Infrastructure"
tofu -chdir=tofu/compute plan -input=false          # clean via canonical hostname + new Connect
cd "ansible" && ansible-playbook playbooks/site.yml  # 0 failed; non-empty asserts on each secret class
```

- [ ] **Step 5: Update docs** — update this plan, the runbook (`docs/runbooks/opconnect-cutover.md`),
  and `docs/.../1Password-Connect.md` to reflect the canonical end state: `opconnect.fusioncloudx.home
  → 1101`, temp subdomain gone. Record the T+90d rotation deadline.

---

## Rollback / abort (quick reference)
- **Before C4:** old Connect untouched → abort = leave 1101 running; fix forward.
- **C4 → C5:** revert Keychain/`.zprofile` env back to the old `.44`; the canonical
  `opconnect.fusioncloudx.home → .44` record was never touched → instant rollback.
- **After C5 (C6 pending):** old VM gone; revert env to the old `.44` IP directly; rebuild is the
  only full restore path.
- **After C6:** restore the `vzdump` or rebuild from the proven 1101.
- **`prevent_destroy` on 1101 (abort teardown):** comment out `protected = true` in `tofu/opconnect/opconnect.tf` → `tofu apply` → `tofu destroy`/recreate → re-add `protected = true` + apply. If `tofu plan` shows `-/+ replace` on 1101, STOP (the seatbelt is working) — never `qm destroy` manually.

## Definition of done
Code/doc PR merged via the full review lifecycle; new Connect on 1101 passes the authenticated `/v1`
gate; fleet repointed first via temp subdomain (C4) then via canonical hostname (C6); broad verify
clean; old snowflake fully retired (token revoked, server deleted, VM 100 gone, old
`opconnect → .44` UDM record deleted, off-box `vzdump` kept); canonical
`opconnect.fusioncloudx.home → 1101`; rotation runbook + alerts in place; DR creds document stored;
ClickUp P4 marked complete.
