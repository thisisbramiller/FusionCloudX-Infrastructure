# FusionCloudX Infrastructure (Terraform + Ansible)

This repository is a starter scaffold that demonstrates a minimal Infrastructure-as-Code workflow using Terraform for provisioning and Ansible for configuration.

Quickstart

1. Install prerequisites:
   - Terraform (v1.0+)
   - Ansible (2.9+), or `ansible-core`

2. Initialize Terraform (run from PowerShell or your shell of choice):

```pwsh
terraform -chdir=terraform init
```

3. Plan Terraform (example using the example tfvars):

```pwsh
terraform -chdir=terraform plan -var-file=terraform/terraform.tfvars.example
```

4. Apply Terraform (careful — creates cloud resources):

```pwsh
terraform -chdir=terraform apply -var-file=terraform/terraform.tfvars.example
```

5. Run Ansible playbook against provisioned hosts (replace inventory or hosts as appropriate):

```pwsh
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/site.yml
```

Structure

- `terraform/` - Terraform root and example module
- `ansible/` - Ansible inventory, playbooks and roles
-- `scripts/` - (removed) No wrapper scripts — use direct CLI commands
- `ci/` - Example GitHub Actions workflow for basic lint/validate checks

Security

- Do not commit real credentials, AWS keys, or state files.
- Use a remote state backend for team projects (S3/State locking, etc.).

License

- Replace or add license as needed.
