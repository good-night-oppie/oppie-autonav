#!/bin/bash

# Script to verify Claude Code secrets are properly configured
# This checks both organization and repository level secrets

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

check_secret() {
    local secret_name=$1
    local scope=$2
    local target=$3
    
    if [ "$scope" == "org" ]; then
        if gh secret list --org "$target" 2>/dev/null | grep -q "^$secret_name"; then
            print_color "$GREEN" "  ✓ $secret_name is configured"
            return 0
        fi
    else
        if gh secret list --repo "$target" 2>/dev/null | grep -q "^$secret_name"; then
            print_color "$GREEN" "  ✓ $secret_name is configured"
            return 0
        fi
    fi
    
    print_color "$RED" "  ✗ $secret_name is NOT configured"
    return 1
}

verify_local_credentials() {
    local creds_file="$1"
    
    if [ -f "$creds_file" ]; then
        print_color "$GREEN" "✓ Found Claude credentials at: $creds_file"
        
        # Check if jq is available
        if command -v jq &> /dev/null; then
            # Extract and validate fields
            ACCESS_TOKEN=$(jq -r '.claudeAiOauth.accessToken' "$creds_file" 2>/dev/null)
            REFRESH_TOKEN=$(jq -r '.claudeAiOauth.refreshToken' "$creds_file" 2>/dev/null)
            EXPIRES_AT=$(jq -r '.claudeAiOauth.expiresAt' "$creds_file" 2>/dev/null)
            
            if [ "$ACCESS_TOKEN" != "null" ] && [ -n "$ACCESS_TOKEN" ]; then
                print_color "$GREEN" "  ✓ Access token present"
            else
                print_color "$RED" "  ✗ Access token missing"
            fi
            
            if [ "$REFRESH_TOKEN" != "null" ] && [ -n "$REFRESH_TOKEN" ]; then
                print_color "$GREEN" "  ✓ Refresh token present"
            else
                print_color "$RED" "  ✗ Refresh token missing"
            fi
            
            if [ "$EXPIRES_AT" != "null" ] && [ -n "$EXPIRES_AT" ]; then
                # Check if token is expired
                CURRENT_TIME=$(date +%s%3N)
                if [ "$CURRENT_TIME" -lt "$EXPIRES_AT" ]; then
                    print_color "$GREEN" "  ✓ Token is valid (not expired)"
                else
                    print_color "$YELLOW" "  ⚠ Token is expired (needs refresh)"
                fi
            else
                print_color "$RED" "  ✗ Expiry time missing"
            fi
        else
            print_color "$YELLOW" "  ⚠ Cannot validate contents (jq not installed)"
        fi
    else
        print_color "$RED" "✗ Claude credentials NOT found at: $creds_file"
        return 1
    fi
}

