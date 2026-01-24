# ==============================================================================
# Update Ansible Inventory from Terraform Outputs (PowerShell)
# ==============================================================================
# This script extracts the PostgreSQL LXC container IP from Terraform and
# updates the Ansible inventory file
# Note: Single PostgreSQL container hosting multiple databases
# ==============================================================================

$ErrorActionPreference = "Stop"

# Paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$TerraformDir = Join-Path $ProjectRoot "terraform"
$InventoryFile = Join-Path $ScriptDir "inventory\hosts.ini"

Write-Host "========================================" -ForegroundColor Blue
Write-Host "Updating Ansible Inventory from Terraform" -ForegroundColor Blue
Write-Host "========================================" -ForegroundColor Blue
Write-Host "Single PostgreSQL container architecture" -ForegroundColor Blue
Write-Host "========================================" -ForegroundColor Blue

# Check if terraform directory exists
if (-not (Test-Path $TerraformDir)) {
    Write-Host "Error: Terraform directory not found at $TerraformDir" -ForegroundColor Red
    exit 1
}

# Change to terraform directory
Push-Location $TerraformDir

try {
    # Check if terraform is initialized
    if (-not (Test-Path ".terraform")) {
        Write-Host "Terraform not initialized. Running terraform init..." -ForegroundColor Yellow
        terraform init
    }

    # Get Terraform outputs
    Write-Host "Fetching Terraform outputs..." -ForegroundColor Blue

    $PostgresqlJson = terraform output -json ansible_inventory_postgresql 2>$null

    if (-not $PostgresqlJson -or $PostgresqlJson -eq "{}" -or $PostgresqlJson -eq "null") {
        Write-Host "Warning: PostgreSQL container not found in Terraform outputs" -ForegroundColor Yellow
        Write-Host "Make sure you've run 'terraform apply' first" -ForegroundColor Yellow
        exit 1
    }

    # Parse JSON
    Write-Host "Parsing container information..." -ForegroundColor Blue
    $PostgresqlData = $PostgresqlJson | ConvertFrom-Json

    $Hostname = $PostgresqlData.hostname
    $IP = $PostgresqlData.ip -replace '/24$', ''
    $VmId = $PostgresqlData.vm_id
    $Databases = ($PostgresqlData.databases.name -join ', ')

    Write-Host "Found PostgreSQL container:" -ForegroundColor Green
    Write-Host "  Hostname: $Hostname"
    Write-Host "  IP: $IP"
    Write-Host "  VM ID: $VmId"
    Write-Host "  Databases: $Databases"

    # Create inventory entry
    $PostgresqlEntry = "$Hostname ansible_host=$IP"

    # Read current inventory
    $InventoryContent = Get-Content $InventoryFile -Raw

    # Backup original inventory
    $BackupFile = "$InventoryFile.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $InventoryFile $BackupFile
    Write-Host "Created backup: $BackupFile" -ForegroundColor Green

    # Update the [postgresql] section
    Write-Host "Updating inventory file..." -ForegroundColor Blue

    $Lines = $InventoryContent -split "`r?`n"
    $NewLines = @()
    $InPostgresql = $false
    $AddedEntry = $false

    foreach ($Line in $Lines) {
        if ($Line -match '^\[postgresql\]') {
            $NewLines += $Line
            $InPostgresql = $true
            continue
        }

        if ($Line -match '^\[.*\]' -and $InPostgresql) {
            # End of postgresql section - add entry if not already added
            if (-not $AddedEntry) {
                $NewLines += $PostgresqlEntry
                $AddedEntry = $true
            }
            $InPostgresql = $false
        }

        if ($InPostgresql) {
            # Keep comments, blank lines, and ansible_ variables
            if ($Line -match '^#' -or $Line.Trim() -eq '' -or $Line -match '^ansible_') {
                $NewLines += $Line
            }
            # Skip old host entries (non-comment, non-blank, non-ansible_ lines)
            elseif ($Line -match '^[a-zA-Z]' -and $Line -notmatch '^ansible_') {
                continue
            }
            else {
                $NewLines += $Line
            }
        } else {
            $NewLines += $Line
        }
    }

    # If we're still in postgresql section at end of file
    if ($InPostgresql -and -not $AddedEntry) {
        $NewLines += $PostgresqlEntry
    }

    # Write updated inventory
    $NewLines -join "`n" | Set-Content $InventoryFile -NoNewline

    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Inventory update complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "PostgreSQL container added:" -ForegroundColor White
    Write-Host "  $PostgresqlEntry"
    Write-Host "  (Hosting databases: $Databases)"
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Blue
    Write-Host "1. Review the updated inventory: cat $InventoryFile"
    Write-Host "2. Test connectivity: ansible postgresql -m ping"
    Write-Host "3. Deploy PostgreSQL: ansible-playbook playbooks/postgresql.yml"
    Write-Host ""
    Write-Host "Important:" -ForegroundColor Yellow
    Write-Host "- This is a SINGLE container hosting MULTIPLE databases"
    Write-Host "- Ensure 1Password CLI is installed and authenticated"
    Write-Host "- Database credentials are managed via 1Password"
    Write-Host ""

} finally {
    Pop-Location
}
