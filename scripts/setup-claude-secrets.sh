#!/bin/bash

# Script to set up Claude Code organization secrets for GitHub Actions
# This script helps configure the necessary secrets for self-hosted Claude Code reviews

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Function to check if gh CLI is installed
check_gh_cli() {
    if ! command -v gh &> /dev/null; then
        print_color "$RED" "Error: GitHub CLI (gh) is not installed."
        print_color "$YELLOW" "Please install it from: https://cli.github.com/"
        exit 1
    fi
}

# Function to check if user is authenticated with gh
check_gh_auth() {
    if ! gh auth status &> /dev/null; then
        print_color "$RED" "Error: You are not authenticated with GitHub CLI."
        print_color "$YELLOW" "Please run: gh auth login"
        exit 1
    fi
}

# Function to extract credentials from local file
extract_credentials() {
    local creds_file="$HOME/.claude/credentials.json"
    
    # Check if credentials file exists
    if [ ! -f "$creds_file" ]; then
        print_color "$RED" "Error: Claude credentials file not found at $creds_file"
        print_color "$YELLOW" "Please ensure Claude Code is installed and authenticated:"
        print_color "$YELLOW" "  1. npm install -g @anthropic-ai/claude-code"
        print_color "$YELLOW" "  2. claude auth"
        exit 1
    fi
    
    # Extract tokens using jq
    if ! command -v jq &> /dev/null; then
        print_color "$RED" "Error: jq is not installed."
        print_color "$YELLOW" "Installing jq..."
        sudo apt-get update && sudo apt-get install -y jq
    fi
    
    ACCESS_TOKEN=$(jq -r '.claudeAiOauth.accessToken' "$creds_file")
    REFRESH_TOKEN=$(jq -r '.claudeAiOauth.refreshToken' "$creds_file")
    EXPIRES_AT=$(jq -r '.claudeAiOauth.expiresAt' "$creds_file")
    
    if [ "$ACCESS_TOKEN" == "null" ] || [ "$REFRESH_TOKEN" == "null" ]; then
        print_color "$RED" "Error: Could not extract tokens from credentials file"
        exit 1
    fi
    
    print_color "$GREEN" "Successfully extracted Claude credentials"
}

# Function to set organization secret
set_org_secret() {
    local secret_name=$1
    local secret_value=$2
    local org=$3
    
    print_color "$BLUE" "Setting organization secret: $secret_name"
    
    # Use gh secret set command for organization
    echo "$secret_value" | gh secret set "$secret_name" --org "$org" --visibility all
    
    if [ $? -eq 0 ]; then
        print_color "$GREEN" "✓ Successfully set $secret_name"
    else
        print_color "$RED" "✗ Failed to set $secret_name"
        return 1
    fi
}

# Function to set repository secret
set_repo_secret() {
    local secret_name=$1
    local secret_value=$2
    local repo=$3
    
    print_color "$BLUE" "Setting repository secret: $secret_name"
    
    # Use gh secret set command for repository
    echo "$secret_value" | gh secret set "$secret_name" --repo "$repo"
    
    if [ $? -eq 0 ]; then
        print_color "$GREEN" "✓ Successfully set $secret_name"
    else
        print_color "$RED" "✗ Failed to set $secret_name"
        return 1
    fi
}

