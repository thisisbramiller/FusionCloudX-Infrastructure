# opconnect Cutover Runbook — P4.0 – P4.5

## Purpose

This runbook replaces the snowflake 1Password Connect (VM 100 @ `192.168.40.44`) with the
IaC-managed opconnect VM 1101. The cutover strategy is build-new → real authenticated verify →
repoint → hardened clean-cut retire. opconnect is the **secrets root**: every IaC consumer
(`ssh-key-loader`, `postgresql/fetch-secrets`, the `compute` tofu `onepassword` provider) reads
1Password through it — Connect down = all IaC dead. The sequence is therefore gated and
reversible up to the final cut. All mutations are explicit `[CUT]` steps; `[BUILD]` steps are
additive and non-destructive.

---

## Prerequisites / shell env

Set these in every shell before executing any phase step:

```bash
export AWS_PROFILE=fcx-sso
export UNIFI_API_KEY="$(security find-generic-password -a "$USER" -s claudeudmproapikey -w)"
```

The old-Connect env (`OP_CONNECT_HOST` / `OP_CONNECT_TOKEN`) **stays set until P4.4**. It is the
build-time auth for P4.2; do not unset or overwrite it before the P4.4 repoint.

**Infra vault UUID:** `ve6jgmyk77ssj7aqpeodt2uhyi`

**Step markers:**
- `[OP]` — requires an interactive `op signin` / your 1Password account credentials
- `[BUILD]` — additive, non-destructive
- `[CUT]` — mutates live state
- `[CONFIRM]` — stop; get explicit confirmation before proceeding

---

## P4.0 — Pre-flight (no destructive action)

### Step 1 — [OP] Verify the pinned image pair

Confirm `1password/connect-api:1.7.3` **and** `1password/connect-sync:1.7.3` both exist on
Docker Hub as a matched pair; capture both image digests. Record them in a comment next to
`opconnect_connect_version` in `ansible/roles/opconnect/defaults/main.yml` (follow-up commit on
a small branch). If 1.7.3 is not a valid matched pair, pick the latest matched pair and update
the default.

### Step 2 — DNS — temp subdomain (no pre-apply deletion needed)

Confirm the existing record:

```bash
dig +short opconnect.fusioncloudx.home @192.168.40.1
```

Expected output: `192.168.40.44` (old). Leave this record untouched. The P4.2 apply passes
`-var opconnect_dns_name=opconnect-new`, so `module.opconnect_dns` creates
`opconnect-new.fusioncloudx.home → 1101` — no collision with the existing `.44` record. The old
Connect remains reachable by IP (`192.168.40.44`) throughout, so all consumers are unaffected.
The canonical name is reclaimed at P4.6 after VM 100 is retired. **No pre-apply deletion or
import is required before P4.2.**

**Token-scope good news (verified):** the old token sees exactly ONE vault —
`ve6jgmyk77ssj7aqpeodt2uhyi` ("FusionCloudX"). The new 90d token scoped to that single vault
gives exact parity with no darkout. Device-cert items in `ansible/inventory/devices.yaml` target
LOCAL DESKTOP 1Password (not Connect) — out of scope.

### Step 3 — Enumerate every `op://` consumer → confirm one vault

```bash
grep -rnoE 'op://[^ "'\'']+' \
  "/Users/fcx/Developer/Personal/repos/FusionCloudX Infrastructure/ansible" \
  "/Users/fcx/Developer/Personal/repos/FusionCloudX Infrastructure/tofu" \
  2>/dev/null | sort -u
```

Also enumerate items read by `onepassword.connect` / `onepassword_item` lookups: Ansible SSH
Key, GitLab Root, GitLab Runner Token, PostgreSQL Admin, PostgreSQL Wazuh DB User, TLS certs.
Confirm all live in vault `ve6jgmyk77ssj7aqpeodt2uhyi`. If any live elsewhere, collect the full
vault set for the `--vaults` / `--vault` flags in P4.1.

### Step 4 — [OP] Verify the live `op` CLI flag form

```bash
op connect token create --help
```

Confirm `op connect token create` accepts `--vault` (or `--vaults`) + `--expires-in 90d` on the
installed `op` version.

### Step 5 — Confirm backend reachable

```bash
aws sts get-caller-identity   # AWS_PROFILE=fcx-sso must be set
tofu -chdir=tofu/opconnect init -input=false
```

Expected: `aws sts` returns the mgmt account JSON; `tofu init` succeeds with no error.

---

