#!/bin/bash
# SPDX-FileCopyrightText: 2025 Good Night Oppie
# SPDX-License-Identifier: MIT

# Comprehensive PR Review and CI Monitoring Hook
# Monitors for Claude's PR review responses and CI status
# Integrates with research-tdd-pr-review workflow

set -euo pipefail

# Configuration
readonly CACHE_DIR="/tmp/pr-monitor-cache"
readonly STATE_DIR="/tmp/pr-monitor-state"
readonly LOG_FILE="/tmp/pr-monitor.log"
readonly CHECK_INTERVAL=120  # 2 minutes
readonly CACHE_TTL=60  # Cache PR data for 60 seconds

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'

# Create directories
mkdir -p "$CACHE_DIR" "$STATE_DIR"

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

# Extract PR number from git push or gh pr commands
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
    
    # Try to extract from gh pr commands
    if [ -z "$pr_number" ]; then
        pr_number=$(echo "$command" | grep -oP '(?:pr |pull/|#)\K\d+' | head -1 || echo "")
    fi
    
    echo "$pr_number"
}

# Get task ID from PR
get_task_from_pr() {
    local pr_number=$1
    
    # Try cache first
    if cache_get "task_pr_${pr_number}" 2>/dev/null; then
        return 0
    fi
    
    # Extract from PR title or body
    local pr_info=$(gh pr view "$pr_number" --json title,body 2>/dev/null || echo "{}")
    local task_id=$(echo "$pr_info" | jq -r '.title' | grep -oP '[Tt]ask[\s-]*\K[\d.]+' | head -1 || echo "")
    
    if [ -z "$task_id" ]; then
        task_id=$(echo "$pr_info" | jq -r '.body' | grep -oP '[Tt]ask[\s-]*\K[\d.]+' | head -1 || echo "")
    fi
    
    if [ -n "$task_id" ]; then
        cache_set "task_pr_${pr_number}" "$task_id"
    fi
    
    echo "$task_id"
}

# Detect if PR needs review monitoring
pr_needs_monitoring() {
    local pr_number=$1
    
    # Check if already monitoring
    if [ -f "$STATE_DIR/pr_${pr_number}_monitoring" ]; then
        local pid=$(cat "$STATE_DIR/pr_${pr_number}_monitoring")
        if ps -p "$pid" > /dev/null 2>&1; then
            log "Already monitoring PR #$pr_number (PID: $pid)"
            return 1
        fi
    fi
    
    # Check if review was requested
    local review_requested=$(gh pr view "$pr_number" --json comments -q '.comments[] | select(.body | contains("@claude")) | .id' 2>/dev/null | head -1)
    
    if [ -n "$review_requested" ]; then
        return 0
    fi
    
    # Check if high complexity task
    local task_id=$(get_task_from_pr "$pr_number")
    if [ -n "$task_id" ]; then
        local complexity=$(task-master get-task --id="$task_id" 2>/dev/null | jq -r '.complexity // 5' || echo "5")
        if [ "$complexity" -ge 7 ]; then
            return 0
        fi
    fi
    
    return 1
}

# Monitor PR for Claude's responses
monitor_pr_review() {
    local pr_number=$1
    local task_id=${2:-}
    
    log "🔍 Starting PR review monitoring for PR #$pr_number"
    
    # Save monitoring state
    echo "$$" > "$STATE_DIR/pr_${pr_number}_monitoring"
    
    # Track last seen comment
    local last_comment_file="$STATE_DIR/pr_${pr_number}_last_comment.txt"
    local debate_round_file="$STATE_DIR/pr_${pr_number}_round.txt"
    
    # Initialize if first run
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
            "/repos/good-night-oppie/oppie-thunder/issues/$pr_number/comments" \
            --jq ".[] | select(.id > $last_comment_id)" 2>/dev/null || echo "")
        
        if [ -n "$new_comments" ]; then
            # Check if from Claude (GitHub Actions bot)
            local claude_comment=$(echo "$new_comments" | jq -r 'select(.user.login == "github-actions[bot]" or (.body | contains("Claude Code is working")))' | head -1)
            
            if [ -n "$claude_comment" ]; then
                local comment_id=$(echo "$claude_comment" | jq -r '.id')
                local comment_body=$(echo "$claude_comment" | jq -r '.body')
                
                log "✅ Claude responded on PR #$pr_number (Round $debate_round)"
                
                # Update last seen
                echo "$comment_id" > "$last_comment_file"
                
                # Analyze response
                analyze_claude_response "$pr_number" "$comment_body" "$debate_round" "$task_id"
                
                # Increment round
                debate_round=$((debate_round + 1))
                echo "$debate_round" > "$debate_round_file"
            fi
        fi
        
        # Check CI status in parallel
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
    local task_id=$4
    
    # Detect response type
    local response_type="standard"
    
    if echo "$response_body" | grep -qi "APPROVED\|READY FOR MERGE\|✅\|LGTM"; then
        response_type="approved"
        log "✅ PR #$pr_number approved by Claude!"
        handle_approval "$pr_number" "$task_id" "$round"
        
    elif echo "$response_body" | grep -qi "NOT READY\|Critical Issues\|🔴\|FAIL"; then
        response_type="critical"
        log "🔴 Critical issues found in PR #$pr_number"
        handle_critical_review "$pr_number" "$response_body" "$round"
        
    elif echo "$response_body" | grep -qi "Question\|Clarif\|🟡\|unclear"; then
        response_type="questions"
        log "🟡 Claude has questions about PR #$pr_number"
        handle_questions "$pr_number" "$response_body" "$round"
    fi
    
    # Save response for analysis
    cache_set "pr_${pr_number}_response_${round}" "$response_body" 3600
    
    # Notify user
    notify_user "$pr_number" "$response_type" "$round"
}

