# UniFi Provider Maintained-Fork Formalization — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Turn the ad-hoc local patched UniFi provider into a reproducible, version-pinned, checksum-locked maintained fork consumed via a Terraform filesystem mirror (no `dev_overrides`).

**Architecture:** A pushed fork `thisisbramiller/terraform-provider-unifi` carries a clean `patches` branch (base SHA `f5d6a42f` + 4 logical patches as a linear series with DEP-3 trailers + `PATCHES.md`). A rewritten build script clones the fork at a pinned SHA, gate-checks, `go build`s into a filesystem mirror, and locks `h1:` checksums into `.terraform.lock.hcl`. `provider.tf` points `unifi` at a synthetic host + pinned version.

**Tech Stack:** Go, Terraform (filesystem mirror, `providers lock`), git (cherry-pick/trailers — **no `-i`, this env blocks interactive rebase**), `gh` CLI.

**Spec:** `docs/superpowers/specs/2026-06-02-unifi-provider-fork-design.md`.

**Locked values (use verbatim):**
- Local provider repo: `/Users/fcx/Developer/Personal/repos/terraform-provider-unifi`
- Pinned upstream base SHA: **`f5d6a42f`** (`chore: Refactor traffic route`, 2026-03-13)
- Synthetic source host: **`tf.fusioncloudx.home`** → full source `tf.fusioncloudx.home/ubiquiti-community/unifi`
- Synthetic version: **`0.42.0-fcx1`** (sorts above `0.41.25`, below a future real `0.42.0`; bump suffix `fcx2`… per rebuild)
- Mirror root: `~/.terraform.d/plugins` → binary at `~/.terraform.d/plugins/tf.fusioncloudx.home/ubiquiti-community/unifi/0.42.0-fcx1/<os_arch>/terraform-provider-unifi_v0.42.0-fcx1`
- Infra repo: `/Users/fcx/Developer/Personal/repos/FusionCloudX-Infrastructure`

---

## Execution gating

- **[OPERATOR]** = touches GitHub (fork/push), `~/.terraformrc`, or runs `terraform init/plan` against live — pause and run with Branden. **[BUILD]** = local file authoring + offline checks (subagent-safe).
- No unit tests (git/shell/terraform glue). "TDD-where-applies" = offline checks (`go build`, `go vet`, `git diff` assertions) + real-system verification (lockfile has `h1:`, `terraform plan` clean).

---

## Task 1: Build the clean `patches` series [BUILD, local git]

**Repo:** `/Users/fcx/Developer/Personal/repos/terraform-provider-unifi`

