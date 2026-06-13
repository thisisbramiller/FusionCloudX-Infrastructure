# UNAS nfs-mountd Reconciler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make UNAS NFS mounts self-heal the `rpc.mountd` stale-resolver denial that follows a Proxmox VM clean-room rebuild, using a blast-radius-scoped forced-command SSH key — never the root password, never a new OS user.

**Architecture:** A new shared Ansible role `nfs_mount` wraps each NFS mount in `block`/`rescue`. On a mount denial it bounces the serving host's `nfs-mountd` (UNAS → via a `restrict,command="…"` scoped key loaded from 1Password Connect; managed VM → via a direct `delegate_to` `systemctl restart`, since we already hold root there), waits, and retries. A separate operator-run shell script installs the scoped key on the UNAS using the root password over keyboard-interactive SSH (expect), re-run after firmware updates. The unattended path holds only the scoped key.

**Tech Stack:** Ansible (`ansible.posix.mount`, `onepassword.connect.field_info`), OpenSSH forced-command keys, 1Password (Connect for the controller, desktop/Touch-ID for the operator bootstrap), `expect`, Terraform (for the integration reproduction).

**Spec:** `docs/superpowers/specs/2026-06-02-nfs-mountd-reconciler-design.md` (approved, committed `c19fb32`).

**Working directory for all commands:** `/Users/fcx/Developer/Personal/repos/FusionCloudX-Infrastructure` (the repo). Branch: `feat/dns-automation`.

---

## Execution gating (read first)

