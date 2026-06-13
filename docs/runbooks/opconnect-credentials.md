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
ansible/playbooks/opconnect_credentials.yml  ->  roles/opconnect_credentials/  (standalone role, NO docker dep)
```

It is **idempotent + expiry-aware**: seeds if the secret is absent, rotates only the
token if it is within `opconnect_creds_rotate_threshold_days` (14) of expiry, else
no-ops. Rotation preserves the server identity + the ansible keypair (no fleet-wide
bootstrap-key churn).

## One-time control-node setup (macOS)
The `amazon.aws`/`community.aws` modules **and** the `aws_secret` lookup need `boto3` in the
interpreter Ansible itself runs on, so build a venv and run Ansible **from it** (the repo path
must be space-free — see the 2026-06-13 rename):
```bash
cd ansible
uv venv .venv
uv pip install --python .venv/bin/python ansible-core boto3 botocore cryptography
.venv/bin/ansible-galaxy collection install amazon.aws community.aws community.crypto
```

## Preconditions (every run)
1. 1Password **desktop app unlocked** (account-mode `op`; the seed forces `OP_CONNECT_*` unset).
2. `aws sso login --sso-session fcx-sso` (FIDO).
3. The `15-opconnect-credentials` layer is applied (the empty secret exists).

## Seed / rotate
```bash
cd ansible
OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES no_proxy='*' \
  .venv/bin/ansible-playbook -i 'localhost,' \
  -e "ansible_python_interpreter=$PWD/.venv/bin/python" \
  playbooks/opconnect_credentials.yml            # seed if absent / rotate if near expiry
# add -e force=true to force a rotation now
```
The env matters (all validated 2026-06-13):
- run via the **venv's** `ansible-playbook` — the `aws_secret` lookup runs in the *controller*, so `boto3` must be there;
- `OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES` + `no_proxy='*'` — avoid the macOS fork-safety "worker in a dead state" crash on the in-process lookup;
- `ansible_python_interpreter` → the venv (module tasks also get `boto3`);
- **no `AWS_PROFILE`** — the role passes the SSO profile to `sts_assume_role` as a *param* (else `amazon.aws` errors "both a profile and access tokens").
> **NEVER** pass `-v` / `-vvv` — verbose bypasses `no_log` and would leak the bundle.

Expected: first run "seeded; token_expires …" (`changed`); re-run "valid … nothing to do"
(seed/rotate block skipped); with `-e force=true`, "rotated; token_expires …" advanced —
`connect_credentials_json` + ansible keypair **preserved**, only the token + expiry change.

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

## Status — seed/rotate VALIDATED live 2026-06-13
- **Seed:** first run created the Connect server + minted a 90-day token + keypair + wrote the bundle (`changed=True`).
- **Idempotent:** an immediate re-run skipped the entire seed/rotate block (no churn).
- **Rotate (`-e force=true`):** re-minted the token only — `connect_credentials_json`, `ansible_public_key`, `ansible_private_key` byte-identical before/after; `connect_token` + `token_expires` + `created` advanced. Verified by field SHA comparison.
- Confirmed: Jinja expiry math, `op connect ... --expires-in`, `amazon.aws`/`community.aws` params, vault = `FusionCloudX`, and the macOS env above.
- **NOT yet validated:** the recovery/consume path — that this bundle can *rebuild* opconnect. That's Phase C4 (ansible reads) + the clean-room DR drill (destroy → restore → confirm Connect serves).