## P4.1 — [OP] Bootstrap the new Connect identity (old Connect untouched)

### Step 1 — [OP][CONFIRM] Create the server + token

Run **in your own terminal** (or via `!` in an interactive shell). Keep the new token OUT of
the build shell env.

```bash
op signin
op connect server create opconnect --vaults ve6jgmyk77ssj7aqpeodt2uhyi   # emits ./1password-credentials.json
op connect token create opconnect-fleet --server opconnect \
    --vault ve6jgmyk77ssj7aqpeodt2uhyi --expires-in 90d                   # capture the printed token
```

Record the token issuance date and compute T+90d (the rotation deadline).

### Step 2 — [OP] Store the DR copy

```bash
op document create ./1password-credentials.json \
    --title "opconnect 1101 credentials" \
    --vault ve6jgmyk77ssj7aqpeodt2uhyi
```

Also keep an encrypted off-Connect backup (Backrest/restic). Document out-of-band retrieval:
`op signin` + `op document get` — never via Connect itself.

---

## P4.2 — [BUILD] Build VM 1101 + bring up Connect

### Step 1 — Apply the opconnect state

After the P4.0 pre-flight (no DNS pre-deletion needed):

```bash
cd "/Users/fcx/Developer/Personal/repos/FusionCloudX Infrastructure"
tofu -chdir=tofu/opconnect plan -input=false -var opconnect_dns_name=opconnect-new   # expect 7 add / 0 change / 0 destroy
tofu -chdir=tofu/opconnect apply -input=false -var opconnect_dns_name=opconnect-new  # [CONFIRM] before apply
```

Expected: VM 1101 created; `opconnect-new.fusioncloudx.home → 1101` DNS record created;
`opconnect_ip` output populated once the guest agent leases an IP. The canonical
`opconnect.fusioncloudx.home → .44` record is untouched.

### Step 2 — [OP] Stage the credentials on 1101

```bash
scp 1password-credentials.json ansible@<1101-IP>:/tmp/ && \
ssh ansible@<1101-IP> 'sudo install -m600 -o root -g root /tmp/1password-credentials.json \
    /root/1password-credentials.json && shred -u /tmp/1password-credentials.json'
```

`/root/1password-credentials.json` = `opconnect_credentials_src`. The role copies it to
`/opt/opconnect/1password-credentials.json` (non-empty validation in the role will fail fast if
the file is missing or zero-length).

### Step 3 — Run the opconnect play

Build auth = old Connect (already in env):

```bash
cd "ansible" && ansible-playbook playbooks/opconnect.yml
```

Expected: `connect-api` + `connect-sync` up; `/heartbeat` 200; `/health` reports `sqlite ACTIVE`
and `version` == the pinned tag. `sync=TOKEN_NEEDED` here is expected and normal — it is primed
by the P4.3 authenticated `/v1` read, not by the play.

---

## P4.3 — [BUILD] GATE — authenticated proof against 1101's IP

**Do not proceed past this gate until both curl checks return a passing result.**

### Step 1 — Prime sync + prove the token reads the vault

```bash
NEWTOK='<new token from P4.1>'; IP='<1101-IP>'

# (a) vault visible
curl -fsS \
  -H "Authorization: Bearer $NEWTOK" \
  -H 'Content-type: application/json' \
  "http://$IP:8080/v1/vaults"

# (b) items listed (the real gate) — retry until non-empty or timeout
curl -fsS \
  -H "Authorization: Bearer $NEWTOK" \
  -H 'Content-type: application/json' \
  "http://$IP:8080/v1/vaults/ve6jgmyk77ssj7aqpeodt2uhyi/items"
```

Expected:
- **(a)** HTTP 200; JSON array includes the infra vault (`ve6jgmyk77ssj7aqpeodt2uhyi`).
- **(b)** HTTP 200; JSON array lists the Ansible SSH key + representative app secrets
  (GitLab, PostgreSQL, Wazuh, TLS). **Empty or partial = NOT-PASS.** Wait + retry (sync priming
  takes a few seconds on a fresh server); hard timeout → **ABORT** (VM 100 is fully intact;
  leave 1101 running, fix forward).

### Step 2 — [CONFIRM]

Gate passed: vault + items confirmed via the NEW token. Both Connects still running; nothing on
VM 100 has been touched. Confirm before proceeding to P4.4.

---

## P4.4 — [CUT, reversible] Repoint to temp subdomain + broad verify

### Step 1 — Verify the temp DNS record

