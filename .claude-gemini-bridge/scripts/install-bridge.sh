#!/bin/bash
# ABOUTME: Master installation script for Claude-Gemini Bridge with advanced hooks

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONAV_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAUDE_SETTINGS_FILE="$HOME/.claude/settings.json"
BACKUP_SUFFIX=$(date +%Y%m%d_%H%M%S)

# Parse arguments
INSTALL_MODE="project"  # project or global
TARGET_DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --global)
            INSTALL_MODE="global"
            TARGET_DIR="$HOME/.claude-gemini-bridge"
            shift
            ;;
        --project)
            INSTALL_MODE="project"
            TARGET_DIR="$(pwd)/.claude-gemini-bridge"
            shift
            ;;
        --target)
            TARGET_DIR="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--global|--project] [--target DIR]"
            echo ""
            echo "Options:"
            echo "  --global    Install globally in ~/.claude-gemini-bridge"
            echo "  --project   Install in current project (default)"
            echo "  --target    Specify custom installation directory"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set default target if not specified
if [ -z "$TARGET_DIR" ]; then
    if [ "$INSTALL_MODE" = "global" ]; then
        TARGET_DIR="$HOME/.claude-gemini-bridge"
    else
        TARGET_DIR="$(pwd)/.claude-gemini-bridge"
    fi
fi

echo -e "${MAGENTA}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║     🚀 Oppie AutoNav - Bridge Installation 🚀       ║${NC}"
echo -e "${MAGENTA}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to log with emoji
log() {
    local level=$1
    shift
    case $level in
        info) echo -e "${GREEN}✅${NC} $*" ;;
        warn) echo -e "${YELLOW}⚠️${NC}  $*" ;;
        error) echo -e "${RED}❌${NC} $*" ;;
        step) echo -e "${BLUE}▶${NC}  $*" ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    log step "Checking prerequisites..."
    
    local missing=()
    
    # Check required tools
    for tool in claude gemini gh jq; do
        if ! command -v $tool &> /dev/null; then
            missing+=($tool)
            log warn "$tool not found"
        else
            log info "$tool found: $(which $tool)"
        fi
    done
    
    # Check optional tools
    for tool in shellcheck npm python3; do
        if ! command -v $tool &> /dev/null; then
            log warn "$tool not found (optional)"
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log error "Missing required tools: ${missing[*]}"
        echo ""
        echo "Installation instructions:"
        echo "  claude: npm install -g @anthropic-ai/claude-code"
        echo "  gemini: https://github.com/google/generative-ai-cli"
        echo "  gh: https://cli.github.com/"
        echo "  jq: sudo apt-get install jq (Ubuntu) or brew install jq (Mac)"
        exit 1
    fi
    
    log info "All prerequisites met"
}

# Backup existing settings
backup_settings() {
    if [ -f "$CLAUDE_SETTINGS_FILE" ]; then
        local backup_file="${CLAUDE_SETTINGS_FILE}.backup.${BACKUP_SUFFIX}"
        cp "$CLAUDE_SETTINGS_FILE" "$backup_file"
        log info "Settings backed up to: $backup_file"
    else
        mkdir -p "$(dirname "$CLAUDE_SETTINGS_FILE")"
        echo '{"hooks": {}}' > "$CLAUDE_SETTINGS_FILE"
        log warn "Created new Claude settings file"
    fi
}

# Copy bridge files
install_bridge_files() {
    log step "Installing bridge files to: $TARGET_DIR"
    
    # Create target directory
    mkdir -p "$TARGET_DIR"
    
    # Copy essential directories
    for dir in hooks scripts test docs; do
        if [ -d "$AUTONAV_DIR/$dir" ]; then
            cp -r "$AUTONAV_DIR/$dir" "$TARGET_DIR/" 2>/dev/null || true
            log info "Copied $dir/"
        fi
    done
    
    # Copy configuration files
    for file in README.md LICENSE; do
        if [ -f "$AUTONAV_DIR/$file" ]; then
            cp "$AUTONAV_DIR/$file" "$TARGET_DIR/" 2>/dev/null || true
        fi
    done
    
    # Create working directories
    mkdir -p "$TARGET_DIR"/{cache/gemini,logs/debug,cache/pr-monitor}
    
    log info "Bridge files installed successfully"
}

