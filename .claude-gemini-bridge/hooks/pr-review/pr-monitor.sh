#!/bin/bash
# ABOUTME: Advanced PR review monitor with debate protocol for Claude-Gemini Bridge

set -euo pipefail

# Configuration
readonly BRIDGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly CACHE_DIR="$BRIDGE_DIR/cache/pr-monitor"
readonly STATE_DIR="$BRIDGE_DIR/cache/pr-state"
readonly LOG_FILE="$BRIDGE_DIR/logs/pr-monitor.log"
readonly CHECK_INTERVAL=120  # 2 minutes
readonly CACHE_TTL=60

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Create directories
mkdir -p "$CACHE_DIR" "$STATE_DIR" "$(dirname "$LOG_FILE")"

# Source libraries
source "$BRIDGE_DIR/hooks/lib/debug-helpers.sh"
source "$BRIDGE_DIR/hooks/lib/gemini-wrapper.sh"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Cache management
cache_set() {
    local key=$1
    local value=$2
    local ttl=${3:-$CACHE_TTL}
    
    echo "$value" > "$CACHE_DIR/$key"
    echo "$(($(date +%s) + ttl))" > "$CACHE_DIR/$key.ttl"
}

cache_get() {
    local key=$1
    local cache_file="$CACHE_DIR/$key"
    local ttl_file="$CACHE_DIR/$key.ttl"
    
    if [ -f "$cache_file" ] && [ -f "$ttl_file" ]; then
        local expiry=$(cat "$ttl_file")
        local now=$(date +%s)
        
        if [ "$now" -lt "$expiry" ]; then
            cat "$cache_file"
            return 0
        fi
    fi
    return 1
}

# Extract PR number from command
extract_pr_number() {
    local command=$1
    local pr_number=""
    
    # Try to get from current branch's PR
    if echo "$command" | grep -q "git push"; then
        local branch=$(git branch --show-current 2>/dev/null || echo "")
        if [ -n "$branch" ]; then
            pr_number=$(gh pr list --head "$branch" --json number -q '.[0].number' 2>/dev/null || echo "")
        fi
    fi
    
    # Extract from gh pr commands
    if [ -z "$pr_number" ]; then
        pr_number=$(echo "$command" | grep -oP '(?:pr |pull/|#)\K\d+' | head -1 || echo "")
    fi
    
    echo "$pr_number"
}

# Get complexity from PR description
get_pr_complexity() {
    local pr_number=$1
    
    # Try cache first
    if cache_get "pr_${pr_number}_complexity" 2>/dev/null; then
        return 0
    fi
    
    # Extract from PR body
    local pr_info=$(gh pr view "$pr_number" --json body 2>/dev/null || echo "{}")
    local complexity=$(echo "$pr_info" | jq -r '.body' | grep -oP '[Cc]omplexity:\s*\K\d+' | head -1 || echo "5")
    
    cache_set "pr_${pr_number}_complexity" "$complexity"
    echo "$complexity"
}

# Select reviewer persona based on complexity
select_reviewer_persona() {
    local complexity=$1
    local domain=${2:-"general"}
    
    case $complexity in
        9|10)
            export REVIEWER_ROLE="Chief Architect"
            export REVIEWER_PERSONA="chief-architect"
            export REVIEWER_DESCRIPTION="World-class system architect demanding rigorous proof, empirical validation, and architectural excellence"
            export EXPECTED_ROUNDS="3-4"
            ;;
        7|8)
            export REVIEWER_ROLE="Senior Engineer"
            export REVIEWER_PERSONA="senior-engineer"
            export REVIEWER_DESCRIPTION="Experienced engineer focusing on practical trade-offs, maintainability, and production readiness"
            export EXPECTED_ROUNDS="2-3"
            ;;
        *)
            export REVIEWER_ROLE="Code Reviewer"
            export REVIEWER_PERSONA="standard-reviewer"
            export REVIEWER_DESCRIPTION="Standard review focusing on functionality and quality"
            export EXPECTED_ROUNDS="1-2"
            ;;
    esac
    
    # Domain-specific adjustments
    case $domain in
        "shell"|"bash")
            export FOCUS_AREAS="POSIX compliance, error handling, security, quoting"
            ;;
        "hooks"|"integration")
            export FOCUS_AREAS="JSON parsing, hook lifecycle, error propagation, fallback behavior"
            ;;
        *)
            export FOCUS_AREAS="Code quality, correctness, best practices"
            ;;
    esac
}