The P4.2 apply created `opconnect-new.fusioncloudx.home → 1101`. Confirm it is live:

```bash
dig +short opconnect-new.fusioncloudx.home @192.168.40.1
```

Expected: `<1101-IP>`. Do not trust the temp hostname until this passes. The canonical
`opconnect.fusioncloudx.home → .44` record has NOT been touched.

### Step 2 — [OP] Repoint the fleet env to the temp subdomain

```bash
security add-generic-password -U -a "$USER" -s opconnectfcxtoken -w '<new token>'
# edit ~/.zprofile: OP_CONNECT_HOST -> http://opconnect-new.fusioncloudx.home:8080
#                   OP_CONNECT_TOKEN -> new token (sourced from Keychain)
#                   TF_VAR_onepassword_connect_token -> new token
```

Update the DR 1P-document note. Open a **fresh shell** (re-sources `.zprofile` → picks up the
new `OP_CONNECT_TOKEN` / `OP_CONNECT_HOST` / `TF_VAR_onepassword_connect_token`). Restart any
long-lived consumers (launchd services, cron jobs, CI runners).

### Step 3 — Broad verify via the NEW Connect

```bash
cd "/Users/fcx/Developer/Personal/repos/FusionCloudX Infrastructure"
tofu -chdir=tofu/compute plan -input=false          # clean, reads secrets via new Connect

cd "ansible" && ansible-playbook playbooks/site.yml  # 0 failed; non-empty asserts on each secret class
```

Expected: `tofu/compute plan` clean (0 errors, reads secrets through the new Connect);
`site.yml` reports 0 failed with non-empty asserts on every critical secret class. Confirm
traffic is hitting 1101 (server-side log on 1101 or `/health` served-from), **not** `.44`.

### Step 4 — Rollback window note

Until P4.5 runs, rollback is instant: revert Keychain / `.zprofile` env back to the old `.44`.
The canonical `opconnect.fusioncloudx.home → .44` record was never touched; old token + server
+ VM 100 are still live. No destruction has occurred.

---

## P4.5 — [CUT, irreversible] Hardened clean-cut retire

### Step 1 — [CONFIRM]

Broad verify clean and traffic confirmed on 1101. **This step is irreversible — explicit user
confirmation required before any destruction proceeds.**

### Step 2 — [OP] Cold off-box backup

```bash
pvesm status                                          # find the OFF-BOX storage id (e.g. pbs / nfs-backup)
vzdump 100 --storage <off-box-storage-id> --mode stop  # bare `vzdump 100` defaults to node-LOCAL — must target off-box
```

This is zero-surface insurance (offline backup), not a running fallback. **Bare `vzdump 100`
writes to the node's default storage (often `local`) — if that is the same node you then delete
in Step 4, the insurance is gone.** Pass an explicit off-box `--storage` and **confirm the dump
file landed off-box (`pvesm list <off-box-storage-id> | grep vzdump-.*-100-`) before Step 3.**

### Step 3 — [OP][CUT] Retire the old identity

```bash
op connect token  delete <old-token> --server <old-server>
op connect server delete <old-server>           # CLI-only, irreversible; safe for cloud vault data
op connect server list                          # confirm old server absent; new server present with infra vault
```

Expected: `op connect server list` shows only the new `opconnect` server scoped to
`ve6jgmyk77ssj7aqpeodt2uhyi`; the old server is absent.

### Step 4 — [OP][CUT] Decommission VM 100

Stop + delete the snowflake VM 100 in Proxmox.

### Step 5 — [OP][CUT] Delete the old `opconnect → .44` UDM A record

In the UniFi DNS UI, delete the `opconnect.fusioncloudx.home → 192.168.40.44` A record. VM 100
is gone; the canonical name is now free to be reclaimed at P4.6.

### Step 6 — Finalize

1. Update `docs/.../1Password-Connect.md`: host = 1101, correct `/health` expectation (no
   `{"state":"ACTIVE"}` field — the real shape is `{name, version, dependencies[]}`), out-of-band
   DR retrieval documented.
2. Record the T+90d rotation deadline in the token-rotation runbook (`docs/runbooks/opconnect-token-rotation.md`).
3. Set T-14d and T-3d monitored alerts for the rotation deadline.
4. `prevent_destroy` on VM 1101 stays on (the escape hatch is documented in the Rollback section
   below).

### Step 7 — Verify done

```bash
op connect server list                                    # old server absent; new present
tofu -chdir=tofu/compute plan -input=false               # clean via new Connect
tofu -chdir=tofu/opconnect plan -input=false             # clean
```

