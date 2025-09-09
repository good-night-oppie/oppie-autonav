#!/bin/bash
# SPDX-FileCopyrightText: 2025 Good Night Oppie
# SPDX-License-Identifier: MIT

# Wrapper for git push that automatically starts CI monitoring
# Usage: git-push-with-ci-monitor.sh [push arguments]

set -euo pipefail

# Configuration - can be overridden by environment variables
MONITOR_SCRIPT="${OPPIE_MONITOR_SCRIPT:-monitor_ci_automated.sh}"
MONITOR_PATH="${OPPIE_MONITOR_PATH:-$(command -v "$MONITOR_SCRIPT" 2>/dev/null || echo "")}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

echo -e "${BLUE}=== Git Push with CI Monitoring ===${NC}"

# Function to cleanup on exit
cleanup() {
    if [ -n "${MONITOR_PID:-}" ] && kill -0 "$MONITOR_PID" 2>/dev/null; then
        echo -e "\n${YELLOW}Stopping CI monitor (PID: $MONITOR_PID)...${NC}"
        kill "$MONITOR_PID" 2>/dev/null || true
    fi
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Get current branch
BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo -e "${GREEN}Branch: $BRANCH${NC}"

# Perform the git push
echo -e "${YELLOW}Pushing to remote...${NC}"
git push "$@"
PUSH_EXIT_CODE=$?

if [ $PUSH_EXIT_CODE -ne 0 ]; then
    echo -e "${RED}❌ Push failed with exit code $PUSH_EXIT_CODE${NC}"
    exit $PUSH_EXIT_CODE
fi

echo -e "${GREEN}✅ Push successful${NC}"

# Check for PR
PR_NUMBER=$(gh pr view --json number -q .number 2>/dev/null || echo "")

if [ -n "$PR_NUMBER" ]; then
    echo -e "${BLUE}📋 Found PR #$PR_NUMBER${NC}"
    echo -e "${MAGENTA}🚀 Starting CI monitoring...${NC}"
    
    # Start monitoring in foreground with auto-fix capability
    if [ -n "$MONITOR_PATH" ]; then
        "$MONITOR_PATH" pr "$PR_NUMBER" &
        MONITOR_PID=$!
    else
        echo -e "${YELLOW}⚠️  Monitor script not found. Skipping CI monitoring.${NC}"
        echo "Set OPPIE_MONITOR_PATH environment variable to the script location."
    fi
    
    if [ -n "${MONITOR_PID:-}" ]; then
        echo -e "${GREEN}CI monitor running (PID: $MONITOR_PID)${NC}"
        echo "Press Ctrl+C to stop monitoring and exit"
        
        # Wait for monitor to complete or user interrupt
        wait $MONITOR_PID
        MONITOR_EXIT_CODE=$?
        
        if [ $MONITOR_EXIT_CODE -eq 0 ]; then
            echo -e "${GREEN}✅ CI passed successfully!${NC}"
        else
            echo -e "${YELLOW}⚠️  CI monitoring completed with issues${NC}"
            echo "Check the logs above for details"
        fi
    fi
else
    echo -e "${YELLOW}ℹ️  No PR associated with branch $BRANCH${NC}"
    
    # Monitor latest run for 2 minutes
    if [ -n "$MONITOR_PATH" ]; then
        echo -e "${BLUE}Monitoring latest CI run for 2 minutes...${NC}"
        timeout 120 "$MONITOR_PATH" fix || true
    else
        echo -e "${YELLOW}⚠️  Monitor script not found. Skipping CI monitoring.${NC}"
    fi
fi

echo -e "${GREEN}✨ Git push with CI monitoring complete${NC}"