main() {
    print_color "$BLUE" "════════════════════════════════════════════════"
    print_color "$BLUE" "     Claude Code Secrets Verification Tool"
    print_color "$BLUE" "════════════════════════════════════════════════"
    echo
    
    # Check if gh CLI is available
    if ! command -v gh &> /dev/null; then
        print_color "$YELLOW" "⚠ GitHub CLI not installed - cannot check GitHub secrets"
        print_color "$YELLOW" "  Install from: https://cli.github.com/"
    else
        # Check if authenticated
        if ! gh auth status &> /dev/null; then
            print_color "$YELLOW" "⚠ Not authenticated with GitHub CLI"
            print_color "$YELLOW" "  Run: gh auth login"
        else
            # Get current repository or organization
            if [ -n "$1" ]; then
                TARGET="$1"
                SCOPE="$2"
            else
                # Try to detect current repo
                if git remote -v 2>/dev/null | grep -q "github.com"; then
                    REPO_URL=$(git remote get-url origin 2>/dev/null)
                    REPO=$(echo "$REPO_URL" | sed -E 's|.*github.com[/:]([^/]+/[^/]+).*|\1|' | sed 's/\.git$//')
                    print_color "$BLUE" "Checking repository: $REPO"
                    TARGET="$REPO"
                    SCOPE="repo"
                else
                    print_color "$YELLOW" "No repository detected. Please specify:"
                    read -p "Enter org name or repo (owner/repo): " TARGET
                    if [[ "$TARGET" == *"/"* ]]; then
                        SCOPE="repo"
                    else
                        SCOPE="org"
                    fi
                fi
            fi
            
            echo
            print_color "$BLUE" "Checking GitHub Secrets ($SCOPE: $TARGET):"
            print_color "$BLUE" "─────────────────────────────────────────"
            
            # Required secrets
            REQUIRED_SECRETS=(
                "CLAUDE_ACCESS_TOKEN"
                "CLAUDE_REFRESH_TOKEN"
                "CLAUDE_TOKEN_EXPIRY"
                "CLAUDE_CODE_OAUTH_TOKEN"
            )
            
            ALL_GOOD=true
            for secret in "${REQUIRED_SECRETS[@]}"; do
                if ! check_secret "$secret" "$SCOPE" "$TARGET"; then
                    ALL_GOOD=false
                fi
            done
            
            echo
            if [ "$ALL_GOOD" = true ]; then
                print_color "$GREEN" "✓ All required GitHub secrets are configured!"
            else
                print_color "$RED" "✗ Some GitHub secrets are missing"
                print_color "$YELLOW" "  Run: ./scripts/setup-claude-secrets.sh"
            fi
        fi
    fi
    
    echo
    print_color "$BLUE" "Checking Local Credentials:"
    print_color "$BLUE" "─────────────────────────────────────────"
    
    # Check multiple possible locations
    CRED_LOCATIONS=(
        "$HOME/.claude/credentials.json"
        "$HOME/.claude/.credentials.json"
        "/root/.claude/credentials.json"
        "/root/.claude/.credentials.json"
    )
    
    FOUND_CREDS=false
    for location in "${CRED_LOCATIONS[@]}"; do
        if [ -f "$location" ]; then
            verify_local_credentials "$location"
            FOUND_CREDS=true
            break
        fi
    done
    
    if [ "$FOUND_CREDS" = false ]; then
        print_color "$RED" "✗ No local Claude credentials found"
        print_color "$YELLOW" "  Expected locations:"
        for location in "${CRED_LOCATIONS[@]}"; do
            print_color "$YELLOW" "    - $location"
        done
    fi
    
    echo
    print_color "$BLUE" "Checking Workflow Files:"
    print_color "$BLUE" "─────────────────────────────────────────"
    
    WORKFLOW_DIR=".github/workflows"
    if [ -d "$WORKFLOW_DIR" ]; then
        if [ -f "$WORKFLOW_DIR/claude-self-hosted.yml" ]; then
            print_color "$GREEN" "✓ claude-self-hosted.yml exists"
        else
            print_color "$RED" "✗ claude-self-hosted.yml not found"
        fi
        
        if [ -f "$WORKFLOW_DIR/claude-pr-review.yml" ]; then
            print_color "$GREEN" "✓ claude-pr-review.yml exists"
        else
            print_color "$YELLOW" "⚠ claude-pr-review.yml not found"
        fi
    else
        print_color "$RED" "✗ Workflow directory not found"
    fi
    
    echo
    print_color "$BLUE" "════════════════════════════════════════════════"
    print_color "$BLUE" "              Verification Complete"
    print_color "$BLUE" "════════════════════════════════════════════════"
    echo
    
    # Summary and recommendations
    print_color "$YELLOW" "Recommendations:"
    if [ "$FOUND_CREDS" = false ]; then
        print_color "$YELLOW" "1. Set up Claude credentials locally:"
        print_color "$YELLOW" "   npm install -g @anthropic-ai/claude-code"
        print_color "$YELLOW" "   claude auth"
    fi
    
    if [ "$ALL_GOOD" = false ] 2>/dev/null; then
        print_color "$YELLOW" "2. Configure GitHub secrets:"
        print_color "$YELLOW" "   ./scripts/setup-claude-secrets.sh"
    fi
    
    print_color "$YELLOW" "3. Ensure self-hosted runner has tags:"
    print_color "$YELLOW" "   self-hosted, linux, claude-runner"
}

# Run with optional org/repo argument
main "$@"