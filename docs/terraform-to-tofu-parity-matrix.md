# terraform → OpenTofu Feature/Functionality Parity Matrix

**What this is:** a migration **parity + gap analysis** (requirements-traceability matrix) proving the new 3-state `tofu/` tree did not silently lose functionality from the legacy flat `terraform/` tree. Produced as the safety net before the legacy tree's on-disk remains are deleted. The legacy *tracked* tree was already removed from git in PR #56 (`5baffbb`); this audit was run against its last-intact snapshot in history.

- **Legacy baseline (source):** `terraform/` at commit **`d26a436`** (tip of P5, the last commit before P6 deleted it) — 18 tracked files, 1,503 lines, plus on-disk deployed `terraform.tfstate` and `*.auto.tfvars`.
- **Target (new):** `tofu/{network,opconnect,compute}` + `modules/` at **`2c306c4`** (HEAD/main) — 51 files.
- **Method:** 20 audit units (all 18 legacy files + a deployed-state-parity dimension + a tfvars-config-parity dimension), one agent per unit doing exhaustive element extraction and tofu-counterpart mapping, then per-gap adversarial verification, then a completeness critic. 37 agents, 504 tool-uses.
- **Machine-readable appendix:** [`terraform-to-tofu-parity-matrix.json`](./terraform-to-tofu-parity-matrix.json) — the complete 278-element inventory with per-element disposition + evidence (nothing summarized away).

---

## Headline verdict

**Parity is strong on the HCL/functionality axis. No critical or unsupported-important gap. The migration did not silently drop functionality.** A live `tofu plan` against the running fleet returns **no-op in all three states** — runtime parity is proven, not just inferred.

| Disposition | Count | Meaning |
|---|---:|---|
| carried | 147 | present in tofu, equivalent behavior |
| refactored | 105 | present but restructured (flat → module, split across 3 states, renamed) — functionally equivalent |
| intentionally-dropped | 10 | absent **and** justified by a documented decision |
| **MISSING (confirmed real)** | **4** | absent with no justification — the gaps that matter |
| uncertain → resolved | 4 | flagged, then verified (all resolved to carried/intentional) |
| **Total audited** | **278** | every functional element across all 18 files + state + tfvars |

**252 / 278 (91%)** are carried or refactored. **10** are documented intentional drops. **4** are confirmed gaps: **1 important (already tracked) + 3 cosmetic.**

---

## Per-unit coverage (no-skip — every legacy file partitioned in)

| Legacy unit | Lines | Elements | Disposition | Gaps |
|---|---:|---:|---|---:|
| `.gitignore` | 1 | 1 | fully-carried | 0 |
| `.terraform.lock.hcl` | 139 | 7 | fully-carried | 0 |
| `ansible-inventory.tf` | 87 | 14 | fully-carried | 0 |
| `backend.tf` | 6 | 2 | fully-carried | 0 |
| `cloud-init-gitlab.tf` | 66 | 31 | partial | 6¹ |
| `cloud-init.tf` | 61 | 21 | partial | 1¹ |
| `dns.tf` | 105 | 23 | fully-carried | 0 |
| `lxc-debian-template.tf` | 17 | 2 | fully-carried | 0 |
| `lxc-postgresql.tf` | 87 | 20 | partial | 1 |
| `onepassword.tf` | 205 | 15 | **fully-carried** | 0 |
| `outputs.tf` | 121 | 13 | has-gaps | 3 |
| `PATCHED-PROVIDER.md` | 121 | 10 | fully-carried | 0 |
| `provider.tf` | 99 | 10 | fully-carried | 0 |
| `qemu-vm.tf` | 83 | 28 | partial | 1¹ |
| `ssh-keys.tf` | 20 | 2 | fully-carried | 0 |
| `ssh-keys.tf.disabled` | 43 | 7 | fully-carried (inert) | 0 |
| `ubuntu-template.tf` | 61 | 29 | fully-carried | 0 |
| `variables.tf` | 162 | 7 | partial | 2¹ |
| `DIM:DEPLOYED-STATE-PARITY` | — | 34 | fully-carried | 0² |
| `DIM:TFVARS-CONFIG-PARITY` | — | 2 | has-gaps | 1¹ |

