#!/bin/bash
# ABOUTME: Verify Oppie AutoNav installation and diagnose issues

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Find installation directory
find_installation() {
    # Check project-local first
    if [ -d "./.claude-gemini-bridge" ]; then
        echo "./.claude-gemini-bridge"
    # Check global
    elif [ -d "$HOME/.claude-gemini-bridge" ]; then
        echo "$HOME/.claude-gemini-bridge"
    # Check if running from oppie-autonav
    elif [ -d "$(dirname "$0")/../hooks" ]; then
        echo "$(cd "$(dirname "$0")/.." && pwd)"
    else
        echo ""
    fi
}

INSTALL_DIR=$(find_installation)
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}  Oppie AutoNav Installation Verification${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""

# Track issues
ERRORS=0
WARNINGS=0

# Helper functions
check_pass() {
    echo -e "${GREEN}✅${NC} $1"
}

check_warn() {
    echo -e "${YELLOW}⚠️${NC}  $1"
    WARNINGS=$((WARNINGS + 1))
}

check_fail() {
    echo -e "${RED}❌${NC} $1"
    ERRORS=$((ERRORS + 1))
}

section() {
    echo ""
    echo -e "${BLUE}▶ $1${NC}"
    echo "─────────────────────────────────"
}

# Check installation directory
section "Installation Directory"
if [ -n "$INSTALL_DIR" ] && [ -d "$INSTALL_DIR" ]; then
    check_pass "Found installation: $INSTALL_DIR"
    
    # Check subdirectories
    for dir in hooks scripts test docs; do
        if [ -d "$INSTALL_DIR/$dir" ]; then
            check_pass "$dir/ directory exists"
        else
            check_warn "$dir/ directory missing"
        fi
    done
else
    check_fail "No installation found"
    echo "   Run: ./scripts/install-bridge.sh"
fi

# Check Claude settings
section "Claude Configuration"
if [ -f "$CLAUDE_SETTINGS" ]; then
    check_pass "Claude settings file exists"
    
    # Check hooks
    if grep -q "gemini-bridge.sh" "$CLAUDE_SETTINGS" 2>/dev/null; then
        check_pass "Gemini delegation hook configured"
    else
        check_fail "Gemini delegation hook not configured"
    fi
    
    if grep -q "unified-automation.sh\|pr-monitor.sh" "$CLAUDE_SETTINGS" 2>/dev/null; then
        check_pass "PR monitoring hook configured"
    else
        check_warn "PR monitoring hook not configured"
    fi
else
    check_fail "Claude settings file not found"
    echo "   Expected at: $CLAUDE_SETTINGS"
fi

# Check required tools
section "Required Tools"
for tool in claude gemini gh jq; do
    if command -v $tool &> /dev/null; then
        check_pass "$tool: $(which $tool)"
    else
        check_fail "$tool not found"
        case $tool in
            claude)
                echo "   Install: npm install -g @anthropic-ai/claude-code"
                ;;
            gemini)
                echo "   Install: https://github.com/google/generative-ai-cli"
                ;;
            gh)
                echo "   Install: https://cli.github.com/"
                ;;
            jq)
                echo "   Install: sudo apt-get install jq (Ubuntu) or brew install jq (Mac)"
                ;;
        esac
    fi
done

# Check optional tools
section "Optional Tools"
for tool in shellcheck npm python3 git; do
    if command -v $tool &> /dev/null; then
        check_pass "$tool: installed"
    else
        check_warn "$tool not found (optional)"
    fi
done

# Check API configuration
section "API Configuration"
if [ -n "${GEMINI_API_KEY:-}" ]; then
    check_pass "GEMINI_API_KEY is set"
    
    # Test Gemini connection
    if echo "test" | gemini -p "respond with ok" &> /dev/null; then
        check_pass "Gemini API connection working"
    else
        check_fail "Gemini API connection failed"
        echo "   Check your API key and network"
    fi
else
    check_warn "GEMINI_API_KEY not set"
    echo "   Export: export GEMINI_API_KEY='your-key'"
fi

# Check GitHub auth
if gh auth status &> /dev/null; then
    check_pass "GitHub CLI authenticated"
else
    check_warn "GitHub CLI not authenticated"
    echo "   Run: gh auth login"
fi

# Check hook scripts
section "Hook Scripts"
if [ -n "$INSTALL_DIR" ]; then
    # Check main hooks
    for script in "hooks/gemini-bridge.sh" "hooks/unified-automation.sh" "hooks/pr-review/pr-monitor.sh"; do
        if [ -f "$INSTALL_DIR/$script" ]; then
            if [ -x "$INSTALL_DIR/$script" ]; then
                check_pass "$script is executable"
            else
                check_fail "$script is not executable"
                echo "   Fix: chmod +x $INSTALL_DIR/$script"
            fi
        else
            check_fail "$script not found"
        fi
    done
