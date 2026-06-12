# opconnect Connect-Independence via op-CLI Write-Back — Implementation Plan

**Goal:** Close the regression `d6dd2af` introduced — make `tofu/opconnect` apply with ZERO live-Connect dependency again — using option D (op-CLI write-back), the minimal-blast-radius fix. Full best-practice architecture is deferred to task #68 (`docs/enhance-harden-later.md`).

**Architecture:** opconnect keeps generating the Ansible keypair with `tls_private_key` (stays in state, same key) and uses the public half for cloud-init. The `onepassword_item` *resource* (which forced the `onepassword` provider → required Connect) is replaced by a `null_resource` `local-exec` that writes the keypair to 1Password via the **desktop `op` CLI in account mode (Connect-free)**. The `onepassword` provider is removed from opconnect entirely. compute + ansible read the key from 1Password unchanged.

**Scope:** `tofu/opconnect/` only. No changes to compute, ansible, or cloud-init.

**Item contract to reproduce (live-verified):** title `Infrastructure Ansible SSH Key`, category `SECURE_NOTE`; section `Private Key` → `private_key`(CONCEALED) + `key_type`(STRING); section `Public Key` → `public_key`(STRING) + `public_key_fingerprint_sha256`(STRING); plus a static provenance note.

---

### Task 1: Safety — back up opconnect state
- [ ] `tofu -chdir=tofu/opconnect state pull > ~/opconnect-state-backup-pre-D.json` ; confirm non-empty.

### Task 2: Write the write-back script
- [ ] Create `tofu/opconnect/scripts/op-write-ssh-key.sh` (0755): receives `OP_VAULT`, `OP_ITEM_TITLE`, `SSH_PUBLIC_KEY`, `SSH_PRIVATE_KEY`, `KEY_TYPE` via env (never argv). Forces account mode with `env -u OP_CONNECT_HOST -u OP_CONNECT_TOKEN -u OP_SERVICE_ACCOUNT_TOKEN op …`. Idempotent: if the item exists with a matching `public_key`, no-op; else (create or replace) build the item JSON in a `mktemp` 0600 file (private key only in that file, never argv), `op item create --vault … --template <file>`, then `shred`/`rm` the file. Public key compared on the command line is fine (not secret).

### Task 3: Rewrite `tofu/opconnect/ssh-keys.tf`
- [ ] Keep `resource "tls_private_key" "ansible"` and `local.ansible_ssh_public_key`.
- [ ] Remove `resource "onepassword_item" "ansible_ssh_key"`.
- [ ] Add `resource "null_resource" "ansible_ssh_key_writeback"` with `triggers` = fingerprint + title + vault, and a `local-exec` calling the script, passing key material via the `environment` block.

### Task 4: Drop the onepassword provider from opconnect
- [ ] `tofu/opconnect/providers.tf`: remove the `onepassword = { … }` `required_providers` entry and the `provider "onepassword" {}` block. Keep proxmox/unifi/tls/ansible. Update the header comment (no longer a Connect/SA secrets consumer).
- [ ] `tofu/opconnect/variables.tf`: keep `ansible_ssh_key_item_title` + `onepassword_vault_id` (the script needs them); leave `ansible_pubkey` removed.

### Task 5: De-manage the existing item + validate
- [ ] `tofu -chdir=tofu/opconnect state rm onepassword_item.ansible_ssh_key` (REQUIRED before removing the provider — leaves the 1P item intact).
- [ ] `tofu -chdir=tofu/opconnect init` (settle provider removal) ; `tofu validate`.
- [ ] `tofu -chdir=tofu/opconnect plan` — expect: `+ null_resource.ansible_ssh_key_writeback`, NO destroy of any onepassword resource, no `onepassword` provider referenced.

### Task 6: Apply + prove Connect-independence
- [ ] `tofu -chdir=tofu/opconnect apply` (runs the write-back; item already correct → script no-ops or re-creates identically).
- [ ] **Proof:** `env -u OP_CONNECT_HOST -u OP_CONNECT_TOKEN tofu -chdir=tofu/opconnect plan` → clean, NO `Invalid provider configuration` / `Client init failure`. This is the regression closed.
- [ ] Verify the 1P item still resolves with the exact field structure (op item get) AND Connect serves it (curl `/v1/vaults/<id>/items`).

### Task 7: Commit
- [ ] `git add tofu/opconnect/ docs/` ; commit `fix(opconnect): restore Connect-independence via op-CLI write-back (drop onepassword provider)`. NO `Co-Authored-By` trailer.

---

**Then (separate, already-planned):** re-run compute e2e serialized → 6/6 → P6 docs → delete legacy `terraform/` → PR.