Current `base..patched`: `5cae7576`(#139) → `51ef91f0`(review fixup) → `94b7d602`(#174) → `9bbbe6cb`(local) → `ffc6b206`(logger). Target `patches` = base + 4 logical patches, ordered most-likely-merge-first: **#139, #174, logger(#168 port), local-controller-error**, each with DEP-3 trailers, fixup squashed.

- [ ] **Step 1: Confirm arch + classify the fixup**

```bash
cd /Users/fcx/Developer/Personal/repos/terraform-provider-unifi
go env GOOS GOARCH                       # expect darwin arm64 (record for the mirror path)
git show --stat 51ef91f0                 # which patch does the review fixup belong to?
```
Expected: `darwin arm64`. The `51ef91f0` diff should touch the same file(s) as `5cae7576` (the `unifi_client` reconcile / `client_resource*.go`) → it folds into #139. If instead it touches the #174 files, fold it there in Step 2.

- [ ] **Step 2: Rebuild the series non-interactively (cherry-pick + squash fixup + DEP-3 trailers)**

```bash
cd /Users/fcx/Developer/Personal/repos/terraform-provider-unifi
git branch -f patches-backup patched          # safety net
git checkout -B patches f5d6a42f
U=https://github.com/ubiquiti-community/terraform-provider-unifi/pull
# #139 (+ squash the review fixup 51ef91f0 into it)
git cherry-pick 5cae7576
git cherry-pick --no-commit 51ef91f0 && git commit --amend --no-edit
git commit --amend --trailer "Forwarded: ${U}/139"
# #174
git cherry-pick 94b7d602
git commit --amend --trailer "Forwarded: ${U}/174"
# logger race (ported from OPEN PR #168)
git cherry-pick ffc6b206
git commit --amend --trailer "Origin: backport, ${U}/168" --trailer "Forwarded: ${U}/168"
# local-only controller-connection error (carry indefinitely unless submitted)
git cherry-pick 9bbbe6cb
git commit --amend --trailer "Forwarded: no"
```
If any cherry-pick conflicts (shouldn't — patches touch disjoint files), STOP and report. If `--trailer` is unsupported (git < 2.32), append the trailer manually via `git commit --amend` with the trailer line in the message body.

- [ ] **Step 3: Verify the series is clean + the deps gate holds**

```bash
git log --reverse --format='%h %s%n    %(trailers:only,unfold)' f5d6a42f..patches
echo "=== go.mod/go.sum unchanged vs base? (must be empty) ==="
git diff f5d6a42f..patches -- go.mod go.sum && echo "DEPS_CLEAN"
go mod verify
go build ./... 2>&1 | tail -5 && echo "BUILD_OK"
```
Expected: 4 commits, each showing its `Forwarded:`/`Origin:` trailer; empty `go.mod`/`go.sum` diff (`DEPS_CLEAN`); `go mod verify` → "all modules verified"; `BUILD_OK`. If `go.mod`/`go.sum` changed, a patch moved a dependency — STOP and report (supply-chain gate).

- [ ] **Step 4: (no commit — branch is the artifact; pushed in Task 3)**

---

## Task 2: Write `PATCHES.md` ledger [BUILD, local]

**Files:** Create `/Users/fcx/Developer/Personal/repos/terraform-provider-unifi/PATCHES.md` (on the `patches` branch)

- [ ] **Step 1: Write the ledger**

```markdown
# Carried Patches — thisisbramiller/terraform-provider-unifi `patches` branch

Base: upstream `ubiquiti-community/terraform-provider-unifi` @ `f5d6a42f` (2026-03-13).
Patches are a linear series on top, ordered most-likely-to-merge-first so they
fall out as empty on rebase when upstream lands them. Each commit carries DEP-3
trailers (`Forwarded:`/`Origin:`/`Applied-Upstream:`). Off-ramp: when a patch's PR
merges AND releases upstream, drop it on the next rebase + `terraform init -upgrade`.

| # | Patch (commit subject) | Upstream PR | Status | Retires when |
|---|---|---|---|---|
| 1 | fix: reconcile unifi_client state after create (incl. review fixup) | [#139](https://github.com/ubiquiti-community/terraform-provider-unifi/pull/139) | open-PR | #139 merges + releases |
| 2 | fix(client): zero-diff for blocked/groups/qos_rate | [#174](https://github.com/ubiquiti-community/terraform-provider-unifi/pull/174) | open-PR | #174 merges + releases |
| 3 | fix(logging): per-subsystem masking (concurrent-map race) | [#168](https://github.com/ubiquiti-community/terraform-provider-unifi/pull/168) | ported-from-PR | #168 merges + releases |
| 4 | feat(provider): clarify controller-connection error | — | local-only (`Forwarded: no`) | submit upstream or carry indefinitely |

## Rebuild / rebase
- Build + install + lock: `FusionCloudX Infrastructure/scripts/build-unifi-provider.sh`.
- Bump upstream base: `git rebase --onto <new-upstream-sha> f5d6a42f patches`, re-run the deps gate, bump the synthetic version (`fcx2`…), rebuild, re-lock.

## Exit
Migrate to `filipowm/terraform-provider-unifi` (registry-published, framework rewrite) when this ledger is near-empty AND a v1.0.0 state migration is budgeted (NOT a drop-in).
```

- [ ] **Step 2: Commit on the `patches` branch**

```bash
cd /Users/fcx/Developer/Personal/repos/terraform-provider-unifi
git add PATCHES.md
git commit -m "docs: add PATCHES.md ledger (carried patches + off-ramp)"
```
(This is the only added commit beyond the cherry-picked series; it sits at the tip.)

---

## Task 3: Create the fork + push `patches` [OPERATOR]

- [ ] **Step 1: Create the fork repo + add remote (Branden runs / approves `gh`)**

```bash
cd /Users/fcx/Developer/Personal/repos/terraform-provider-unifi
export GH_TOKEN="${GH_TOKEN:-$GITHUB_PERSONAL_ACCESS_TOKEN}"
gh repo fork ubiquiti-community/terraform-provider-unifi --org "" --remote=false --clone=false 2>&1 || \
  gh repo create thisisbramiller/terraform-provider-unifi --public --source=. --remote=fork --push=false 2>&1
git remote add fork https://github.com/thisisbramiller/terraform-provider-unifi.git 2>/dev/null || git remote set-url fork https://github.com/thisisbramiller/terraform-provider-unifi.git
git remote -v | grep fork
```
Expected: a `fork` remote pointing at `thisisbramiller/terraform-provider-unifi`. (`gh repo fork` is preferred — it preserves the upstream link; fall back to `gh repo create` if forking the org repo isn't permitted.)

- [ ] **Step 2: Push the branch + record the tip SHA**

```bash
git push -u fork patches
git rev-parse patches    # RECORD this SHA — it's the pinned fork commit the build clones
```
Expected: branch pushed; copy the SHA into the build script (Task 4) + `PATCHED-PROVIDER.md` (Task 5).

---

## Task 4: Rewrite `build-unifi-provider.sh` [BUILD]

**Files:** Modify `/Users/fcx/Developer/Personal/repos/FusionCloudX-Infrastructure/scripts/build-unifi-provider.sh` (full rewrite)

- [ ] **Step 1: Replace the script**

```bash
#!/usr/bin/env bash
# =============================================================================
# build-unifi-provider.sh — build the patched UniFi provider from our FORK and
# install it into a Terraform FILESYSTEM MIRROR (no dev_overrides).
#
# Source of truth: thisisbramiller/terraform-provider-unifi @ branch `patches`
# (clean rebase-able series on upstream base f5d6a42f; see its PATCHES.md).
# Consumed by terraform/provider.tf as tf.fusioncloudx.home/ubiquiti-community/unifi.
# Full rationale: terraform/PATCHED-PROVIDER.md
# =============================================================================
set -euo pipefail

FORK="https://github.com/thisisbramiller/terraform-provider-unifi.git"
PIN_SHA="${UNIFI_FORK_SHA:?set UNIFI_FORK_SHA to the pinned patches-branch commit (Task 3 Step 2)}"
BASE_SHA="f5d6a42f"
HOST="tf.fusioncloudx.home"
VERSION="${UNIFI_PROVIDER_VERSION:-0.42.0-fcx1}"
MIRROR="${HOME}/.terraform.d/plugins"
BUILD_DIR="$(mktemp -d /tmp/unifi-fork-build.XXXXXX)"   # clean dir — never touch the user's working clone
OSARCH="$(go env GOOS)_$(go env GOARCH)"
DEST="${MIRROR}/${HOST}/ubiquiti-community/unifi/${VERSION}/${OSARCH}"

command -v go >/dev/null || { echo "FATAL: Go not found"; exit 1; }
trap 'rm -rf "$BUILD_DIR"' EXIT

echo ">> clone fork @ ${PIN_SHA}"
git clone --quiet "$FORK" "$BUILD_DIR"
cd "$BUILD_DIR"
git checkout --quiet "$PIN_SHA"

echo ">> supply-chain gate: go.mod/go.sum unchanged vs base ${BASE_SHA}"
git diff --exit-code "${BASE_SHA}..${PIN_SHA}" -- go.mod go.sum >/dev/null \
  || { echo "FATAL: patches changed go.mod/go.sum — review before trusting"; exit 1; }
go mod verify

echo ">> build -> ${DEST}/terraform-provider-unifi_v${VERSION}"
mkdir -p "$DEST"
go build -o "${DEST}/terraform-provider-unifi_v${VERSION}" .

cat <<EOF

>> DONE. Installed: ${DEST}/terraform-provider-unifi_v${VERSION}
   Next (once, or after a version bump), from the terraform/ dir:
     terraform providers lock \\
       -fs-mirror="${MIRROR}" \\
       -platform=darwin_arm64 [-platform=linux_amd64]
   That writes h1: checksums for tf.fusioncloudx.home/ubiquiti-community/unifi into .terraform.lock.hcl.
   ~/.terraformrc must use filesystem_mirror (NOT dev_overrides) — see PATCHED-PROVIDER.md.
EOF
```

- [ ] **Step 2: Offline-validate**

```bash
cd "/Users/fcx/Developer/Personal/repos/FusionCloudX-Infrastructure"
bash -n scripts/build-unifi-provider.sh && echo SYNTAX_OK
command -v shellcheck >/dev/null && shellcheck scripts/build-unifi-provider.sh || echo "shellcheck skipped"
```
Expected: `SYNTAX_OK`.

- [ ] **Step 3: Commit**

```bash
git add scripts/build-unifi-provider.sh
git commit -m "build(unifi): build from fork @ pinned SHA into filesystem mirror (drop v0.41.25 clone)"
```

---

## Task 5: `provider.tf` source/version + rewrite `PATCHED-PROVIDER.md` [BUILD]

**Files:** Modify `terraform/provider.tf` (lines 21-24); rewrite `terraform/PATCHED-PROVIDER.md`

- [ ] **Step 1: Repoint the `unifi` provider**

Replace:
```hcl
    unifi = {
      source  = "ubiquiti-community/unifi"
      version = "0.41.25"
    }
```
with:
```hcl
    unifi = {
      # Patched fork via filesystem mirror — see terraform/PATCHED-PROVIDER.md.
      # Synthetic host/version; binary installed by scripts/build-unifi-provider.sh.
      source  = "tf.fusioncloudx.home/ubiquiti-community/unifi"
      version = "0.42.0-fcx1"
    }
```

- [ ] **Step 2: Rewrite `terraform/PATCHED-PROVIDER.md`** to document: the fork (`thisisbramiller/terraform-provider-unifi` `patches` @ pinned SHA, base `f5d6a42f`), the patch set (point to the fork's `PATCHES.md`), the filesystem-mirror + synthetic host/version, the `~/.terraformrc` `filesystem_mirror` block, the `terraform providers lock` step, the supply-chain gate, and the off-ramp (per-patch PR → drop on release → filipowm). Explicitly state **`dev_overrides` is no longer used**.

- [ ] **Step 3: Syntax-check + commit**

```bash
cd "/Users/fcx/Developer/Personal/repos/FusionCloudX-Infrastructure"
terraform -chdir=terraform fmt -check provider.tf || terraform -chdir=terraform fmt provider.tf
git add terraform/provider.tf terraform/PATCHED-PROVIDER.md
git commit -m "refactor(unifi): consume patched provider via filesystem mirror (synthetic host/version)"
```

---

## Task 6: Switch consumption to the mirror + lock [OPERATOR]

- [ ] **Step 1: Edit `~/.terraformrc` — remove `dev_overrides`, add `filesystem_mirror`**

New `~/.terraformrc`:
```hcl
provider_installation {
  filesystem_mirror {
    path    = "/Users/fcx/.terraform.d/plugins"
    include = ["tf.fusioncloudx.home/ubiquiti-community/unifi"]
  }
  direct {
    exclude = ["tf.fusioncloudx.home/ubiquiti-community/unifi"]
  }
}
```
(Back up first: `cp ~/.terraformrc ~/.terraformrc.bak`.)

- [ ] **Step 2: Build the provider into the mirror**

```bash
export GH_TOKEN="${GH_TOKEN:-$GITHUB_PERSONAL_ACCESS_TOKEN}"
export UNIFI_FORK_SHA="<patches tip SHA from Task 3 Step 2>"
"/Users/fcx/Developer/Personal/repos/FusionCloudX-Infrastructure/scripts/build-unifi-provider.sh"
ls -la ~/.terraform.d/plugins/tf.fusioncloudx.home/ubiquiti-community/unifi/0.42.0-fcx1/*/
```
Expected: `terraform-provider-unifi_v0.42.0-fcx1` present under the `darwin_arm64` dir.

- [ ] **Step 3: Lock checksums (run via login shell for UNIFI_API_KEY etc.)**

```bash
cd "/Users/fcx/Developer/Personal/repos/FusionCloudX-Infrastructure/terraform"
zsh -ilc 'terraform providers lock -fs-mirror="$HOME/.terraform.d/plugins" -platform=darwin_arm64'
grep -A4 'tf.fusioncloudx.home/ubiquiti-community/unifi' .terraform.lock.hcl
```
Expected: a lock block for `tf.fusioncloudx.home/ubiquiti-community/unifi` with `version = "0.42.0-fcx1"` and `hashes = ["h1:..."]`.

---

## Task 7: Verify the new consumption path [OPERATOR]

- [ ] **Step 1: init + plan with no dev_overrides**

```bash
cd "/Users/fcx/Developer/Personal/repos/FusionCloudX-Infrastructure/terraform"
zsh -ilc 'terraform init -input=false 2>&1 | tail -15'
zsh -ilc 'terraform plan -input=false -no-color > /tmp/fork_verify.out 2>&1; echo "PLAN_EXIT=$?"'
echo "--- dev_overrides warning gone? (want 0) ---"; grep -c 'dev_overrides\|development overrides' /tmp/fork_verify.out
echo "--- crash markers? (want 0) ---"; grep -c 'concurrent map\|plugin crashed' /tmp/fork_verify.out
echo "--- plan summary ---"; grep -E '^Plan:|No changes|^Error' /tmp/fork_verify.out | tail -3
```
Expected: `init` succeeds installing `unifi` from the mirror with the locked checksum; `PLAN_EXIT=0`; **0** dev_overrides warnings; **0** crash markers; `No changes` (or expected diff). This is the green evidence.

- [ ] **Step 2: Reproducibility — rebuild satisfies the lock**

```bash
export UNIFI_FORK_SHA="<same SHA>"
"/Users/fcx/Developer/Personal/repos/FusionCloudX-Infrastructure/scripts/build-unifi-provider.sh"
cd "/Users/fcx/Developer/Personal/repos/FusionCloudX-Infrastructure/terraform"
zsh -ilc 'terraform init -input=false 2>&1 | grep -iE "unifi|lock|checksum|error" | tail -5'
```
Expected: re-init succeeds against the unchanged lockfile (the rebuilt binary matches the `h1:`), no checksum mismatch.

---

## Task 8: Commit infra changes + PR + final review [BUILD/OPERATOR]

- [ ] **Step 1: Commit the lockfile change**

```bash
cd "/Users/fcx/Developer/Personal/repos/FusionCloudX-Infrastructure"
git add terraform/.terraform.lock.hcl
git commit -m "chore(unifi): lock patched provider (h1:) from filesystem mirror"
```

- [ ] **Step 2: requesting-code-review** on the infra diff (build script + provider.tf + PATCHED-PROVIDER.md + lockfile) and the fork's `patches` branch.

- [ ] **Step 3: [OPERATOR] PR** the infra branch (build-script + provider.tf + lockfile + PATCHED-PROVIDER.md). The fork's `patches` branch is its own pushed artifact (Task 3); optionally open the per-patch upstream PRs per `PATCHES.md` off-ramp (separate, later).

---

## Self-Review

**Spec coverage:** fork branch + DEP-3 + ordering → Task 1; PATCHES.md → Task 2; fork push/pin → Task 3; build-script rewrite (clone fork, gate, mirror) → Task 4; provider.tf source/version + PATCHED-PROVIDER.md → Task 5; drop dev_overrides + filesystem_mirror + lock → Task 6; verify (no warning/no crash) + reproducibility → Task 7; supply-chain gate → Task 1 Step 3 + Task 4 (go.mod/go.sum + `go mod verify`); off-ramp → PATCHES.md + Task 8 Step 3. ✓ All spec sections covered.

**Placeholder scan:** the only intentional fill-ins are runtime values — the `patches` tip SHA (produced in Task 3, consumed in Tasks 4/6/7 via `UNIFI_FORK_SHA`) and the `51ef91f0` squash target (classified by inspection in Task 1 Step 1). No vague "handle errors"/"TBD". ✓

**Consistency:** host `tf.fusioncloudx.home`, version `0.42.0-fcx1`, base `f5d6a42f`, mirror `~/.terraform.d/plugins`, source `tf.fusioncloudx.home/ubiquiti-community/unifi` — identical across the build script, provider.tf, ~/.terraformrc, the lock command, and verification. ✓