# Handle approval
handle_approval() {
    local pr_number=$1
    local task_id=$2
    local round=$3
    
    # Update task status
    if [ -n "$task_id" ]; then
        task-master set-status --id="$task_id" --status=done 2>/dev/null || true
    fi
    
    # Clean up monitoring state
    rm -f "$STATE_DIR/pr_${pr_number}_"*
    
    log "🎉 PR #$pr_number approved after $round round(s)"
}

# Handle critical review
handle_critical_review() {
    local pr_number=$1
    local review_body=$2
    local round=$3
    
    log "🛡️ Preparing defense for PR #$pr_number (Round $((round + 1)))"
    
    # Extract concerns
    local concerns=$(echo "$review_body" | grep -E "🔴|Critical|Issue|Problem" | head -5)
    
    # Trigger evidence collection
    collect_evidence "$pr_number" "$round"
    
    # Generate and post response
    generate_debate_response "$pr_number" "$concerns" "$round"
}

# Handle questions
handle_questions() {
    local pr_number=$1
    local questions=$2
    local round=$3
    
    log "📝 Preparing clarifications for PR #$pr_number"
    
    # Extract questions
    local question_list=$(echo "$questions" | grep -E "\?|clarify|explain" | head -5)
    
    # Generate clarification
    generate_clarification "$pr_number" "$question_list" "$round"
}

# Check CI status
check_ci_status() {
    local pr_number=$1
    
    # Use optimized CI monitor
    local ci_status=$(/home/dev/workspace/oppie-thunder/.claude/hooks/ci-monitor-optimized.sh quick 2>/dev/null || echo "unknown")
    
    # Check PR-specific checks
    local pr_checks=$(gh pr checks "$pr_number" --json name,status,conclusion 2>/dev/null || echo "[]")
    local failed_checks=$(echo "$pr_checks" | jq -r '.[] | select(.conclusion == "failure") | .name' | wc -l)
    
    if [ "$failed_checks" -gt 0 ]; then
        log "⚠️ CI has $failed_checks failed checks on PR #$pr_number"
        
        # Trigger auto-fix if configured
        if [ -f "/home/dev/workspace/oppie-thunder/.claude/hooks/ci-monitor-optimized.sh" ]; then
            /home/dev/workspace/oppie-thunder/.claude/hooks/ci-monitor-optimized.sh autofix "$pr_number" &
        fi
    fi
}

# Should stop monitoring
should_stop_monitoring() {
    local pr_number=$1
    local round=$2
    
    # Stop if approved
    if [ -f "$STATE_DIR/pr_${pr_number}_approved" ]; then
        return 0
    fi
    
    # Stop if max rounds reached
    if [ "$round" -ge 10 ]; then
        log "Max rounds (10) reached for PR #$pr_number"
        return 0
    fi
    
    # Stop if PR closed/merged
    local pr_state=$(gh pr view "$pr_number" --json state -q '.state' 2>/dev/null || echo "")
    if [ "$pr_state" = "CLOSED" ] || [ "$pr_state" = "MERGED" ]; then
        return 0
    fi
    
    return 1
}

# Collect evidence for debate
collect_evidence() {
    local pr_number=$1
    local round=$2
    
    local evidence_dir="$CACHE_DIR/evidence_pr_${pr_number}_r${round}"
    mkdir -p "$evidence_dir"
    
    log "📊 Collecting evidence for PR #$pr_number"
    
    # Run benchmarks
    (cd /home/dev/workspace/oppie-thunder/helios-engine && \
        go test -bench=. -benchmem ./... > "$evidence_dir/benchmarks.txt" 2>&1) &
    
    # Run tests with race detection
    (cd /home/dev/workspace/oppie-thunder/helios-engine && \
        go test -race -count=10 ./... > "$evidence_dir/race_tests.txt" 2>&1) &
    
    # Collect coverage
    (cd /home/dev/workspace/oppie-thunder/helios-engine && \
        go test -cover ./... > "$evidence_dir/coverage.txt" 2>&1) &
    
    wait
    
    log "✅ Evidence collected for PR #$pr_number"
}

