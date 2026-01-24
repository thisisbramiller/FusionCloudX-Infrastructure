# ==============================================================================
# 1Password Connect Test Script (PowerShell)
# ==============================================================================
# This script tests the 1Password Connect collection setup on Windows
# Run this after setting up authentication to verify everything works
# ==============================================================================

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "1Password Connect Test Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Test 1: Check if ansible is installed
Write-Host "Test 1: Checking Ansible installation..." -ForegroundColor Yellow
try {
    $ansibleVersion = ansible --version 2>&1 | Select-Object -First 1
    Write-Host "[OK] Ansible installed: $ansibleVersion" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] Ansible not found. Please install Ansible first." -ForegroundColor Red
    exit 1
}
Write-Host ""

# Test 2: Check environment variables
Write-Host "Test 2: Checking 1Password authentication..." -ForegroundColor Yellow
$authMethod = $null

if ($env:OP_SERVICE_ACCOUNT_TOKEN) {
    Write-Host "[OK] OP_SERVICE_ACCOUNT_TOKEN is set (Service Account method)" -ForegroundColor Green
    $authMethod = "service_account"
} elseif ($env:OP_CONNECT_HOST -and $env:OP_CONNECT_TOKEN) {
    Write-Host "[OK] OP_CONNECT_HOST and OP_CONNECT_TOKEN are set (Connect Server method)" -ForegroundColor Green
    Write-Host "   Connect Host: $env:OP_CONNECT_HOST" -ForegroundColor Gray
    $authMethod = "connect_server"
} else {
    Write-Host "[FAIL] No 1Password authentication found!" -ForegroundColor Red
    Write-Host "   Please set either:" -ForegroundColor Yellow
    Write-Host "   - `$env:OP_SERVICE_ACCOUNT_TOKEN (for Service Account)" -ForegroundColor Yellow
    Write-Host "   - `$env:OP_CONNECT_HOST and `$env:OP_CONNECT_TOKEN (for Connect Server)" -ForegroundColor Yellow
    exit 1
}
Write-Host ""

