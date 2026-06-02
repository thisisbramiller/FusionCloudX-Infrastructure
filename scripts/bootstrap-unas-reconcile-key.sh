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
