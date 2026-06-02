# UniFi Terraform Provider — Maintained-Fork Formalization Design Spec

**Date:** 2026-06-02
**Status:** Final (design approved; pending spec review → implementation plan)
**Repos:** `FusionCloudX Infrastructure` (consumer) + a new fork `thisisbramiller/terraform-provider-unifi` (producer)
**Related:** memory `project_unifi_138_patched_provider`, `docs/superpowers/specs/2026-06-02-nfs-mountd-reconciler-design.md` (the logger patch came from there).

---

## Goal

Replace the ad-hoc patched UniFi provider (untracked local clone + a dangerous build script + `dev_overrides`) with a **reproducible, version-pinned, checksum-locked maintained fork**: a clean rebase-able patch series on a pinned upstream base, distributed via a Terraform **filesystem mirror with a real lockfile**, supply-chain gated, with a documented upstream off-ramp.

## Background — why this is needed

We must run a *source-built* `ubiquiti-community/terraform-provider-unifi` because the framework rewrite we depend on (the `unifi_dns_record` resource) is **unreleased** (latest release `v0.41.25`, Mar 13 2026, is the old SDK line; the framework code lives only on `main`). On top of that we carry local fixes that are unmerged upstream. So "use a release" is impossible.

Today's setup has three real problems:
1. **`dev_overrides` is the wrong distribution for real `plan/apply`.** HashiCorp documents it as a *provider-development* tool: it disables version + checksum verification, bypasses `.terraform.lock.hcl`, and warns on every command. For a tool that changes real infrastructure, the two safety properties that make a `plan` trustworthy (pinning + checksums) are off.
2. **The build script is wrong and dangerous.** `scripts/build-unifi-provider.sh` `rm -rf`s the repo and clones the `v0.41.25` *tag* (old SDK line) + applies only PRs #139/#174 — which does **not** match the running `main`-based framework provider, and would destroy the working provider.
3. **The fork isn't version-controlled or tracked.** The patch set lives only on a local `patched` branch, never pushed; there's no ledger of what we carry, why, or when to drop it.

## Architecture (one paragraph)

A fork `thisisbramiller/terraform-provider-unifi` holds a long-lived **`patches`** branch = a pinned upstream-`main` commit (the base) + our patches as a clean linear commit series, ordered most-likely-to-merge-first, each commit carrying Debian **DEP-3** trailers, with a top-level **`PATCHES.md`** ledger. A rewritten build script clones the fork at a pinned SHA, runs a supply-chain gate, `go build`s, and installs into a Terraform **filesystem mirror** under a synthetic source host; `terraform providers lock -fs-mirror` writes `h1:` checksums into `.terraform.lock.hcl`. `dev_overrides` is removed; `provider.tf` points the `unifi` provider at the synthetic host + a pinned synthetic version, so `plan/apply` consume the patched provider as a fully version-pinned, checksum-verified dependency.

---

## Components & files

### Producer — fork `thisisbramiller/terraform-provider-unifi`
- Branch **`patches`** = pinned upstream `main` SHA (base) + the patch commit series (ordered most-likely-merge-first so they fall out as empty on rebase when upstream lands them).
- Each patch commit carries **DEP-3 trailers**:
  - `Forwarded: <upstream-PR-url> | no | not-needed`
  - `Origin: backport, <url>` for the patch ported from an open PR
  - `Applied-Upstream: <version>` set when it lands
- **`PATCHES.md`** ledger at repo root — one row per patch: subject · upstream PR · status (`local-only` / `open-PR` / `ported-from-PR` / `merged-pending-release`) · retires-at-upstream-version.
- `go.sum` committed (reproducible builds).

### Patch set to carry (exact commits enumerated in the plan)
| Patch | Source | DEP-3 `Forwarded`/`Origin` |
|---|---|---|
| `unifi_client` reconcile `fixed_ip` after create/adopt | upstream PR #139 | `Forwarded: .../pull/139` |
| `blocked`/`groups`/`qos_rate` zero-diff | upstream PR #174 | `Forwarded: .../pull/174` |
| traffic-route schema/refactor fixes | check: PR or local | `Forwarded: <url or no>` |
| controller-connection error message (`9bbbe6cb`) | local | `Forwarded: no` (or submit) |
| logger concurrency (subsystem masking) (`ffc6b206`) | port of open PR #168 | `Origin: backport, .../pull/168` |