# Configure Claude hooks
configure_hooks() {
    log step "Configuring Claude hooks..."
    
    local current_config=$(cat "$CLAUDE_SETTINGS_FILE")
    
    # Update configuration with both PreToolUse and PostToolUse hooks
    local updated_config=$(echo "$current_config" | jq --arg dir "$TARGET_DIR" '
        # Ensure hooks object exists
        .hooks = (.hooks // {}) |
        
        # Configure PreToolUse for Gemini delegation
        .hooks.PreToolUse = (.hooks.PreToolUse // []) |
        
        # Remove old gemini-bridge entries
        .hooks.PreToolUse |= map(select(
            if .hooks[]?.command then
                (.hooks[]?.command | contains("gemini-bridge.sh") | not)
            else
                true
            end
        )) |
        
        # Add Gemini delegation hook
        .hooks.PreToolUse += [{
            "matcher": "Read|Grep|Glob|Task",
            "hooks": [{
                "type": "command",
                "command": ($dir + "/hooks/gemini-bridge.sh"),
                "description": "Delegate large operations to Gemini"
            }]
        }] |
        
        # Configure PostToolUse for PR monitoring
        .hooks.PostToolUse = (.hooks.PostToolUse // []) |
        
        # Remove old PR monitoring entries
        .hooks.PostToolUse |= map(select(
            if .hooks[]?.command then
                (.hooks[]?.command | contains("pr-monitor.sh") | not) and
                (.hooks[]?.command | contains("unified-automation.sh") | not)
            else
                true
            end
        )) |
        
        # Add PR monitoring and automation hooks
        .hooks.PostToolUse += [
            {
                "matcher": "Bash",
                "hooks": [{
                    "type": "command",
                    "command": ($dir + "/hooks/unified-automation.sh \"${CLAUDE_TOOL_INPUT}\""),
                    "conditions": {
                        "patterns": [
                            "git push",
                            "gh pr create",
                            "gh pr comment.*@claude"
                        ]
                    },
                    "description": "Unified automation for PR and CI monitoring"
                }]
            }
        ]
    ')
    
    echo "$updated_config" > "$CLAUDE_SETTINGS_FILE"
    log info "Hooks configured successfully"
}

# Set up GitHub Actions
setup_github_actions() {
    log step "Setting up GitHub Actions workflows..."
    
    local project_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
    local workflows_dir="$project_root/.github/workflows"
    
    if [ "$project_root" = "$AUTONAV_DIR" ]; then
        log warn "Skipping GitHub Actions setup (in oppie-autonav itself)"
        return
    fi
    
    if [ -d "$workflows_dir" ]; then
        log warn "GitHub workflows directory already exists"
        read -p "Copy Claude PR review workflow? (y/N): " copy_workflow
        
        if [[ "$copy_workflow" =~ ^[Yy]$ ]]; then
            cp "$AUTONAV_DIR/.github/workflows/claude-pr-review.yml" "$workflows_dir/"
            log info "Copied Claude PR review workflow"
        fi
    else
        mkdir -p "$workflows_dir"
        cp "$AUTONAV_DIR/.github/workflows/claude-pr-review.yml" "$workflows_dir/"
        log info "Created GitHub Actions workflow"
    fi
    
    echo ""
    log warn "Remember to set GitHub secrets:"
    echo "  CLAUDE_CODE_OAUTH_TOKEN"
    echo "  CLAUDE_ACCESS_TOKEN (optional)"
    echo "  CLAUDE_REFRESH_TOKEN (optional)"
    echo "  SECRETS_ADMIN_PAT (optional)"
}

# Install OTW commands
install_otw_commands() {
    log step "Installing OTW workflow commands..."
    
    local claude_commands_dir="$HOME/.claude/commands"
    
    if [ -d "$claude_commands_dir/otw" ]; then
        log warn "OTW commands already exist"
        read -p "Update OTW commands? (y/N): " update_otw
        
        if [[ "$update_otw" =~ ^[Yy]$ ]]; then
            cp -r "$AUTONAV_DIR/.claude/commands/otw" "$claude_commands_dir/"
            log info "Updated OTW commands"
        fi
    else
        mkdir -p "$claude_commands_dir"
        cp -r "$AUTONAV_DIR/.claude/commands/otw" "$claude_commands_dir/"
        log info "Installed OTW commands"
    fi
}

# Verify installation
verify_installation() {
    log step "Verifying installation..."
    
    local errors=0
    
    # Check bridge files
    if [ -d "$TARGET_DIR" ]; then
        log info "Bridge directory exists"
    else
        log error "Bridge directory not found"
        errors=$((errors + 1))
    fi
    
    # Check hooks configuration
    if grep -q "gemini-bridge.sh" "$CLAUDE_SETTINGS_FILE"; then
        log info "Gemini delegation hook configured"
    else
        log error "Gemini delegation hook not configured"
        errors=$((errors + 1))
    fi
    
    if grep -q "unified-automation.sh" "$CLAUDE_SETTINGS_FILE"; then
        log info "PR monitoring hook configured"
    else
        log error "PR monitoring hook not configured"
        errors=$((errors + 1))
    fi
    
    # Test Gemini connection
    if echo "test" | gemini -p "respond with ok" &> /dev/null; then
        log info "Gemini connection working"
    else
        log warn "Gemini connection failed (check API key)"
    fi
    
    if [ $errors -eq 0 ]; then
        log info "Installation verified successfully!"
        return 0
    else
        log error "Installation verification failed with $errors errors"
        return 1
    fi
}

# Create helper aliases
create_aliases() {
    log step "Creating helper aliases..."
    
    local alias_file="$TARGET_DIR/aliases.sh"
    cat > "$alias_file" << EOF
#!/bin/bash
# Oppie AutoNav helper aliases

# PR monitoring
alias autonav-pr-monitor='$TARGET_DIR/hooks/pr-review/pr-monitor.sh monitor'
alias autonav-pr-request='$TARGET_DIR/hooks/pr-review/pr-monitor.sh request'
alias autonav-pr-status='$TARGET_DIR/hooks/pr-review/pr-monitor.sh status'
alias autonav-pr-stop='$TARGET_DIR/hooks/pr-review/pr-monitor.sh stop'

# Cache management
alias autonav-cache-clear='rm -rf $TARGET_DIR/cache/gemini/*'
alias autonav-cache-size='du -sh $TARGET_DIR/cache'

# Log viewing
alias autonav-logs='tail -f $TARGET_DIR/logs/debug/\$(date +%Y%m%d).log'
alias autonav-pr-logs='tail -f $TARGET_DIR/logs/pr-monitor.log'

# Testing
alias autonav-test='$TARGET_DIR/test/test-runner.sh'
alias autonav-verify='$TARGET_DIR/scripts/verify-installation.sh'

echo "Oppie AutoNav aliases loaded"
EOF
    
    chmod +x "$alias_file"
    log info "Helper aliases created: source $alias_file"
}

# Display summary
display_summary() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           ✅ Installation Complete! ✅               ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "📋 Installation Summary:"
    echo "  • Mode: $INSTALL_MODE"
    echo "  • Location: $TARGET_DIR"
    echo "  • Hooks: Configured in $CLAUDE_SETTINGS_FILE"
    echo ""
    echo "🚀 Features Enabled:"
    echo "  ✓ Gemini delegation for large operations"
    echo "  ✓ Automatic PR review monitoring"
    echo "  ✓ Multi-round debate protocol"
    echo "  ✓ CI/CD status tracking"
    echo "  ✓ Evidence-based responses"
    echo ""
    echo "📝 Next Steps:"
    echo ""
    echo "1. Load helper aliases:"
    echo -e "   ${BLUE}source $TARGET_DIR/aliases.sh${NC}"
    echo ""
    echo "2. Configure API keys (if not done):"
    echo -e "   ${BLUE}export GEMINI_API_KEY='your-key'${NC}"
    echo ""
    echo "3. Test the installation:"
    echo -e "   ${BLUE}$TARGET_DIR/scripts/verify-installation.sh${NC}"
    echo ""
    echo "4. Create your first PR with review:"
    echo -e "   ${BLUE}git checkout -b feature/test${NC}"
    echo -e "   ${BLUE}# make changes${NC}"
    echo -e "   ${BLUE}git commit -m 'feat: Test\n\nComplexity: 7/10'${NC}"
    echo -e "   ${BLUE}git push origin feature/test${NC}"
    echo -e "   ${BLUE}gh pr create${NC}"
    echo -e "   ${BLUE}gh pr comment --body '@claude please review'${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  Remember to restart Claude Code for hooks to take effect!${NC}"
    echo ""
    echo -e "${MAGENTA}🎉 Welcome to Oppie AutoNav - Automate Everything! 🎉${NC}"
}

# Main installation flow
main() {
    check_prerequisites
    backup_settings
    install_bridge_files
    configure_hooks
    setup_github_actions
    install_otw_commands
    create_aliases
    verify_installation
    display_summary
}

# Run installation
main "$@"