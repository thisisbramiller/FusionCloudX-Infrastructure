# ==============================================================================
# Update Ansible Inventory from Terraform Outputs (PowerShell)
# ==============================================================================
# This script extracts PostgreSQL LXC container IPs from Terraform and
# updates the Ansible inventory file
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

    if (-not $PostgresqlJson -or $PostgresqlJson -eq "{}") {
        Write-Host "Warning: No PostgreSQL containers found in Terraform outputs" -ForegroundColor Yellow
        Write-Host "Make sure you've run 'terraform apply' first" -ForegroundColor Yellow
        exit 1
    }

    # Parse JSON
    Write-Host "Parsing container information..." -ForegroundColor Blue
    $PostgresqlData = $PostgresqlJson | ConvertFrom-Json

    # Build inventory entries
    $PostgresqlEntries = @()
    foreach ($key in $PostgresqlData.PSObject.Properties.Name) {
        $container = $PostgresqlData.$key
        $ip = $container.ip -replace '/24$', ''
        $entry = "$key ansible_host=$ip"
        $PostgresqlEntries += $entry
    }

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
    $AddedEntries = $false

    foreach ($Line in $Lines) {
        if ($Line -match '^\[postgresql\]') {
            $NewLines += $Line
            $InPostgresql = $true
            continue
        }

        if ($Line -match '^\[.*\]' -and $InPostgresql) {
            # End of postgresql section - add entries if not already added
            if (-not $AddedEntries) {
                $NewLines += $PostgresqlEntries
                $AddedEntries = $true
            }
            $InPostgresql = $false
        }

        if ($InPostgresql) {
            # Skip old entries (non-comment lines that don't start with ansible_)
            if ($Line -match '^[a-zA-Z]' -and $Line -notmatch '^#' -and $Line -notmatch '^ansible_') {
                continue
            }
            # Keep comments and variable definitions
            if ($Line -match '^#' -or $Line -match '^ansible_' -or $Line.Trim() -eq '') {
                $NewLines += $Line
            }
        } else {
            $NewLines += $Line
        }
    }

    # If we're still in postgresql section at end of file
    if ($InPostgresql -and -not $AddedEntries) {
        $NewLines += $PostgresqlEntries
    }

    # Write updated inventory
    $NewLines -join "`n" | Set-Content $InventoryFile -NoNewline

    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Inventory update complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "PostgreSQL containers added:" -ForegroundColor White
    $PostgresqlEntries | ForEach-Object { Write-Host $_ }
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Blue
    Write-Host "1. Review the updated inventory: cat $InventoryFile"
    Write-Host "2. Test connectivity: ansible postgresql -m ping"
    Write-Host "3. Deploy PostgreSQL: ansible-playbook playbooks/postgresql.yml"
    Write-Host ""

} finally {
    Pop-Location
}
