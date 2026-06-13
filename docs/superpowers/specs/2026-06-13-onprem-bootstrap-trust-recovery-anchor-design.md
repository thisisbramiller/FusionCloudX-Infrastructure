# onprem Bootstrap-Trust + Recovery-Anchor — Design Spec (Wave 1)

**Status:** APPROVED (brainstorm 2026-06-13) — pending written review before writing-plans
**Task:** #68 (FusionCloudX hybrid machine-identity + secrets + bootstrap-trust)
**Repos touched:** `aws-foundation` (new layer) + `onprem-infra` / FusionCloudX Infrastructure (consumer)
**Supersedes:** the "Option D" stopgap (desktop `op` CLI account-mode write-back) as the bootstrap mechanism.

---

## Goal

Give the on-prem secrets root (opconnect / 1Password Connect) a **disaster-recoverable, FIDO-gated bootstrap** by relocating the bootstrap secret-zero into AWS — the trust anchor that already holds the OpenTofu state — **without** giving opconnect a standing machine identity and **without** moving day-2 operational secrets off-prem.

---

## Problem

- **Secret-zero / circular dependency:** opconnect runs 1Password Connect, which serves secrets to compute + Ansible (day-2). So opconnect's *bootstrap* cannot depend on Connect, and no `OP_SERVICE_ACCOUNT_TOKEN` exists. Today's "Option D" works but is **Mac-bound + manual** (desktop `op` CLI account-mode) — not DR-portable.
- **Issue #8:** the Ansible SSH private key + generated DB passwords currently persist in encrypted OpenTofu state.
- **Hybrid estate:** on-prem Proxmox fleet (onprem-infra: OpenTofu 3-state + Ansible) + AWS prod org (aws-foundation: LZA-style layers; Identity Center SSO; `tmpx` CMKs; `tmpx-TerraformExecutionRole`; tfstate in S3+SSE-KMS). onprem-infra already consumes aws-foundation's backend (same bucket + tfstate CMK + assume-role).

## Locked decisions (from the brainstorm)

