#!/bin/bash
# SPDX-FileCopyrightText: 2025 Good Night Oppie
# SPDX-License-Identifier: MIT

# Installation script for PR Review Monitoring hooks
# Adds PostToolUse hooks for comprehensive automation

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CLAUDE_HOOKS_CONFIG="$HOME/.config/claude-code/hooks.json"
BACKUP_DIR="$HOME/.config/claude-code/backups"
SCRIPTS_DIR="$(dirname "$0")"

echo -e "${BLUE}=== PR Review Monitoring Hooks Installation ===${NC}"
echo ""

# Check dependencies
echo "Checking dependencies..."
for script in pr-review-monitor.sh unified-automation.sh ci-monitor-optimized.sh; do
    if [ ! -f "$SCRIPTS_DIR/$script" ]; then
        echo -e "${RED}❌ Error: $script not found${NC}"
        exit 1
    fi
done

# Make scripts executable
echo "Making scripts executable..."
chmod +x "$SCRIPTS_DIR"/*.sh

# Create backup
mkdir -p "$BACKUP_DIR"
if [ -f "$CLAUDE_HOOKS_CONFIG" ]; then
    BACKUP_FILE="$BACKUP_DIR/hooks.json.$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}📦 Backing up to: $BACKUP_FILE${NC}"
    cp "$CLAUDE_HOOKS_CONFIG" "$BACKUP_FILE"
else
    echo "Creating new hooks configuration..."
    mkdir -p "$(dirname "$CLAUDE_HOOKS_CONFIG")"
    echo '{"hooks": {}, "settings": {}}' > "$CLAUDE_HOOKS_CONFIG"
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}❌ Error: jq is required${NC}"
    exit 1
fi

# Update configuration
echo ""
echo -e "${BLUE}Installing PR monitoring hooks...${NC}"

CURRENT_CONFIG=$(cat "$CLAUDE_HOOKS_CONFIG")

# Add comprehensive PostToolUse hooks
UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | jq --arg dir "$SCRIPTS_DIR" '
    # Ensure hooks object exists
    .hooks = (.hooks // {}) |
    
    # Add/Update post-tool-use hooks
    .hooks["post-tool-use"] = (
        .hooks["post-tool-use"] // [] |
        
        # Remove old duplicates
        map(select(
            if .name then
                (.name | contains("PR Review Monitor") | not) and
                (.name | contains("Unified Automation") | not)
            else
                true
            end
        )) +
        
        # Add PR monitoring for push commands
        [{
            "name": "PR Review Monitor - Git Push",
            "description": "Monitor PR reviews after git push",
            "enabled": true,
            "trigger": {
                "tool": "Bash",
                "pattern": "git push",
                "excludePatterns": ["--dry-run", "--help", "-n"]
            },
            "action": {
                "type": "script",
                "script": ($dir + "/unified-automation.sh"),
                "args": ["${CLAUDE_TOOL_INPUT}"],
                "timeout": 2,
                "background": true
            }
        },
        
        # Add PR creation monitoring
        {
            "name": "PR Review Monitor - PR Create",
            "description": "Setup monitoring after PR creation",
            "enabled": true,
            "trigger": {
                "tool": "Bash",
                "pattern": "gh pr create",
                "excludePatterns": ["--help"]
            },
            "action": {
                "type": "script",
                "script": ($dir + "/unified-automation.sh"),
                "args": ["${CLAUDE_TOOL_INPUT}"],
                "timeout": 5,
                "background": false
            }
        },
        
        # Add review request monitoring
        {
            "name": "PR Review Monitor - Claude Mention",
            "description": "Monitor when Claude review is requested",
            "enabled": true,
            "trigger": {
                "tool": "Bash",
                "pattern": "gh pr comment.*@claude",
                "excludePatterns": []
            },
            "action": {
                "type": "script",
                "script": ($dir + "/pr-review-monitor.sh"),
                "args": ["detect", "${CLAUDE_TOOL_INPUT}"],
                "timeout": 2,
                "background": true
            }
        },
        
        # Add CI status check with auto-monitoring
        {
            "name": "CI Status Monitor",
            "description": "Check CI status with auto-fix",
            "enabled": true,
            "trigger": {
                "tool": "Bash",
                "pattern": "gh (run|pr checks)",
                "excludePatterns": ["--help"]
            },
            "action": {
                "type": "script",
                "script": ($dir + "/unified-automation.sh"),
                "args": ["${CLAUDE_TOOL_INPUT}"],
                "timeout": 3,
                "background": false
            }
        }]
    ) |
    
    # Add pre-tool-use hook for status check
    .hooks["pre-tool-use"] = (
        .hooks["pre-tool-use"] // [] |
        
        # Remove old status check if exists
        map(select(
            if .name then
                (.name | contains("Automation Status") | not)
            else
                true
            end
        )) +
        
        [{
            "name": "Automation Status Check",
            "description": "Show automation status on request",
            "enabled": true,
            "trigger": {
                "tool": "Bash",
                "pattern": "automation status|monitor status",
                "excludePatterns": []
            },
            "action": {
                "type": "script",
                "script": ($dir + "/unified-automation.sh"),
                "args": ["status"],
                "timeout": 2,
                "background": false
            }
        }]
    ) |
    
    # Update settings
    .settings = (.settings // {}) |
    .settings.enableHooks = true |
    .settings.logHookExecutions = true |
    .settings.logPath = "/tmp/claude-code-hooks.log" |
    .settings.maxConcurrentHooks = 5 |
    .settings.prMonitoring = {
        "enabled": true,
        "autoRequestReview": true,
        "complexityThreshold": 7,
        "maxDebateRounds": 10,
        "checkInterval": 120
    }
')

# Write updated configuration
echo "$UPDATED_CONFIG" > "$CLAUDE_HOOKS_CONFIG"

echo -e "${GREEN}✅ Hooks configuration updated!${NC}"

# Verify installation
echo ""
echo -e "${BLUE}Verifying installation...${NC}"

if grep -q "pr-review-monitor\|unified-automation" "$CLAUDE_HOOKS_CONFIG"; then
    echo -e "${GREEN}✅ PR monitoring hooks installed${NC}"
else
    echo -e "${RED}❌ Installation verification failed${NC}"
    exit 1
fi

# Test the scripts
echo ""
echo -e "${BLUE}Testing scripts...${NC}"

# Test unified automation status
if "$SCRIPTS_DIR/unified-automation.sh" status 2>/dev/null; then
    echo -e "${GREEN}✅ Unified automation working${NC}"
else
    echo -e "${YELLOW}⚠️ Script test failed (may be normal on first run)${NC}"
fi

# Display summary
echo ""
echo -e "${GREEN}=== Installation Complete ===${NC}"
echo ""
echo "📋 Features Enabled:"
echo "  ✅ Automatic PR review monitoring after git push"
echo "  ✅ Claude review request for complex tasks (≥7/10)"
echo "  ✅ Automatic debate responses with evidence"
echo "  ✅ CI failure detection and auto-fix"
echo "  ✅ Unified status dashboard"
echo ""
echo "🚀 Automation Triggers:"
echo "  • git push → CI + PR monitoring"
echo "  • gh pr create → Auto-review request"
echo "  • @claude mention → Review monitoring"
echo "  • gh run/checks → CI status + auto-fix"
echo ""
echo "📝 Commands:"
echo "  • Check status: automation status"
echo "  • Clean cache: $SCRIPTS_DIR/unified-automation.sh clean"
echo "  • View logs: tail -f /tmp/unified-automation/unified.log"
echo ""
echo "🔧 Configuration:"
echo "  • Hooks config: $CLAUDE_HOOKS_CONFIG"
echo "  • Backup: $BACKUP_FILE"
echo ""
echo -e "${BLUE}The system will now automatically monitor and respond to:${NC}"
echo "  1. CI failures with auto-fix attempts"
echo "  2. Claude's PR review comments with evidence-based responses"
echo "  3. High-complexity tasks with specialized review personas"
echo "  4. Multi-round debates until approval"
echo ""
echo -e "${GREEN}Happy automated development! 🎉${NC}"