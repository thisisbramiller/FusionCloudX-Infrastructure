# opconnect 90-Day Token Rotation Runbook

## Purpose

The fleet's `OP_CONNECT_TOKEN` (Keychain key `opconnectfcxtoken`) is created with
`--expires-in 90d` and scoped to vault UUID `ve6jgmyk77ssj7aqpeodt2uhyi`. Two properties
of Connect access tokens are **immutable after creation**:

- The vault set the token can access
- The expiry date

There is no in-place renewal. Rotation is **revoke + reissue**, not extension.

An expired token causes a silent fleet-wide 401 cliff. Connect will continue to serve cached
reads, masking the failure — the cliff only becomes visible on the next re-auth or `tofu
apply` / `ansible-playbook` run. Because opconnect is the secrets root ("Connect down = all
IaC dead"), the rotation must be proactively monitored and executed before expiry.

---

## Deadline Tracking

Record the **issuance date** every time a token is created. The T+90d deadline is:

```
deadline = issuance_date + 90 days
```

Two independent alert layers are required so a single point of failure cannot hide the cliff:

### Layer 1 — Monitored check (automated)

Set up a check that calls `GET /v1/vaults` with the live token:

```bash
curl -fsS \
  -H "Authorization: Bearer $OP_CONNECT_TOKEN" \
  -H "Content-type: application/json" \
  http://opconnect.fusioncloudx.home:8080/v1/vaults
```

- A non-200 response or connection failure = alert immediately (token expired or Connect down).
- Alert at **T-14d** (14 days before deadline) — rotation window opens.
- Alert at **T-3d** (3 days before deadline) — rotation is urgent.

The check should be wired to a notification channel (email, Slack, PagerDuty, or equivalent)
that Branden actively monitors.

### Layer 2 — Calendar reminder (independent)

Create a calendar event at **T-14d** and a second event at **T-3d**, independent of the
monitoring stack. If the monitor silently fails (misconfiguration, network partition, the
rotation runbook itself is broken), the calendar reminder is the backstop.

Update both calendar events immediately after each rotation with the new deadline.

---

## Overlap Rotation Procedure (Zero Downtime)

The old token remains valid until the final revoke step. Do not skip ahead.

### Step 1 — Create the new token

```bash
op connect token create opconnect-fleet-<YYYY-MM-DD> \
  --server opconnect \
  --vault ve6jgmyk77ssj7aqpeodt2uhyi \
  --expires-in 90d
```

- Replace `<YYYY-MM-DD>` with today's date (token name is a human-readable label only).
- Capture the returned token value — it is shown **once** and cannot be retrieved again.
- Record the issuance date; compute the new T+90d deadline immediately.

### Step 2 — Verify the new token serves

Before touching any live consumer, confirm the new token is functional:

```bash
curl -fsS \
  -H "Authorization: Bearer <newtoken>" \
  -H "Content-type: application/json" \
  http://opconnect.fusioncloudx.home:8080/v1/vaults
```

Expected: HTTP 200 with the infra vault (`ve6jgmyk77ssj7aqpeodt2uhyi`) present in the
response. If this returns anything other than 200, **stop** — do not proceed to step 3.
Debug Connect health (`GET /health`, container logs) before continuing.

### Step 3 — Repoint all credential stores

Update every location that holds the token:

**Keychain (primary runtime source):**
```bash
security add-generic-password -U -a "$USER" -s opconnectfcxtoken -w '<newtoken>'
```

`.zprofile` re-derives `OP_CONNECT_TOKEN` and `TF_VAR_onepassword_connect_token` from
Keychain at shell startup — no direct edits to `.zprofile` are needed unless the variable
names or the Keychain key name changed.

**DR 1Password document:**
Update the `1password-credentials.json` document stored in the infra vault to include the
new token value and the new deadline date. This is the out-of-band recovery copy and must
stay current.

### Step 4 — Restart every long-lived consumer

Re-sourcing `.zprofile` in the current shell is not enough — any process that inherited the
old token in its environment will continue to use it until restarted.

Restart all of the following:

- Open a **fresh shell** (new terminal session; do not just `source ~/.zprofile` in an
  existing one that already has the old token exported).
- **launchd agents** that set or consume `OP_CONNECT_TOKEN` — `launchctl stop` + `start`
  (or `unload` + `load`) for each relevant agent.
- **Cron jobs / CI runners** — restart or reload so the next run picks up the new token from
  Keychain/env rather than a stale in-process copy.

### Step 5 — Verify fleet-wide (before revoking old token)

With the new token live in env and all consumers restarted, run a full fleet check:

```bash
# OpenTofu: provider should authenticate via new token, plan should be clean
tofu -chdir=tofu/compute plan

# Ansible: full site playbook with non-empty asserts on every critical secret class
ansible-playbook playbooks/site.yml
```

Pass criteria:
- `tofu plan` exits 0, no unexpected changes.
- `ansible-playbook` exits with 0 failures and non-empty assert results (secrets were
  actually fetched — not empty strings that silently passed assertion).

If either check fails, **do not proceed to step 6**. Diagnose, fix, and re-run the verify.
The old token is still valid at this point — rollback is instant (restore old token to
Keychain, restart consumers).

### Step 6 — Revoke the old token (last step)

Only after step 5 passes:

```bash
op connect token delete <old-token> --server opconnect
```

The old token is now invalid. The fleet is fully on the new token with zero downtime because
the old token remained valid through steps 1–5.

---

## Update Deadline Tracking

After a successful rotation:

1. Update the monitored check with the new T+90d deadline.
2. Update the calendar reminders (T-14d and T-3d) to the new deadline dates.
3. Record the new issuance date in this runbook or in the infra vault DR document.

---

## Gotchas

**Token vault-set and expiry are immutable.** There is no `--extend` or `--revault`. If the
wrong vault UUID or a short expiry is used at create time, the only fix is to revoke that
token and issue a new one.

**Restarted consumers must re-read env from Keychain.** `security` writes to Keychain, but
any process that already has the old token in its environment will not pick up the change
until it is restarted. A `source ~/.zprofile` in an existing shell is not sufficient — the
shell already has the old exported value. Open a new terminal.

**Do not revoke first.** The overlap is intentional. Revoking the old token before verifying
the new one causes an immediate outage if the new token or its deployment has any problem.
The revoke (step 6) is always last.

**Connect cached reads mask an expired token.** Connect may continue serving reads from its
SQLite cache after the token expires. The 401 cliff only surfaces on re-auth or a fresh
provider/role run. This is why the monitored check must call an **authenticated** endpoint
(`GET /v1/vaults`), not `/heartbeat` (unauthenticated liveness only).
