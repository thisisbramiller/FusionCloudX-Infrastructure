#!/usr/bin/env bash
# =============================================================================
# build-unifi-provider.sh — build the patched UniFi provider from our FORK and
# install it into a Terraform FILESYSTEM MIRROR (no dev_overrides).
#
# Source of truth: thisisbramiller/terraform-provider-unifi @ branch `patches`
# (clean rebase-able series on upstream base f5d6a42f; see its PATCHES.md).
# Consumed by tofu/{network,compute}/providers.tf as tf.fusioncloudx.home/ubiquiti-community/unifi.
# Full rationale: tofu/PATCHED-PROVIDER.md
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
# -trimpath + -buildid= make the binary REPRODUCIBLE (same source + toolchain ->
# identical bytes), so a rebuild at the pinned SHA satisfies the committed h1:
# lockfile checksum. Without these, the embedded mktemp build path + build-id
# differ every run and break the lock.
go build -trimpath -ldflags=-buildid= -o "${DEST}/terraform-provider-unifi_v${VERSION}" .

cat <<EOF

>> DONE. Installed: ${DEST}/terraform-provider-unifi_v${VERSION}
   Next (once, or after a version bump), from each tofu state dir:
     tofu providers lock \\
       -fs-mirror="${MIRROR}" \\
       -platform=darwin_arm64 -platform=linux_amd64
   That writes h1: checksums for tf.fusioncloudx.home/ubiquiti-community/unifi into .terraform.lock.hcl.
   The repo-root .tofurc (or ~/.terraformrc) must use filesystem_mirror (NOT dev_overrides) — see PATCHED-PROVIDER.md.
EOF