Also confirm: old token revoked; VM 100 absent in Proxmox; off-box `vzdump` exists.

---

## P4.6 — [CUT] Finalize: reclaim the canonical name

Only after P4.5 is fully complete (VM 100 gone, old token/server revoked, old
`opconnect → .44` UDM record deleted).

### Step 1 — Apply with the default var (canonical name)

```bash
cd "/Users/fcx/Developer/Personal/repos/FusionCloudX Infrastructure"
tofu -chdir=tofu/opconnect apply -input=false      # default opconnect_dns_name=opconnect
```

Expected: `opconnect.fusioncloudx.home → 1101` created; `opconnect-new.fusioncloudx.home` record
destroyed in the same apply.

### Step 2 — Verify canonical DNS

```bash
dig +short opconnect.fusioncloudx.home @192.168.40.1     # must equal <1101-IP>
dig +short opconnect-new.fusioncloudx.home @192.168.40.1  # must be empty (record gone)
```

### Step 3 — [OP] Repoint fleet env to canonical hostname

```bash
# edit ~/.zprofile: OP_CONNECT_HOST -> http://opconnect.fusioncloudx.home:8080
```

Token is unchanged. Open a fresh shell; restart long-lived consumers (launchd services, cron
jobs, CI runners).

### Step 4 — Final broad verify

```bash
cd "/Users/fcx/Developer/Personal/repos/FusionCloudX Infrastructure"
tofu -chdir=tofu/compute plan -input=false          # clean via canonical hostname + new Connect
cd "ansible" && ansible-playbook playbooks/site.yml  # 0 failed; non-empty asserts on each secret class
```

### Step 5 — Update docs

Update this runbook, the plan (`docs/superpowers/plans/2026-06-06-p4-opconnect-cutover.md`), and
`docs/.../1Password-Connect.md` to reflect the canonical end state: `opconnect.fusioncloudx.home
→ 1101`, temp `opconnect-new` subdomain gone. Record the T+90d rotation deadline.

---

## Rollback / abort

| Window | Rollback action |
|---|---|
| **Before P4.4** | Old Connect untouched — abort = leave 1101 running (harmless parallel); fix forward. |
| **P4.4 → P4.5** | Revert Keychain / `.zprofile` env back to the old `.44`; the canonical `opconnect → .44` record was never touched → instant rollback. Old token + server + VM 100 still live. |
| **After P4.5 (P4.6 pending)** | Old VM gone; revert env to use the `.44` IP directly; rebuild is the only full restore path. |
| **After P4.6** | Old gone — restore from the `vzdump` or rebuild from the proven 1101. |

### `prevent_destroy` escape hatch (VM 1101)

To tear down / recreate VM 1101 on a failed cutover:

1. Comment out `protected = true` (→ disposable variant) in `tofu/opconnect/opconnect.tf`.
2. `tofu apply` — removes the guard from state intent.
3. `tofu destroy` / recreate.
4. Re-add `protected = true` + apply.

**Plan-time rule:** if `tofu plan` shows `-/+ replace` on VM 1101, **STOP** — the seatbelt is
working. Never `qm destroy` manually (causes state drift).

---

## Definition of done

- [ ] Code/doc PR (`feat/p4-opconnect-cutover`) merged via the full review lifecycle (local + `@claude`).
- [ ] New Connect on 1101 passes the authenticated `/v1/vaults` + `/v1/vaults/{uuid}/items` gate with the new token before any cutover.
- [ ] `dig +short opconnect-new.fusioncloudx.home` resolves to `<1101-IP>` after P4.2 apply.
- [ ] Fleet repointed to `opconnect-new.fusioncloudx.home` (P4.4); broad verify clean via the new Connect.
- [ ] Old snowflake fully retired: old token revoked, old server deleted, VM 100 gone from Proxmox, old `opconnect → .44` UDM record deleted, off-box `vzdump` kept.
- [ ] `dig +short opconnect.fusioncloudx.home` resolves to `<1101-IP>` after P4.6 finalize; `opconnect-new` record gone.
- [ ] Fleet repointed to canonical `opconnect.fusioncloudx.home:8080` (P4.6); final broad verify clean.
- [ ] Rotation runbook + T-14d/T-3d alerts in place.
- [ ] DR `1password-credentials.json` document stored in the infra vault with out-of-band retrieval documented.
- [ ] ClickUp P4 marked complete.