| # | Decision | Rationale |
|---|---|---|
| D1 | **Two tiers.** Operational/day-2 secrets stay **local** (1Password Connect on-prem, unchanged). The **recovery root-of-trust** goes **off-site** (AWS). | Locality is a runtime-availability rule (a remote vault is a total-blast-radius SPOF); the recovery anchor is governed by a different rule — survive the destruction of everything it recovers. Consensus + AWS guidance. |
| D2 | **Human-orchestrated bootstrap.** The trusted orchestrator is Branden via AWS SSO (`fcx-sso`) + FIDO (YubiKey + Titan). **No CI delegation, no Roles Anywhere, no new always-on service.** | Bootstrap = disaster-recovery / new-hardware: the operator is present, nothing else exists yet, and self-hosted GitLab is built *after* opconnect so it can't bootstrap it. Human + hardware key in the loop is a feature for the root of trust. |
| D3 | **AWS is the recovery anchor.** Secret-zero collapses up to the AWS root/org account, break-glass, behind FIDO. | AWS is already the tfstate anchor — on-prem already can't cold-start without AWS, so this names a dependency already accepted, not a new one. |
| D4 | **Option 1 — break-glass bundle whole in aws-foundation** (key + data colocated), separation enforced by the **key policy** (IAM), not by splitting repos. | AWS never separates a key from the data it wraps; recovery-of-the-estate is a foundation concern, not a workload; a recovery anchor must not depend "down" on the estate it recovers; one-place DR for a solo op. Separation-of-duties is an IAM concern, satisfied by the key policy. |
| D5 | **CMK + IAM trust + bundle live in a NEW aws-foundation numbered layer** (`15-recovery-anchor`), not bolted onto `10-bootstrap`. **No new repo.** | aws-foundation convention: each CMK lives in the layer owning its consumer; decade-gaps exist for insertion; `10-bootstrap` is the highest-blast-radius prevent_destroy state — don't overload it. A new repo has no independent owner/cadence (pure overhead for a solo op). |
| D6 | **Wire by KMS alias, NOT `terraform_remote_state`.** onprem-infra references `alias/tmpx/onprem-bootstrap` via a `data "aws_kms_alias"` data source. | HashiCorp explicitly discourages cross-state `remote_state` reads (consumer gets the producer's entire state snapshot + tight coupling). The alias is a stable string contract with zero coupling. |
| D7 | **1Password stays the day-2 secrets plane** (on-prem Connect, unchanged). The 1Password→AWS Secrets Sync (beta) is an **optional future day-2 nicety** (humans edit in 1Password, fan-out to AWS Secrets Manager for AWS-native consumers; least-privilege on AWS access) — **not** part of Wave 1, and structurally cannot bootstrap (one-way, presupposes 1P is up). | Keeps the single human-facing pane; the sync is orthogonal to bootstrap. |

---

## Architecture

```
                AWS  (off-site recovery domain, already the tfstate anchor)
  ┌─────────────────────────────────────────────────────────────────────┐
  │ aws-foundation / 15-recovery-anchor   (NEW layer, own tofu state)     │
  │   • CMK  alias/tmpx/onprem-bootstrap   (dedicated; NOT the tfstate CMK)│
  │   • key policy: kms:Decrypt → IdC AdministratorAccess SSO role only    │
  │       (FIDO-gated by Identity Center MFA; no kms:ViaService; no CI)    │
  │   • break-glass bundle SECRET (Secrets Manager, whole)                 │
  │   • outputs: bootstrap_cmk_arn, bootstrap_cmk_alias, breakglass_secret │
  └─────────────────────────────────────────────────────────────────────┘
        ▲ alias string contract (no remote_state)        │ human reads via
        │                                                 │ SSO+FIDO at bootstrap/DR
  ┌─────┴───────────────────────────────────────────────▼─────────────────┐
  │ onprem-infra  (consumer)                                                │
  │   tofu/opconnect (+ a tiny bootstrap read step):                        │
  │     data "aws_kms_alias" "bootstrap" { name = "alias/tmpx/onprem-..." } │
  │     ephemeral read of the bundle → inject 1P Connect creds into         │
  │     opconnect at build time (cloud-init / ansible) → Connect comes up   │
  │   Day-2: 1Password Connect (on-prem) serves the fleet — UNCHANGED       │
  └────────────────────────────────────────────────────────────────────────┘

  OFFLINE 3-2-1 copy of the bundle (encrypted, FIDO/passphrase-openable)
  → covers the "AWS unreachable" cold-start case.
```

**Trusted-orchestrator model:** whoever runs `tofu apply` (Branden, authenticated via `fcx-sso` + FIDO) is the trust root. They read the bundle from AWS, inject it into opconnect at build time. opconnect itself never holds an AWS credential or a standing machine identity.

---

## Components

### A. `aws-foundation/15-recovery-anchor/` (NEW layer)
- **Backend block:** byte-for-byte the estate convention — `bucket tmpx-tfstate-065094257518-use2`, `key 15-recovery-anchor/terraform.tfstate`, `use_lockfile=true`, explicit `kms_key_id` (tfstate CMK), `assume_role` OrganizationAccountAccessRole, plus the `terraform { encryption {} }` native AES-GCM block (enforced).
- **`alias/tmpx/onprem-bootstrap` CMK** + alias. Key policy: root-enable to shared-services root (estate convention) + `kms:Decrypt`/`kms:DescribeKey` to the **IdC AdministratorAccess permission set** (`ArnLike AWSReservedSSO_AdministratorAccess_*`), **no `kms:ViaService`** (the documented cross-account-grant hook). No CI principal.
- **break-glass bundle secret** (AWS Secrets Manager, JSON), encrypted under the CMK. Written **write-only** (`secret_string_wo` / managed out-of-state) so the plaintext never lands in this layer's state either.
- **outputs:** `bootstrap_cmk_arn`, `bootstrap_cmk_alias` (`alias/tmpx/onprem-bootstrap`), `breakglass_secret_arn`.
- **Account placement (default):** **shared-services** (where tfstate + the `tmpx` CMKs live; already a separate failure domain from Proxmox). *Decision to confirm:* SRA-purest is a dedicated **security/recovery account** (keep mgmt near-empty) — deferred as a future hardening unless chosen now.

### B. `onprem-infra` consumer (opconnect bootstrap)
- A small bootstrap read in `tofu/opconnect` (or a tiny `tofu/00-recovery-read` step): `data "aws_kms_alias" "bootstrap"` + an **`ephemeral`** read of the Secrets Manager bundle (OpenTofu 1.12 ephemeral resources) → inject the 1Password Connect `1password-credentials.json` + Connect token into opconnect via cloud-init `write_files` / the `opconnect` Ansible role. Nothing persists in onprem state.
- **Result:** opconnect's Connect comes up from AWS-delivered material (Connect-free bootstrap, DR-portable, no Mac dependency). Replaces the Option-D `op`-CLI write-back as the *bootstrap* path.

### C. The break-glass bundle (contents)
The **on-prem recovery seed** — gated by AWS SSO+FIDO. Candidate contents (pin in plan):
- 1Password Connect `1password-credentials.json` + a Connect/SA token (the seed that brings Connect up).
- The Ansible SSH keypair seed (or: generated once + stored as a 1P item served by Connect post-boot — preferred, also closes #8 for the SSH key).
- Proxmox root + GitLab root **restore pointers** (not the live creds — references / recovery procedure).
- **NOT** the AWS root/account break-glass codes — those stay **offline/physical** (putting AWS-root recovery inside AWS is circular).

### D. Offline 3-2-1 copy
An encrypted export of the bundle (e.g. `age`/`gpg` or a 1Password export), stored offline (encrypted USB / fireproof), openable with FIDO/passphrase alone — for the AWS-unreachable cold-start. Runbook item.

---

## Issue #8 handling (secrets out of state)
- Bundle written/read with **write-only / ephemeral** (`secret_string_wo` on write; `ephemeral` on read) → never in either repo's tofu state.
- Move the Ansible SSH key to **Connect-served** (a 1P item) post-bootstrap so opconnect no longer needs `tls_private_key` in state; generated DB passwords migrate to `password_wo` / Connect-served. (#8 closes as a consequence; track residual in plan.)

---

## Security model
- **FIDO-gating is free:** reading the bundle requires the `fcx-sso` login, which Identity Center enforces with always-on MFA (YubiKey + Titan). No extra resource.
- **Separation of duties via key policy:** the `tmpx-TerraformExecutionRole` boundary already denies `ScheduleKeyDeletion`/`DisableKey`/`PutKeyPolicy` on CMKs (key-admin guardrail); the SSO Admin role gets `kms:Decrypt` only (key-user). Admin ≠ use, enforced by IAM, not repo split.
- **No reverse dependency:** the anchor never depends on onprem-infra or 1Password Connect (the systems it recovers). One-way: foundation → onprem.
- **Blast radius:** the recovery layer is its own state, separate from `10-bootstrap` (the locked, highest-blast-radius state).

---

## Out of scope — future waves (documented, deferred with triggers)
- **Wave 2a — CI machine identity:** GitHub/GitLab OIDC → AWS (the `aws-foundation/30-identity` OIDC plan, issue #27) for **day-2 deploys**. Trigger: the GitLab migration / wanting hands-off fleet deploys. NOT for bootstrap.
- **Wave 2b — standing machine identity (IAM Roles Anywhere):** only if a fleet host ever needs to **autonomously** pull AWS secrets at runtime. Trigger: an autonomous-runtime-fetch need (may never fire under the human-injects model). Needs an X.509 CA + rotation.
- **Day-2 1Password→AWS Secrets Sync** (D7) — optional, when a cloud-native consumer would otherwise round-trip to on-prem Connect.
- **Repo rename** (onprem-infra → hybrid-infra) — ties to #67; orthogonal, doesn't change this placement.

## Open decisions to confirm in review / plan
1. **Account:** shared-services (default, simplest) vs a dedicated security/recovery account (SRA-purest).
2. **Bundle store:** AWS Secrets Manager (default — multi-field JSON + rotation) vs SSM SecureString (cheaper, simpler).
3. **Exact bundle contents** (section C) + whether the Ansible SSH key becomes Connect-served (recommended) vs stays in the bundle.
4. **onprem read placement:** fold into `tofu/opconnect` vs a dedicated tiny `00-recovery-read` step.

## Acceptance criteria
- `aws-foundation/15-recovery-anchor` exists, `tofu validate`/`plan` clean, follows the estate backend + encryption + tagging conventions; CMK + alias + bundle + outputs present; key policy grants the SSO Admin role `kms:Decrypt` only, no CI/ViaService.
- onprem-infra reads the key by **alias data source** (no `remote_state`), reads the bundle **ephemerally** (not in state), injects into opconnect at build; a from-scratch opconnect bootstrap succeeds **without** the Mac `op` CLI account-mode path.
- No private key / DB password persists in either repo's tofu state (#8).
- Offline 3-2-1 copy + DR runbook exist.
- Anchor has **no** dependency on onprem-infra or 1Password Connect.

## Test plan
- `tofu validate` + `plan` both layers (live AWS, `fcx-sso`).
- DR drill: from a clean opconnect (destroy + rebuild), bootstrap **only** via the AWS bundle + SSO/FIDO (no Mac `op` account mode); confirm Connect serves day-2.
- Negative: confirm a principal WITHOUT the SSO Admin role / FIDO cannot `kms:Decrypt` the bundle.
- Grep both states post-apply: zero plaintext key/password material.

## Risks
- **AWS-unreachable cold-start** → mitigated by the offline 3-2-1 copy (D4/section D).
- **Ephemeral-resource maturity** (OpenTofu 1.12) → validate in plan; fallback is a scripted SDK read that never writes state.
- **Account-placement churn** if shared-services → dedicated-recovery-account later → minimize by clean module boundaries.

---

*Design approved via voice brainstorm 2026-06-13. Grounded in: the #68 candidate research, the hybrid-secrets-locality research, and the hybrid-IaC best-practice + aws-foundation deep-scan research (this session). Next: writing-plans for Wave 1.*
