# UNAS NFS-mountd Reconciler — Design Spec

**Date:** 2026-06-02
**Status:** Final (design approved; pending spec review → implementation plan)
**Repo:** FusionCloudX Infrastructure
**Branch:** `feat/dns-automation`
**Related:** `docs/superpowers/specs/2026-05-31-network-layer-greenfield-design.md` (the static-IP track that will eventually retire this reconciler), memory `project_unas_nfs_mountd_resolver_fix`.

---

## Goal

When a Proxmox VM is rebuilt clean-room (`terraform -replace`), it gets a new MAC → new DHCP IP. The UNAS Pro's `rpc.mountd` caches a stale resolver **negative** for the new IP and refuses the NFS mount (`mount.nfs: access denied by server`) even though DNS already resolves correctly. This reconciler makes the Ansible NFS mount **self-recover** by bouncing `nfs-mountd` over a **blast-radius-scoped, forced-command SSH key** — not the root password, not a new user.

## Architecture (one paragraph)

A shared Ansible role wraps every UNAS NFS mount in a `block`/`rescue`: attempt the mount; on denial, SSH to the UNAS with a dedicated key whose `authorized_keys` entry is locked to exactly `systemctl restart nfs-mountd.service` (OpenSSH `restrict` + forced `command=`), wait for the resolver to settle, and retry the mount. The scoped private key is the **only** UNAS credential the unattended runner holds — it can do nothing but bounce mountd. The root password is used **once**, by a separate operator-run bootstrap script, to install that `authorized_keys` line; it is re-run only after a UniFi OS firmware update (which wipes the overlay).

---

## Root cause (proven 2026-06-01)

- VM rebuild → new IP. The VM connects to the UNAS **before its reverse-DNS/PTR has propagated**. `rpc.mountd` can't map the IP → domain and caches `<newIP> → -no-domain-` in `/proc/net/rpc/auth.unix.ip/content` ("unmatched host"). mountd uses its **own internal resolver cache**, separate from the kernel and systemd-resolved.
- Forward **and** reverse DNS both resolving correctly (`getent` both ways) is **NOT sufficient** — mountd ignores live DNS while its cache is stale (TTL = hours).
- `exportfs -f` does **not** fix it (flushes only the kernel export table). `udc nfs exports regen` does **not** fix it (`/etc/exports.d/*.exports` byte-identical; never touches mountd resolution).
- `systemctl restart nfs-mountd.service` **does** fix it — drops the stale resolver, re-resolves every export hostname fresh, new IP matches, mount allowed. Low risk: existing mounts run through `nfsd` (kernel) and keep working; only a *new* mount during the ~1s bounce blips.
- **Timing rule (load-bearing):** the bounce must fire *after* the new IP's PTR has settled, else mountd re-caches the negative. This is why placement is **reactive** (at mount-failure time, when the VM has been up and DNS has propagated), not proactive (at `terraform apply`, when the record was just written).

## Decision record (why A+, and why not the alternatives)

Ground truth from read-only SSH recon of the UNAS (2026-06-02):

- **New SSH user (rejected — infeasible).** `sshd` is group-locked: `/etc/ssh/sshd_config.d/10-allow-group.conf` → `AllowGroups root unifi-drive-ssh`. A new user can only log in if it's in group `root` (= full root, defeats the purpose) or `unifi-drive-ssh` — and that group is hardwired to `ForceCommand /usr/local/bin/rsync-shell` (rsync only; can't run `systemctl`). The whole account/sshd/sudoers layer lives on the overlay (`overlayfs-root`, `upperdir=/mnt/.rwfs/data`); `/etc/passwd` mtime equals the last firmware-update date → the files are **regenerated on update**. There is **no** `on_boot.d`/`udm-boot` hook installed, and that community persistence pattern is UDM-centric, unofficial, documented to break across firmware bumps, and **not validated on UNAS Pro**. So a new user is the *most* fragile option, not the safest.
- **IP-based ACL via the Drive API (rejected — over-investment + own fragility).** Would eliminate the resolver race (literal IPs, mountd never resolves), but the Drive API is **undocumented and SPA-hidden**, so UniFi can break it silently on any update. Bigger build (session auth + rotating CSRF + reverse-engineered PUT body + full `connections` list). The reconciler is an **interim bridge** (see below), so this is over-built.
- **Subnet/CIDR ACL (rejected).** The UNAS UI validator rejects CIDR as invalid input, and opening the export to a whole subnet was explicitly declined.
- **Static cloud-init IP (out of scope — separate track).** The network-layer greenfield design is **locked** on static cloud-init IP + one canonical map. Once that lands, IPs/PTRs are stable → mountd's cache never goes stale → **this reconciler is no longer needed**. This reconciler is therefore the *interim bridge* for the current DHCP-based fleet, which is the reason to keep it minimal. Do **not** fold static-IP into this spec.