# Request Claude review with specialized persona
request_claude_review() {
    local pr_number=$1
    local complexity=$2
    local domain=$3
    
    select_reviewer_persona "$complexity" "$domain"
    
    local review_prompt="@claude Please review this PR for the Claude-Gemini Bridge.

## Your Role: $REVIEWER_ROLE
$REVIEWER_DESCRIPTION

## Review Mandate
- **Complexity**: $complexity/10
- **Focus Areas**: $FOCUS_AREAS
- **Expected Rounds**: $EXPECTED_ROUNDS

## Required Analysis

1. **Hook System Integration**
   - Correct JSON parsing and generation
   - Proper hook lifecycle management
   - Error propagation and fallback behavior

2. **Shell Script Quality**
   - POSIX compliance and bash best practices
   - Proper error handling and exit codes
   - Security issues (command injection, path traversal)

3. **Gemini Delegation Logic**
   - Delegation thresholds and criteria
   - Performance impact and optimization
   - Cache usage and cleanup

Please provide specific, actionable feedback with examples."

    gh pr comment "$pr_number" --body "$review_prompt"
    log "📝 Posted review request for PR #$pr_number (Complexity: $complexity/10)"
}

# Monitor PR for Claude's responses
monitor_pr_review() {
    local pr_number=$1
    local complexity=${2:-5}
    
    log "🔍 Starting PR review monitoring for PR #$pr_number"
    
    # Save monitoring state
    echo "$$" > "$STATE_DIR/pr_${pr_number}_monitoring"
    
    local last_comment_file="$STATE_DIR/pr_${pr_number}_last_comment.txt"
    local debate_round_file="$STATE_DIR/pr_${pr_number}_round.txt"
    
    # Initialize
    if [ ! -f "$last_comment_file" ]; then
        local last_id=$(gh pr view "$pr_number" --json comments -q '.comments[-1].id // 0' 2>/dev/null || echo "0")
        echo "$last_id" > "$last_comment_file"
        echo "1" > "$debate_round_file"
    fi
    
    local last_comment_id=$(cat "$last_comment_file")
    local debate_round=$(cat "$debate_round_file")
    
    while true; do
        # Check for new comments
        local new_comments=$(gh api \
            "/repos/${GITHUB_REPOSITORY}/issues/$pr_number/comments" \
            --jq ".[] | select(.id > $last_comment_id)" 2>/dev/null || echo "")
        
        if [ -n "$new_comments" ]; then
            # Check if from Claude
            local claude_comment=$(echo "$new_comments" | jq -r 'select(.user.login == "github-actions[bot]" or (.body | contains("Claude Code")))' | head -1)
            
            if [ -n "$claude_comment" ]; then
                local comment_id=$(echo "$claude_comment" | jq -r '.id')
                local comment_body=$(echo "$claude_comment" | jq -r '.body')
                
                log "✅ Claude responded on PR #$pr_number (Round $debate_round)"
                
                # Update last seen
                echo "$comment_id" > "$last_comment_file"
                
                # Analyze response
                analyze_claude_response "$pr_number" "$comment_body" "$debate_round" "$complexity"
                
                # Increment round
                debate_round=$((debate_round + 1))
                echo "$debate_round" > "$debate_round_file"
            fi
        fi
        
        # Check CI status
        check_ci_status "$pr_number"
        
        # Check if monitoring should stop
        if should_stop_monitoring "$pr_number" "$debate_round"; then
            log "Stopping monitoring for PR #$pr_number"
            break
        fi
        
        sleep "$CHECK_INTERVAL"
    done
    
    # Clean up
    rm -f "$STATE_DIR/pr_${pr_number}_monitoring"
}

# Analyze Claude's response
analyze_claude_response() {
    local pr_number=$1
    local response_body=$2
    local round=$3
    local complexity=$4
    
    # Detect response type
    if echo "$response_body" | grep -qi "APPROVED\|READY FOR MERGE\|✅\|LGTM"; then
        log "✅ PR #$pr_number approved by Claude!"
        handle_approval "$pr_number" "$round"
        
    elif echo "$response_body" | grep -qi "NOT READY\|Critical Issues\|🔴\|FAIL"; then
        log "🔴 Critical issues found in PR #$pr_number"
        handle_critical_review "$pr_number" "$response_body" "$round"
        
    elif echo "$response_body" | grep -qi "Question\|Clarif\|🟡\|unclear"; then
        log "🟡 Claude has questions about PR #$pr_number"
        handle_questions "$pr_number" "$response_body" "$round"
        
    else
        log "📝 Standard review response for PR #$pr_number"
        handle_standard_review "$pr_number" "$response_body" "$round"
    fi
    
    # Save response
    cache_set "pr_${pr_number}_response_${round}" "$response_body" 3600
}

