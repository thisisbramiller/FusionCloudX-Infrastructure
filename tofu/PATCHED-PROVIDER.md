# Patched UniFi Provider (maintained fork + filesystem mirror)

**TL;DR** — Stock `ubiquiti-community/unifi` v0.41.25 cannot create `unifi_client`
DHCP reservations on this controller (UDM-Pro, UniFi OS 5.x / Network App 10.x), and
its logger races under parallel reads. We carry a small patch series on a **maintained
fork** (`thisisbramiller/terraform-provider-unifi`, branch `patches`), build it into a
OpenTofu **filesystem mirror**, and pin it with `h1:` checksums in
`.terraform.lock.hcl`. This **replaces `dev_overrides`** — `plan`/`apply` now consume
the provider as a fully version-pinned, checksum-verified dependency.

Build it: `scripts/build-unifi-provider.sh` (requires Go: `brew install go`).

## Why a fork (not a release, not `main`, not `dev_overrides`)

- `v0.41.25` is the **latest release** and is itself broken on 10.x; the framework
  resource we depend on (`unifi_dns_record`) lives only on `main` and is **unreleased**.
  So "use a release" is impossible.
- We also carry fixes that are **unmerged upstream** (open PRs + one local-only patch).
- `dev_overrides` is a *provider-development* tool: it disables version + checksum
  verification, bypasses `.terraform.lock.hcl`, and warns on every command. For a tool
  that changes real infrastructure, that throws away the two properties that make a
  `plan` trustworthy (pinning + checksums). The fork + filesystem mirror restores both.

## The fork

- Repo: `github.com/thisisbramiller/terraform-provider-unifi` (fork of
  `ubiquiti-community/terraform-provider-unifi`).
- Branch **`patches`** = pinned upstream base **`f5d6a42f`** (2026-03-13) + a clean
  linear patch series, ordered most-likely-to-merge-first so patches fall out as empty
  on rebase when upstream lands them. Each commit carries Debian **DEP-3** trailers
  (`Forwarded:`/`Origin:`/`Applied-Upstream:`). The ledger lives at the fork's
  **`PATCHES.md`**.

| # | Patch | Upstream PR | Status |
|---|-------|-------------|--------|
| 1 | `unifi_client` reconcile state after create/adopt (`.fixed_ip` null, issue #138) | [#139](https://github.com/ubiquiti-community/terraform-provider-unifi/pull/139) | open-PR |
| 2 | `blocked`/`groups`/`qos_rate` zero-diff on 10.x | [#174](https://github.com/ubiquiti-community/terraform-provider-unifi/pull/174) | open-PR |
| 3 | per-subsystem log masking (fixes concurrent-map crash on parallel reads) | [#168](https://github.com/ubiquiti-community/terraform-provider-unifi/pull/168) | ported-from-PR |
| 4 | clarify controller-connection error, point to API-key auth | — | local-only (`Forwarded: no`) |

## Distribution: filesystem mirror + lockfile

The provider is installed under a **synthetic source host** so a filesystem mirror can
serve it without ever touching the network:

```
~/.terraform.d/plugins/tf.fusioncloudx.home/ubiquiti-community/unifi/0.42.0-fcx1/<os_arch>/terraform-provider-unifi_v0.42.0-fcx1
```

`provider.tf` points the provider at that host + pinned version:

```hcl
unifi = {
  source  = "tf.fusioncloudx.home/ubiquiti-community/unifi"
  version = "0.42.0-fcx1"
}
```

The synthetic version `0.42.0-fcx1` sorts above the real `0.41.25` and below a future
real `0.42.0`, so when upstream catches up, `tofu init -upgrade` retires the fork
cleanly. Bump the suffix (`fcx2`, `fcx3`, …) on each rebuild.

This `provider_installation` block routes only this provider to the mirror (everything
else to the registry). OpenTofu auto-discovers `~/.terraformrc`, and the repo also
commits a `.tofurc` carrying the same block — point CI at it with
`TF_CLI_CONFIG_FILE=$PWD/.tofurc`:

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

> No `dev_overrides`. If a `dev_overrides` block is present it silently wins and
> disables checksums — remove it.

## Build + install + lock

```bash
brew install go                                   # one-time prereq
export UNIFI_FORK_SHA=<patches-branch tip SHA>    # the pinned fork commit
scripts/build-unifi-provider.sh                   # clone fork @ SHA -> gate -> go build -> mirror
cd tofu/network   # any state dir; repeat for compute
tofu providers lock \
  -fs-mirror="$HOME/.terraform.d/plugins" \
  -platform=darwin_arm64                          # add -platform=linux_amd64 if a linux runner consumes it
```

`tofu providers lock` writes the `h1:` checksums for
`tf.fusioncloudx.home/ubiquiti-community/unifi` into `.terraform.lock.hcl`. After that,
`tofu init` installs the provider from the mirror and **verifies it against the
lockfile** — no override warning, no network fetch for `unifi`.

## Supply-chain gate

`build-unifi-provider.sh` enforces (and these were confirmed building the series):

- Clones the fork into a fresh temp dir and checks out the **pinned SHA** (never a
  moving branch, never the user's working clone).
- Asserts `git diff <base>..<pin> -- go.mod go.sum` is **empty** — the patches do not
  silently move a dependency. Build fails otherwise.
- `go mod verify` → all modules verified.
- The lockfile `h1:` is the artifact pin at the consumption layer; a re-build at the
  same SHA must satisfy the committed checksum.

Out of scope by design (over-engineering for a solo operator who builds + runs the
artifact himself): SLSA provenance, cosign/Sigstore signing, a private registry.

## Off-ramp

- One focused upstream PR per carried patch; for the ported #168 patch, contribute to
  the existing PR rather than compete.
- `PATCHES.md` drives retirement: when a patch's PR **merges and releases**, drop the
  commit on the next rebase (it falls out empty) and `tofu init -upgrade`.
- Eventual exit: migrate to `filipowm/terraform-provider-unifi` (actively maintained,
  registry-published, framework rewrite) once `PATCHES.md` is near-empty **and** a
  v1.0.0 **state migration** is budgeted — it is *not* a drop-in.
