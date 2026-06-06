# P4 — opconnect cutover (design)

**Status:** Approved (brainstorm complete, doc-verified) · 2026-06-06
**Parent:** `docs/superpowers/specs/2026-06-06-onprem-greenfield-restructure-design.md` (this details that spec's P4 phase)
**Branch:** `feat/p4-opconnect-cutover`

## Goal

Replace the hand-built **snowflake** 1Password Connect (VM 100 @ `192.168.40.44`) with the
IaC-managed **opconnect VM 1101** (the `tofu/opconnect` tree, merged in P3), with **zero
unplanned secret-access outage**, via build-new → verify-for-real → repoint → clean-cut-retire.

opconnect is the **secrets root**: every other state/role that reads 1Password via Connect
(`ssh-key-loader`, `postgresql/fetch-secrets`, the `compute` tofu `onepassword` provider)
depends on it. "Connect down = all IaC dead." The cutover is therefore gated and reversible
up to the final cut.

## Locked decisions (this session)

1. **Build-time auth = old Connect.** The one-time cutover bootstraps the new Connect using the
   existing old Connect (it is up now). No Service Account is provisioned (none exists:
   `OP_SERVICE_ACCOUNT_TOKEN` is unset, nothing in `.zprofile`/Keychain). The "can't make Connect
   with Connect" circular-dependency only bites a *from-scratch* bootstrap, not a cutover where the
   old server exists. DR for a future from-scratch rebuild is handled by storing the new
   `1password-credentials.json` as a 1P **document**, restored out-of-band via operator `op signin`
   (no standing SA needed).
2. **Retire = hardened clean-cut at verify.** After the *real* authenticated gate passes (not a
   `/heartbeat`/no-op false-positive), immediately revoke the old token, delete the old Connect
   server, stop+delete VM 100. A cold off-box `vzdump` of VM 100 is taken first as zero-surface
   insurance (offline backup, not a running fallback). Rollback after the cut = rebuild from the
   proven 1101.
3. **New token = 90-day expiry** (`--expires-in 90d`), scoped by vault **UUID**, with an overlap
   rotation runbook + T-14d/T-3d monitored alerts (token vault-set + expiry are immutable after
   creation; rotation is revoke+reissue).

## Canonical 1Password Connect facts (doc-verified, authoritative)

Source: `www.1password.dev/connect/{get-started,manage-connect,api-reference}`,
`www.1password.dev/cli/reference/management-commands/connect/`, and the official
`i.1password.com/media/1password-connect/docker-compose.yaml` (490 bytes, verbatim).

**Deployment shape** (official compose = 2 services + 1 named volume):
- Services `op-connect-api` (REST API) and `op-connect-sync` (cloud sync). The authored role uses
  short keys `connect-api`/`connect-sync` — cosmetic, benign.
- Images `1password/connect-api` + `1password/connect-sync`. Official compose uses `:latest`
  (unpinned); **we pin** (deterministic/DR-reproducible) — the correct deviation.
- Ports: `op-connect-api` `8080:8080`; `op-connect-sync` `8081:8080` (sync's host 8081 → container
  8080). The **REST API is reachable on host port 8080**.
- Credentials file: source `./1password-credentials.json` (relative to the **compose project dir**);
  target **inside** both containers `/home/opuser/.op/1password-credentials.json`. The relative `./`
  bind means the file MUST exist, non-empty, at the compose CWD **before** `docker compose up` or the
  bind silently creates an empty dir and sync cannot authenticate.
- Shared named volume `data` → `/home/opuser/.op/data` on **both** services, **read-write** (sync
  writes the synced sqlite DB; api reads it). Both services share the SAME creds file AND the SAME
  data volume — a hard requirement of the api/sync split.
- Official file has **no** `restart`, `healthcheck`, `depends_on`, `networks`, `container_name`, or
  env vars. The authored role adds `restart: always` (good for a secrets root) and `:ro` on the
  creds bind (safe hardening — Connect only reads it). `OP_HTTP_PORT: "8080"` is a no-op tautology
  (re-asserts the image default) → drop. `OP_LOG_LEVEL` is a real-but-undocumented operability
  extension → keep, annotate as non-canonical.

**Health/readiness endpoints** (both unauthenticated):
- `/heartbeat` → HTTP 200 + plaintext `.`. **Liveness only** — proves the api process is up, nothing
  about auth, token validity, or sync. Never the cut gate.
- `/health` → JSON `{name, version, dependencies[]}`. On a fresh server the `sync` dependency reports
  `TOKEN_NEEDED` until the first authenticated request primes it (expected, transient); `sqlite`
  reports `ACTIVE`. (The old role doc's `{"state":"ACTIVE"}` expectation is WRONG — no such field.)
- `GET /v1/vaults` and `GET /v1/vaults/{vaultUUID}/items` require `Authorization: Bearer <token>` +
  `Content-type: application/json`, return 200. `/items` returns metadata (no secret *values*) — so
  "item is listed" is the pass signal, not "secret value retrieved."

**Exact CLI** (`op` must be a **user `op signin`** session; SA tokens cannot manage Connect):
```
op connect server create <name> --vaults <vaultUUID>      # emits ./1password-credentials.json
op connect token  create <tokenName> --server <name> --vault <vaultUUID> --expires-in 90d
op connect vault  grant  --server <name> --vault <vaultUUID>      # add access post-create
op connect server list
op connect server delete <name|id>                         # CLI-only, irreversible
op connect token  list   [--server <name>]
op connect token  delete <token> [--server <name>]
```
- `--expires-in` duration = `(s)(m)(h)(d)(w)` (e.g. `90d`); UI options are 30/90/180d.
- Reference vaults by **UUID**, not name (name → spurious drift). Per-vault perm suffix `,r`/`,w`.
- `--vault` vs `--vaults` on `token create`: the flag table documents `--vault` (repeatable); one
  example uses `--vaults`. **Verify the live `op` CLI accepts the chosen form at P4.0.**
- `server delete` removes only the appliance + its sync credential; it CANNOT touch the cloud vault
  (1password.com is the system of record). Grants are per-server and don't cascade.

## What changes (the thin code/doc PR)

The `tofu/opconnect` tree is already merged (P3). P4's code deliverable:

- **`ansible/playbooks/opconnect.yml`** — relax the hard `OP_SERVICE_ACCOUNT_TOKEN` fail-assertion to
  accept **either** `OP_SERVICE_ACCOUNT_TOKEN` **or** (`OP_CONNECT_HOST` + `OP_CONNECT_TOKEN`). Update
  the header comment to document the chosen old-Connect bootstrap + the from-scratch DR path
  (operator `op signin` → restage creds doc).
- **`tofu/opconnect/providers.tf`** — correct the `onepassword` provider comment: `provider {}`
  auto-detects; with `OP_CONNECT_*` set + no SA token it uses Connect. (No HCL change.)
- **`ansible/roles/opconnect/templates/docker-compose.yml.j2`** — drop the redundant `OP_HTTP_PORT`
  env; keep `restart: always`, creds `:ro`, data volume `rw`. (Service-key rename optional/cosmetic.)
- **`ansible/roles/opconnect/tasks/main.yml`** — add a non-empty validation of the staged creds file
  before `compose up`; replace the bare `/heartbeat` verify with the layered gate (heartbeat →
  `/health` sync-ready → authenticated `/v1` read). Keep `/heartbeat` for container-readiness only.
- **New `docs/runbooks/opconnect-cutover.md`** — the operator P4.0–P4.6 sequence below.
- **New `docs/runbooks/opconnect-token-rotation.md`** — the 90-day overlap rotation runbook.
- **DR:** store the new `1password-credentials.json` as a 1P document in the infra vault; document
  out-of-band retrieval (`op signin` + `op document get`, **never** via Connect). Also keep an
  encrypted off-Connect backup (Backrest/restic) per the self-host convention.

## Cutover sequence (the runbook)

Infra vault UUID = `ve6jgmyk77ssj7aqpeodt2uhyi` (from `TF_VAR_onepassword_vault_id`).
Legend: **[OP]** = operator-gated · **[BUILD]** = additive, non-destructive · **[CUT]** = mutating.

### P4.0 — Pre-flight (no destructive action)
- **[OP]** Verify `1password/connect-api:1.7.3` **and** `connect-sync:1.7.3` both exist on Docker Hub
  as a **matched pair**; record the tag + image digest in a comment next to `opconnect_connect_version`.
  (Mismatched api/sync can wedge sync in a way `/heartbeat` won't catch.)
- **DNS — temp subdomain (no reconcile needed):** `opconnect.fusioncloudx.home` currently resolves
  to `.44` — leave it untouched. The P4.2 apply passes `-var opconnect_dns_name=opconnect-new`,
  so `module.opconnect_dns` creates `opconnect-new.fusioncloudx.home → 1101` instead of the
  canonical name. No collision with the existing `.44` record; the UDM controller never sees a
  duplicate. The old Connect remains reachable by IP (`192.168.40.44`) throughout, so every
  consumer with `OP_CONNECT_HOST` pointing at that IP is unaffected. The canonical name
  `opconnect.fusioncloudx.home` is reclaimed at the new P4.6 finalize step after VM 100 is retired.
- **Consumer enumeration:** list every `op://` reference across tofu `onepassword` data sources AND
  `ansible site.yml` + all roles; resolve each to its vault; confirm all live in the infra vault (or
  assemble the full vault set). Known consumers: Infrastructure Ansible SSH Key, GitLab Root, GitLab
  Runner Token, PostgreSQL Admin, PostgreSQL Wazuh DB User, TLS certs. **Token-scope good news
  (verified):** the old token sees exactly ONE vault — `ve6jgmyk77ssj7aqpeodt2uhyi` ("FusionCloudX").
  The new 90d token scoped to that single vault therefore gives exact parity with no darkout. Note:
  `ansible/inventory/devices.yaml` device-cert items target LOCAL DESKTOP 1Password (not Connect) —
  out of scope, not a concern.
- **[OP]** Confirm the live `op` CLI accepts the chosen `--vault`/`--vaults` form + `--expires-in 90d`.
- Confirm S3+CMK backend reachable (`AWS_PROFILE=fcx-sso`) for the opconnect state.
- Decide `prevent_destroy` handling for 1101 (see Rollback): keep it on with the documented escape
  hatch (default) — it is already merged.

### P4.1 — Bootstrap the new Connect identity **[OP]** (old Connect untouched)
```
op signin                                                  # user account session
op connect server create opconnect --vaults ve6jgmyk77ssj7aqpeodt2uhyi   # -> ./1password-credentials.json
op connect token create opconnect-fleet --server opconnect \
    --vault ve6jgmyk77ssj7aqpeodt2uhyi --expires-in 90d    # capture token + issuance date (T+90d deadline)
```
Keep the new token OUT of the build shell env. Store the new `1password-credentials.json` as a 1P
document + an encrypted off-Connect backup (out-of-band retrieval documented).

### P4.2 — Build VM 1101 **[BUILD]** (auth = old Connect)
- `export AWS_PROFILE=fcx-sso; export UNIFI_API_KEY=…` (Keychain). Old Connect env stays set.
- `tofu -chdir=tofu/opconnect apply -input=false -var opconnect_dns_name=opconnect-new` — the
  `onepassword` provider reads the one item (Ansible SSH key) via the **old Connect**; builds VM
  1101 + the DNS record `opconnect-new.fusioncloudx.home → 1101` (no collision with the canonical
  `.44` record, which is left untouched).
- Stage `1password-credentials.json` onto 1101 at `opconnect_credentials_src` (`/root/…`); the role
  copies it to the compose dir `/opt/opconnect/1password-credentials.json` (validated non-empty).
- `ansible-playbook playbooks/opconnect.yml` — brings up `connect-api 8080` + `connect-sync 8081`
  (pinned, creds `:ro`, data `rw`, `restart: always`). Role waits for `/heartbeat` 200 = **container
  liveness only**.

### P4.3 — GATE: readiness + authenticated proof **[BUILD]** (test 1101's IP directly)
1. `/heartbeat` 200 (liveness, done by the role).
2. Poll `GET http://<1101-IP>:8080/health` with backoff until `sync` leaves `TOKEN_NEEDED` AND
   `sqlite` is `ACTIVE`; a hard timeout **ABORTS** (VM 100 fully intact). Confirm `version` == pinned tag.
3. **Authenticated:** `GET http://<1101-IP>:8080/v1/vaults` (Bearer = new token) → 200 + infra vault
   present; then `GET /v1/vaults/ve6jgmyk77ssj7aqpeodt2uhyi/items` → must list the Ansible SSH key +
   representative app secrets (GitLab/PostgreSQL/Wazuh/TLS). Empty/partial = NOT-PASS (retry/backoff,
   then abort). Both Connects still running; nothing on VM 100 touched.

### P4.4 — Repoint to temp subdomain + broad verify **[CUT, reversible]**
- The P4.2 apply already created `opconnect-new.fusioncloudx.home → 1101`; **verify** `dig +short
  opconnect-new.fusioncloudx.home == <1101-IP>` before trusting the temp hostname. The canonical
  record `opconnect.fusioncloudx.home → .44` is NOT touched.
- Update Keychain `opconnectfcxtoken` → new token; `.zprofile` `OP_CONNECT_HOST` →
  `http://opconnect-new.fusioncloudx.home:8080` (resolves to 1101); `TF_VAR_onepassword_connect_token`
  → new token; the DR 1P-document copy. Start a fresh shell; restart long-lived consumers (launchd/cron/CI).
- **Broad verify** (not a single no-op): `tofu -chdir=tofu/compute plan` (clean, via new token) AND a
  full `ansible-playbook site.yml` with **assert/fail-on-empty** for each critical secret class AND an
  explicit `/v1` item read per vault/secret class. Prove traffic hits **1101** (server log / `/health`
  served-from), not `.44`.
- Rollback in this window = revert host/token env back to the old `.44`; the canonical
  `opconnect.fusioncloudx.home → .44` record was never touched, old token still valid, old server
  + VM 100 still up.

### P4.5 — Retire (hardened clean-cut) **[CUT, irreversible]**
Only after the P4.4 broad verify is clean:
1. `vzdump 100` → off-box storage (cold backup; not a running fallback).
2. `op connect token delete <old-token>` ; `op connect server delete <old-server>` (CLI-only,
   irreversible; safe for cloud vault data).
3. Stop + delete snowflake VM 100 (Proxmox).
4. **Delete the old `opconnect → .44` A record on the UDM** (UniFi DNS UI). VM 100 is gone; the
   canonical name is now free to be reclaimed at P4.6.
5. `prevent_destroy` on 1101 stays on; the abort escape-hatch is documented (see Rollback).
6. Update `docs/.../1Password-Connect.md` (host = 1101, correct `/health` expectation, out-of-band DR
   retrieval) + record the T+90d rotation deadline.

### P4.6 — Finalize: reclaim the canonical name **[CUT]**
Only after P4.5 is complete (old VM + record deleted, old token/server revoked):
1. Run `tofu -chdir=tofu/opconnect apply -input=false` (default var — `opconnect_dns_name=opconnect`).
   OpenTofu creates `opconnect.fusioncloudx.home → 1101` and destroys the temp
   `opconnect-new.fusioncloudx.home` record in one apply.
2. **Verify:** `dig +short opconnect.fusioncloudx.home @192.168.40.1 == <1101-IP>` AND confirm
   `opconnect-new.fusioncloudx.home` no longer resolves.
3. Repoint `OP_CONNECT_HOST → http://opconnect.fusioncloudx.home:8080` in `.zprofile` + Keychain note
   (token unchanged). Open a fresh shell; restart long-lived consumers.
4. **Final broad verify:** `tofu -chdir=tofu/compute plan -input=false` clean (0 errors) AND
   `ansible-playbook site.yml` 0 failures. Confirm traffic hits 1101 via the canonical hostname.
5. Update docs (this spec, the runbook, `docs/.../1Password-Connect.md`) to reflect canonical end state.

**End state:** `opconnect.fusioncloudx.home → 1101` (canonical); `opconnect-new` record gone; old
VM 100, old token, and old server all absent. The temp subdomain was ephemeral scaffolding — it
never appeared in any consumer's `OP_CONNECT_HOST` beyond this session.

## Auth & secret flow
- **Build (P4.2):** old Connect (`OP_CONNECT_*` in env) → onepassword provider reads the Ansible SSH
  key item; `ssh-key-loader` play likewise.
- **New Connect:** granted the infra vault (UUID) at create; new token scoped to the infra vault,
  90d.
- **Post-cutover (P4.4+):** every consumer reads via the new Connect (env repoint).

## Error handling / rollback / abort
- **Before P4.4:** old Connect untouched → abort = leave 1101 running (harmless parallel) and fix
  forward.
- **P4.4 → P4.5:** revert Keychain/`.zprofile` env to old `.44`; the canonical
  `opconnect.fusioncloudx.home → .44` record was never touched → instant rollback (old still valid).
- **After P4.5:** old gone; rollback = restore the `vzdump` or rebuild from the proven 1101.
- **`prevent_destroy` escape hatch (VM 1101):** to tear down/recreate 1101 on a failed cutover —
  (a) comment out `protected = true` (→ disposable variant) in `tofu/opconnect/opconnect.tf`,
  (b) `tofu apply` (removes the guard from state intent), (c) `tofu destroy`/recreate, (d) re-add
  `protected = true` + apply. Plan-time rule: if `tofu plan` shows `-/+ replace` on VM 1101, **STOP**
  — the seatbelt is working; never `qm destroy` manually (state drift).

## Verification (acceptance gates; real-system, no unit tests)
- `/heartbeat` 200 on 1101.
- `/health`: `sync` not `TOKEN_NEEDED`, `sqlite ACTIVE`, `version` == pinned tag.
- Authenticated `GET /v1/vaults` + `/v1/vaults/{uuid}/items` with the new token list the infra vault
  + the Ansible SSH key + representative app secrets — **before** any cutover.
- `dig +short opconnect-new.fusioncloudx.home == <1101-IP>` after the P4.2 apply (temp subdomain).
- `dig +short opconnect.fusioncloudx.home == <1101-IP>` after P4.6 finalize (canonical).
- Post-repoint `tofu -chdir=tofu/compute plan` clean (via new token); `ansible site.yml` 0 failures
  with non-empty asserts on every critical secret class.
- Old fully gone: `op connect server list` lacks the old server; old token revoked; VM 100 absent in
  Proxmox; off-box `vzdump` exists.

## Token rotation runbook (90-day, overlap = zero downtime)
1. Monitored check calls `GET /v1/vaults` with the live token; alerts at **T-14d** and **T-3d**
   before the computed deadline (issuance date known).
2. Rotate: `op connect token create` a NEW token (same server, same vault) → verify it serves via
   authenticated `GET /v1/vaults` → update Keychain `opconnectfcxtoken` + `TF_VAR_onepassword_connect_token`
   + the DR doc → re-source + restart every long-lived consumer → one verify (`site.yml` + asserts)
   → **only then** `op connect token delete <old>`.
3. Old token stays valid until the final delete = zero downtime if overlap is honored.

## Out of scope
P5 compute rebuild; provisioning a Service Account; auto-reading creds from 1P at provision
(operator-mediated only); the HTTPS/8443 Connect hardening (separate later work); broader P6 docs.

## Definition of done
- Code/doc PR (`feat/p4-opconnect-cutover`) merged via the full review lifecycle (local +
  `@claude`).
- New Connect on 1101 verified by the authenticated `/v1` gate; fleet repointed via temp subdomain
  (P4.4) then canonical hostname (P4.6); broad verify clean.
- Old snowflake fully retired (token revoked, server deleted, VM 100 gone, old `opconnect → .44`
  UDM record deleted, off-box `vzdump` kept); canonical `opconnect.fusioncloudx.home → 1101`.
- Rotation runbook + T-14d/T-3d alerts in place; DR creds document stored with out-of-band retrieval
  documented; ClickUp P4 marked complete.