### Consumer — `FusionCloudX Infrastructure`
- `scripts/build-unifi-provider.sh` — **rewritten**: clone the fork @ pinned SHA into a clean build dir → supply-chain gate → `go build` → install to the filesystem-mirror path → `terraform providers lock`. Never `rm -rf` the user's working clone; never clone the wrong tag.
- `terraform/provider.tf` — `required_providers.unifi.source` → synthetic host (e.g. `tf.fusioncloudx.home/ubiquiti-community/unifi`) + a pinned synthetic `version`.
- `terraform/.terraform.lock.hcl` — gains the `unifi` provider entry with `h1:` checksums (multi-platform: `darwin_arm64` + `linux_amd64`).
- `terraform/PATCHED-PROVIDER.md` — rewritten to describe the fork, the mirror, the lockfile, and the off-ramp (supersedes the v0.41.25 narrative).
- `~/.terraformrc` — **remove** the `dev_overrides` block; add an explicit `provider_installation { filesystem_mirror { path, include=[<host>/ubiquiti-community/unifi] }, direct { exclude=[same] } }` so the synthetic-host provider always loads from the mirror and everything else from the registry.

### Distribution layout
```
~/.terraform.d/plugins/<host>/ubiquiti-community/unifi/<version>/<os_arch>/terraform-provider-unifi_v<version>
```
- `<host>` = synthetic source host (never resolved over the network for a filesystem mirror).
- `<version>` = a sortable synthetic version derived from the upstream base + `-patch.N` (so a future real release sorts higher and `terraform init -upgrade` retires the fork cleanly).

## Data flow

**Build:** `build-unifi-provider.sh` → clone fork @ pinned SHA → assert `git diff base..HEAD -- go.mod go.sum` empty + `go mod verify` → `go build` → install to mirror path → `terraform providers lock -fs-mirror=… -platform=darwin_arm64 -platform=linux_amd64`.

**Consume:** `terraform init` (no `dev_overrides`) resolves `unifi` from the filesystem mirror, verifies the `h1:` checksum in `.terraform.lock.hcl`; `plan/apply` run pinned + verified, no warning, no concurrent-map crash (logger fix in the binary).

## Supply-chain (minimal sane bar — explicitly NOT more)

- Pin the upstream **base SHA** (not a moving branch); record it in the build script + `PATCHED-PROVIDER.md`.
- Assert `git diff <base>..HEAD -- go.mod go.sum` is **empty** (patches don't silently move dependencies); fail the build if not.
- `go mod verify`; commit `go.sum` on the fork.
- The lockfile `h1:` is the artifact pin at the consumption layer.
- **Out of scope (over-engineering for a solo operator who builds + runs the artifact himself):** SLSA provenance, cosign/Sigstore signing, reproducible-toolchain attestation, a private Terraform registry.

## Off-ramp

- One focused upstream PR per carried patch (the ported-from-#168 one: contribute to / co-author the existing PR rather than compete).
- `PATCHES.md` drives retirement: when a patch's PR **merges and releases**, drop the commit on the next rebase (it falls out as empty) and `terraform init -upgrade`.
- Fork shrinks toward zero (or to only `Forwarded: not-needed` patches).
- **filipowm/unifi migration** is the eventual exit (actively maintained, registry-published, doing the framework rewrite). Trigger: `PATCHES.md` near-empty **and** budget for a v1.0.0 **state migration** (it is *not* a drop-in — schema changes). Out of scope here; documented as the future exit.

## Verification (evidence before completion)

1. Fork pushed; `patches` branch = base SHA + the series; every commit has DEP-3 trailers; `PATCHES.md` matches.
2. Build script: clean clone @ pinned SHA → gate passes (empty go.mod/go.sum diff, `go mod verify` ok) → builds → lands in the mirror path at `<version>`.
3. `.terraform.lock.hcl` contains the `unifi` provider at the synthetic version with `h1:` checksums for both platforms.
4. `dev_overrides` removed; `terraform init` succeeds from the mirror; `terraform plan` runs **with no `dev_overrides` warning**, **no concurrent-map crash**, and `No changes` / expected diff (= the logger fix + the consumption change both hold).
5. Reproducibility: re-running the build at the pinned SHA yields a binary that satisfies the committed lockfile `h1:`.

## Scope / sequencing

- **In scope:** the fork repo + `patches` branch + DEP-3 + `PATCHES.md`; the rewritten build script; the `provider.tf` source/version change; the filesystem mirror + lockfile; removing `dev_overrides`; the supply-chain gate; `PATCHED-PROVIDER.md` rewrite.
- **Sequencing (decided):** formalize the fork **first** (fleet may stay down during IaC dev), **then** recover the fleet (`terraform apply` → `site.yml`) **through the new mirror+lockfile path** — the recovery is the immediate follow-on, not part of this spec.
- **Out of scope:** the LXC `vzshutdown` timeout (separate `bpg/proxmox` issue); the filipowm migration (future); the fleet recovery itself (next action after this).
