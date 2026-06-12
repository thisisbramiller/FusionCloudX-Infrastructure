#!/bin/bash
# ==============================================================================
# FusionCloudX Infrastructure - Status Check
# ==============================================================================
# This script provides a quick overview of your infrastructure status
#
# Stack: OpenTofu (3 remote states: network -> opconnect -> compute) + an
# OpenTofu-state-backed Ansible dynamic inventory. Remote state lives in S3
# with SSE-KMS, so every tofu/aws call needs a live AWS SSO session. This
# script is designed to run OFFLINE: a missing SSO session WARNS and the
# script still exits 0 — it never hard-fails on an expected-offline check.
# ==============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

warn() { echo -e "${YELLOW}⚠ $*${NC}"; }

echo -e "${CYAN}"
echo "========================================"
echo "  FusionCloudX Infrastructure Status"
echo "========================================"
echo -e "${NC}"

# Track whether any remote state is empty so [5/5] can recommend an apply.
STATE_EMPTY=0
SSO_LIVE=0

# ------------------------------------------------------------------------------
# [1/5] Toolchain + AWS SSO session
# ------------------------------------------------------------------------------
echo -e "${BLUE}[1/5] Checking toolchain + AWS SSO...${NC}"

if ! command -v tofu >/dev/null 2>&1; then
    echo -e "${RED}✗ OpenTofu (tofu) not found on PATH — install it: https://opentofu.org/docs/intro/install/${NC}"
    echo -e "${RED}  Aborting: the rest of this check needs the tofu binary.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ OpenTofu: $(tofu version | head -n1)${NC}"

# Repo-root CLI config so the patched UniFi provider resolves on CI / fresh
# machines (local devs auto-discover ~/.terraformrc — see .tofurc header).
export TF_CLI_CONFIG_FILE="$PWD/.tofurc"
echo -e "${CYAN}  TF_CLI_CONFIG_FILE=$TF_CLI_CONFIG_FILE${NC}"

if [ -z "${AWS_PROFILE:-}" ]; then
    warn "AWS_PROFILE is unset (expected: fcx-sso) — export AWS_PROFILE=fcx-sso"
else
    echo -e "${GREEN}✓ AWS_PROFILE=$AWS_PROFILE${NC}"
fi

# Guarded: a dead SSO session must WARN, never abort under set -e.
if aws sts get-caller-identity >/dev/null 2>&1; then
    SSO_LIVE=1
    echo -e "${GREEN}✓ AWS SSO session live${NC}"
else
    warn "AWS SSO session not live — run: aws sso login --profile fcx-sso"
fi

echo ""

# ------------------------------------------------------------------------------
# [2/5] Remote states (network -> opconnect -> compute)
# ------------------------------------------------------------------------------
echo -e "${BLUE}[2/5] Checking remote states...${NC}"

for STATE in network opconnect compute; do
    if tofu -chdir="tofu/$STATE" init -input=false >/dev/null 2>&1; then
        COUNT=$(tofu -chdir="tofu/$STATE" state list 2>/dev/null | wc -l | tr -d ' ')
        echo -e "${CYAN}  $STATE: $COUNT resources${NC}"
        if [ "$COUNT" -eq 0 ]; then
            STATE_EMPTY=1
        fi
    else
        # init failed (almost always a dead SSO session against the S3 backend).
        warn "$STATE: tofu init failed (S3 backend unreachable — likely no AWS SSO session)"
        STATE_EMPTY=1
    fi
done

echo ""

# ------------------------------------------------------------------------------
# [3/5] Compute infrastructure summary
# ------------------------------------------------------------------------------
echo -e "${BLUE}[3/5] Compute infrastructure summary...${NC}"

SUMMARY="$(tofu -chdir="tofu/compute" output -json infrastructure_summary 2>/dev/null || true)"
if [ -z "$SUMMARY" ] || [ "$SUMMARY" = "null" ]; then
    warn "No infrastructure_summary output (compute not applied, or no AWS SSO session)"
else
    # Pretty-print; tolerate null IPs (container not yet leased). Prefer jq,
    # fall back to python3, else dump the raw JSON.
    if command -v jq >/dev/null 2>&1; then
        echo "$SUMMARY" | jq -r '
            to_entries[]
            | "  \(.key): " +
              ( .value
                | if type == "object"
                  then "id=\(.vm_id // "?") host=\(.hostname // "?") ip=\(.ip // .ipv4 // "pending")"
                  else tostring
                  end )
        ' 2>/dev/null || echo "$SUMMARY"
    elif command -v python3 >/dev/null 2>&1; then
        echo "$SUMMARY" | python3 -m json.tool 2>/dev/null || echo "$SUMMARY"
    else
        echo "$SUMMARY"
    fi
fi

echo ""

# ------------------------------------------------------------------------------
# [4/5] Ansible dynamic inventory + connectivity
# ------------------------------------------------------------------------------
echo -e "${BLUE}[4/5] Checking Ansible dynamic inventory...${NC}"

if command -v ansible >/dev/null 2>&1; then
    # Dynamic inventory reads OpenTofu compute state directly (no hosts.ini).
    if ansible-inventory -i ansible/inventory/ --list >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Dynamic inventory resolves (ansible/inventory/)${NC}"
    else
        warn "Dynamic inventory did not resolve (compute state empty, or no AWS SSO session)"
    fi

    echo -e "${CYAN}  Pinging postgresql group:${NC}"
    ansible -i ansible/inventory/ postgresql -m ping --one-line 2>/dev/null || echo -e "${YELLOW}    no hosts reachable${NC}"
else
    warn "Ansible not installed"
fi

echo ""

# ------------------------------------------------------------------------------
# [5/5] Recommended next steps
# ------------------------------------------------------------------------------
echo -e "${BLUE}[5/5] Recommended next steps:${NC}"

if [ "$SSO_LIVE" -eq 0 ]; then
    echo -e "${YELLOW}  → Start an AWS SSO session: aws sso login --profile fcx-sso${NC}"
fi

if [ "$STATE_EMPTY" -eq 1 ]; then
    echo -e "${YELLOW}  → Apply states in order:${NC}"
    echo -e "${YELLOW}      tofu -chdir=tofu/network init   && tofu -chdir=tofu/network apply${NC}"
    echo -e "${YELLOW}      tofu -chdir=tofu/opconnect init && tofu -chdir=tofu/opconnect apply${NC}"
    echo -e "${YELLOW}      tofu -chdir=tofu/compute init   && tofu -chdir=tofu/compute apply${NC}"
else
    echo -e "${GREEN}  ✓ Infrastructure looks good!${NC}"
    echo -e "${CYAN}  → Deploy PostgreSQL: ansible-playbook -i ansible/inventory/ ansible/playbooks/postgresql.yml${NC}"
fi

echo ""
echo -e "${CYAN}========================================"
echo "For detailed documentation, see:"
echo "  - README.md"
echo "  - CLAUDE.md"
echo "  - docs/runbooks/opconnect-cutover.md"
echo -e "========================================${NC}"
echo ""
