#!/usr/bin/env bash
# ==============================================================================
# build-runitup-image.sh — build the Run It Up app image ON THIS WORKSTATION
# (the controller / Mac) and stage it as a tarball for the Ansible runitup role
# to ship to the VM (docker save -> copy -> docker load).
#
# WHY: runitup is the only first-party (private-source) app in the estate. The
# decided end-state is "VM pulls a pre-built pinned image from the GitLab
# container registry" — but GitLab/CI/registry isn't ready yet. This is the
# INTERIM: build off-VM here (where the operator's GitHub SSH key already
# works), ship the image. No source clone, no build, and NO GitHub credential
# ever land on the VM.
#
# UPGRADE PATH (when the GitLab container registry is live): replace the
# `docker save` below with `docker push <registry>/fusioncloudx/runitup:<tag>`,
# and the role's `docker load` with a registry pull + a read_registry deploy
# token. The build-off-VM model here does not change.
#
# Prereqs (controller): Docker w/ buildx, and an SSH key authorized for the
# private GitHub repo loaded in the agent (already true on Branden's Mac).
# Arch note: this host is arm64; the VM target is linux/amd64, so this is a
# single-platform cross-build (buildx emulates the amd64 layer — fine for a
# Node/Vite app; the build moves to a native amd64 GitLab CI runner at Phase 2).
# ==============================================================================
set -euo pipefail

REPO="${RUNITUP_REPO:-git@github.com:thisisbramiller/run-it-up-tracker.git}"
REF="${RUNITUP_REF:-main}"
ROLE_FILES="$(cd "$(dirname "$0")/.." && pwd)/ansible/roles/runitup/files"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Cloning $REPO ($REF)"
git clone --depth 1 --branch "$REF" "$REPO" "$WORK/app"
SHA="$(git -C "$WORK/app" rev-parse --short HEAD)"
TAG_SHA="runitup:${SHA}"
TAG_LOCAL="runitup:local"

echo "==> Building $TAG_SHA (+ $TAG_LOCAL) for linux/amd64"
# --provenance=false --sbom=false: emit a PLAIN single-arch image, not a
# manifest list with attestations. A manifest list doesn't `docker load` cleanly
# on a standard docker-ce host (it's a push-only artifact); a plain image
# save/loads everywhere. Also matches the decision to skip provenance/SLSA for
# this private, single-producer/consumer image.
docker buildx build --platform linux/amd64 --provenance=false --sbom=false \
  -t "$TAG_SHA" -t "$TAG_LOCAL" --load "$WORK/app"

mkdir -p "$ROLE_FILES"
TARBALL="$ROLE_FILES/runitup-image.tar"
echo "==> Saving image -> $TARBALL"
docker save "$TAG_LOCAL" "$TAG_SHA" -o "$TARBALL"

echo
echo "==> Done. Built commit $SHA -> $TAG_SHA (role deploys $TAG_LOCAL)."
echo "    Tarball: $TARBALL ($(du -h "$TARBALL" | cut -f1))"
echo "    Deploy:  cd ansible && ansible-playbook playbooks/site.yml --limit runitup,localhost"
