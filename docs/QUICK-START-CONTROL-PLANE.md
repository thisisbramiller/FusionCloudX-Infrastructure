# Quick Start: Semaphore Control Plane

5-minute guide to get your Infrastructure Control Plane running.

## Prerequisites

- [ ] Proxmox is running
- [ ] Terraform and Ansible installed on workstation
- [ ] 1Password service account token ready
- [ ] SSH access to your homelab

## Step 1: Deploy Infrastructure (2 minutes)

```bash
cd terraform/
terraform apply
```

Get the semaphore-ui IP:
```bash
terraform output vm_ipv4_addresses
```

## Step 2: Run Bootstrap (3 minutes)

```bash
./scripts/bootstrap-control-plane.sh
```

Provide:
- Semaphore IP address
- 1Password service account token

Wait for completion (5-10 minutes).

## Step 3: Configure SSH Keys (2 minutes)

### GitHub Deploy Key

```bash
ssh ansible@SEMAPHORE_IP 'cat ~/.ssh/github_deploy_key.pub'
```

Add to: `https://github.com/thisisbramiller/FusionCloudX-Infrastructure/settings/keys`

### Proxmox SSH Access

```bash
ssh ansible@SEMAPHORE_IP 'cat ~/.ssh/proxmox_terraform_key.pub'
```

Add to Proxmox:
```bash
ssh root@zero.fusioncloudx.home
echo 'PUBLIC_KEY' >> /root/.ssh/authorized_keys
```

## Step 4: Configure Semaphore (5 minutes)

Open `http://SEMAPHORE_IP:3000`

### Create Admin User
- Username: `admin`
- Email: `admin@fusioncloudx.home`
- Password: (store in 1Password)

### Add Repository
Settings → Repositories → New:
- Name: `FusionCloudX Infrastructure`
- URL: `git@github.com:thisisbramiller/FusionCloudX-Infrastructure.git`
- Branch: `main`
- SSH Key: Select deploy key

### Add Environment
Settings → Environments → New:
- Name: `Production`
- Variables:
```json
{
  "ANSIBLE_HOST_KEY_CHECKING": "False",
  "TF_VAR_proxmox_api_url": "https://zero.fusioncloudx.home:8006"
}
```

### Add Inventory
Settings → Inventory → New:
- Name: `Homelab`
- Type: `Static`
- Copy from: `ansible/inventory/hosts.ini`
- Update with actual IP addresses

## Step 5: Create Task Templates (3 minutes)

### Terraform Apply
- Name: `Deploy Infrastructure`
- Type: `Deploy`
- Override CLI: ✓
- Command:
```bash
cd /opt/infrastructure/terraform && terraform init && terraform apply -auto-approve
```

### Configure Hosts
- Name: `Configure All Hosts`
- Type: `Deploy`
- Repository: `FusionCloudX Infrastructure`
- Environment: `Production`
- Inventory: `Homelab`
- Playbook: `ansible/playbooks/site.yml`

## Step 6: Test It! (1 minute)

1. Click "Tasks"
2. Select "Configure All Hosts"
3. Click "Run Task"
4. Watch the magic happen!

---

## That's It!

You now have a fully functional Infrastructure Control Plane.

**Access**: `http://SEMAPHORE_IP:3000`

**Next**: Read [CONTROL-PLANE.md](./CONTROL-PLANE.md) for detailed documentation.

---

## Troubleshooting

**Can't SSH to semaphore-ui?**
```bash
# Check if VM is up
terraform output vm_ipv4_addresses

# Test SSH
ssh ansible@SEMAPHORE_IP
```

**Semaphore UI not loading?**
```bash
# Check service
ssh ansible@SEMAPHORE_IP 'sudo systemctl status semaphore'

# Check logs
ssh ansible@SEMAPHORE_IP 'sudo journalctl -u semaphore -f'
```

**1Password not working?**
```bash
# Test connection
ssh ansible@SEMAPHORE_IP 'op vault list'

# Check token
ssh ansible@SEMAPHORE_IP 'echo $OP_SERVICE_ACCOUNT_TOKEN'
```

---

**Full Documentation**: See [docs/CONTROL-PLANE.md](./CONTROL-PLANE.md)
