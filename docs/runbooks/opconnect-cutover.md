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

### Step 2 — DNS reconcile (apply-blocker)

Confirm the existing record:

```bash
dig +short opconnect.fusioncloudx.home @192.168.40.1
```

Expected output: `192.168.40.44` (old). The P4.2 `tofu apply` creates
`module.opconnect_dns`'s `unifi_dns_record` for the same hostname → the UDM controller will
reject the duplicate with a 400/409. Identify the existing A record on the UDM (UniFi DNS UI or
`unifi_dns_record` import). **[CONFIRM]** the reconcile approach — manual delete on UDM vs
`tofu import` — before proceeding to C2/P4.2.

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

After the P4.0 DNS reconcile:

```bash
cd "/Users/fcx/Developer/Personal/repos/FusionCloudX Infrastructure"
tofu -chdir=tofu/opconnect plan -input=false      # expect 7 add / 0 change / 0 destroy
tofu -chdir=tofu/opconnect apply -input=false      # [CONFIRM] before apply
```

Expected: VM 1101 created; `opconnect_ip` output populated once the guest agent leases an IP.

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

## P4.4 — [CUT, reversible] DNS flip + repoint + broad verify

### Step 1 — Flip + verify DNS

The P4.2 apply created the A record pointing to 1101. Verify it is live:

```bash
dig +short opconnect.fusioncloudx.home @192.168.40.1
```

Expected: `<1101-IP>` (NOT `.44`). Do not trust the hostname until this passes.

### Step 2 — [OP] Repoint the fleet env

```bash
security add-generic-password -U -a "$USER" -s opconnectfcxtoken -w '<new token>'
# edit ~/.zprofile: OP_CONNECT_HOST -> http://opconnect.fusioncloudx.home:8080
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

Until P4.5 runs, rollback is instant: revert Keychain / `.zprofile` / DNS back to `.44`. The
old token + server + VM 100 are still live. No destruction has occurred.

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

### Step 5 — Finalize

1. Update `docs/.../1Password-Connect.md`: host = 1101, correct `/health` expectation (no
   `{"state":"ACTIVE"}` field — the real shape is `{name, version, dependencies[]}`), out-of-band
   DR retrieval documented.
2. Record the T+90d rotation deadline in the token-rotation runbook (`docs/runbooks/opconnect-token-rotation.md`).
3. Set T-14d and T-3d monitored alerts for the rotation deadline.
4. `prevent_destroy` on VM 1101 stays on (the escape hatch is documented in the Rollback section
   below).

### Step 6 — Verify done

```bash
op connect server list                                    # old server absent; new present
tofu -chdir=tofu/compute plan -input=false               # clean via new Connect
tofu -chdir=tofu/opconnect plan -input=false             # clean
```

Also confirm: old token revoked; VM 100 absent in Proxmox; off-box `vzdump` exists.

---

## Rollback / abort

| Window | Rollback action |
|---|---|
| **Before P4.4** | Old Connect untouched — abort = leave 1101 running (harmless parallel); fix forward. |
| **P4.4 → P4.5** | Revert Keychain / `.zprofile` / DNS to `.44` → instant rollback. Old token + server + VM 100 still live. |
| **After P4.5** | Old gone — restore from the `vzdump` or rebuild from the proven 1101. |

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
- [ ] `dig +short opconnect.fusioncloudx.home` resolves to `<1101-IP>` after the flip.
- [ ] `tofu -chdir=tofu/compute plan` clean and `ansible-playbook site.yml` 0 failures via the new Connect.
- [ ] Old snowflake fully retired: old token revoked, old server deleted, VM 100 gone from Proxmox, off-box `vzdump` kept.
- [ ] Rotation runbook + T-14d/T-3d alerts in place.
- [ ] DR `1password-credentials.json` document stored in the infra vault with out-of-band retrieval documented.
- [ ] ClickUp P4 marked complete.
