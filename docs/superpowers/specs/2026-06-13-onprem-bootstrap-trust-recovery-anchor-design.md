# onprem opconnect off-site credentials — Bootstrap-Trust Design Spec (Wave 1)

**Status:** APPROVED + locked (brainstorm 2026-06-13) — **refined same day** via voice: (a) seed/rotate is a pure-**Ansible** playbook, not a script and not in `site.yml`; (b) naming purged of the recovery-anchor/break-glass *metaphor* → the literal **opconnect-credentials**; (c) the CMK key policy is **root-enable-only** (as-built), not SSO-admin-conditional.
**Task:** #68 (FusionCloudX hybrid machine-identity + secrets + bootstrap-trust)
**Repos touched:** `aws-foundation` (`15-opconnect-credentials` layer) + `onprem-infra` / FusionCloudX Infrastructure (consumer + seed).
**Supersedes:** the "Option D" stopgap (desktop `op` CLI account-mode write-back) as the bootstrap mechanism. A standalone **bash** seed script was prototyped this session and **rejected** in favor of Ansible (worst-of-both-worlds: hand-rolled secret-handling + the bundle schema trapped in a second language).

> **Naming note:** "recovery anchor" / "break-glass" describe the *role* this material plays in a disaster; they are **not** the artifact's identity. The thing itself is **opconnect's credentials**, stored off-site. Names are literal (matching `opconnect`, `gitlab`, `immich`); "recovery"/"break-glass" appear only as descriptors in prose.

---

## Goal

Give the on-prem secrets root (opconnect / 1Password Connect) a **disaster-recoverable, FIDO-gated bootstrap** by storing an off-site copy of opconnect's credentials in AWS — the trust anchor that already holds the OpenTofu state — **without** giving opconnect a standing machine identity and **without** moving day-2 operational secrets off-prem.

---

## Problem

- **Secret-zero / circular dependency:** opconnect runs 1Password Connect, which serves secrets to compute + Ansible (day-2). So opconnect's *bootstrap* cannot depend on Connect, and no `OP_SERVICE_ACCOUNT_TOKEN` exists. Today's "Option D" works but is **Mac-bound + manual** (desktop `op` CLI account-mode) — not DR-portable.
- **Issue #8:** the Ansible SSH private key + generated DB passwords currently persist in encrypted OpenTofu state.
- **Hybrid estate:** on-prem Proxmox fleet (onprem-infra: OpenTofu 3-state + Ansible) + AWS prod org (aws-foundation: LZA-style layers; Identity Center SSO; `tmpx` CMKs; `tmpx-TerraformExecutionRole`; tfstate in S3+SSE-KMS). onprem-infra already consumes aws-foundation's backend (same bucket + tfstate CMK + assume-role).

## Locked decisions (from the brainstorm)

