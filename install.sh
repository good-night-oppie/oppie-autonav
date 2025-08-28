#!/bin/bash
# ABOUTME: Master installer for complete Oppie AutoNav system

set -euo pipefail

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

clear

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                                  ║${NC}"
echo -e "${CYAN}║        🚀 OPPIE AUTONAV - Complete Installation Suite 🚀        ║${NC}"
echo -e "${CYAN}║                                                                  ║${NC}"
echo -e "${CYAN}║      Automate Everything, Review Everything, Ship Fast!         ║${NC}"
echo -e "${CYAN}║                                                                  ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Installation menu
show_menu() {
    echo -e "${BLUE}What would you like to install?${NC}"
    echo ""
    echo "  1) 🎯 Complete System (Recommended)"
    echo "     - Claude-Gemini Bridge"
    echo "     - MCP Stack (Context7, Serena, Exa, etc.)"
    echo "     - PR Review Automation"
    echo "     - OTW Workflows"
    echo "     - GitHub Actions"
    echo ""
    echo "  2) 🌉 Claude-Gemini Bridge Only"
    echo "     - Intelligent task delegation to Gemini"
    echo "     - PR monitoring hooks"
    echo ""
    echo "  3) 🧠 MCP Stack Only"
    echo "     - Essential MCPs for research and analysis"
    echo "     - Context7, DeepWiki, Exa, Serena, Sequential"
    echo ""
    echo "  4) 🔧 Custom Installation"
    echo "     - Choose specific components"
    echo ""
    echo "  5) ✅ Verify Installation"
    echo "     - Check existing setup"
    echo ""
    echo "  6) ❌ Exit"
    echo ""
}

# Complete installation
install_complete() {
    echo -e "${GREEN}Installing Complete Oppie AutoNav System...${NC}"
    echo ""
    
    # Install MCP Stack first
    echo -e "${BLUE}Step 1/3: Installing MCP Stack...${NC}"
    "$SCRIPT_DIR/scripts/install-mcp-stack.sh"
    echo ""
    
    # Install Claude-Gemini Bridge
    echo -e "${BLUE}Step 2/3: Installing Claude-Gemini Bridge...${NC}"
    "$SCRIPT_DIR/scripts/install-bridge.sh" --global
    echo ""
    
    # Verify installation
    echo -e "${BLUE}Step 3/3: Verifying installation...${NC}"
    "$SCRIPT_DIR/scripts/verify-installation.sh"
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         ✅ Complete Installation Successful! ✅          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
}

# Bridge only
install_bridge() {
    echo -e "${GREEN}Installing Claude-Gemini Bridge...${NC}"
    echo ""
    
    read -p "Install globally or in current project? (g/p): " mode
    
    if [[ "$mode" == "g" ]]; then
        "$SCRIPT_DIR/scripts/install-bridge.sh" --global
    else
        "$SCRIPT_DIR/scripts/install-bridge.sh" --project
    fi
}

# MCP only
install_mcp() {
    echo -e "${GREEN}Installing MCP Stack...${NC}"
    echo ""
    "$SCRIPT_DIR/scripts/install-mcp-stack.sh"
}

# Custom installation
install_custom() {
    echo -e "${BLUE}Custom Installation${NC}"
    echo ""
    echo "Select components to install:"
    echo ""
    
    components=()
    
    read -p "1. Claude-Gemini Bridge? (y/n): " install_bridge
    [[ "$install_bridge" == "y" ]] && components+=("bridge")
    
    read -p "2. MCP Stack (Context7, Serena, etc.)? (y/n): " install_mcp
    [[ "$install_mcp" == "y" ]] && components+=("mcp")
    
    read -p "3. OTW Workflows? (y/n): " install_otw
    [[ "$install_otw" == "y" ]] && components+=("otw")
    
    read -p "4. GitHub Actions templates? (y/n): " install_gh
    [[ "$install_gh" == "y" ]] && components+=("github")
    
    echo ""
    echo "Installing selected components..."
    
    for component in "${components[@]}"; do
        case $component in
            bridge)
                "$SCRIPT_DIR/scripts/install-bridge.sh" --global
                ;;
            mcp)
                "$SCRIPT_DIR/scripts/install-mcp-stack.sh"
                ;;
            otw)
                cp -r "$SCRIPT_DIR/.claude/commands/otw" "$HOME/.claude/commands/"
                echo "✅ OTW workflows installed"
                ;;
            github)
                if [ -d ".github" ]; then
                    cp "$SCRIPT_DIR/.github/workflows/"*.yml ".github/workflows/" 2>/dev/null
                    echo "✅ GitHub Actions templates copied"
                else
                    echo "⚠️  Not in a git repository, skipping GitHub Actions"
                fi
                ;;
        esac
    done
}