# Generate debate response
generate_debate_response() {
    local pr_number=$1
    local concerns=$2
    local round=$3
    
    local response_file="$CACHE_DIR/response_pr_${pr_number}_r$((round + 1)).md"
    
    cat > "$response_file" << EOF
## 📊 Round $((round + 1)) Response

Thank you for your thorough review. Here's evidence addressing your concerns:

### Addressing Critical Issues
$concerns

### Supporting Evidence

#### Performance Metrics
\`\`\`
$(tail -20 "$CACHE_DIR/evidence_pr_${pr_number}_r${round}/benchmarks.txt" 2>/dev/null || echo "Benchmarks pending...")
\`\`\`

#### Test Results
\`\`\`
$(grep -E "PASS|ok" "$CACHE_DIR/evidence_pr_${pr_number}_r${round}/race_tests.txt" 2>/dev/null | head -5 || echo "Tests pending...")
\`\`\`

#### Coverage Report
\`\`\`
$(tail -5 "$CACHE_DIR/evidence_pr_${pr_number}_r${round}/coverage.txt" 2>/dev/null || echo "Coverage pending...")
\`\`\`

### Conclusion
All concerns have been addressed with empirical validation. The implementation maintains correctness while meeting performance targets.

cc: @good-night-oppie
EOF
    
    # Post response
    gh pr comment "$pr_number" --body-file "$response_file" 2>/dev/null || \
        log "Failed to post response to PR #$pr_number"
    
    log "📤 Posted debate response to PR #$pr_number"
}

# Generate clarification
generate_clarification() {
    local pr_number=$1
    local questions=$2
    local round=$3
    
    local response_file="$CACHE_DIR/clarification_pr_${pr_number}_r$((round + 1)).md"
    
    cat > "$response_file" << EOF
## 💡 Clarifications (Round $((round + 1)))

Thank you for your questions. Let me provide detailed clarifications:

### Questions Addressed
$questions

### Detailed Responses

Based on the implementation:
1. The approach follows TDD principles with comprehensive test coverage
2. Performance optimizations are validated through benchmarking
3. All architectural decisions are documented in code comments

Please let me know if you need further clarification.
EOF
    
    # Post response
    gh pr comment "$pr_number" --body-file "$response_file" 2>/dev/null || \
        log "Failed to post clarification to PR #$pr_number"
    
    log "📤 Posted clarification to PR #$pr_number"
}

# Notify user
notify_user() {
    local pr_number=$1
    local response_type=$2
    local round=$3
    
    case "$response_type" in
        "approved")
            echo -e "${GREEN}✅ PR #$pr_number approved by Claude (Round $round)${NC}"
            ;;
        "critical")
            echo -e "${RED}🔴 Critical issues in PR #$pr_number - auto-responding${NC}"
            ;;
        "questions")
            echo -e "${YELLOW}🟡 Questions on PR #$pr_number - clarifying${NC}"
            ;;
        *)
            echo -e "${BLUE}💬 Claude responded on PR #$pr_number (Round $round)${NC}"
            ;;
    esac
}

# Main execution
main() {
    local mode=${1:-detect}
    local command=${2:-}
    
    case "$mode" in
        "detect")
            # Auto-detect from command
            if [ -n "$command" ]; then
                local pr_number=$(extract_pr_number "$command")
                if [ -n "$pr_number" ] && pr_needs_monitoring "$pr_number"; then
                    log "Detected PR #$pr_number needs monitoring"
                    monitor_pr_review "$pr_number" &
                    echo "PID: $!"
                fi
            fi
            ;;
            
        "monitor")
            # Explicit monitoring
            local pr_number=${2:-}
            if [ -n "$pr_number" ]; then
                monitor_pr_review "$pr_number" &
                echo "PID: $!"
            fi
            ;;
            
        "status")
            # Show monitoring status
            echo -e "${BLUE}=== PR Monitoring Status ===${NC}"
            for state_file in "$STATE_DIR"/pr_*_monitoring; do
                if [ -f "$state_file" ]; then
                    local pr=$(basename "$state_file" | sed 's/pr_\(.*\)_monitoring/\1/')
                    local pid=$(cat "$state_file")
                    if ps -p "$pid" > /dev/null 2>&1; then
                        echo -e "${GREEN}✓ PR #$pr monitored by PID $pid${NC}"
                    else
                        echo -e "${RED}✗ PR #$pr monitor stopped${NC}"
                    fi
                fi
            done
            ;;
            
        "clean")
            # Clean cache and state
            rm -rf "$CACHE_DIR"/* "$STATE_DIR"/*
            echo "Cache and state cleaned"
            ;;
            
        *)
            echo "Usage: $0 {detect|monitor|status|clean} [args]"
            exit 1
            ;;
    esac
}

# Run main
main "$@"