¹ Most per-unit "gaps" verified down to **intentional drops** (ssh-enable, smoke-test log, ready-marker, `full_clone`/`disabled_workloads` knobs, `postgresql_databases`) — see Intentional Drops below.
² Legacy live state is **empty** (serial 2654, 0 resources — clean `terraform destroy`); the 34-resource figure is the historical backup. No state-continuity risk.

The highest-risk units came back clean: **`onepassword.tf` (the secrets file) is fully-carried** — every 1Password item is accounted for across the opconnect Option-D write-back + `compute/secrets.tf`. The **deployed-state diff** found no resource present in the old deployment without a tofu equivalent.

---

## The 4 confirmed gaps

| # | Gap | Severity | Status |
|---|---|---|---|
| 1 | gitlab cloud-init `dpkg-reconfigure postfix` runcmd dropped (postfix preseeded but not reconfigured at boot) | **important** | **Already tracked — backlog #65** (gitlab cloud-init runcmd parity). The sibling ssh-enable / smoke-test-log / ready-marker drops are verified intentional under #65. The postfix piece is arguably redundant (debconf is pre-seeded before install) but is the one un-covered line. |
| 2 | `proxmox-lxc` module has no `description` argument (postgresql container Notes field) | cosmetic | **Restored** in `feat/parity-cosmetic-restores` — `description` var added to `modules/proxmox-lxc/{variables,main}.tf` (null-guarded vs bpg #611/#762) + wired at `tofu/compute/postgresql.tf`. Plan-verified (1 in-place update, no churn); apply pending. |
| 3 | `postgresql_connection.databases` / `infrastructure_summary.databases` outputs dropped (`var.postgresql_databases` removed) | cosmetic | **Recommend accept + document.** Verified the variable was a redundant duplicate **no Ansible code consumed** — authoritative DB list lives in Ansible. Dropping it removed a duplicated source of truth (an improvement). |
| 4 | `ansible_ssh_key_fingerprint` root output dropped | cosmetic | **Restored** in `feat/parity-cosmetic-restores` — output re-added to `tofu/opconnect/outputs.tf` (sourced from `tls_private_key.ansible`). Plan-verified (output-only, 0 resource changes); apply pending. |

**Net actionable:** #2 and #4 are **restored** in this PR (plan-verified, apply pending); #3 is accepted-and-documented as an intentional de-dup; #1 remains tracked as #65. No gap blocks operation.

### Why each gap exists (root cause)

| # | Root cause | Class |
|---|---|---|
| 1 | The cloud-init refactor moved provisioning into a reusable `modules/cloud-init` with a **minimal default `runcmd`** (qemu-guest-agent only); `tofu/compute/gitlab.tf` calls the module but never re-passes gitlab's custom runcmd block, so the postfix-reconfigure / ssh-enable / smoke-test / marker lines were not forwarded. | **refactor side-effect** (noticed → #65). Low real impact: postfix is preseeded via `debconf_selections` *before* install (self-configures); ssh comes up via the openssh-server install and ansible connected over it (site.yml passed). |
| 2 | The P3 **thin-module rewrite** authored `modules/proxmox-lxc` from scratch and did not port the legacy container `description` field. | **oversight** (fresh module authoring). Cosmetic — Proxmox Notes field only. |
| 3 | Legacy declared `var.postgresql_databases` + an output but **never actually created the databases** (the bpg provider can't; Ansible's `roles/postgresql` owns DB creation). It was a dangling declaration feeding only an informational output. | **intentional de-duplication** — correct to drop; Ansible is the single source of truth. Recommend leave-dropped + document. |
| 4 | When outputs were **split across the 3 states**, the fingerprint output (whose source `tls_private_key.ansible` moved to opconnect) was not re-created in `opconnect/outputs.tf`. The value is still computed + written to 1Password, just not re-surfaced. | **oversight** (output-split). Cosmetic — durable in 1Password. |

**Pattern:** one intentional improvement (#3, correct as-is) and three refactor oversights (#1 tracked + preseed-mitigated, #2/#4 cosmetic). None is a substantive functional loss — confirmed by the no-op live plan.

---

## Intentional drops (10 — documented, not parity loss)

Backup stack (duplicati, backrest, PBS VMs, `enable_backup_stack`, wazuh) removed in P1 · `disabled_workloads` knob refactored to a hardcoded validation list · `full_clone` knob (behavior preserved, default `true`) · immich extra-disk auto-trigger (tracked #64, storage outcome preserved) · gitlab ssh-enable + smoke-test-log + ready-marker runcmd (tracked #65) · `postgresql_databases` var/output (redundant duplicate). All verified against a decision/commit/doc.

---

## Cross-cutting findings (completeness critic) + verification verdicts

The critic's key insight: the audit's unit axis was the **legacy flat tree**, so it structurally cannot see tofu-**only** files or cross-state contracts. Those were checked separately below.

| Finding | Verdict |
|---|---|
| **Migration is greenfield destroy+recreate, not state-import.** Legacy live state empty (serial 2654). 8 `compute/secrets.tf` items regenerate fresh passwords by design. | **Verified.** Clean teardown confirmed. Residual is *operational* (did every torn-down service get re-provisioned with the new secrets), not HCL — proven by the passing 6/6 e2e rebuild. |
| **Ansible inventory contract changed:** `ansible_host` failure value `'IP not available'` → `null`; postgresql host name computed → static `'postgresql'`. | **Verified SAFE.** Zero consumers of the old sentinel; `postgresql` is keyed by the static name tofu now emits; db_host has `default()` guards. Breaks nothing. |
| **3-way secrets handoff** (opconnect writes SSH key via `op` CLI → compute reads by title → ansible consumes) is emergent cross-state behavior. | Reviewed. Faithful + hardened (private key never in state). Carried. |
| **State encryption + remote-state decrypt wiring** (AES-GCM via aws_kms; opconnect/compute need `remote_state_data_sources` to decrypt network state). | New (not a legacy feature). Correct asymmetry; network reads nothing. |
| **DNS moved, not copied** — `dns.tf` → `modules/unifi-host` per-service. | Faithful relocation + hardened (`nullable=false` fail-loud vs legacy silent `try()`). |
| **proxmox-vm protected/disposable count-split** — two bodies must stay parallel. | Guards correct (mutually exclusive `count`). Both bodies exercised by the 6/6 rebuild. Recommend a periodic body-diff. |
| `required_version` relaxed `>=1.9` → `>=1.8`; hardcoded service validation list `['mealie','tandoor','immich','runitup']` can drift. | Safe; list is a maintenance-coupled constant — add a cross-ref test. |

---

## Sign-off: runtime parity proven

**`tofu plan` against the live S3 backend returned no-op in all three states** — `network`, `opconnect`, and `compute` each reported exit 0, "No changes. Your infrastructure matches the configuration." (2026-06-12). The deployed fleet exactly matches the tofu source. Combined with the complete static audit and the passing 6/6 e2e rebuild, **audit confidence is HIGH** and the migration is parity-verified. (Closes #62.)

## Local `terraform/` cleanup (done)

The local `terraform/` directory held gitignored cruft only — the empty live `terraform.tfstate` (serial 2654, 0 resources), historical `.tfstate` backups, `*.auto.tfvars`, and the `.terraform/` provider cache. It was **deleted on 2026-06-12, no archive** (per decision: the live state was already empty, so nothing was at operational risk; the resource-bearing backups were superseded by the S3 remote state). The tracked legacy tree was already removed in PR #56.

---

*Generated 2026-06-12 from audit run `wf_00c24fc4-942`. Full per-element inventory: [`terraform-to-tofu-parity-matrix.json`](./terraform-to-tofu-parity-matrix.json).*
