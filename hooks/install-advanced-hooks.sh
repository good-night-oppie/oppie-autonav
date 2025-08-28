#!/bin/bash
# ABOUTME: Install advanced PR review and CI monitoring hooks for Claude-Gemini Bridge

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CLAUDE_SETTINGS_FILE="$HOME/.claude/settings.json"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SUFFIX=$(date +%Y%m%d_%H%M%S)

echo -e "${BLUE}=== Claude-Gemini Bridge Advanced Hooks Installation ===${NC}"
echo ""

# Check dependencies
echo "Checking dependencies..."
for dep in jq gh shellcheck; do
    if ! command -v $dep &> /dev/null; then
        echo -e "${YELLOW}⚠️  Warning: $dep not found${NC}"
        echo "   Some features may not work without $dep"
    fi
done

# Make scripts executable
echo "Making scripts executable..."
chmod +x "$SCRIPTS_DIR"/*.sh
chmod +x "$SCRIPTS_DIR"/pr-review/*.sh 2>/dev/null || true
chmod +x "$SCRIPTS_DIR"/lib/*.sh 2>/dev/null || true

# Backup existing settings
if [ -f "$CLAUDE_SETTINGS_FILE" ]; then
    cp "$CLAUDE_SETTINGS_FILE" "${CLAUDE_SETTINGS_FILE}.backup.${BACKUP_SUFFIX}"
    echo -e "${GREEN}✅ Settings backed up${NC}"
else
    echo -e "${YELLOW}⚠️  No existing Claude settings found${NC}"
    mkdir -p "$(dirname "$CLAUDE_SETTINGS_FILE")"
    echo '{"hooks": {}}' > "$CLAUDE_SETTINGS_FILE"
fi

# Function to update settings
update_claude_settings() {
    local current_config=$(cat "$CLAUDE_SETTINGS_FILE")
    
    # Add PostToolUse hooks for PR monitoring
    local updated_config=$(echo "$current_config" | jq --arg dir "$SCRIPTS_DIR" '
        # Ensure hooks object exists
        .hooks = (.hooks // {}) |
        
        # Add PostToolUse hooks
        .hooks.PostToolUse = (.hooks.PostToolUse // []) |
        
        # Remove old PR monitoring hooks if they exist
        .hooks.PostToolUse |= map(select(
            if .hooks[]?.command then
                (.hooks[]?.command | contains("pr-monitor.sh") | not)
            else
                true
            end
        )) |
        
        # Add PR monitoring hooks
        .hooks.PostToolUse += [
            {
                "matcher": "Bash",
                "hooks": [
                    {
                        "type": "command",
                        "command": ($dir + "/pr-review/pr-monitor.sh detect \"${CLAUDE_TOOL_INPUT}\""),
                        "conditions": {
                            "patterns": [
                                "git push.*origin",
                                "gh pr create",
                                "gh pr comment.*@claude"
                            ],
                            "excludePatterns": [
                                "--dry-run",
                                "--help"
                            ]
                        },
                        "description": "Monitor PR reviews and CI status"
                    }
                ]
            }
        ] |
        
        # Ensure PreToolUse hooks still exist for Gemini delegation
        .hooks.PreToolUse = (.hooks.PreToolUse // [])
    ')
    
    echo "$updated_config" > "$CLAUDE_SETTINGS_FILE"
}

# Update settings
echo ""
echo -e "${BLUE}Updating Claude settings with advanced hooks...${NC}"
update_claude_settings

# Verify installation
echo ""
echo -e "${BLUE}Verifying installation...${NC}"

if grep -q "pr-monitor.sh" "$CLAUDE_SETTINGS_FILE"; then
    echo -e "${GREEN}✅ PR monitoring hook installed${NC}"
else
    echo -e "${RED}❌ PR monitoring hook installation failed${NC}"
fi

if grep -q "gemini-bridge.sh" "$CLAUDE_SETTINGS_FILE"; then
    echo -e "${GREEN}✅ Gemini delegation hook present${NC}"
else
    echo -e "${YELLOW}⚠️  Gemini delegation hook not found${NC}"
fi

# Create helper aliases
ALIASES_FILE="$SCRIPTS_DIR/aliases.sh"
cat > "$ALIASES_FILE" << 'EOF'
#!/bin/bash
# Claude-Gemini Bridge helper aliases

# PR monitoring commands
alias cgb-pr-monitor='$SCRIPTS_DIR/pr-review/pr-monitor.sh monitor'
alias cgb-pr-request='$SCRIPTS_DIR/pr-review/pr-monitor.sh request'
alias cgb-pr-status='$SCRIPTS_DIR/pr-review/pr-monitor.sh status'
alias cgb-pr-stop='$SCRIPTS_DIR/pr-review/pr-monitor.sh stop'

# Cache management
alias cgb-cache-clear='rm -rf $SCRIPTS_DIR/../cache/gemini/*'
alias cgb-cache-size='du -sh $SCRIPTS_DIR/../cache'

# Log viewing
alias cgb-logs='tail -f $SCRIPTS_DIR/../logs/debug/$(date +%Y%m%d).log'
alias cgb-pr-logs='tail -f $SCRIPTS_DIR/../logs/pr-monitor.log'

# Testing
alias cgb-test='$SCRIPTS_DIR/../test/test-runner.sh'

echo "Claude-Gemini Bridge aliases loaded"
EOF

chmod +x "$ALIASES_FILE"

# Display summary
echo ""
echo -e "${GREEN}=== Installation Complete ===${NC}"
echo ""
echo "📋 Summary:"
echo "  - Advanced hooks installed to: $CLAUDE_SETTINGS_FILE"
echo "  - Backup saved as: ${CLAUDE_SETTINGS_FILE}.backup.${BACKUP_SUFFIX}"
echo ""
echo "🚀 Features enabled:"
echo "  - Automatic PR review monitoring"
echo "  - Claude debate protocol with evidence collection"
echo "  - CI status monitoring and auto-fix attempts"
echo "  - Complexity-based reviewer personas"
echo "  - Multi-round debate handling"
echo ""
echo "📝 Usage:"
echo "  1. Create a PR: gh pr create"
echo "  2. Request review: gh pr comment <pr> --body '@claude please review'"
echo "  3. Monitor status: $SCRIPTS_DIR/pr-review/pr-monitor.sh status"
echo ""
echo "🔧 Helper aliases:"
echo "  Source this file to use shortcuts:"
echo "  source $ALIASES_FILE"
echo ""
echo "⚡ Quick commands:"
echo "  - Start monitoring: cgb-pr-monitor <pr_number> [complexity]"
echo "  - Request review: cgb-pr-request <pr_number> [complexity]"
echo "  - Check status: cgb-pr-status"
echo "  - View logs: cgb-pr-logs"
echo ""
echo -e "${YELLOW}⚠️  Remember to restart Claude Code for hooks to take effect!${NC}"
echo ""
echo -e "${BLUE}Advanced PR monitoring is now ready! 🎉${NC}"