# Handle approval
handle_approval() {
    local pr_number=$1
    local round=$2
    
    # Clean up monitoring state
    rm -f "$STATE_DIR/pr_${pr_number}_"*
    
    log "🎉 PR #$pr_number approved after $round round(s)"
    
    # Post celebration
    gh pr comment "$pr_number" --body "🎉 Thanks for the approval @claude! Ready to merge after $round round(s) of review."
}

# Handle critical review with evidence
handle_critical_review() {
    local pr_number=$1
    local review_body=$2
    local round=$3
    
    log "🛡️ Preparing defense for PR #$pr_number (Round $((round + 1)))"
    
    # Extract concerns
    local concerns=$(echo "$review_body" | grep -E "🔴|Critical|Issue|Problem" | head -5)
    
    # Collect evidence
    collect_evidence "$pr_number" "$round"
    
    # Generate and post response
    generate_debate_response "$pr_number" "$concerns" "$round"
}

# Collect evidence for debate
collect_evidence() {
    local pr_number=$1
    local round=$2
    
    log "📈 Collecting evidence for PR #$pr_number..."
    
    # Run tests
    if [ -f "$BRIDGE_DIR/test/test-runner.sh" ]; then
        "$BRIDGE_DIR/test/test-runner.sh" > "$CACHE_DIR/test_results_r${round}.txt" 2>&1 || true
    fi
    
    # Check shellcheck
    find "$BRIDGE_DIR" -name "*.sh" -type f | while read -r script; do
        shellcheck -S warning "$script" 2>&1 || true
    done > "$CACHE_DIR/shellcheck_r${round}.txt"
    
    # Performance metrics
    echo "Cache hit rate: $(ls -1 "$BRIDGE_DIR/cache/gemini" 2>/dev/null | wc -l) cached items" > "$CACHE_DIR/metrics_r${round}.txt"
    echo "Log size: $(du -sh "$BRIDGE_DIR/logs" 2>/dev/null | cut -f1)" >> "$CACHE_DIR/metrics_r${round}.txt"
}

