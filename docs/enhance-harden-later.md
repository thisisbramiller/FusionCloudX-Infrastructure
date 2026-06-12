# Enhance / Harden / Later — Deferred Backlog

**Purpose.** Items deliberately deferred OUT of the terraform→tofu migration scope. The
migration's goal is **engine + structure** (terraform→tofu, three-state split, fleet running on
tofu, S3 backend). Everything in this file is real, tracked, and **not lost** — but explicitly
post-migration. Captured 2026-06-12 after a deep secret-zero / identity-architecture detour, so
the research isn't wasted.

---

## A. opconnect secret-zero / bootstrap-trust architecture  (Task #68)

**Context.** The opconnect Ansible-SSH-key bootstrap (the "secret-zero" problem) was never
cleanly solved in the migration: the original spec (#7) assumed an `OP_SERVICE_ACCOUNT_TOKEN`
that **does not exist** (design spec confirms it is unset; nothing in `.zprofile`/Keychain). The
TF `onepassword` provider can authenticate only via Connect or an SA token — it **cannot** use
the desktop `op` CLI (proven: `tofu plan` with Connect env stripped → `Invalid provider
configuration`). So any opconnect design that uses the `onepassword` provider (read OR write)
requires a live Connect or an SA token — the chicken-and-egg. The migration ships a **minimal
Connect-independent fix**; the durable architecture is deferred here.

**Research findings (preserve — this took real work):**

- **Canonical problem:** "secret zero" / "chicken-and-egg" / "secure introduction" / "bootstrap
  trust" (HashiCorp's own framing — `hashicorp.com/.../delivering-secret-zero-vault-approle`).
- **Recognized patterns:** provider-dependency inversion (the layer that provisions the secrets
  backend must NOT configure/depend on that backend's provider); generate-keypair-in-IaC +
  write-back the private half to a store (packaged: `rhythmictech/terraform-aws-secretsmanager-keypair`
  — `tls_private_key` → public to `aws_key_pair`, private to Secrets Manager); out-of-band seeding
  (how 1Password Connect seeds its OWN `1password-credentials.json` + token via
  `op connect server/token create`; how Vault seeds via `operator init` + Shamir unseal); trusted
  machine identity (cloud IAM removes static secret-zero); auto-unseal "**relocates rather than
  eliminates**" the trust anchor.

- **AWS SSM anchor design** (convention-compliant per the full 108-file map of `aws-foundation`):
  - New LOW layer `onprem-infra/tofu/00-foundation`: generate `tls_private_key` (ed25519) → write
    the private key to **SSM SecureString** at `/tmpx/onprem/bootstrap/ssh/private` under a **NEW**
    purpose CMK `alias/tmpx/onprem-bootstrap` (NEVER the state CMK `alias/tmpx/tfstate`) in
    **shared-services 065094257518 / us-east-2** via `tmpx-TerraformExecutionRole`; publish **only
    the public key** via `terraform_remote_state`. opconnect/compute read the pubkey via remote
    state; ansible reads the private key from SSM via the SSO session. NOT in `aws-foundation`
    (its README bars workload secrets); NOT bolted onto opconnect's providers.
  - Conventions to obey: `tmpx`/`use2`/snake_case naming, `tmpx:` default-tags, S3-native lockfile,
    enforced native AES-GCM state encryption, the remote_state output contract.
  - Biggest risk: private key in that layer's state → mitigated by enforced AES-GCM + tight
    state-read scope.

- **North star — IAM Roles Anywhere:** an X.509 trust anchor in the identity plane → on-prem hosts
  present client certs, exchange for short-lived STS creds, pull their own secrets from AWS → the
  static SSH key (and the SSM SecureString as a *standing* secret) get **retired entirely**.
  `30-identity` already plans the sibling CI half (GitHub/GitLab OIDC, issue #27 — not yet built).
  Roles Anywhere is **not** in the repo today (zero references).

- **Machine-identity spine options researched** (decision deferred): IAM Roles Anywhere vs
  self-hosted Vault (KMS auto-unseal + SSH secrets engine/PKI) vs SPIFFE/SPIRE vs SSH-CA
  (step-ca / OpenSSH CA) vs 1Password-at-scale vs TPM/vTPM attestation. The
  `machine-identity-spine-research` workflow was authored + launched, then **stopped mid-run** when
  we re-grounded on the migration — re-run it (script saved in the session workflows dir) when
  tackling #68.

---

## B. Secret-in-state hardening  (original spec #8 — relaxed during migration)

Replace `resource "tls_private_key"` (private key → plaintext state) with `ephemeral
"tls_private_key"` + a **write-only** `value_wo` push to 1Password; prefer `password_wo` for
generated DB passwords. Relaxed by explicit decision ("why do we need write-only? → M1, no
write-only; get it working first, harden later").

---

## C. AWS landing-zone alignment  (discovered this session)

**OAAR → `tmpx-TerraformExecutionRole`.** Every on-prem `backend.tf` assumes
`arn:aws:iam::065094257518:role/OrganizationAccountAccessRole`, but `aws-foundation/10-bootstrap`
defines `tmpx-TerraformExecutionRole` as THE intended exec identity (AdministratorAccess +
`tmpx-TerraformExecutionBoundary`), which the backends do not use. Migrate the on-prem backends'
assume-role target to the intended exec role (repo-wide, deliberate).

---

## D. Tracked task backlog (one-liners → Claude task IDs)

- **#68** hybrid machine-identity + secrets + bootstrap-trust architecture (section A above)
- **#67** rename "09-Homelab" / retire "homelab" framing across vault + repo docs
- **#58** reconcile `devices.yaml` NAS `.50` → `.137`
- **#59** make `.tofurc` Linux/CI portable
- **#60** store `1password-credentials.json` as a 1Password DR document
- **#61** execute opconnect 90-day Connect token rotation (~Sep 5 2026)
- **#64** immich missing 32 GB extra disk (parity)
- **#65** gitlab cloud-init runcmd parity (postfix + smoke tests + marker)
- **#66** site.yml shouldn't abort the whole fleet when one app play fails
- **#6**  re-architect runitup to pull a pinned image from the registry
- **#29** encrypt or migrate ansible `group_vars/vault.yml` (plaintext placeholders)
- **#22** harden `~/.ssh/config` fleet block for rebuild host-key churn (scoped known_hosts)
- **#18** debug NFS reconcile mount hang after mountd bounce
- **#2/#3** container registry + SDLC supply-chain stack decision + backlog stories
