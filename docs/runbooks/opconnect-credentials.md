# Runbook — opconnect off-site credentials (seed / rotate / DR)

The AWS Secrets Manager secret `tmpx/onprem/opconnect-credentials` is the **off-site
copy of opconnect's credentials** (1Password Connect `credentials.json` + token +
the ansible bootstrap keypair), encrypted under `alias/tmpx/onprem-opconnect` in
`aws-foundation/15-opconnect-credentials`. It exists to recover the on-prem secrets
root (opconnect) after a disaster, new hardware, or a clean rebuild — **without**
depending on the very thing it recovers.

> Distinct from [`opconnect-token-rotation.md`](opconnect-token-rotation.md), which
> rotates the **live operational** Connect token. This runbook manages the **off-site
> DR copy**. Design: spec `docs/superpowers/specs/2026-06-13-onprem-bootstrap-trust-recovery-anchor-design.md` (#68, D8).

## The tool

A pure-Ansible playbook — **not** a script, **not** in `site.yml`:

```
ansible/playbooks/opconnect_credentials.yml  ->  roles/opconnect/tasks/seed.yml
```

It is **idempotent + expiry-aware**: seeds if the secret is absent, rotates only the
token if it is within `opconnect_creds_rotate_threshold_days` (14) of expiry, else
no-ops. Rotation preserves the server identity + the ansible keypair (no fleet-wide
bootstrap-key churn).

## Preconditions (every run)
1. 1Password **desktop app unlocked** (account-mode `op`; the seed forces `OP_CONNECT_*` unset).
2. `aws sso login --sso-session fcx-sso` (FIDO).
3. The `15-opconnect-credentials` layer is applied (the empty secret exists).

## Seed / rotate
```bash
cd ansible
ansible-playbook playbooks/opconnect_credentials.yml            # seed if absent / rotate if near expiry
ansible-playbook playbooks/opconnect_credentials.yml -e force=true   # force a rotation now
```
> **NEVER** pass `-v` / `-vvv` — verbose bypasses `no_log` and would leak the bundle.

Expected: on first run "seeded; token_expires …"; on a re-run "valid … nothing to do"
(`changed=false`); with `force=true`, "rotated; token_expires …" (advanced).

## Offline 3-2-1 copy (AWS-unreachable cold-start; closes #60)
After a seed/rotate, export an encrypted copy to an offline location (encrypted USB /
fireproof):
```bash
# read the bundle (SSO + assume-role), encrypt symmetrically, store offline
aws secretsmanager get-secret-value --secret-id tmpx/onprem/opconnect-credentials \
  --query SecretString --output text | age -p > opconnect-credentials.age   # or: gpg -c
```
Passphrase custody: memorized / FIDO-protected, **NOT** in 1Password (circular).

## Clean-room DR drill (acceptance)
1. (GATED) Destroy opconnect (`tofu -chdir=tofu/opconnect destroy`; lift `prevent_destroy` for the drill, restore after).
2. Re-bootstrap using ONLY: `aws sso login --sso-session fcx-sso` → `tofu -chdir=tofu/opconnect apply` → `cd ansible && ansible-playbook playbooks/opconnect.yml`. **No** Mac `op` account-mode step.
3. Verify: Connect `/heartbeat` OK + serves a test secret; `tofu state list` (both layers) greps zero `tls_private_key`/plaintext (#8); a principal without SSO/OAAR gets AccessDenied on `get-secret-value`.

## Status
First-run validation **pending** (gated B3 in the plan): the seed playbook's Jinja
expiry math, the `op connect ... --expires-in` flags, and the `amazon.aws`/`community.aws`
param names are confirmed live on the first real seed. Written from the approved plan
2026-06-13.