**Chosen — A+ (scoped forced-command root key, reactive in Ansible, no password in the runner).** It delivers the blast-radius isolation of "not root," uses Ubiquiti's own native SSH-scoping mechanism (ForceCommand), leans on the one credential the platform persists and manages (root), and is a minimal build. `systemctl restart` over the supported root login is a far more stable primitive than a reverse-engineered SPA API.

## UNAS facts the design depends on (recon 2026-06-02)

- OpenSSH on Debian 11 (bullseye) userland, kernel `5.10.216-alpine-unas` aarch64. `PubkeyAuthentication yes`, `PasswordAuthentication no` (our interactive auth is keyboard-interactive/PAM), `kbdinteractiveauthentication yes`. `restrict` option supported (OpenSSH 8.4).
- `AllowGroups root unifi-drive-ssh` — root is allowed; the scoped key goes in **root's** `authorized_keys`.
- `/root/.ssh` exists and is **empty** (no `authorized_keys` today) — bootstrap installs it.
- Restart target confirmed: `nfs-mountd.service`, `FragmentPath=/lib/systemd/system/nfs-mountd.service`, `ExecStart=/usr/sbin/rpc.mountd`, **no ExecReload** (must restart, not reload).
- Overlay root FS → `authorized_keys` survives **reboot** (rw layer persists) but is expected to be **wiped on firmware update** (overlay regeneration). The design is robust to this: a wiped key fails loudly with a "run the bootstrap script" message; no silent root fallback.

---

## Components & files

All paths relative to repo root.

### New: `ansible/roles/nfs_mount/`
Shared role that wraps a single UNAS NFS mount with reconcile-on-failure. Invoked via `include_role` with per-call vars.

- `defaults/main.yml`
  - `nfs_mount_unas_host: "192.168.40.137"`
  - `nfs_mount_reconcile_key_op_item`, `_field`, `_section` — 1Password Connect coordinates for the **scoped private key** (mirrors `ssh-key-loader` vars).
  - `nfs_mount_reconcile_key_temp_path: "/tmp/unas-nfs-reconcile-key"` (controller-side, 0600).
  - `nfs_mount_retries: 3`, `nfs_mount_settle_delay: 8` (seconds to wait after bounce before retry).
  - `nfs_mount_known_hosts` handling (StrictHostKeyChecking policy for the UNAS).
- `tasks/main.yml`
  - Load the scoped key from 1Password Connect to the temp file **once** (`run_once`, `delegate_to: localhost`, `no_log`), reusing the `onepassword.connect.field_info` pattern from `ssh-key-loader`.
  - `block:` attempt `ansible.posix.mount` with the caller's `src`/`path`/`opts`, `state: mounted`.
  - `rescue:` (a) `delegate_to: localhost` run `ssh -i {{ key }} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new root@{{ unas_host }} true` → forced command bounces mountd; (b) `wait_for`/`pause` `settle_delay`; (c) retry the mount with `retries`/`until`. On final failure, fail with the original mount error **plus** a hint to check DNS/PTR.
  - Distinguish **key-auth failure** (key wiped post-firmware-update) → fail with: *"UNAS reconcile key rejected — run `scripts/bootstrap-unas-reconcile-key.sh` (firmware update wipes it)."*
- `tasks/cleanup.yml` — remove the temp key file (called at playbook end, like `ssh-key-loader` cleanup).

### New: `scripts/bootstrap-unas-reconcile-key.sh`
Operator-run shell script (`expect` + keyboard-interactive SSH + 1Password desktop/Touch-ID), **not** part of `site.yml`. Installs/refreshes the forced-command `authorized_keys` line on the UNAS using the **root password** (1Password item "Claude UNAS Pro SSH"). Idempotent + clean rotation: no-op if the exact line is present, else strip any prior `nfs-mountd` reconcile line and write the current one (other root keys untouched). Run once initially, and after every UniFi OS firmware update. Documents the dependency in its header.