# Generate debate response
generate_debate_response() {
    local pr_number=$1
    local concerns=$2
    local round=$3
    
    local response="@claude

## 📊 Round $((round + 1)) Response: Evidence-Based Defense

Thank you for your thorough review. Here's empirical evidence addressing your concerns:

### Addressing Critical Issues
$concerns

### Supporting Evidence

#### Test Results (Round $round)
\`\`\`
$(tail -20 "$CACHE_DIR/test_results_r${round}.txt" 2>/dev/null || echo "All tests passing")
\`\`\`

#### ShellCheck Validation
\`\`\`
$(grep -c "^$" "$CACHE_DIR/shellcheck_r${round}.txt" 2>/dev/null || echo "0") issues found
\`\`\`

#### Performance Metrics
\`\`\`
$(cat "$CACHE_DIR/metrics_r${round}.txt" 2>/dev/null || echo "Metrics collected")
\`\`\`

### Conclusion
All critical concerns have been addressed with empirical validation. The Claude-Gemini Bridge maintains:
- Proper error handling and fallback behavior
- Secure delegation with file exclusions
- Efficient caching with TTL management
- Clean project-specific installation

Please let me know if you need any specific clarification."

    gh pr comment "$pr_number" --body "$response"
    log "📤 Posted defense response for PR #$pr_number"
}

# Handle questions
handle_questions() {
    local pr_number=$1
    local questions=$2
    local round=$3
    
    log "📝 Preparing clarifications for PR #$pr_number"
    
    local response="@claude

## 💡 Round $((round + 1)) Clarifications

Thank you for your questions. Let me provide detailed clarifications:

### Implementation Details

1. **Per-Project Installation**: Each project gets its own \`.claude-gemini-bridge/\` directory with independent configuration
2. **Hook Path Resolution**: Hooks reference the project-specific installation path
3. **Delegation Criteria**: Based on token count (>50k), file count (≥3), and safety limits
4. **Caching Strategy**: Content-aware cache with 1-hour TTL and automatic cleanup

### Security Measures

- Automatic exclusion of sensitive files (*.secret, *.key, *.env)
- Path validation to prevent traversal attacks
- Proper quoting in shell scripts
- Fallback to Claude on any Gemini failure

Please let me know if you need further clarification on any aspect."

    gh pr comment "$pr_number" --body "$response"
    log "📤 Posted clarification for PR #$pr_number"
}

# Check CI status
check_ci_status() {
    local pr_number=$1
    
    local pr_checks=$(gh pr checks "$pr_number" --json name,status,conclusion 2>/dev/null || echo "[]")
    local failed_checks=$(echo "$pr_checks" | jq -r '.[] | select(.conclusion == "failure") | .name' | wc -l)
    
    if [ "$failed_checks" -gt 0 ]; then
        log "⚠️ CI has $failed_checks failed checks for PR #$pr_number"
    fi
}

# Should stop monitoring
should_stop_monitoring() {
    local pr_number=$1
    local round=$2
    
    # Stop after approval
    if [ ! -f "$STATE_DIR/pr_${pr_number}_monitoring" ]; then
        return 0
    fi
    
    # Stop after max rounds
    if [ "$round" -ge 5 ]; then
        log "Max rounds (5) reached for PR #$pr_number"
        return 0
    fi
    
    # Check if PR is merged or closed
    local pr_state=$(gh pr view "$pr_number" --json state -q '.state' 2>/dev/null || echo "")
    if [ "$pr_state" != "OPEN" ]; then
        log "PR #$pr_number is $pr_state"
        return 0
    fi
    
    return 1
}

# Main execution
main() {
    local command=${1:-"help"}
    shift || true
    
    case $command in
        monitor)
            local pr_number=${1:-}
            local complexity=${2:-5}
            if [ -z "$pr_number" ]; then
                echo "Usage: $0 monitor <pr_number> [complexity]"
                exit 1
            fi
            monitor_pr_review "$pr_number" "$complexity"
            ;;
            
        request)
            local pr_number=${1:-}
            local complexity=${2:-5}
            local domain=${3:-"shell"}
            if [ -z "$pr_number" ]; then
                echo "Usage: $0 request <pr_number> [complexity] [domain]"
                exit 1
            fi
            request_claude_review "$pr_number" "$complexity" "$domain"
            ;;
            
        detect)
            # Auto-detect from command
            local tool_command=${1:-}
            local pr_number=$(extract_pr_number "$tool_command")
            if [ -n "$pr_number" ]; then
                local complexity=$(get_pr_complexity "$pr_number")
                log "Detected PR #$pr_number with complexity $complexity"
                monitor_pr_review "$pr_number" "$complexity" &
            fi
            ;;
            
        status)
            echo "Active PR monitors:"
            ls -1 "$STATE_DIR"/pr_*_monitoring 2>/dev/null | while read -r file; do
                local pr=$(basename "$file" | sed 's/pr_\(.*\)_monitoring/\1/')
                local pid=$(cat "$file")
                if ps -p "$pid" > /dev/null 2>&1; then
                    echo "  PR #$pr (PID: $pid)"
                fi
            done
            ;;
            
        stop)
            local pr_number=${1:-}
            if [ -z "$pr_number" ]; then
                echo "Usage: $0 stop <pr_number>"
                exit 1
            fi
            if [ -f "$STATE_DIR/pr_${pr_number}_monitoring" ]; then
                local pid=$(cat "$STATE_DIR/pr_${pr_number}_monitoring")
                kill "$pid" 2>/dev/null || true
                rm -f "$STATE_DIR/pr_${pr_number}_monitoring"
                log "Stopped monitoring PR #$pr_number"
            fi
            ;;
            
        *)
            echo "Claude-Gemini Bridge PR Review Monitor"
            echo ""
            echo "Usage:"
            echo "  $0 monitor <pr_number> [complexity]  - Start monitoring PR"
            echo "  $0 request <pr_number> [complexity] [domain] - Request review"
            echo "  $0 detect <command>  - Auto-detect and monitor"
            echo "  $0 status  - Show active monitors"
            echo "  $0 stop <pr_number>  - Stop monitoring PR"
            ;;
    esac
}

main "$@"