# Main script
main() {
    print_color "$BLUE" "════════════════════════════════════════════════"
    print_color "$BLUE" "  Claude Code GitHub Secrets Configuration Tool"
    print_color "$BLUE" "════════════════════════════════════════════════"
    echo
    
    # Check prerequisites
    check_gh_cli
    check_gh_auth
    
    # Get organization/repository information
    print_color "$YELLOW" "Where do you want to set the secrets?"
    echo "1) Organization secrets (available to all repos)"
    echo "2) Repository secrets (specific repo only)"
    read -p "Choice (1 or 2): " choice
    
    case $choice in
        1)
            read -p "Enter organization name: " ORG_NAME
            if [ -z "$ORG_NAME" ]; then
                print_color "$RED" "Organization name cannot be empty"
                exit 1
            fi
            SECRET_SCOPE="organization"
            TARGET="$ORG_NAME"
            ;;
        2)
            read -p "Enter repository (owner/repo): " REPO_NAME
            if [ -z "$REPO_NAME" ]; then
                print_color "$RED" "Repository name cannot be empty"
                exit 1
            fi
            SECRET_SCOPE="repository"
            TARGET="$REPO_NAME"
            ;;
        *)
            print_color "$RED" "Invalid choice"
            exit 1
            ;;
    esac
    
    # Option to use provided credentials or extract from local
    print_color "$YELLOW" "Credential source:"
    echo "1) Use local Claude credentials (~/.claude/credentials.json)"
    echo "2) Enter credentials manually"
    read -p "Choice (1 or 2): " cred_choice
    
    case $cred_choice in
        1)
            extract_credentials
            ;;
        2)
            print_color "$YELLOW" "Enter Claude OAuth Access Token:"
            read -s ACCESS_TOKEN
            echo
            print_color "$YELLOW" "Enter Claude OAuth Refresh Token:"
            read -s REFRESH_TOKEN
            echo
            print_color "$YELLOW" "Enter Token Expiry (timestamp in milliseconds):"
            read EXPIRES_AT
            ;;
        *)
            print_color "$RED" "Invalid choice"
            exit 1
            ;;
    esac
    
    # Confirm before setting secrets
    print_color "$YELLOW" "Ready to set the following secrets in $SECRET_SCOPE '$TARGET':"
    echo "  - CLAUDE_ACCESS_TOKEN"
    echo "  - CLAUDE_REFRESH_TOKEN"
    echo "  - CLAUDE_TOKEN_EXPIRY"
    echo "  - CLAUDE_CODE_OAUTH_TOKEN (alias for ACCESS_TOKEN)"
    echo
    read -p "Proceed? (y/n): " confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        print_color "$YELLOW" "Operation cancelled"
        exit 0
    fi
    
    # Set the secrets
    print_color "$BLUE" "Setting secrets..."
    echo
    
    if [ "$SECRET_SCOPE" == "organization" ]; then
        set_org_secret "CLAUDE_ACCESS_TOKEN" "$ACCESS_TOKEN" "$TARGET"
        set_org_secret "CLAUDE_REFRESH_TOKEN" "$REFRESH_TOKEN" "$TARGET"
        set_org_secret "CLAUDE_TOKEN_EXPIRY" "$EXPIRES_AT" "$TARGET"
        set_org_secret "CLAUDE_CODE_OAUTH_TOKEN" "$ACCESS_TOKEN" "$TARGET"
    else
        set_repo_secret "CLAUDE_ACCESS_TOKEN" "$ACCESS_TOKEN" "$TARGET"
        set_repo_secret "CLAUDE_REFRESH_TOKEN" "$REFRESH_TOKEN" "$TARGET"
        set_repo_secret "CLAUDE_TOKEN_EXPIRY" "$EXPIRES_AT" "$TARGET"
        set_repo_secret "CLAUDE_CODE_OAUTH_TOKEN" "$ACCESS_TOKEN" "$TARGET"
    fi
    
    echo
    print_color "$GREEN" "════════════════════════════════════════════════"
    print_color "$GREEN" "  ✓ Claude Code secrets successfully configured!"
    print_color "$GREEN" "════════════════════════════════════════════════"
    echo
    print_color "$YELLOW" "Next steps:"
    print_color "$YELLOW" "1. The claude-self-hosted.yml workflow will now use these secrets"
    print_color "$YELLOW" "2. Self-hosted runners should be tagged with: self-hosted, linux, claude-runner"
    print_color "$YELLOW" "3. Test by creating a PR or commenting '@claude please review'"
    echo
    
    # Optional: Verify secrets were set
    print_color "$BLUE" "Verifying secrets..."
    if [ "$SECRET_SCOPE" == "organization" ]; then
        gh secret list --org "$TARGET" | grep -E "CLAUDE_" || true
    else
        gh secret list --repo "$TARGET" | grep -E "CLAUDE_" || true
    fi
}

# Run main function
main "$@"