fi

# Check cache and logs
section "Cache and Logs"
if [ -n "$INSTALL_DIR" ]; then
    # Check cache directory
    if [ -d "$INSTALL_DIR/cache" ]; then
        local cache_size=$(du -sh "$INSTALL_DIR/cache" 2>/dev/null | cut -f1)
        check_pass "Cache directory exists (Size: ${cache_size:-0})"
    else
        check_warn "Cache directory missing"
        echo "   Create: mkdir -p $INSTALL_DIR/cache/gemini"
    fi
    
    # Check logs directory
    if [ -d "$INSTALL_DIR/logs" ]; then
        local log_count=$(find "$INSTALL_DIR/logs" -name "*.log" 2>/dev/null | wc -l)
        check_pass "Logs directory exists ($log_count log files)"
    else
        check_warn "Logs directory missing"
        echo "   Create: mkdir -p $INSTALL_DIR/logs/debug"
    fi
fi

# Check GitHub Actions
section "GitHub Actions"
if [ -d ".git" ]; then
    if [ -f ".github/workflows/claude-pr-review.yml" ]; then
        check_pass "Claude PR review workflow exists"
        
        # Check for secrets
        echo "   Checking GitHub secrets..."
        for secret in CLAUDE_CODE_OAUTH_TOKEN CLAUDE_ACCESS_TOKEN; do
            if gh secret list 2>/dev/null | grep -q "$secret"; then
                check_pass "Secret $secret is set"
            else
                check_warn "Secret $secret not found"
            fi
        done
    else
        check_warn "Claude PR review workflow not found"
        echo "   Copy from: $INSTALL_DIR/.github/workflows/"
    fi
else
    check_warn "Not in a git repository"
fi

# Test hook execution
section "Hook Tests"
if [ -n "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/hooks/gemini-bridge.sh" ]; then
    echo "Testing Gemini bridge hook..."
    
    # Create test input
    local test_input='{"tool_name":"Read","tool_input":{"file_path":"test.txt"}}'
    
    if echo "$test_input" | "$INSTALL_DIR/hooks/gemini-bridge.sh" &> /dev/null; then
        check_pass "Gemini bridge hook test passed"
    else
        check_warn "Gemini bridge hook test failed (may be normal)"
    fi
fi

# Check OTW commands
section "OTW Commands (Optional)"
if [ -d "$HOME/.claude/commands/otw" ]; then
    check_pass "OTW commands installed"
    
    for cmd in research-tdd-pr-review.md execute-workflow.sh; do
        if [ -f "$HOME/.claude/commands/otw/$cmd" ]; then
            check_pass "$cmd exists"
        else
            check_warn "$cmd missing"
        fi
    done
else
    check_warn "OTW commands not installed"
    echo "   These enable advanced Research-TDD workflows"
fi

# Performance check
section "Performance Check"
if [ -n "$INSTALL_DIR" ]; then
    # Measure hook execution time
    local start=$(date +%s%N)
    echo '{"tool_name":"test"}' | "$INSTALL_DIR/hooks/unified-automation.sh" &> /dev/null || true
    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 ))
    
    if [ $duration -lt 1000 ]; then
        check_pass "Hook execution time: ${duration}ms (excellent)"
    elif [ $duration -lt 5000 ]; then
        check_warn "Hook execution time: ${duration}ms (acceptable)"
    else
        check_fail "Hook execution time: ${duration}ms (too slow)"
    fi
fi

# Summary
echo ""
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}                 Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}🎉 Perfect! Everything is configured correctly.${NC}"
    echo ""
    echo "You're ready to use Oppie AutoNav!"
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}✅ Installation is functional with $WARNINGS warning(s).${NC}"
    echo ""
    echo "The system will work but some features may be limited."
else
    echo -e "${RED}❌ Found $ERRORS error(s) and $WARNINGS warning(s).${NC}"
    echo ""
    echo "Please fix the errors above for the system to work properly."
fi

echo ""
echo "Quick Commands:"
echo "  • Start PR monitor: autonav-pr-monitor <pr_number>"
echo "  • Check status: autonav-pr-status"
echo "  • View logs: autonav-pr-logs"
echo "  • Clear cache: autonav-cache-clear"
echo ""

if [ $ERRORS -gt 0 ]; then
    exit 1
fi