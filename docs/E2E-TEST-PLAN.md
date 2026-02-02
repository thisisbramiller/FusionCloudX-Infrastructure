# End-to-End Infrastructure Test Plan
## Full Disaster Recovery / Tabletop Exercise

**Objective**: Validate complete infrastructure provisioning and configuration from scratch

**Duration**: ~45-60 minutes

**Risk Level**: Medium (destroys existing VMs - backup critical data first)

---

## Pre-Test Checklist

### 1. Backup Critical Data ✅
- [ ] Export 1Password vault (if needed)
- [ ] Backup GitLab data (if important repos exist): `sudo gitlab-backup create`
- [ ] Document current VM IPs for comparison
- [ ] Take Proxmox snapshots (optional safety net)

### 2. Verify Prerequisites ✅
- [ ] Proxmox cluster is healthy and accessible (https://192.168.40.206:8006)
- [ ] 1Password service account token is available
- [ ] Workstation has Terraform installed: `terraform version`
- [ ] Workstation has Ansible installed: `ansible --version`
- [ ] Workstation can SSH to Proxmox host: `ssh root@192.168.40.206`
- [ ] GitHub access working from workstation
- [ ] Sufficient Proxmox resources:
  - `nas-infrastructure` datastore has space for templates
  - `vm-data` datastore has space for VM disks (~150GB needed)

### 3. Verify Environment Variables ✅
```bash
# Your environment variables are already loaded in your shell
# They pull secrets from macOS Keychain via ~/.zprofile
# Just verify they're loaded in your current shell session

# Verify 1Password Service Account Token (used by bootstrap playbook)
echo ${OP_SERVICE_ACCOUNT_TOKEN:0:20}...  # Should show "ops_..."

# Verify 1Password Connect Token (used by Ansible onepassword.connect collection)
echo ${OP_CONNECT_TOKEN:0:30}...  # Should show JWT token prefix

# Verify 1Password Connect host
echo $OP_CONNECT_HOST  # Should show "http://192.168.40.44:8080"

# Verify 1Password vault ID
echo $TF_VAR_onepassword_vault_id  # Should show vault UUID

# Verify Proxmox API token
echo ${PROXMOX_VE_API_TOKEN:0:30}...  # Should show "terraform@pve!provider=..."

# If any are empty, reload your profile
source ~/.zprofile
```

**Note**: You're using **dual 1Password authentication**:
- **Service Account Token** (`OP_SERVICE_ACCOUNT_TOKEN`): Used by bootstrap playbook to set up semaphore-ui
- **1Password Connect** (`OP_CONNECT_TOKEN` + `OP_CONNECT_HOST`): Used by Ansible collections for ongoing secret retrieval
- Connect Server: http://192.168.40.44:8080
- Both tokens loaded from macOS Keychain

---

## Phase 1: Infrastructure Teardown (5 minutes)

### 1.1 Document Current State
```bash
cd terraform/

# Capture current state
terraform output -json > /tmp/pre-destroy-state.json
cat /tmp/pre-destroy-state.json

# List current VMs
terraform state list | grep proxmox_virtual_environment_vm
```

**Expected Output**:
```
proxmox_virtual_environment_vm.qemu-vm["gitlab"]
proxmox_virtual_environment_vm.qemu-vm["semaphore-ui"]
proxmox_virtual_environment_vm.ubuntu_template
proxmox_virtual_environment_container.postgresql_lxc
```

**Proxmox UI Checkpoint** 🖥️:
- Navigate to Datacenter → VMs
- Note VM IDs: 1000 (template), 1102 (semaphore-ui), 1103 (gitlab), 2001 (postgresql)

### 1.2 Destroy Infrastructure
```bash
# Run destroy
terraform destroy

# Type 'yes' when prompted
```

**Expected Timeline**:
- Terraform plans destruction: ~10 seconds
- VMs/LXC destruction: ~2-3 minutes
- Template removal: ~30 seconds

**Proxmox UI Monitoring** 🖥️:
- Watch VMs disappear from list
- Check Tasks tab for completion
- Verify VM IDs 1000, 1102, 1103, 2001 are gone

### 1.3 Verify Clean State
```bash
# Verify terraform state is empty (except provider)
terraform state list

# Check Proxmox manually
ssh root@192.168.40.206 'qm list'
ssh root@192.168.40.206 'pct list'
```

**Expected Output**: No VMs with IDs 1000-1103, 2001

---

## Phase 2: Terraform Infrastructure Provisioning (10-15 minutes)

### 2.1 Initialize Terraform
```bash
cd terraform/

# Re-initialize (should be quick)
terraform init

# Validate configuration
terraform validate
```

**Expected Output**: "Success! The configuration is valid."

### 2.2 Plan Infrastructure
```bash
# Generate execution plan
terraform plan -out=tfplan

# Review the plan carefully
```

**Expected Resources to Create**:
```
+ proxmox_virtual_environment_download_file.ubuntu_noble_img
+ proxmox_virtual_environment_vm.ubuntu_template
+ proxmox_virtual_environment_file.cloud_init_user_data_file["gitlab"]
+ proxmox_virtual_environment_file.cloud_init_user_data_file["semaphore-ui"]
+ proxmox_virtual_environment_file.shared_vendor_data_file
+ proxmox_virtual_environment_file.semaphore_vendor_data_file
+ proxmox_virtual_environment_vm.qemu-vm["gitlab"]
+ proxmox_virtual_environment_vm.qemu-vm["semaphore-ui"]
+ proxmox_virtual_environment_container.postgresql_lxc
+ onepassword_item.gitlab_root_password
+ onepassword_item.postgresql_passwords["semaphore"]
+ onepassword_item.postgresql_passwords["wazuh"]
```

**Total Resources**: ~11-13 resources

### 2.3 Apply Infrastructure
```bash
# Apply the plan
terraform apply tfplan

# Or apply with auto-approve (if you're confident)
# terraform apply -auto-approve
```

**Expected Timeline**:
1. **Ubuntu template download** (~2 minutes): Downloads Ubuntu Noble cloud image to Proxmox
2. **Template creation** (~1 minute): Creates VM template (ID 1000)
3. **Cloud-init files** (~10 seconds): Creates snippets on `nas-infrastructure`
4. **VM cloning** (~3-5 minutes): Clones template for semaphore-ui (1102) and gitlab (1103)
5. **LXC creation** (~2 minutes): Creates PostgreSQL container (2001)
6. **1Password items** (~10 seconds): Creates credential items
7. **Guest agent wait** (~1-2 minutes): Waits for QEMU guest agent to report IPs

**Proxmox UI Monitoring** 🖥️:
- Watch for template download in Tasks (pve node → Tasks)
- See VM 1000 appear (template)
- Watch VMs 1102, 1103 being cloned
- Monitor LXC 2001 creation
- Check cloud-init progress: VM → Cloud-Init tab
- Verify VMs get IP addresses automatically

**Critical Success Indicators**:
✅ All VMs have status "running"
✅ QEMU guest agent shows green checkmark in Proxmox
✅ terraform output shows IP addresses

### 2.4 Verify Terraform Outputs
```bash
# Display all outputs
terraform output

# Specific outputs
terraform output vm_ipv4_addresses
terraform output postgresql_lxc_ipv4_address
```

**Expected Output Example**:
```
vm_ipv4_addresses = {
  "gitlab" = "192.168.40.98"
  "semaphore-ui" = "192.168.40.26"
}
postgresql_lxc_ipv4_address = "192.168.40.102"
```

**⚠️ IMPORTANT**: Note these IPs - you'll need them for Ansible inventory

### 2.5 Verify VM Accessibility
```bash
# Test SSH access to VMs (cloud-init should have configured ansible user)
ssh ansible@192.168.40.26 'whoami'  # semaphore-ui
ssh ansible@192.168.40.98 'whoami'  # gitlab
ssh ansible@192.168.40.102 'whoami' # postgresql (if SSH enabled)
```

**Expected Output**: "ansible"

### 2.6 Check Cloud-init Completion
```bash
# Verify cloud-init finished
ssh ansible@192.168.40.26 'cloud-init status'
ssh ansible@192.168.40.98 'cloud-init status'

# Check marker files
ssh ansible@192.168.40.26 'ls -l /var/lib/cloud-init.*.ready'
ssh ansible@192.168.40.98 'ls -l /var/lib/cloud-init.*.ready'
```

**Expected Output**: "status: done" and marker files exist

---

## Phase 3: Ansible Inventory Update (2 minutes)

### 3.1 Update Ansible Inventory
```bash
cd ../ansible/

# Check current inventory
cat inventory/hosts.ini

# Update with new IPs from terraform output
# Option 1: Manual edit
vim inventory/hosts.ini

# Option 2: Use update script (if available)
../ansible/update-inventory.sh
```

### 3.2 Verify Inventory Configuration
```bash
# Your inventory should look like this:
cat inventory/hosts.ini
```

**Expected Content**:
```ini
[postgresql]
postgresql ansible_host=192.168.40.102

[application_servers]
gitlab ansible_host=192.168.40.98
semaphore-ui ansible_host=192.168.40.26

[monitoring]
# wazuh ansible_host=192.168.1.XXX

[homelab:children]
postgresql
application_servers
monitoring

[homelab:vars]
ansible_user=ansible
ansible_python_interpreter=/usr/bin/python3
```

### 3.3 Test Ansible Connectivity
```bash
# Ping all hosts
ansible all -i inventory/hosts.ini -m ping

# Check if hosts are reachable
ansible all -i inventory/hosts.ini -m command -a "uptime"
```

**Expected Output**: All hosts return SUCCESS with "pong"

---

## Phase 4: Ansible Configuration - PostgreSQL (5-8 minutes)

### 4.1 Run PostgreSQL Playbook
```bash
cd ansible/

# Run PostgreSQL setup
ansible-playbook -i inventory/hosts.ini playbooks/postgresql.yml

# Or with 1Password token
ansible-playbook -i inventory/hosts.ini playbooks/postgresql.yml \
  -e "onepassword_service_account_token=$OP_SERVICE_ACCOUNT_TOKEN"
```

**Expected Tasks**:
1. ✅ Install PostgreSQL 15+
2. ✅ Configure postgresql.conf (listen_addresses, port)
3. ✅ Configure pg_hba.conf (allow homelab network access)
4. ✅ Create databases: semaphore, wazuh
5. ✅ Create database users with passwords from 1Password
6. ✅ Grant database permissions
7. ✅ Restart PostgreSQL service

**Expected Timeline**: 5-8 minutes

**Validation Commands**:
```bash
# Check PostgreSQL is running
ansible postgresql -i inventory/hosts.ini -m command -a "systemctl status postgresql"

# Check databases exist
ssh ansible@192.168.40.102 'sudo -u postgres psql -c "\l"'

# Test remote connection (from workstation)
psql -h 192.168.40.102 -U semaphore -d semaphore -c "SELECT version();"
```

**Expected Output**: PostgreSQL version string

---

## Phase 5: Ansible Configuration - GitLab (10-15 minutes)

### 5.1 Run GitLab Playbook
```bash
# Run GitLab installation and configuration
ansible-playbook -i inventory/hosts.ini playbooks/gitlab.yml

# Or run site.yml (includes all playbooks)
# ansible-playbook -i inventory/hosts.ini playbooks/site.yml --tags gitlab
```

**Expected Tasks**:
1. ✅ Install dependencies (curl, ca-certificates, postfix, ufw)
2. ✅ Add GitLab CE repository
3. ✅ Install GitLab Omnibus package (~10 minutes)
4. ✅ Configure gitlab.rb with memory-constrained settings
5. ✅ Run gitlab-ctl reconfigure
6. ✅ Configure UFW firewall rules (HTTP, HTTPS, SSH)
7. ✅ Verify GitLab service is running

**Expected Timeline**: 10-15 minutes (GitLab installation is slow)

**Proxmox UI Monitoring** 🖥️:
- Watch GitLab VM (1103) CPU usage spike during installation
- Memory usage should stay within 8GB limit

**Validation Commands**:
```bash
# Check GitLab service status
ssh ansible@192.168.40.98 'sudo gitlab-ctl status'

# Check GitLab version
ssh ansible@192.168.40.98 'sudo gitlab-rake gitlab:env:info'

# Get root password (should be in 1Password)
op item get "GitLab Root User" --vault "homelab" --fields password
```

### 5.2 Verify GitLab Web Access
```bash
# Check GitLab is responding
curl -I http://192.168.40.98

# Or open in browser
open http://192.168.40.98
# Or: open http://gitlab.fusioncloudx.home (if DNS configured)
```

**Expected Output**:
- HTTP 302 redirect to sign-in page
- GitLab login page loads in browser
- Can log in with root user and password from 1Password

---

## Phase 6: Ansible Configuration - Semaphore Control Plane (8-12 minutes)

### 6.1 Update Bootstrap Inventory
```bash
# Update bootstrap inventory with actual IP
vim ansible/inventory/bootstrap-semaphore.ini
```

**Update to**:
```ini
[semaphore_controller]
semaphore-ui ansible_host=192.168.40.26

[semaphore_controller:vars]
ansible_user=ansible
ansible_python_interpreter=/usr/bin/python3
```

### 6.2 Run Bootstrap Playbook
```bash
# Run semaphore bootstrap
ansible-playbook -i inventory/bootstrap-semaphore.ini \
  playbooks/bootstrap-semaphore.yml \
  -e "onepassword_service_account_token=$OP_SERVICE_ACCOUNT_TOKEN"
```

**Expected Tasks** (from semaphore-controller role):
1. ✅ Install Terraform 1.10.3
2. ✅ Install 1Password CLI 2.30.3
3. ✅ Install Semaphore UI
4. ✅ Generate 3 SSH keys (management, GitHub, Proxmox)
5. ✅ Clone infrastructure repository to /opt/infrastructure
6. ✅ Install Ansible collections
7. ✅ Configure environment variables
8. ✅ Create and start Semaphore systemd service
9. ✅ Verify all installations

**Expected Timeline**: 8-12 minutes

**Critical Output to Capture**:
```
TASK [Display SSH public keys]
  - Management Key: ssh-ed25519 AAAA... ansible@semaphore-ui
  - GitHub Deploy Key: ssh-ed25519 AAAA... semaphore-ui-deploy-key@fusioncloudx
  - Proxmox Terraform Key: ssh-ed25519 AAAA... semaphore-terraform@proxmox
```

**⚠️ ACTION REQUIRED**: Save these public keys for manual configuration

### 6.3 Verify Semaphore Installation
```bash
# Check Semaphore service
ssh ansible@192.168.40.26 'systemctl status semaphore'

# Check installed components
ssh ansible@192.168.40.26 'terraform version'
ssh ansible@192.168.40.26 'op --version'
ssh ansible@192.168.40.26 'semaphore version'

# Check repository was cloned
ssh ansible@192.168.40.26 'ls -la /opt/infrastructure/'

# Check SSH keys were generated
ssh ansible@192.168.40.26 'ls -la ~/.ssh/'
```

**Expected Output**:
- Semaphore service: active (running)
- All version commands succeed
- /opt/infrastructure/ contains cloned repo
- ~/.ssh/ contains id_ed25519, github_deploy_key, proxmox_terraform_key

### 6.4 Configure SSH Keys (Manual Steps)

**GitHub Deploy Key**:
```bash
# Get the public key
ssh ansible@192.168.40.26 'cat ~/.ssh/github_deploy_key.pub'

# Add to GitHub:
# 1. Go to: https://github.com/thisisbramiller/fusioncloudx-infrastructure/settings/keys
# 2. Click "Add deploy key"
# 3. Paste the public key
# 4. Allow write access (if needed)
```

**Proxmox Terraform Key**:
```bash
# Get the public key
ssh ansible@192.168.40.26 'cat ~/.ssh/proxmox_terraform_key.pub'

# Add to Proxmox terraform user:
ssh root@192.168.40.206
mkdir -p /home/terraform/.ssh
echo 'ssh-ed25519 AAAA...' >> /home/terraform/.ssh/authorized_keys
chmod 700 /home/terraform/.ssh
chmod 600 /home/terraform/.ssh/authorized_keys
chown -R terraform:terraform /home/terraform/.ssh
```

### 6.5 Verify Semaphore Web Access
```bash
# Check Semaphore is responding
curl -I http://192.168.40.26:3000

# Or open in browser
open http://192.168.40.26:3000
```

**Expected Output**:
- HTTP 200 or redirect
- Semaphore login/setup page loads
- Can create first admin user

---

## Phase 7: End-to-End Validation (5 minutes)

### 7.1 Infrastructure Validation Checklist

**Terraform State**:
```bash
cd terraform/
terraform state list | wc -l  # Should show ~11-13 resources
terraform output                # Should show all IPs
```

**Proxmox Validation** 🖥️:
- [ ] VM 1000 (template) exists and stopped
- [ ] VM 1102 (semaphore-ui) running, 8GB RAM, 8 CPUs
- [ ] VM 1103 (gitlab) running, 8GB RAM, 4 CPUs
- [ ] LXC 2001 (postgresql) running, 4GB RAM, 2 CPUs
- [ ] All VMs show green QEMU guest agent icon
- [ ] All VMs have valid IP addresses

**Service Validation**:
```bash
# PostgreSQL
ssh ansible@192.168.40.102 'sudo systemctl status postgresql'
psql -h 192.168.40.102 -U semaphore -d semaphore -c "SELECT 1;"

# GitLab
curl -I http://192.168.40.98
ssh ansible@192.168.40.98 'sudo gitlab-ctl status | grep "run:"'

# Semaphore
curl -I http://192.168.40.26:3000
ssh ansible@192.168.40.26 'systemctl status semaphore'
```

**Expected Output**: All services respond and show "active" or "running"

### 7.2 Connectivity Matrix Test
```bash
# Test internal connectivity
# GitLab → PostgreSQL
ssh ansible@192.168.40.98 'nc -zv 192.168.40.102 5432'

# Semaphore → PostgreSQL
ssh ansible@192.168.40.26 'nc -zv 192.168.40.102 5432'

# Semaphore → GitLab
ssh ansible@192.168.40.26 'curl -I http://192.168.40.98'

# Semaphore → Proxmox
ssh ansible@192.168.40.26 'curl -k https://192.168.40.206:8006'
```

**Expected Output**: All connections succeed

### 7.3 1Password Integration Test
```bash
# Test from semaphore-ui
ssh ansible@192.168.40.26 'op vault list'
ssh ansible@192.168.40.26 'op item get "GitLab Root User" --fields password'
```

**Expected Output**: Vault list shows homelab vault, password retrieval succeeds

### 7.4 Terraform from Control Plane Test
```bash
# Test Terraform can run on semaphore-ui
ssh ansible@192.168.40.26 'cd /opt/infrastructure/terraform && terraform version'
ssh ansible@192.168.40.26 'cd /opt/infrastructure/terraform && terraform validate'
```

**Expected Output**: Terraform commands work correctly

---

## Phase 8: Cleanup and Documentation (3 minutes)

### 8.1 Update Main Ansible Inventory
```bash
# Uncomment and update semaphore-ui in main inventory
vim ansible/inventory/hosts.ini
```

**Update to**:
```ini
[application_servers]
semaphore-ui ansible_host=192.168.40.26  # Uncommented and updated
gitlab ansible_host=192.168.40.98
```

### 8.2 Commit Changes
```bash
# Stage inventory changes
git add ansible/inventory/hosts.ini
git add ansible/inventory/bootstrap-semaphore.ini

# Commit
git commit -m "test: update inventory after E2E infrastructure rebuild

- Updated semaphore-ui IP to 192.168.40.26
- Updated GitLab IP to 192.168.40.98
- Updated PostgreSQL IP to 192.168.40.102
- Full E2E test successful"

# Push
git push
```

### 8.3 Document Test Results
```bash
# Create test report
cat > /tmp/e2e-test-results.txt <<EOF
E2E Infrastructure Test Results
Date: $(date)
Duration: [FILL IN] minutes

Phase 1: Teardown - ✅ PASS
Phase 2: Terraform Provisioning - ✅ PASS
Phase 3: Inventory Update - ✅ PASS
Phase 4: PostgreSQL Configuration - ✅ PASS
Phase 5: GitLab Configuration - ✅ PASS
Phase 6: Semaphore Control Plane - ✅ PASS
Phase 7: End-to-End Validation - ✅ PASS

Final VM IPs:
- semaphore-ui: 192.168.40.26
- gitlab: 192.168.40.98
- postgresql: 192.168.40.102

Notes:
[Add any issues or observations here]
EOF

cat /tmp/e2e-test-results.txt
```

---

## Success Criteria Summary

### ✅ All Tests Must Pass:

**Infrastructure**:
- [ ] All VMs created with correct IDs, RAM, CPU specs
- [ ] All VMs have valid IP addresses from DHCP
- [ ] QEMU guest agent working on all VMs
- [ ] Cloud-init completed on all VMs

**Services**:
- [ ] PostgreSQL running with semaphore and wazuh databases
- [ ] GitLab accessible via web browser on port 80
- [ ] Semaphore accessible via web browser on port 3000
- [ ] All systemd services show "active (running)"

**Configuration**:
- [ ] Terraform can manage infrastructure from workstation
- [ ] Ansible can configure all hosts from workstation
- [ ] Semaphore has Terraform, 1Password CLI, and Ansible installed
- [ ] SSH keys generated and distributed correctly
- [ ] Infrastructure repository cloned to /opt/infrastructure
- [ ] 1Password integration working from semaphore-ui

**Validation**:
- [ ] Can log into GitLab with root password from 1Password
- [ ] Can access Semaphore web UI and create admin user
- [ ] Can SSH to all VMs as ansible user
- [ ] All internal connectivity tests pass

---

## Troubleshooting Guide

### Issue: Terraform destroy fails
**Symptom**: VMs won't delete or timeout
**Solution**:
```bash
# Force remove from state
terraform state rm proxmox_virtual_environment_vm.qemu-vm[\"gitlab\"]

# Manually delete in Proxmox
ssh root@192.168.40.206 'qm stop 1103 && qm destroy 1103'
```

### Issue: QEMU guest agent not reporting IP
**Symptom**: terraform apply hangs waiting for IP address
**Solution**:
```bash
# Check guest agent is running in VM
ssh ansible@192.168.40.26 'systemctl status qemu-guest-agent'

# Restart guest agent
ssh ansible@192.168.40.26 'sudo systemctl restart qemu-guest-agent'

# Or skip IP detection by using DHCP reservation
```

### Issue: Cloud-init didn't finish
**Symptom**: ansible user doesn't exist or SSH fails
**Solution**:
```bash
# Check cloud-init status from Proxmox console
# (Use Proxmox web UI: VM > Console)
cloud-init status --long
cat /var/log/cloud-init.log
```

### Issue: Ansible can't connect to hosts
**Symptom**: "Host unreachable" or "Connection refused"
**Solution**:
```bash
# Verify SSH service is running
ssh ansible@192.168.40.26 'systemctl status ssh'

# Check firewall isn't blocking
ssh ansible@192.168.40.26 'sudo ufw status'

# Test with verbose SSH
ssh -vvv ansible@192.168.40.26
```

### Issue: GitLab installation times out
**Symptom**: Task hangs for >20 minutes
**Solution**:
```bash
# Check if GitLab package is downloading
ssh ansible@192.168.40.98 'ps aux | grep apt'

# Check disk space
ssh ansible@192.168.40.98 'df -h'

# Resume manual installation if needed
ssh ansible@192.168.40.98
sudo apt-get install gitlab-ce
sudo gitlab-ctl reconfigure
```

### Issue: Semaphore can't connect to PostgreSQL
**Symptom**: Semaphore service fails to start
**Solution**:
```bash
# Check PostgreSQL is listening on network
ssh ansible@192.168.40.102 'sudo netstat -tlnp | grep 5432'

# Test connection from semaphore-ui
ssh ansible@192.168.40.26 'psql -h 192.168.40.102 -U semaphore -d semaphore'

# Check pg_hba.conf allows homelab network
ssh ansible@192.168.40.102 'sudo cat /etc/postgresql/*/main/pg_hba.conf | grep 192.168'
```

### Issue: 1Password CLI can't authenticate
**Symptom**: "op vault list" returns 401 Unauthorized
**Solution**:
```bash
# Verify token is set
ssh ansible@192.168.40.26 'echo $OP_SERVICE_ACCOUNT_TOKEN'

# Re-export token in environment
export OP_SERVICE_ACCOUNT_TOKEN="ops_..."

# Re-run playbook with explicit token
ansible-playbook ... -e "onepassword_service_account_token=$OP_SERVICE_ACCOUNT_TOKEN"
```

---

## Rollback Plan

If test fails catastrophically and you need to restore quickly:

### Option 1: Keep Current State
```bash
# Don't destroy - debug and fix issues
# VMs still exist, just need configuration fixes
```

### Option 2: Restore from Snapshots (if created)
```bash
# Restore VM snapshots in Proxmox UI
# Datacenter > VM > Snapshots > Restore
```

### Option 3: Rebuild from Last Known Good State
```bash
# Checkout last known good commit
git log --oneline
git checkout <commit-hash>

# Run terraform apply with old config
terraform apply
```

---

## Post-Test Actions

### 1. Mark ClickUp Tasks as Complete ✅
If all tests pass:
- [ ] Mark all 7 subtasks as COMPLETE
- [ ] Mark parent task 86b7r74z8 as COMPLETE
- [ ] Add test results as comment to parent task

### 2. Update Documentation
- [ ] Update CLAUDE.md with any new learnings
- [ ] Update CONTROL-PLANE.md if architecture changed
- [ ] Document any issues encountered in TROUBLESHOOTING.md

### 3. Create Backup
- [ ] Export terraform state: `terraform state pull > terraform-state-backup.json`
- [ ] Document final IP assignments
- [ ] Backup 1Password vault

---

## Estimated Timeline

| Phase | Duration | Cumulative |
|-------|----------|------------|
| Pre-Test Checklist | 5 min | 5 min |
| Phase 1: Teardown | 5 min | 10 min |
| Phase 2: Terraform | 15 min | 25 min |
| Phase 3: Inventory | 2 min | 27 min |
| Phase 4: PostgreSQL | 8 min | 35 min |
| Phase 5: GitLab | 15 min | 50 min |
| Phase 6: Semaphore | 12 min | 62 min |
| Phase 7: Validation | 5 min | 67 min |
| Phase 8: Cleanup | 3 min | 70 min |

**Total Estimated Time**: ~70 minutes (1 hour 10 minutes)

**Actual time may vary** based on:
- Network speed (Ubuntu image download)
- Proxmox performance
- GitLab installation speed (slowest component)

---

## Quick Reference Commands

### Terraform
```bash
cd terraform/
terraform destroy                    # Teardown
terraform plan -out=tfplan          # Plan
terraform apply tfplan              # Apply
terraform output                    # Show outputs
```

### Ansible
```bash
cd ansible/
ansible all -i inventory/hosts.ini -m ping                           # Test connectivity
ansible-playbook -i inventory/hosts.ini playbooks/postgresql.yml    # PostgreSQL
ansible-playbook -i inventory/hosts.ini playbooks/gitlab.yml         # GitLab

# Semaphore bootstrap (token loaded from ~/.zprofile)
ansible-playbook -i inventory/bootstrap-semaphore.ini \
  playbooks/bootstrap-semaphore.yml \
  -e "onepassword_service_account_token=$OP_SERVICE_ACCOUNT_TOKEN"
```

### Validation
```bash
# Service status
ssh ansible@192.168.40.102 'systemctl status postgresql'
ssh ansible@192.168.40.98 'sudo gitlab-ctl status'
ssh ansible@192.168.40.26 'systemctl status semaphore'

# Web access
curl -I http://192.168.40.98          # GitLab
curl -I http://192.168.40.26:3000     # Semaphore
```

---

## Notes Section (Fill in during test)

**Start Time**: ________________

**Issues Encountered**:
```
1.
2.
3.
```

**IP Assignments**:
```
semaphore-ui: ________________
gitlab: ________________
postgresql: ________________
```

**Test Result**: ☐ PASS  ☐ FAIL (with acceptable issues)  ☐ FAIL (critical)

**Follow-up Actions Needed**:
```
1.
2.
3.
```