| # | Decision | Rationale |
|---|---|---|
| D1 | **Two tiers.** Operational/day-2 secrets stay **local** (1Password Connect on-prem, unchanged). The off-site copy of opconnect's credentials goes **off-site** (AWS). | Locality is a runtime-availability rule (a remote vault is a total-blast-radius SPOF); the off-site copy is governed by a different rule — survive the destruction of everything it recovers. Consensus + AWS guidance. |
| D2 | **Human-orchestrated bootstrap.** The trusted orchestrator is Branden via AWS SSO (`fcx-sso`) + FIDO (YubiKey + Titan). **No CI delegation, no Roles Anywhere, no new always-on service.** | Bootstrap = disaster-recovery / new-hardware: the operator is present, nothing else exists yet, and self-hosted GitLab is built *after* opconnect so it can't bootstrap it. Human + hardware key in the loop is a feature for the root of trust. |
| D3 | **AWS is the trust anchor.** Secret-zero collapses up to the AWS root/org account, break-glass, behind FIDO. | AWS is already the tfstate anchor — on-prem already can't cold-start without AWS, so this names a dependency already accepted, not a new one. |
| D4 | **The CMK + the secret live together in a NEW aws-foundation numbered layer** (`15-opconnect-credentials`), separation enforced by the **key policy** (IAM), not by splitting repos. | AWS never separates a key from the data it wraps; recovery-of-the-estate is a foundation concern, not a workload; the layer must not depend "down" on the estate it recovers; one-place DR for a solo op. Separation-of-duties is an IAM concern, satisfied by the key policy. |
| D5 | **The layer is a NEW aws-foundation layer**, not bolted onto `10-bootstrap`. **No new repo.** | aws-foundation convention: each CMK lives in the layer owning its consumer; decade-gaps exist for insertion; `10-bootstrap` is the highest-blast-radius prevent_destroy state — don't overload it. A new repo has no independent owner/cadence (pure overhead for a solo op). |
| D6 | **Wire by KMS alias + secret name, NOT `terraform_remote_state`.** onprem references `alias/tmpx/onprem-opconnect` (`data "aws_kms_alias"`, tofu) + `tmpx/onprem/opconnect-credentials` (`amazon.aws.aws_secret`, Ansible). | HashiCorp explicitly discourages cross-state `remote_state` reads (consumer gets the producer's entire state snapshot + tight coupling). The alias/name is a stable string contract with zero coupling. |
| D7 | **1Password stays the day-2 secrets plane** (on-prem Connect, unchanged). The 1Password→AWS Secrets Sync (beta) is an **optional future day-2 nicety**, **not** part of Wave 1, and structurally cannot bootstrap (one-way, presupposes 1P is up). | Keeps the single human-facing pane; the sync is orthogonal to bootstrap. |
| **D8** | **Seed/rotate is a pure-Ansible playbook** (`opconnect_credentials.yml` → `opconnect` role `tasks/seed.yml`), **idempotent + expiry-aware**, run by hand on the operator workstation, **NOT** imported by `site.yml`, **NOT** a bash script. | Ansible is the estate's config-mgmt + the DR *restore* path is already an Ansible role, so a script would mean a second toolchain + a forked bundle schema (drift). `no_log` + module params are safer-by-default than hand-rolled shred/trap. The play breaks four properties `site.yml` must keep (can't run unattended/biometric; targets localhost not the fleet; no-reverse-dependency; highest-privilege ≠ most-frequent) → separate operator-run entry point, which is still 100% as-code (Ansible's own sample layout). |

---

## Architecture

```
                AWS  (off-site recovery domain, already the tfstate anchor)
  ┌─────────────────────────────────────────────────────────────────────────┐
  │ aws-foundation / 15-opconnect-credentials   (NEW layer, own tofu state)   │
  │   • CMK  alias/tmpx/onprem-opconnect   (dedicated; NOT the tfstate CMK)    │
  │   • key policy: ROOT-ENABLE ONLY (estate convention) — use delegated to   │
  │       shared-services IAM; both human-gated paths (IdC AdministratorAccess │
  │       SSO + OrganizationAccountAccessRole) use it via IAM; FIDO-gating is  │
  │       structural via Identity Center MFA. No kms:ViaService. No CI.        │
  │   • SECRET  tmpx/onprem/opconnect-credentials  (Secrets Manager, JSON)     │
  │       tofu owns the EMPTY container; value seeded out-of-band (Ansible)    │
  │   • outputs: opconnect_cmk_arn/alias, opconnect_credentials_secret_arn/id  │
  └─────────────────────────────────────────────────────────────────────────┘
        ▲ alias + name string contract (no remote_state)     │ human reads via
        │                                                     │ SSO+FIDO at seed/DR
  ┌─────┴─────────────────────────────────────────────────────▼───────────────┐
  │ onprem-infra                                                                │
  │   SEED (produce):  ansible playbook opconnect_credentials.yml  (localhost)  │
  │     → opconnect role tasks/seed.yml: mint/rotate Connect token (account     │
  │       op), assemble bundle, write tmpx/onprem/opconnect-credentials.        │
  │       idempotent + expiry-aware. NOT in site.yml. NOT a script.             │
  │   CONSUME (restore):  tofu/opconnect reads the PUBLIC ansible key (alias    │
  │     data source + ephemeral pubkey, non-secret) for cloud-init; the         │
  │     opconnect/ssh-key-loader roles read credentials.json + token + private  │
  │     key via amazon.aws.aws_secret (never tofu → never in state).            │
  │   Day-2: 1Password Connect (on-prem) serves the fleet — UNCHANGED           │
  └─────────────────────────────────────────────────────────────────────────────┘

  OFFLINE 3-2-1 copy of the bundle (encrypted, FIDO/passphrase-openable)
  → covers the "AWS unreachable" cold-start case.
```

**Trusted-orchestrator model:** whoever runs the seed playbook / `tofu apply` (Branden, via `fcx-sso` + FIDO + an unlocked 1Password desktop app) is the trust root. opconnect itself never holds an AWS credential or a standing machine identity.

---

## Components

### A. `aws-foundation/15-opconnect-credentials/` (NEW layer — applied; rename pending)
- **Backend:** estate convention — `bucket tmpx-tfstate-065094257518-use2`, `key 15-opconnect-credentials/terraform.tfstate`, `use_lockfile=true`, explicit `kms_key_id` (tfstate CMK), `assume_role` OrganizationAccountAccessRole, + the native `encryption {}` AES-GCM block (enforced).
- **`alias/tmpx/onprem-opconnect` CMK** + alias. **Key policy = ROOT-ENABLE ONLY** (identical to the tfstate CMK in `10-bootstrap`): root-enable to shared-services root; use delegated to IAM. Both human-gated identities that touch the secret hold AdministratorAccess and use the key via IAM — the IdC AdministratorAccess SSO role (human bootstrap) **and** OrganizationAccountAccessRole (assumed by onprem ansible to read at seed/restore). **No `kms:ViaService`.** No CI principal. *(Earlier drafts scoped `kms:Decrypt` to the SSO-admin role only; that was corrected because it wrongly denied the OAAR read path — scoping is via IdC MFA + IAM, not a narrow key condition.)*
- **`tmpx/onprem/opconnect-credentials` secret** (Secrets Manager, JSON), encrypted under the CMK. tofu owns the **empty container only**; value seeded out-of-band (Component E) so it never transits this layer's state.
- **outputs:** `opconnect_cmk_arn`, `opconnect_cmk_alias` (`alias/tmpx/onprem-opconnect`), `opconnect_credentials_secret_arn`, `opconnect_credentials_secret_id`.
- **Account:** **shared-services (065094257518)** (where tfstate + the `tmpx` CMKs live; already a separate failure domain from Proxmox).

### B. `onprem-infra` CONSUME (opconnect restore)
- `tofu/opconnect` reads the recovery CMK **by alias** (`data "aws_kms_alias"`, D6) and the **public** ansible key from the bundle (ephemeral read — public key is non-secret) for cloud-init `write_files`.
- The Ansible `opconnect` + `ssh-key-loader` roles read the **secret** material (`1password-credentials.json` + Connect token + the ansible private key) via `amazon.aws.aws_secret` at provision time → never via tofu → never in state. The role deploys the Connect compose stack as today.
- **Result:** opconnect bootstraps from AWS-delivered material (Connect-free bootstrap, DR-portable, no Mac dependency). Replaces the Option-D `op`-CLI write-back as the *bootstrap* path.

### C. The bundle (secret contents)
The off-site copy of opconnect's credentials — gated by AWS SSO+FIDO. JSON fields:
- `connect_credentials_json` (base64 of `1password-credentials.json`) + `connect_token` — the seed that brings Connect up.
- `ansible_public_key` + `ansible_private_key` — the bootstrap keypair (closes the SSH-key half of #8; tofu reads only the public half, Ansible reads the private).
- `token_expires` (ISO-8601, **plain** non-secret field) — written at mint time so the seed playbook's rotation conditional is a clean date-compare (no fragile in-Jinja JWT decode).
- `created` (ISO-8601) + `notes` (proxmox/gitlab **restore pointers** — references, not live creds).
- **NOT** the AWS root/account break-glass codes — those stay **offline/physical** (putting AWS-root recovery inside AWS is circular).

### D. Offline 3-2-1 copy
An encrypted export of the bundle (`age`/`gpg`), stored offline (encrypted USB / fireproof), openable with FIDO/passphrase alone — for the AWS-unreachable cold-start. Runbook item (closes #60).

### E. SEED / ROTATE — the Ansible playbook (D8)
- `ansible/playbooks/opconnect_credentials.yml` → `import_role: name=opconnect, tasks_from=seed`. **NOT** imported by `site.yml`.
- `hosts: localhost, connection: local, gather_facts: false` (biometric `op` + AWS FIDO live on the operator workstation; smaller fact-leak surface).
- **Idempotent + expiry-aware:** read the current secret (`amazon.aws.aws_secret`, `on_missing: skip`); compute `need_seed` (secret absent → first-time `op connect server create`, which is **not** idempotent → guarded) and `need_rotate` (`token_expires` within `rotate_threshold_days`, default 14, or `force`). Otherwise no-op ("valid, expires X, nothing to do").
- Rotation **re-mints only the token** (preserves the server identity + the ansible keypair → no fleet-wide bootstrap-key churn).
- `op` mint task: `command`, `no_log: true`, `environment: { OP_CONNECT_HOST: "", OP_CONNECT_TOKEN: "" }` (forces account mode — Connect env vars otherwise lock `op` into Connect API mode, which **cannot** create servers/tokens; a Service Account gets 403). Biometric approval surfaces via the unlocked desktop app.
- Write: `amazon.aws.sts_assume_role` → temp creds → `community.aws.secretsmanager_secret` (`json_secret`, `kms_key_id`, `no_log`; idempotent — unchanged value = no version churn). *(The write module is `community.aws.secretsmanager_secret`; the read is the `amazon.aws.aws_secret`/`secretsmanager_secret` lookup. No Ansible collection mints Connect tokens — `op connect ... create` is wrapped in `ansible.builtin.command`.)*
- **Never run at `-vvv`** (documented `no_log` bypass + CVE lineage) — runbook rule.

## Issue #8 handling (secrets out of state)
- The bundle is read by Ansible (`amazon.aws.aws_secret`) for all secret fields → never in either repo's tofu state. tofu reads only the public key.
- The Ansible SSH key becomes **Connect-served / bundle-served** post-bootstrap so opconnect no longer needs `tls_private_key` in state; generated DB passwords migrate to `password_wo` / Connect-served. (#8 closes as a consequence; track residual in plan.)

## Security model
- **FIDO-gating is free:** reading the secret requires the `fcx-sso` login, which Identity Center enforces with always-on MFA (YubiKey + Titan). No extra resource.
- **Separation of duties via key policy + permission boundary:** the `tmpx-TerraformExecutionRole` boundary already denies `ScheduleKeyDeletion`/`DisableKey`/`PutKeyPolicy` on CMKs (key-admin guardrail). The CMK is **root-enable-only** — use is an IAM concern; admin ≠ use, enforced by IAM + the boundary, not a repo split or a narrow key condition.
- **No reverse dependency:** the layer never depends on onprem-infra or 1Password Connect (the systems it recovers). One-way: foundation → onprem.
- **Blast radius:** the layer is its own state, separate from `10-bootstrap` (the locked, highest-blast-radius state).
- **Seed leak surface:** `no_log` on every secret task; `connection: local`, `gather_facts: false`; never `-vvv`; biometric `op` (account mode, `OP_CONNECT_*` unset). Secrets pass as module params (not `argv`), held in registered vars (no temp files).

## Out of scope — future waves (documented, deferred with triggers)
- **Wave 2a — CI machine identity:** GitHub/GitLab OIDC → AWS (the `aws-foundation/30-identity` OIDC plan, issue #27) for **day-2 deploys**. Trigger: the GitLab migration / hands-off fleet deploys. NOT for bootstrap.
- **Wave 2b — standing machine identity (IAM Roles Anywhere):** only if a fleet host ever needs to **autonomously** pull AWS secrets at runtime. Trigger: an autonomous-runtime-fetch need (may never fire under the human-injects model). Needs an X.509 CA + rotation.
- **Day-2 1Password→AWS Secrets Sync** (D7) — optional, when a cloud-native consumer would otherwise round-trip to on-prem Connect.
- **Repo rename** (onprem-infra → hybrid-infra) — ties to #67; orthogonal.
- **Doc filename polish** — spec/plan filenames keep the `bootstrap-trust-recovery-anchor` working name (architecture-level); the artifact naming is literal in-content. Iterate later if desired.

## Decisions locked (2026-06-13)
1. **Account:** ✅ **shared-services (065094257518)** — consistent with tfstate + the `tmpx` CMKs; a dedicated recovery/security account deferred as future hardening.
2. **Store:** ✅ **AWS Secrets Manager** (multi-field JSON + native rotation) under the dedicated CMK.
3. **SSH key:** ✅ **bundle/Connect-served** — closes #8 for the SSH key + retires the Option-D `op`-CLI write-back. The AWS bundle holds the Connect seed + the ansible keypair; tofu reads only the public key.
4. **onprem read placement:** ✅ tofu reads only the **public** key (folded into `tofu/opconnect`); Ansible reads all secrets (`amazon.aws.aws_secret`). No 4th state.
5. **Seed mechanism (D8):** ✅ **pure-Ansible playbook**, idempotent + expiry-aware, separate from `site.yml`; **not** a bash script.
6. **Key policy:** ✅ **root-enable-only** (estate convention), not SSO-admin-conditional.

## Acceptance criteria
- `aws-foundation/15-opconnect-credentials` exists, `tofu validate`/`plan` clean, follows the estate backend + encryption + tagging conventions; CMK + alias + (empty) secret + outputs present; key policy is root-enable-only, no CI/ViaService.
- onprem reads the key by **alias data source** (no `remote_state`) + the **public** key ephemerally; Ansible reads the secrets via `amazon.aws.aws_secret` (not in state); a from-scratch opconnect bootstrap succeeds **without** the Mac `op` CLI account-mode path.
- The seed playbook is **idempotent** (re-run with a valid, non-expiring token = no-op) and **expiry-aware** (rotates only within threshold/force); runs on `localhost`, account-mode `op`, `no_log`; **not** wired into `site.yml`.
- No private key / DB password persists in either repo's tofu state (#8).
- Offline 3-2-1 copy + DR runbook (`docs/runbooks/opconnect-credentials.md`) exist.
- The layer has **no** dependency on onprem-infra or 1Password Connect.

## Test plan
- `tofu validate` + `plan` both layers (live AWS, `fcx-sso`).
- Seed idempotency: run `opconnect_credentials.yml` twice — second run reports "valid, nothing to do" (changed=false on the write).
- Rotation: with `force=true` (or a near-expiry token), confirm a new token is minted, `token_expires` advances, the server identity + keypair are unchanged.
- DR drill: from a clean opconnect (destroy + rebuild), bootstrap **only** via the AWS bundle + SSO/FIDO (no Mac `op` account mode); confirm Connect serves day-2.
- Negative: a principal WITHOUT the SSO/OAAR path cannot `kms:Decrypt` / `get-secret-value`.
- Grep both states post-apply: zero plaintext key/password material.

## Risks
- **AWS-unreachable cold-start** → mitigated by the offline 3-2-1 copy (D/§D).
- **Ephemeral-resource maturity** (OpenTofu) for the public-key read → validate in plan; fallback is a non-secret `aws_ssm_parameter` for the public key.
- **`no_log` edge cases** (verbose runs, CVE lineage) → runbook rule: never `-vvv` the seed play.
- **Account-placement churn** if shared-services → dedicated-recovery-account later → minimize via clean module boundaries.

---

*Design approved via voice brainstorm 2026-06-13; refined same day (seed→Ansible, literal naming, root-enable-only key policy). Grounded in: the #68 candidate research, the hybrid-secrets-locality research, the hybrid-IaC + aws-foundation deep-scan, and the Ansible-vs-script + amazon.aws/onepassword.connect collection research (this session).*

---

## Revision — Phase C re-decided (2026-06-13 PM)

Phase A (CMK + secret) and Phase B (the Ansible seed) shipped + validated. Implementing the **consumer** (Phase C) surfaced two facts that revise the consume-side design below (D1–D8 stand; the bundle, the seed's existence, and the AWS-anchor model are unchanged). Plan: `docs/superpowers/plans/2026-06-13-onprem-phase-c-dedicated-key-directionB.md`.

**Empirical findings (this session, verified live):**
1. **The ephemeral pubkey read (Component B / D6) is structurally impossible — proven, not theoretical.** `tofu plan` on `tofu/opconnect` fails: *"Variable does not allow ephemeral value"* at `opconnect.tf:45` (`ansible_pubkey = local.ansible_ssh_public_key`). An OpenTofu ephemeral value cannot flow into a persisted attribute (cloud-init `user_data`), and bpg/proxmox has **no write-only twin** for it. This is the engine correctly enforcing #8. The spec's own Risk hedge ("fallback is a non-secret `aws_ssm_parameter`") is now the path.
2. **The bundle's seed-generated keypair ≠ the live fleet 1P key** (fingerprints `6dV2…` vs `VrLco8…`). Reconciled as **intentional**, not a fork bug (see D9).
3. **The estate is dev/stage of FusionCloudX business infra, not a homelab** (memory `infra-hybrid-not-just-homelab`; ClickUp roadmap has Teleport/Wazuh/CI-runners/FCX-dev collaborators). Per-host-key isolation for the secrets root is therefore the floor, not enterprise theater — the homelab "shared is fine" discount does not apply on this trajectory.

**Revised decisions:**

| # | Decision | Rationale |
|---|---|---|
| **D9** | **opconnect gets a DEDICATED bootstrap keypair**, distinct from the fleet's `Infrastructure Ansible SSH Key`. opconnect's cloud-init `authorized_keys` trusts ONLY the dedicated key; the fleet key is removed from opconnect. The 4 app VMs are **untouched**. | Blast-radius isolation of the secrets root (a fleet-key compromise — fleet pubkey sits in every VM's authorized_keys — cannot reach opconnect) + rotation decoupling (re-key the fleet without touching the `prevent_destroy` singleton). Under IaC the cost is one-time authoring, so the decision is purely on correctness. Authorities (MS PAM tier model, OWASP, NIST IR 7966, CyberArk, red-team) converge on dedicated-when-trust-differs; the venture trajectory (CI runners + collaborators) hits their "dedicated is mandatory" triggers. The seed already generates this key — D9 makes it intentional. (YubiKey/FIDO is the *human-access* plane — touch-per-use can't back an unattended automation key — so it does not flip this to shared.) |
| **D10** | **tofu reads the dedicated PUBLIC key from an SSM String param** (`/tmpx/onprem/opconnect/ansible_public_key`, published by the seed) via `data "aws_ssm_parameter"` — replacing the (impossible) ephemeral read of D6/Component B. Public key in state is fine (non-secret); the private key + creds never touch tofu. | Realizes the spec's own fallback (Risk §). Auto-synced by the seed (zero manual steps, rotation-safe), keeping a read-only `aws` provider in `tofu/opconnect`. The CMK alias data source is dropped (an SSM String needs no KMS). |
| **D11** | **Full Direction-B consume.** The seed writes the dedicated keypair + the Connect `credentials.json`/token to dedicated **1Password items** (day-2 root) **and** the AWS escrow (break-glass). opconnect's `ssh-key-loader` + deploy role read from **1P via account-mode `op`** (Connect-independent), retiring the manual local-file (`opconnect_credentials_local`) path. The AWS bundle becomes the clean-room-DR-only source. | Completes the never-built C4 (the bundle was seeded-but-unconsumed) and the #68 goal (no Mac/local dependency, AWS-anchored DR + 1P day-2). 1P-account-mode reads are non-circular (they hit 1password.com, not the local Connect). |

**Direction:** **B** — 1Password is the day-2 root; the AWS escrow is break-glass/DR only. The single forced exception (opconnect's *bootstrap pubkey* read from SSM, since `tofu/opconnect` can't use the onepassword provider — circular) is a property of the bootstrap state, not a promotion of escrow to day-2.

**Net effect on D6/Component B/C:** D6's "ephemeral pubkey" → SSM data source (D10). Component B/C's single shared keypair → a dedicated opconnect keypair (D9) homed in 1P + escrow + SSM-pubkey (D11). Everything else (CMK, secret, key policy, the seed's existence, the offline 3-2-1 copy, #8) stands.