Tasks are tagged **[BUILD]** (safe file authoring + offline checks — fine for a subagent) or **[OPERATOR]** (touches live infra/secrets or is destructive — the controller must pause and get Branden's explicit confirmation; do NOT auto-run).

- **[OPERATOR]** Task 1 (keygen + 1Password item), Task 7 (install key on the UNAS + scoping proof), Task 8 (destroy→apply→site.yml reproduction).
- **[BUILD]** Tasks 2–6 (scripts, role, call-site refactors) and Task 9 (PR).

There is no unit-test harness in this repo (Ansible/Terraform glue). "TDD-where-applies" therefore means: offline structural checks (`bash -n`, `yamllint`/`python -c yaml.safe_load`, `ansible-playbook --syntax-check`) as the fast gate, and a **real-system reproduction** (Task 8) as the green evidence.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `ansible/roles/nfs_mount/defaults/main.yml` | Role defaults: UNAS host, 1Password coords for the scoped key, retry/settle tuning | Create |
| `ansible/roles/nfs_mount/tasks/main.yml` | block(mount) → rescue(bounce serving host's mountd → retry); UNAS vs managed-VM branch; fail-loud on wiped key | Create |
| `scripts/bootstrap-unas-reconcile-key.sh` | Operator-run: install/refresh the `restrict,command=` authorized_keys line on the UNAS via root password (expect). Idempotent. Re-run after firmware updates. | Create |
| `ansible/roles/immich/tasks/main.yml` | Replace the inline mount (~line 80) with `include_role: nfs_mount` | Modify |
| `ansible/roles/duplicati/tasks/main.yml` | Replace the inline mount (~line 81) with `include_role: nfs_mount` | Modify |
| `ansible/roles/backrest/tasks/main.yml` | Replace the dest mount (~line 71) and the looped source mounts (~line 120) with `include_role: nfs_mount` | Modify |

Role interface (caller passes via `include_role` `vars:`): `nfs_mount_label`, `nfs_mount_src` (`host:export`), `nfs_mount_path`, `nfs_mount_opts`.

---

## Task 1: Generate the reconcile keypair and store it in 1Password [OPERATOR]

**Files:** none in-repo (the public key lands in 1Password, read at bootstrap time).

This creates the dedicated ed25519 keypair. The **private** key is read by the controller (1Password Connect) during a reconcile; the **public** key is read by the bootstrap script and installed on the UNAS with a forced command.

- [ ] **Step 1: Generate the keypair to a temp location**

```bash
ssh-keygen -t ed25519 -f /tmp/nfs-reconciler-key -N "" -C "nfs-reconciler@fusioncloudx"
```
Expected: creates `/tmp/nfs-reconciler-key` (private) and `/tmp/nfs-reconciler-key.pub` (public).

- [ ] **Step 2: Create the 1Password item with both fields**

Mirror the layout of the existing "Infrastructure Ansible SSH Key" (a `Private Key` section with a `private_key` field). Add a `public_key` field too. Use the vault that `TF_VAR_onepassword_vault_id` points at (same vault as the other infra items).

```bash
op item create --category "SSH Key" --title "UNAS NFS Reconciler Key" \
  --vault "$(op item get 'Infrastructure Ansible SSH Key' --format json | python3 -c 'import sys,json;print(json.load(sys.stdin)["vault"]["id"])')" \
  "Private Key.private_key[password]=$(cat /tmp/nfs-reconciler-key)" \
  "Private Key.public_key[text]=$(cat /tmp/nfs-reconciler-key.pub)"
```
Expected: prints the created item JSON. If the `--category "SSH Key"` auto-generates its own keypair fields, instead create a `--category "Secure Note"` / `Login` item and add the two fields manually in the 1Password UI — the only hard requirement is that `op item get "UNAS NFS Reconciler Key" --fields label=private_key --reveal` and `--fields label=public_key --reveal` both return the right values.

- [ ] **Step 3: Verify retrieval of both halves**

```bash
op item get "UNAS NFS Reconciler Key" --fields label=public_key --reveal | head -c 60; echo
op item get "UNAS NFS Reconciler Key" --fields label=private_key --reveal | head -1
```
Expected: line 1 begins `ssh-ed25519 AAAA…`; line 2 is `-----BEGIN OPENSSH PRIVATE KEY-----`.

- [ ] **Step 4: Shred the local temp keys**

```bash
rm -f /tmp/nfs-reconciler-key /tmp/nfs-reconciler-key.pub
```
Expected: files gone (the only copies now live in 1Password).

- [ ] **Step 5: No commit** (no repo files changed in this task).

---

## Task 2: Operator bootstrap script [BUILD]

**Files:**
- Create: `scripts/bootstrap-unas-reconcile-key.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# =============================================================================
# bootstrap-unas-reconcile-key.sh
# =============================================================================
# Install / refresh the nfs-mountd reconcile key on the UNAS Pro.
#
# OPERATOR-RUN. Run once initially, and AFTER EVERY UniFi OS firmware update —
# the UNAS root filesystem is an overlay, so a firmware update regenerates
# /root/.ssh/authorized_keys and wipes this entry. The unattended reconcile
# (ansible role nfs_mount) will then fail loudly with a pointer back to here.
#
# Mechanism: read the root password ("Claude UNAS Pro SSH") and the reconcile
# public key ("UNAS NFS Reconciler Key") from 1Password (desktop / Touch-ID),
# then append a forced-command authorized_keys line over keyboard-interactive
# SSH (expect; macOS has no sshpass and the UNAS uses PAM keyboard-interactive).
# Idempotent: only appends if the exact public key is not already present.
# =============================================================================
set -euo pipefail

UNAS_HOST="192.168.40.137"
OP_PW_ITEM="Claude UNAS Pro SSH"
OP_KEY_ITEM="UNAS NFS Reconciler Key"

# Use the 1Password desktop integration (Touch-ID), not Connect.
PW="$(env -u OP_CONNECT_HOST -u OP_CONNECT_TOKEN op item get "$OP_PW_ITEM" --fields label=password --reveal)"
PUBKEY="$(env -u OP_CONNECT_HOST -u OP_CONNECT_TOKEN op item get "$OP_KEY_ITEM" --fields label=public_key --reveal)"
[ -n "$PW" ] || { echo "ERROR: empty root password from 1Password ($OP_PW_ITEM)"; exit 1; }
[ -n "$PUBKEY" ] || { echo "ERROR: empty public key from 1Password ($OP_KEY_ITEM)"; exit 1; }

LINE="restrict,command=\"systemctl restart nfs-mountd.service\" ${PUBKEY}"

# Base64-wrap the remote script to avoid all quoting issues over ssh.
B64LINE="$(printf '%s' "$LINE" | base64 | tr -d '\n')"
read -r -d '' REMOTE <<REMOTE_EOF || true
set -e
mkdir -p /root/.ssh && chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
LINE="\$(echo ${B64LINE} | base64 -d)"
if grep -qF "\$LINE" /root/.ssh/authorized_keys; then
  echo ">>>ALREADY_PRESENT"
else
  echo "\$LINE" >> /root/.ssh/authorized_keys
  echo ">>>ADDED"
fi
REMOTE_EOF
B64="$(printf '%s' "$REMOTE" | base64 | tr -d '\n')"
RCMD="echo $B64 | base64 -d | bash"

UNAS_PW="$PW" UNAS_RCMD="$RCMD" expect <<'EXP'
log_user 1
set timeout 45
set pw $env(UNAS_PW)
set rcmd $env(UNAS_RCMD)
spawn -noecho ssh -o StrictHostKeyChecking=accept-new \
  -o PreferredAuthentications=keyboard-interactive,password \
  -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 -o ConnectTimeout=15 \
  root@192.168.40.137 $rcmd
expect {
  -re {[Pp]assword:?\s*$} { send -- "$pw\r"; exp_continue }
  "Permission denied"     { puts "\n>>>AUTH_DENIED"; exit 5 }
  timeout                 { puts "\n>>>TIMEOUT"; exit 6 }
  eof                     { puts "\n>>>EOF" }
}
catch wait result
exit [lindex $result 3]
EXP
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/bootstrap-unas-reconcile-key.sh
```

- [ ] **Step 3: Verify it parses (offline)**

```bash
bash -n scripts/bootstrap-unas-reconcile-key.sh && echo "SYNTAX_OK"
command -v shellcheck >/dev/null && shellcheck scripts/bootstrap-unas-reconcile-key.sh || echo "shellcheck not installed (skipped)"
```
Expected: `SYNTAX_OK`. If shellcheck is present, no errors (warnings about the heredoc `\$` are expected and fine — those `\$` are intentionally escaped for remote evaluation).

- [ ] **Step 4: Commit**

```bash
git add scripts/bootstrap-unas-reconcile-key.sh
git commit -m "feat(nfs): operator bootstrap script for UNAS reconcile key

Installs the forced-command (restrict,command=systemctl restart
nfs-mountd.service) authorized_keys line on the UNAS via root password
over keyboard-interactive SSH. Idempotent; re-run after firmware updates.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: The `nfs_mount` role [BUILD]

**Files:**
- Create: `ansible/roles/nfs_mount/defaults/main.yml`
- Create: `ansible/roles/nfs_mount/tasks/main.yml`

- [ ] **Step 1: Write `defaults/main.yml`**

```yaml
---
# ==============================================================================
# nfs_mount role — Default Variables
# ==============================================================================
# Mounts an NFS share and self-heals the rpc.mountd stale-resolver denial that
# follows a client VM rebuild (new DHCP IP). See
# docs/superpowers/specs/2026-06-02-nfs-mountd-reconciler-design.md
# ==============================================================================

# The UNAS Pro (locked appliance). Mounts served by this host are reconciled
# with the scoped forced-command key; any other server is reconciled by a
# direct delegated restart (we already hold root on managed VMs).
nfs_mount_unas_host: "192.168.40.137"

# 1Password Connect coordinates for the scoped reconcile PRIVATE key.
nfs_mount_reconcile_key_item: "UNAS NFS Reconciler Key"
nfs_mount_reconcile_key_section: "Private Key"
nfs_mount_reconcile_key_field: "private_key"
nfs_mount_reconcile_key_temp_path: "/tmp/.unas_nfs_reconcile_key"
nfs_mount_reconcile_known_hosts: "/tmp/.unas_reconcile_known_hosts"

# Retry behavior after a reconcile bounce.
nfs_mount_retries: 3
nfs_mount_settle_delay: 8

# Caller MUST set (no defaults — fail fast if missing):
#   nfs_mount_label : short name for task output (e.g. "immich-library")
#   nfs_mount_src   : "<server>:<export>"
#   nfs_mount_path  : local mount point
#   nfs_mount_opts  : mount options string
```

- [ ] **Step 2: Write `tasks/main.yml`**

```yaml
---
# ==============================================================================
# nfs_mount role — Mount with mountd-reconcile
# ==============================================================================

- name: "nfs_mount: validate inputs ({{ nfs_mount_label | default('UNSET') }})"
  ansible.builtin.assert:
    that:
      - nfs_mount_label is defined
      - nfs_mount_src is defined
      - "':' in nfs_mount_src"
      - nfs_mount_path is defined
      - nfs_mount_opts is defined
    fail_msg: "nfs_mount requires nfs_mount_label, nfs_mount_src (host:export), nfs_mount_path, nfs_mount_opts"
  tags: ['nfs']

- name: "nfs_mount: check if already mounted ({{ nfs_mount_label }})"
  ansible.builtin.command: "mountpoint -q {{ nfs_mount_path }}"
  register: _nfs_already_mounted
  changed_when: false
  failed_when: false
  tags: ['nfs']

# Only manage the dir when it is NOT already a mountpoint. Once the NFS share
# is mounted, the path is the all-squashed export root and chmod'ing it fails
# with EPERM, which would break idempotent re-runs.
- name: "nfs_mount: ensure mount point exists ({{ nfs_mount_label }})"
  ansible.builtin.file:
    path: "{{ nfs_mount_path }}"
    state: directory
    mode: '0755'
  when: _nfs_already_mounted.rc != 0
  tags: ['nfs']

- name: "nfs_mount: mount with mountd-reconcile ({{ nfs_mount_label }})"
  block:
    - name: "nfs_mount: mount {{ nfs_mount_label }} ({{ nfs_mount_src }})"
      ansible.posix.mount:
        src: "{{ nfs_mount_src }}"
        path: "{{ nfs_mount_path }}"
        fstype: nfs
        opts: "{{ nfs_mount_opts }}"
        state: mounted

  rescue:
    - name: "nfs_mount: resolve serving host for {{ nfs_mount_label }}"
      ansible.builtin.set_fact:
        _nfs_server_host: "{{ nfs_mount_src.split(':')[0] }}"

    # ---- UNAS path: bounce mountd via the scoped forced-command key ----
    - name: "nfs_mount: load UNAS reconcile key from 1Password Connect"
      onepassword.connect.field_info:
        token: "{{ lookup('env', 'OP_CONNECT_TOKEN') }}"
        item: "{{ nfs_mount_reconcile_key_item }}"
        field: "{{ nfs_mount_reconcile_key_field }}"
        section: "{{ nfs_mount_reconcile_key_section }}"
        vault: "{{ lookup('env', 'TF_VAR_onepassword_vault_id') }}"
      environment:
        OP_CONNECT_HOST: "{{ lookup('env', 'OP_CONNECT_HOST') }}"
      delegate_to: localhost
      become: false
      no_log: true
      register: _nfs_reconcile_key
      when: _nfs_server_host == nfs_mount_unas_host

    - name: "nfs_mount: write UNAS reconcile key to secure temp file"
      ansible.builtin.copy:
        content: "{{ _nfs_reconcile_key.field.value }}\n"
        dest: "{{ nfs_mount_reconcile_key_temp_path }}"
        mode: '0600'
      delegate_to: localhost
      become: false
      no_log: true
      when: _nfs_server_host == nfs_mount_unas_host

    - name: "nfs_mount: bounce nfs-mountd on the UNAS (scoped forced-command key)"
      ansible.builtin.command:
        cmd: >-
          ssh -i {{ nfs_mount_reconcile_key_temp_path }} -o IdentitiesOnly=yes
          -o StrictHostKeyChecking=accept-new
          -o UserKnownHostsFile={{ nfs_mount_reconcile_known_hosts }}
          -o BatchMode=yes -o ConnectTimeout=15
          root@{{ nfs_mount_unas_host }} reconcile
      delegate_to: localhost
      become: false
      changed_when: _nfs_unas_bounce.rc == 0
      failed_when: false
      register: _nfs_unas_bounce
      when: _nfs_server_host == nfs_mount_unas_host

    - name: "nfs_mount: remove UNAS reconcile key temp file"
      ansible.builtin.file:
        path: "{{ nfs_mount_reconcile_key_temp_path }}"
        state: absent
      delegate_to: localhost
      become: false
      when: _nfs_server_host == nfs_mount_unas_host

    - name: "nfs_mount: FAIL — UNAS reconcile key rejected (wiped by firmware update)"
      ansible.builtin.fail:
        msg: >-
          UNAS reconcile key rejected (rc={{ _nfs_unas_bounce.rc }}). A UniFi OS
          firmware update wipes /root/.ssh/authorized_keys on the UNAS overlay.
          Re-install it: scripts/bootstrap-unas-reconcile-key.sh
      when: >-
        _nfs_server_host == nfs_mount_unas_host
        and _nfs_unas_bounce is defined
        and _nfs_unas_bounce.rc != 0
        and _nfs_unas_bounce.stderr is search('Permission denied|publickey')

    - name: "nfs_mount: FAIL — UNAS unreachable for reconcile"
      ansible.builtin.fail:
        msg: "Could not reach the UNAS at {{ nfs_mount_unas_host }} to bounce nfs-mountd: {{ _nfs_unas_bounce.stderr }}"
      when: >-
        _nfs_server_host == nfs_mount_unas_host
        and _nfs_unas_bounce is defined
        and _nfs_unas_bounce.rc != 0
        and not (_nfs_unas_bounce.stderr is search('Permission denied|publickey'))

    # ---- Managed-VM path: we already hold root via the ansible key ----
    - name: "nfs_mount: bounce nfs-mountd on managed server {{ _nfs_server_host }}"
      ansible.builtin.command:
        cmd: systemctl restart nfs-mountd.service
      delegate_to: "{{ _nfs_server_host }}"
      become: true
      changed_when: true
      when: _nfs_server_host != nfs_mount_unas_host

    # ---- Retry the mount after the reconcile ----
    - name: "nfs_mount: retry mount {{ nfs_mount_label }} after reconcile"
      ansible.posix.mount:
        src: "{{ nfs_mount_src }}"
        path: "{{ nfs_mount_path }}"
        fstype: nfs
        opts: "{{ nfs_mount_opts }}"
        state: mounted
      register: _nfs_remount
      until: _nfs_remount is succeeded
      retries: "{{ nfs_mount_retries }}"
      delay: "{{ nfs_mount_settle_delay }}"
  tags: ['nfs']
```

- [ ] **Step 3: Verify both files parse as YAML (offline)**

```bash
python3 -c "import yaml,sys; [yaml.safe_load(open(f)) for f in sys.argv[1:]]; print('YAML_OK')" \
  ansible/roles/nfs_mount/defaults/main.yml ansible/roles/nfs_mount/tasks/main.yml
```
Expected: `YAML_OK`.

- [ ] **Step 4: Lint the role if ansible-lint is available**

```bash
command -v ansible-lint >/dev/null && ansible-lint ansible/roles/nfs_mount/ || echo "ansible-lint not installed (skipped)"
```
Expected: no errors (or "skipped"). `no-changed-when` should NOT fire — `changed_when` is set on both command tasks.

- [ ] **Step 5: Commit**

```bash
git add ansible/roles/nfs_mount/
git commit -m "feat(nfs): nfs_mount role — mount with mountd-reconcile

block(mount) -> rescue(bounce serving host's nfs-mountd -> retry). UNAS
mounts bounce via a scoped forced-command key from 1Password Connect;
managed-VM mounts bounce via a direct delegated systemctl restart.
Fails loud (no silent root fallback) when the scoped key is rejected.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Refactor the immich mount call site [BUILD]

**Files:**
- Modify: `ansible/roles/immich/tasks/main.yml` (the `Mount NFS photo library from UNAS Pro` task, ~lines 79–86)

- [ ] **Step 1: Replace the inline mount task**

Find this task:
```yaml
- name: Mount NFS photo library from UNAS Pro
  ansible.posix.mount:
    src: "{{ immich_nfs_server }}:{{ immich_nfs_export }}"
    path: "{{ immich_upload_location }}"
    fstype: nfs
    opts: "{{ immich_nfs_mount_opts }}"
    state: mounted
  tags: ['immich', 'nfs']
```
Replace it with:
```yaml
- name: Mount NFS photo library from UNAS Pro (with mountd reconcile)
  ansible.builtin.include_role:
    name: nfs_mount
  vars:
    nfs_mount_label: "immich-library"
    nfs_mount_src: "{{ immich_nfs_server }}:{{ immich_nfs_export }}"
    nfs_mount_path: "{{ immich_upload_location }}"
    nfs_mount_opts: "{{ immich_nfs_mount_opts }}"
  tags: ['immich', 'nfs']
```
Leave the surrounding "Check if NFS is already mounted" / "Create NFS mount point" tasks untouched (the role re-ensures the directory; harmless and idempotent).

- [ ] **Step 2: Syntax-check the full playbook**

```bash
ansible-playbook playbooks/site.yml --syntax-check
```
Expected: prints the play list and exits 0 (no parse errors).

- [ ] **Step 3: Commit**

```bash
git add ansible/roles/immich/tasks/main.yml
git commit -m "refactor(immich): mount NFS via nfs_mount role (mountd reconcile)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Refactor the duplicati mount call site [BUILD]

**Files:**
- Modify: `ansible/roles/duplicati/tasks/main.yml` (the `Mount NFS backup destination from UNAS Pro` task, ~lines 80–87)

- [ ] **Step 1: Replace the inline mount task**

Find:
```yaml
- name: Mount NFS backup destination from UNAS Pro
  ansible.posix.mount:
    src: "{{ duplicati_nfs_server }}:{{ duplicati_nfs_export }}"
    path: "{{ duplicati_backup_mount }}"
    fstype: nfs
    opts: "{{ duplicati_nfs_mount_opts }}"
    state: mounted
  tags: ['duplicati', 'nfs']
```
Replace with:
```yaml
- name: Mount NFS backup destination from UNAS Pro (with mountd reconcile)
  ansible.builtin.include_role:
    name: nfs_mount
  vars:
    nfs_mount_label: "duplicati-backups"
    nfs_mount_src: "{{ duplicati_nfs_server }}:{{ duplicati_nfs_export }}"
    nfs_mount_path: "{{ duplicati_backup_mount }}"
    nfs_mount_opts: "{{ duplicati_nfs_mount_opts }}"
  tags: ['duplicati', 'nfs']
```

- [ ] **Step 2: Syntax-check**

```bash
ansible-playbook playbooks/site.yml --syntax-check
```
Expected: exits 0.

- [ ] **Step 3: Commit**

```bash
git add ansible/roles/duplicati/tasks/main.yml
git commit -m "refactor(duplicati): mount NFS via nfs_mount role (mountd reconcile)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Refactor the backrest mount call sites [BUILD]

**Files:**
- Modify: `ansible/roles/backrest/tasks/main.yml` (the dest mount ~lines 70–77 and the looped source mounts ~lines 119–130)

- [ ] **Step 1: Replace the destination mount task**

Find:
```yaml
- name: Mount NFS backup destination from UNAS Pro
  ansible.posix.mount:
    src: "{{ backrest_nfs_server }}:{{ backrest_nfs_export }}"
    path: "{{ backrest_backup_mount }}"
    fstype: nfs
    opts: "{{ backrest_nfs_mount_opts }}"
    state: mounted
  tags: ['backrest', 'nfs']
```
Replace with:
```yaml
- name: Mount NFS backup destination from UNAS Pro (with mountd reconcile)
  ansible.builtin.include_role:
    name: nfs_mount
  vars:
    nfs_mount_label: "backrest-backups"
    nfs_mount_src: "{{ backrest_nfs_server }}:{{ backrest_nfs_export }}"
    nfs_mount_path: "{{ backrest_backup_mount }}"
    nfs_mount_opts: "{{ backrest_nfs_mount_opts }}"
  tags: ['backrest', 'nfs']
```

- [ ] **Step 2: Replace the looped source mounts task**

Find:
```yaml
- name: Mount NFS source shares
  ansible.posix.mount:
    src: "{{ item.src }}"
    path: "{{ item.path }}"
    fstype: nfs
    opts: "{{ backrest_source_nfs_mount_opts }}"
    state: mounted
  loop: "{{ backrest_source_mounts }}"
  loop_control:
    label: "{{ item.name }}"
  when: backrest_source_mounts | length > 0
  tags: ['backrest', 'nfs']
```
Replace with:
```yaml
- name: Mount NFS source shares (with mountd reconcile)
  ansible.builtin.include_role:
    name: nfs_mount
  vars:
    nfs_mount_label: "{{ item.name }}"
    nfs_mount_src: "{{ item.src }}"
    nfs_mount_path: "{{ item.path }}"
    nfs_mount_opts: "{{ backrest_source_nfs_mount_opts }}"
  loop: "{{ backrest_source_mounts }}"
  loop_control:
    label: "{{ item.name }}"
  when: backrest_source_mounts | length > 0
  tags: ['backrest', 'nfs']
```
(`backrest_source_mounts` defaults to `[]`, so this loop is inert until populated in host_vars. Source servers are managed VMs → the role takes the direct delegated-restart branch for them.)

- [ ] **Step 3: Syntax-check**

```bash
ansible-playbook playbooks/site.yml --syntax-check
```
Expected: exits 0.

- [ ] **Step 4: Commit**

```bash
git add ansible/roles/backrest/tasks/main.yml
git commit -m "refactor(backrest): mount NFS (dest + sources) via nfs_mount role

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Install the key on the UNAS + prove forced-command scoping [OPERATOR]

**Prerequisite:** Task 1 complete (1Password item exists).

- [ ] **Step 1: Run the bootstrap script**

```bash
./scripts/bootstrap-unas-reconcile-key.sh
```
Expected: a 1Password Touch-ID prompt (twice — password + pubkey), then `>>>ADDED` (first run) and `>>>EOF`, exit 0. Re-running prints `>>>ALREADY_PRESENT` (idempotency).

- [ ] **Step 2: Verify the authorized_keys line is present and correctly scoped**

```bash
op item get "UNAS NFS Reconciler Key" --fields label=private_key --reveal > /tmp/recon_key && chmod 600 /tmp/recon_key
ssh -i /tmp/recon_key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile=/tmp/.unas_reconcile_known_hosts -o BatchMode=yes \
  root@192.168.40.137 'cat /etc/shadow'
echo "exit=$?"
```
Expected: the output is the **mountd restart result**, NOT the contents of `/etc/shadow` — the forced command ignores the requested `cat /etc/shadow`. `exit=0`. This is the scoping proof: the key can do nothing but restart mountd.

- [ ] **Step 3: Confirm the restart actually happened**

```bash
ssh -i /tmp/recon_key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile=/tmp/.unas_reconcile_known_hosts -o BatchMode=yes \
  root@192.168.40.137 anything-here-is-ignored; echo "exit=$?"
# Then verify mountd was freshly restarted (run the proven password recon, or check uptime):
```
Expected: `exit=0`. (The forced command ran `systemctl restart nfs-mountd.service` regardless of the argument.)

- [ ] **Step 4: Clean up the local key copy**

```bash
rm -f /tmp/recon_key
```

- [ ] **Step 5: No commit** (no repo files changed; this is a live-infra action).

---

## Task 8: Integration reproduction — hands-off recovery [OPERATOR]

**This destroys and rebuilds the duplicati VM. Requires Branden's explicit confirmation before each Terraform apply/destroy. Do NOT auto-run.**

**Prerequisites:** Tasks 2–7 complete (role wired, key installed on the UNAS).

- [ ] **Step 1: Force a rebuild of the duplicati VM (new IP)**

```bash
cd terraform
terraform plan  -replace='proxmox_virtual_environment_vm.qemu-vm["duplicati"]'
# PAUSE for Branden's confirmation, then:
terraform apply -replace='proxmox_virtual_environment_vm.qemu-vm["duplicati"]'
```
Expected: duplicati VM destroyed + recreated with a new MAC/IP; `dns.tf` updates its A record + reservation. (Scope: ~2 add, 2 change, 2 destroy — confirm the plan is scoped to duplicati only before approving.)

- [ ] **Step 2: Run the configuration play and watch the reconcile fire**

```bash
cd ../ansible
ansible-playbook playbooks/site.yml --limit duplicati,localhost --tags duplicati,ssh-key
```
Expected (the red→green evidence): the `nfs_mount: mount duplicati-backups …` task **fails into the rescue**; the `bounce nfs-mountd on the UNAS (scoped forced-command key)` task runs `changed`; the `retry mount … after reconcile` task **succeeds**; the play exits **0**. Capture this output — it is the proof the reconciler works hands-off.

- [ ] **Step 3: Idempotency — re-run**

```bash
ansible-playbook playbooks/site.yml --limit duplicati,localhost --tags duplicati,ssh-key
```
Expected: the first mount **succeeds** (already mounted, `changed: false`); the rescue does **not** fire; exit 0.

- [ ] **Step 4: No-fallback proof (the isolation guarantee)**

Temporarily point the role at a missing key, force the rescue, and confirm it fails loud with the bootstrap pointer rather than silently escalating:
```bash
cd ../ansible
# Unmount so the next run re-enters the mount path:
ansible duplicati -m ansible.posix.mount -a "path=/mnt/backups state=unmounted" --limit duplicati
# Run with a bogus key path to simulate a wiped key:
ansible-playbook playbooks/site.yml --limit duplicati,localhost --tags duplicati,ssh-key \
  -e nfs_mount_reconcile_key_temp_path=/tmp/does-not-exist-key
```
Expected: the play **fails** at "FAIL — UNAS reconcile key rejected …" with the `scripts/bootstrap-unas-reconcile-key.sh` pointer. No root password is ever used. Then restore a clean run (Step 2/3) to leave duplicati mounted.

- [ ] **Step 5: No commit** (live-infra verification; evidence captured in the session/PR).

---

## Task 9: Open the PR [BUILD]

**Prerequisite:** Tasks 2–6 committed; Tasks 7–8 verified (paste the Task 8 Step 2 output into the PR as evidence).

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feat/dns-automation
```
(If the branch already tracks origin, a plain `git push`.)

- [ ] **Step 2: Request code review via the superpowers gate**

Use **superpowers:requesting-code-review** against the diff for the `nfs_mount` role, the bootstrap script, and the three role refactors.

- [ ] **Step 3: Open the PR**

```bash
gh pr create --title "feat(nfs): UNAS nfs-mountd reconciler (A+ scoped forced-command key)" --body "$(cat <<'EOF'
## Summary
- New `nfs_mount` Ansible role: block(mount) → rescue(bounce serving host's nfs-mountd → retry). Self-heals the rpc.mountd stale-resolver denial after a VM rebuild changes its IP.
- UNAS mounts reconcile via a `restrict,command="systemctl restart nfs-mountd.service"` scoped key (1Password Connect); managed-VM mounts via a direct delegated restart. No root password in the unattended path; fails loud if the scoped key is wiped by a firmware update.
- Operator bootstrap script installs/refreshes the scoped key on the UNAS (run after firmware updates).
- immich / duplicati / backrest mount call sites refactored onto the role.
- Interim bridge: the static-IP network-layer track will eventually moot this.

## Test plan
- [x] `ansible-playbook playbooks/site.yml --syntax-check` passes.
- [x] Forced-command scoping proven (`cat /etc/shadow` over the key returns the restart, not shadow).
- [x] Hands-off recovery: `terraform -replace` duplicati → `site.yml` → mount denied → rescue bounces → retry mounts → exit 0 (output below).
- [x] Idempotent re-run: mount already mounted, rescue does not fire.
- [x] No-fallback proof: missing key → fail-loud with bootstrap pointer, no root escalation.

<paste Task 8 Step 2 output here>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
Expected: PR created on `feat/dns-automation`. The Claude auto-review should post (per `project_github_claude_review_trigger`).

---

## Self-Review

**Spec coverage:**
- Credential model (scoped forced-command key, no password in runner) → Tasks 1, 2, 3, 7. ✓
- Reactive Ansible placement (block/rescue) → Task 3. ✓
- Four call sites refactored (immich 1, duplicati 1, backrest 2) → Tasks 4, 5, 6. ✓
- Managed-VM vs UNAS reconcile branch (correctness for backrest sources) → Task 3 (`_nfs_server_host != nfs_mount_unas_host`). ✓ (refines the spec, which was UNAS-only on this point — noted in Task 6.)
- Operator bootstrap, re-run after firmware updates → Task 2 (header + idempotency) and Task 7. Spec said "playbook"; implemented as a shell+expect **script** because keyboard-interactive auth doesn't work through Ansible's sshpass path on the macOS controller — intent (operator-run, root-password, idempotent, post-update) preserved. ✓
- Error handling: fail-loud on wiped key (no silent fallback), unreachable host, persistent failure → Task 3 fail tasks + Task 8 Step 4. ✓
- Verification: red→green reproduction, scoping proof, no-fallback proof, idempotency → Tasks 7, 8. ✓
- Security: 1Password-sourced key to 0600 temp file, removed after use, no_log → Task 3. ✓

**Placeholder scan:** Every code/command step contains full content. The only literal placeholder is `<paste Task 8 Step 2 output here>` in the PR body, which is intentional (runtime evidence). No "TBD/handle errors/similar to Task N". ✓

**Consistency:** Var names (`nfs_mount_label/src/path/opts`, `nfs_mount_unas_host`, `nfs_mount_reconcile_key_*`) are identical across defaults, role tasks, and all call sites. The forced-command string `systemctl restart nfs-mountd.service` matches between the bootstrap script and the role's failure-message reference. The 1Password item name `UNAS NFS Reconciler Key` and field `public_key`/`private_key` match across Tasks 1, 2, 3. ✓