# Test 3: Check if collection requirements.yml exists
Write-Host "Test 3: Checking requirements.yml..." -ForegroundColor Yellow
if (Test-Path "requirements.yml") {
    Write-Host "[OK] requirements.yml found" -ForegroundColor Green
} else {
    Write-Host "[FAIL] requirements.yml not found" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Test 4: Install/verify collection
Write-Host "Test 4: Installing 1Password Connect collection..." -ForegroundColor Yellow
try {
    $null = ansible-galaxy collection install -r requirements.yml 2>&1
    Write-Host "[OK] Collection installed successfully" -ForegroundColor Green
} catch {
    Write-Host "[WARN] Collection installation had warnings (may already be installed)" -ForegroundColor Yellow
}
Write-Host ""

# Test 5: Verify collection is installed
Write-Host "Test 5: Verifying collection installation..." -ForegroundColor Yellow
$collectionList = ansible-galaxy collection list 2>&1 | Out-String
if ($collectionList -match "onepassword\.connect\s+([\d.]+)") {
    $collectionVersion = $matches[1]
    Write-Host "[OK] onepassword.connect collection found (version: $collectionVersion)" -ForegroundColor Green
} else {
    Write-Host "[FAIL] onepassword.connect collection not found" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Test 6: Test Connect Server health (if using Connect Server)
if ($authMethod -eq "connect_server") {
    Write-Host "Test 6: Testing Connect Server connectivity..." -ForegroundColor Yellow
    try {
        $headers = @{
            "Authorization" = "Bearer $env:OP_CONNECT_TOKEN"
        }
        $healthCheck = Invoke-RestMethod -Uri "$env:OP_CONNECT_HOST/health" -Headers $headers -Method Get
        if ($healthCheck.name -like "*1Password Connect*") {
            Write-Host "[OK] Connect Server is reachable and healthy" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] Connect Server health check failed" -ForegroundColor Red
            Write-Host "   Response: $healthCheck" -ForegroundColor Gray
            exit 1
        }
    } catch {
        Write-Host "[FAIL] Connect Server health check failed" -ForegroundColor Red
        Write-Host "   Error: $_" -ForegroundColor Gray
        exit 1
    }
    Write-Host ""
}

# Test 7: Test lookup with Ansible
Write-Host "Test 7: Testing 1Password lookup..." -ForegroundColor Yellow
Write-Host "   Attempting to retrieve: PostgreSQL Admin (postgres)" -ForegroundColor Gray
Write-Host "   Vault: FusionCloudX Infrastructure" -ForegroundColor Gray

$lookupCmd = "ansible localhost -m debug -a `"msg={{ lookup('onepassword.connect.generic_item', 'PostgreSQL Admin (postgres)', field='password', vault='FusionCloudX Infrastructure') }}`""

try {
    $null = Invoke-Expression $lookupCmd 2>&1
    Write-Host "[OK] Successfully retrieved credential from 1Password" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] Failed to retrieve credential from 1Password" -ForegroundColor Red
    Write-Host "   This could mean:" -ForegroundColor Yellow
    Write-Host "   - Item 'PostgreSQL Admin (postgres)' doesn't exist in vault" -ForegroundColor Yellow
    Write-Host "   - Vault 'FusionCloudX Infrastructure' doesn't exist" -ForegroundColor Yellow
    Write-Host "   - Service Account doesn't have access to the vault" -ForegroundColor Yellow
    Write-Host "   - Authentication credentials are invalid" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   Run with verbose output to debug:" -ForegroundColor Yellow
    Write-Host "   $lookupCmd -vvv" -ForegroundColor Gray
    exit 1
}
Write-Host ""

# Test 8: Check inventory file
Write-Host "Test 8: Checking inventory configuration..." -ForegroundColor Yellow
if (Test-Path "inventory\hosts.ini") {
    Write-Host "[OK] inventory\hosts.ini found" -ForegroundColor Green
} else {
    Write-Host "[WARN] inventory\hosts.ini not found (may need to run update-inventory.ps1)" -ForegroundColor Yellow
}
Write-Host ""

# Test 9: Check host_vars
Write-Host "Test 9: Checking host_vars configuration..." -ForegroundColor Yellow
if (Test-Path "inventory\host_vars\postgresql.yml") {
    Write-Host "[OK] inventory\host_vars\postgresql.yml found" -ForegroundColor Green

    # Check if it's using the new syntax
    $content = Get-Content "inventory\host_vars\postgresql.yml" -Raw
    if ($content -match "onepassword\.connect\.generic_item") {
        Write-Host "[OK] Using official 1Password Connect collection syntax" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Not using official collection syntax (may need update)" -ForegroundColor Yellow
    }
} else {
    Write-Host "[WARN] inventory\host_vars\postgresql.yml not found" -ForegroundColor Yellow
}
Write-Host ""

# Test 10: Syntax check playbook
Write-Host "Test 10: Checking playbook syntax..." -ForegroundColor Yellow
if (Test-Path "playbooks\postgresql.yml") {
    try {
        $null = ansible-playbook playbooks\postgresql.yml --syntax-check 2>&1
        Write-Host "[OK] playbooks\postgresql.yml syntax is valid" -ForegroundColor Green
    } catch {
        Write-Host "[FAIL] playbooks\postgresql.yml has syntax errors" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[WARN] playbooks\postgresql.yml not found" -ForegroundColor Yellow
}
Write-Host ""

# Final summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "All tests passed!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Test connectivity: ansible postgresql -m ping" -ForegroundColor White
Write-Host "2. Run playbook (check mode): ansible-playbook playbooks\postgresql.yml --check" -ForegroundColor White
Write-Host "3. Run playbook: ansible-playbook playbooks\postgresql.yml" -ForegroundColor White
Write-Host ""
Write-Host "Authentication method: $authMethod" -ForegroundColor Cyan
Write-Host "Collection version: $collectionVersion" -ForegroundColor Cyan
Write-Host ""
Write-Host "For troubleshooting, see:" -ForegroundColor Yellow
Write-Host "- 1PASSWORD_MIGRATION.md" -ForegroundColor White
Write-Host "- ONEPASSWORD_QUICKSTART.md" -ForegroundColor White
Write-Host "- README.md" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