**Tooling decision — shell script, not Ansible (researched 2026-06-02):** a native Ansible playbook is *feasible* (the `paramiko` connection does keyboard-interactive auth without `sshpass`) but buys nothing here. The UNAS is an out-of-band locked appliance (not in inventory; the default `ssh` plugin hard-refuses keyboard-interactive), there is no fleet/convergence to gain, `authorized_keys` is *designed to be wiped* on firmware upgrade, and the bootstrap runs precisely when pubkey is unavailable (a procedural password repair — `expect`'s native idiom). `ansible.posix.authorized_key`'s one real edge (clean key rotation) is captured by the script's strip-then-write; secrets stay simpler (`op read` → `expect`, no Vault wiring). Operator-gated regardless — the root password never enters the unattended pipeline (the A+ isolation).

The `authorized_keys` entry installed:
```
restrict,command="systemctl restart nfs-mountd.service" ssh-ed25519 AAAA...<reconciler pubkey>... nfs-reconciler@fusioncloudx
```

### Modified: NFS-mounting roles (replace inline mount with the shared role)
- `ansible/roles/immich/tasks/main.yml` — the single mount at line ~80.
- `ansible/roles/duplicati/tasks/main.yml` — the single mount at line ~81.
- `ansible/roles/backrest/tasks/main.yml` — the destination mount (~71) and the **looped** source mounts (~120). The looped case calls the shared role per item (or the role accepts a list); plan to keep it DRY.

### 1Password
- New item **"UNAS NFS Reconciler Key"** — the ed25519 **private** key (Connect-readable by the controller). Public key is pasted into the bootstrap script / a vars file.
- Existing **"Claude UNAS Pro SSH"** (root password) — used **only** by the bootstrap script, never by `site.yml`.

### Docs / runbook
- A short runbook note (and a one-line update to the memory file `project_unas_nfs_mountd_resolver_fix`): *after a UniFi OS firmware update, run the bootstrap script to reinstall the reconcile key.*

---

## Data flow

1. **(one-time / post-firmware-update)** Operator runs `bootstrap-unas-reconcile-key.sh` → root password → installs the forced-command `authorized_keys` on the UNAS.
2. `terraform apply` rebuilds a VM → new IP; `dns.tf` updates the A record + reservation.
3. `ansible-playbook site.yml` runs the VM's role → `include_role: nfs_mount`.
4. Mount attempt:
   - **succeeds first try** (no stale negative) → done, no bounce (idempotent).
   - **denied** (stale mountd negative) → rescue: SSH with scoped key → forced `systemctl restart nfs-mountd.service` → wait `settle_delay` → retry mount → success.
5. Steady-state re-runs of `site.yml` → mount already mounted → `changed: false`, rescue never fires.

## Error handling

| Condition | Behavior |
|---|---|
| Mount succeeds | No bounce. Idempotent. |
| Mount denied, bounce fixes it | Recover silently within retries; report `changed`. |
| Mount denied, bounce succeeds, still denied after N retries | Fail loudly — PTR genuinely unresolved (DNS problem, not mountd). Surface the mount error + a DNS hint. |
| Scoped key rejected (wiped by firmware update) | Fail loudly with the explicit "run the bootstrap script" message. **No silent password fallback** (preserves isolation). |
| UNAS unreachable | Fail loudly with the SSH error. |

## Security

- **Forced command + `restrict`** → the unattended runner's key can do *nothing* but restart mountd. Leaked key = at-worst a ~1s mountd blip, never data access.
- **No root password in the unattended path.** It is reachable only by the operator-run bootstrap script. A compromised `site.yml` runner cannot escalate to root on the UNAS.
- Private key loaded from **1Password Connect** to a `0600` temp file, `no_log`, removed by cleanup — consistent with the fleet secret pattern. Never plaintext in config.
- Host-key verification for the UNAS (`accept-new` on first contact, pinned thereafter).

## Testing / verification (evidence before completion)

Real-system verification (this is infra glue, not unit-testable logic — the "tests" are reproduction + evidence):

1. **Red → green (the proven reproduction, now hands-off):** `terraform -replace` duplicati VM (+ its DNS) → `terraform apply` → `ansible-playbook site.yml --limit duplicati,localhost`. Expect: mount initially **denied** → rescue bounces mountd → retry **mounts** → play exits **0**. Capture the task output showing the rescue path fired and the mount recovered.
2. **Idempotency:** re-run `site.yml --limit duplicati,localhost` → mount already mounted → `changed: false` on the mount, rescue **not** triggered.
3. **Forced-command scoping (security proof):** `ssh -i <scoped_key> root@unas "cat /etc/shadow"` → the requested command is **ignored**; only the mountd restart runs (exit reflects the restart). Proves the key cannot run arbitrary commands.
4. **No-fallback proof:** temporarily point the role at a bad/absent key → run must **fail** with the "run the bootstrap script" message (proves no silent root fallback).
5. **Bootstrap idempotency:** run `bootstrap-unas-reconcile-key.sh` twice → second run `changed: false`.

## Scope

Single subsystem (Ansible NFS-mount reconcile + operator bootstrap). One implementation plan. No coupling to the static-IP network-layer track beyond the note that it will eventually retire this.

## Out of scope / explicitly not doing

- No `on_boot.d`/`udm-boot` persistence hook (fragile, UNAS-unvalidated).
- No Drive-API IP-ACL push (the B path).
- No static-IP / cloud-init-IP changes (separate locked track).
- No proactive Terraform bounce (timing flaw).
- No new UNAS OS user (infeasible per recon).
