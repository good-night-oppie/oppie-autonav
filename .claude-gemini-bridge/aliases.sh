#!/bin/bash
# Oppie AutoNav helper aliases

# PR monitoring
alias autonav-pr-monitor='/home/dev/workspace/oppie-autonav/.claude-gemini-bridge/hooks/pr-review/pr-monitor.sh monitor'
alias autonav-pr-request='/home/dev/workspace/oppie-autonav/.claude-gemini-bridge/hooks/pr-review/pr-monitor.sh request'
alias autonav-pr-status='/home/dev/workspace/oppie-autonav/.claude-gemini-bridge/hooks/pr-review/pr-monitor.sh status'
alias autonav-pr-stop='/home/dev/workspace/oppie-autonav/.claude-gemini-bridge/hooks/pr-review/pr-monitor.sh stop'

# Cache management
alias autonav-cache-clear='rm -rf /home/dev/workspace/oppie-autonav/.claude-gemini-bridge/cache/gemini/*'
alias autonav-cache-size='du -sh /home/dev/workspace/oppie-autonav/.claude-gemini-bridge/cache'

# Log viewing
alias autonav-logs='tail -f /home/dev/workspace/oppie-autonav/.claude-gemini-bridge/logs/debug/$(date +%Y%m%d).log'
alias autonav-pr-logs='tail -f /home/dev/workspace/oppie-autonav/.claude-gemini-bridge/logs/pr-monitor.log'

# Testing
alias autonav-test='/home/dev/workspace/oppie-autonav/.claude-gemini-bridge/test/test-runner.sh'
alias autonav-verify='/home/dev/workspace/oppie-autonav/.claude-gemini-bridge/scripts/verify-installation.sh'

echo "Oppie AutoNav aliases loaded"
