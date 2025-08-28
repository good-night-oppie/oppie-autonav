#!/bin/bash
# ABOUTME: Interactive script to set up GitHub secrets for oppie-autonav

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

REPO="good-night-oppie/oppie-autonav"

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           GitHub Secrets Setup for Oppie AutoNav            ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if secrets already exist
echo -e "${YELLOW}Checking existing secrets...${NC}"
EXISTING_SECRETS=$(gh secret list --repo "$REPO" 2>/dev/null | awk '{print $1}' || true)

if [ -n "$EXISTING_SECRETS" ]; then
    echo -e "${GREEN}Found existing secrets:${NC}"
    echo "$EXISTING_SECRETS"
    echo ""
fi

# Check if we can copy from oppie-thunder
echo -e "${YELLOW}Option 1: Copy from oppie-thunder${NC}"
echo ""
echo "Since GitHub doesn't allow reading secret values via API,"
echo "you need to manually copy them."
echo ""
echo -e "${CYAN}Steps:${NC}"
echo "1. Open: https://github.com/good-night-oppie/oppie-thunder/settings/secrets/actions"
echo "2. Click on each secret and copy its value"
echo "3. Come back here and paste when prompted"
echo ""

read -p "Do you want to copy secrets from oppie-thunder? (y/n): " copy_thunder

if [ "$copy_thunder" = "y" ]; then
    echo ""
    echo "Please go to oppie-thunder and copy each secret value."
    echo "Then paste them here:"
    echo ""
    
    # CLAUDE_ACCESS_TOKEN
    echo -n "CLAUDE_ACCESS_TOKEN: "
    read -s CLAUDE_ACCESS_TOKEN
    echo ""
    if [ -n "$CLAUDE_ACCESS_TOKEN" ]; then
        gh secret set CLAUDE_ACCESS_TOKEN --repo "$REPO" --body "$CLAUDE_ACCESS_TOKEN"
        echo -e "${GREEN}✓ CLAUDE_ACCESS_TOKEN set${NC}"
    fi
    
    # CLAUDE_CODE_OAUTH_TOKEN
    echo -n "CLAUDE_CODE_OAUTH_TOKEN: "
    read -s CLAUDE_CODE_OAUTH_TOKEN
    echo ""
    if [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
        gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo "$REPO" --body "$CLAUDE_CODE_OAUTH_TOKEN"
        echo -e "${GREEN}✓ CLAUDE_CODE_OAUTH_TOKEN set${NC}"
    fi
    
    # CLAUDE_REFRESH_TOKEN
    echo -n "CLAUDE_REFRESH_TOKEN: "
    read -s CLAUDE_REFRESH_TOKEN
    echo ""
    if [ -n "$CLAUDE_REFRESH_TOKEN" ]; then
        gh secret set CLAUDE_REFRESH_TOKEN --repo "$REPO" --body "$CLAUDE_REFRESH_TOKEN"
        echo -e "${GREEN}✓ CLAUDE_REFRESH_TOKEN set${NC}"
    fi
    
    # CLAUDE_EXPIRES_AT
    echo -n "CLAUDE_EXPIRES_AT: "
    read CLAUDE_EXPIRES_AT
    if [ -n "$CLAUDE_EXPIRES_AT" ]; then
        gh secret set CLAUDE_EXPIRES_AT --repo "$REPO" --body "$CLAUDE_EXPIRES_AT"
        echo -e "${GREEN}✓ CLAUDE_EXPIRES_AT set${NC}"
    fi
    
    # SECRETS_ADMIN_PAT (optional)
    echo -n "SECRETS_ADMIN_PAT (optional, press Enter to skip): "
    read -s SECRETS_ADMIN_PAT
    echo ""
    if [ -n "$SECRETS_ADMIN_PAT" ]; then
        gh secret set SECRETS_ADMIN_PAT --repo "$REPO" --body "$SECRETS_ADMIN_PAT"
        echo -e "${GREEN}✓ SECRETS_ADMIN_PAT set${NC}"
    fi
fi

echo ""
echo -e "${YELLOW}Option 2: Use local Claude CLI tokens${NC}"
echo ""

# Check for local Claude tokens
if [ -f ~/.claude/auth.json ]; then
    echo -e "${GREEN}Found Claude auth file!${NC}"
    
    read -p "Use local Claude tokens? (y/n): " use_local
    
    if [ "$use_local" = "y" ]; then
        # Extract tokens from auth.json
        ACCESS_TOKEN=$(jq -r '.accessToken // empty' ~/.claude/auth.json)
        REFRESH_TOKEN=$(jq -r '.refreshToken // empty' ~/.claude/auth.json)
        EXPIRES_AT=$(jq -r '.expiresAt // empty' ~/.claude/auth.json)
        
        if [ -n "$ACCESS_TOKEN" ]; then
            gh secret set CLAUDE_ACCESS_TOKEN --repo "$REPO" --body "$ACCESS_TOKEN"
            gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo "$REPO" --body "$ACCESS_TOKEN"
            echo -e "${GREEN}✓ Access tokens set${NC}"
        fi
        
        if [ -n "$REFRESH_TOKEN" ]; then
            gh secret set CLAUDE_REFRESH_TOKEN --repo "$REPO" --body "$REFRESH_TOKEN"
            echo -e "${GREEN}✓ Refresh token set${NC}"
        fi
        
        if [ -n "$EXPIRES_AT" ]; then
            gh secret set CLAUDE_EXPIRES_AT --repo "$REPO" --body "$EXPIRES_AT"
            echo -e "${GREEN}✓ Expiry time set${NC}"
        fi
    fi
else
    echo "No local Claude auth found. Run 'claude auth' to authenticate."
fi

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}                         Verification${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Verify secrets
echo "Checking configured secrets..."
REQUIRED_SECRETS=(
    "CLAUDE_ACCESS_TOKEN"
    "CLAUDE_CODE_OAUTH_TOKEN"
    "CLAUDE_EXPIRES_AT"
    "CLAUDE_REFRESH_TOKEN"
)

ALL_SET=true
for SECRET in "${REQUIRED_SECRETS[@]}"; do
    if gh secret list --repo "$REPO" | grep -q "^$SECRET"; then
        echo -e "${GREEN}✓ $SECRET is configured${NC}"
    else
        echo -e "${RED}✗ $SECRET is NOT configured${NC}"
        ALL_SET=false
    fi
done

echo ""
if [ "$ALL_SET" = true ]; then
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         All secrets configured successfully! 🎉              ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Your PR reviews should now work automatically."
    echo "Test by commenting '@claude please review' on any PR."
else
    echo -e "${YELLOW}Some secrets are missing. PR reviews won't work until all are set.${NC}"
    echo ""
    echo "You can:"
    echo "1. Run this script again to set missing secrets"
    echo "2. Set them manually at: https://github.com/$REPO/settings/secrets/actions"
    echo "3. Use organization-level secrets for multiple repos"
fi