# Quick start guide
show_quickstart() {
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}                    Quick Start Guide${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════${NC}"
    echo ""
    echo "1️⃣  Set API Keys:"
    echo "   export GEMINI_API_KEY='your-key'"
    echo "   export EXA_API_KEY='your-key'"
    echo ""
    echo "2️⃣  Restart Claude Code:"
    echo "   pkill -f claude && claude"
    echo ""
    echo "3️⃣  Test the System:"
    echo ""
    echo "   # Create a test PR"
    echo "   git checkout -b test/autonav"
    echo "   echo '# Test' > test.md"
    echo "   git add test.md"
    echo "   git commit -m 'test: AutoNav\n\nComplexity: 7/10'"
    echo "   git push origin test/autonav"
    echo "   gh pr create"
    echo ""
    echo "   # Request Claude review"
    echo "   gh pr comment --body '@claude please review'"
    echo ""
    echo "4️⃣  Use Research Commands:"
    echo "   /otw/research-tdd-pr-review task-1 --complexity 8"
    echo ""
    echo "5️⃣  Monitor Status:"
    echo "   pm2 status  # Check MCP servers"
    echo "   autonav-pr-status  # Check PR monitors"
    echo ""
    echo -e "${CYAN}Documentation: $SCRIPT_DIR/README.md${NC}"
    echo -e "${CYAN}Setup Guide: $SCRIPT_DIR/docs/SETUP_GUIDE.md${NC}"
}

# Main loop
main() {
    while true; do
        show_menu
        read -p "Enter choice (1-6): " choice
        echo ""
        
        case $choice in
            1)
                install_complete
                show_quickstart
                break
                ;;
            2)
                install_bridge
                echo ""
                echo "✅ Claude-Gemini Bridge installed!"
                echo "   Restart Claude Code to activate hooks."
                break
                ;;
            3)
                install_mcp
                echo ""
                echo "✅ MCP Stack installed!"
                echo "   MCPs are running via pm2."
                break
                ;;
            4)
                install_custom
                echo ""
                echo "✅ Custom installation complete!"
                break
                ;;
            5)
                "$SCRIPT_DIR/scripts/verify-installation.sh"
                echo ""
                read -p "Press Enter to continue..."
                clear
                ;;
            6)
                echo "Installation cancelled."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please try again.${NC}"
                echo ""
                ;;
        esac
    done
    
    echo ""
    echo -e "${GREEN}Thank you for installing Oppie AutoNav!${NC}"
    echo -e "${CYAN}Join our community: https://github.com/yourusername/oppie-autonav${NC}"
    echo ""
}

# Check if running with specific flags
if [ $# -gt 0 ]; then
    case $1 in
        --complete)
            install_complete
            show_quickstart
            ;;
        --bridge)
            install_bridge
            ;;
        --mcp)
            install_mcp
            ;;
        --verify)
            "$SCRIPT_DIR/scripts/verify-installation.sh"
            ;;
        --help)
            echo "Usage: $0 [--complete|--bridge|--mcp|--verify|--help]"
            echo ""
            echo "Options:"
            echo "  --complete  Install everything"
            echo "  --bridge    Install Claude-Gemini Bridge only"
            echo "  --mcp       Install MCP Stack only"
            echo "  --verify    Verify installation"
            echo "  --help      Show this help"
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
else
    main
fi