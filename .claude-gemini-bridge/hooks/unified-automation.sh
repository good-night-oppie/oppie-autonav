#!/bin/bash
# ABOUTME: Unified automation for Claude-Gemini Bridge - coordinates PR review, CI monitoring, and debate

set -euo pipefail

# Configuration
readonly SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BRIDGE_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
readonly LOG_FILE="$BRIDGE_DIR/logs/unified-automation.log"
readonly STATE_DIR="$BRIDGE_DIR/cache/automation-state"

# Create directories
mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Extract context from command
extract_context() {
    local command=$1
    local context=""
    
    # Detect git push
    if echo "$command" | grep -q "git push"; then
        context="push"
        local branch=$(git branch --show-current 2>/dev/null || echo "")
        if [ -n "$branch" ]; then
            local pr_number=$(gh pr list --head "$branch" --json number -q '.[0].number' 2>/dev/null || echo "")
            if [ -n "$pr_number" ]; then
                echo "push:$pr_number:$branch"
                return 0
            fi
        fi
    fi
    
    # Detect PR creation
    if echo "$command" | grep -q "gh pr create"; then
        context="pr_create"
        # PR number will be in output
        echo "pr_create::main"
        return 0
    fi
    
    # Detect PR comment with @claude
    if echo "$command" | grep -q "@claude"; then
        context="review_request"
        local pr_number=$(echo "$command" | grep -oP '\d+' | head -1 || echo "")
        echo "review_request:$pr_number:"
        return 0
    fi
    
    # Detect CI commands
    if echo "$command" | grep -q "gh run\|gh pr checks"; then
        context="ci_check"
        echo "ci_check::"
        return 0
    fi
    
    echo "$context"
}

# Detect task complexity from PR or git messages
detect_complexity() {
    local pr_number=$1
    
    # Try to get from PR description
    if [ -n "$pr_number" ] && [ "$pr_number" != "" ]; then
        local pr_body=$(gh pr view "$pr_number" --json body -q '.body' 2>/dev/null || echo "")
        local complexity=$(echo "$pr_body" | grep -oP '[Cc]omplexity:\s*\K\d+' | head -1 || echo "")
        
        if [ -n "$complexity" ]; then
            echo "$complexity"
            return 0
        fi
    fi
    
    # Try to detect from changes
    local file_count=$(git diff --cached --name-only 2>/dev/null | wc -l || echo "0")
    local line_count=$(git diff --cached --stat 2>/dev/null | tail -1 | grep -oP '\d+(?= insertions)' || echo "0")
    
    # Calculate complexity based on changes
    if [ "$line_count" -gt 500 ] || [ "$file_count" -gt 10 ]; then
        echo "8"
    elif [ "$line_count" -gt 200 ] || [ "$file_count" -gt 5 ]; then
        echo "6"
    elif [ "$line_count" -gt 50 ] || [ "$file_count" -gt 2 ]; then
        echo "4"
    else
        echo "3"
    fi
}

# Handle git push
handle_git_push() {
    local pr_number=$1
    local branch=$2
    
    log "🚀 Detected git push to branch: $branch"
    
    # If no PR exists, suggest creating one
    if [ -z "$pr_number" ] || [ "$pr_number" = "" ]; then
        log "📝 No PR found for branch $branch"
        echo "💡 Tip: Create a PR with: gh pr create --title 'Your title' --body 'Complexity: N/10'"
        return 0
    fi
    
    log "📊 Found PR #$pr_number for branch $branch"
    
    # Start CI monitoring in background
    (
        sleep 5  # Wait for push to complete
        log "👁️ Starting CI monitoring for PR #$pr_number"
        
        # Check CI status periodically
        for i in {1..10}; do
            sleep 30
            local checks=$(gh pr checks "$pr_number" --json name,status,conclusion 2>/dev/null || echo "[]")
            local failed=$(echo "$checks" | jq -r '.[] | select(.conclusion == "failure") | .name' | wc -l)
            
            if [ "$failed" -gt 0 ]; then
                log "⚠️ CI failures detected for PR #$pr_number"
                # Could trigger auto-fix here
                break
            fi
            
            local pending=$(echo "$checks" | jq -r '.[] | select(.status == "in_progress") | .name' | wc -l)
            if [ "$pending" -eq 0 ]; then
                log "✅ CI completed for PR #$pr_number"
                break
            fi
        done
    ) &
    
    # Check if review is needed
    local complexity=$(detect_complexity "$pr_number")
    if [ "$complexity" -ge 7 ]; then
        log "🔍 High complexity ($complexity/10) detected - review recommended"
        
        # Check if review already requested
        local review_requested=$(gh pr view "$pr_number" --json comments -q '.comments[] | select(.body | contains("@claude")) | .id' 2>/dev/null | head -1)
        
        if [ -z "$review_requested" ]; then
            log "📝 Suggesting PR review for high complexity task"
            echo "💡 This appears to be a high-complexity change ($complexity/10)"
            echo "   Consider requesting review: gh pr comment $pr_number --body '@claude please review'"
        fi
    fi
}

# Handle PR creation
handle_pr_create() {
    log "📝 PR creation detected"
    
    # Get the newly created PR number (it should be the latest)
    local pr_number=$(gh pr list --limit 1 --json number -q '.[0].number' 2>/dev/null || echo "")
    
    if [ -n "$pr_number" ]; then
        log "✅ Created PR #$pr_number"
        
        # Detect complexity
        local complexity=$(detect_complexity "$pr_number")
        log "📊 Detected complexity: $complexity/10"
        
        # Add complexity to PR if not present
        local pr_body=$(gh pr view "$pr_number" --json body -q '.body' 2>/dev/null || echo "")
        if ! echo "$pr_body" | grep -q "Complexity:"; then
            local new_body="$pr_body

---
Complexity: $complexity/10
Domain: shell/hooks"
            gh pr edit "$pr_number" --body "$new_body" 2>/dev/null || true
            log "📝 Added complexity metadata to PR"
        fi
        
        # Start monitoring if high complexity
        if [ "$complexity" -ge 7 ]; then
            log "🔍 Starting PR monitoring for high-complexity PR #$pr_number"
            "$SCRIPTS_DIR/pr-review/pr-monitor.sh" monitor "$pr_number" "$complexity" &
        fi
    fi
}

# Handle review request
handle_review_request() {
    local pr_number=$1
    
    if [ -z "$pr_number" ] || [ "$pr_number" = "" ]; then
        log "⚠️ Cannot determine PR number for review request"
        return 1
    fi
    
    log "📝 Review requested for PR #$pr_number"
    
    # Detect complexity
    local complexity=$(detect_complexity "$pr_number")
    
    # Start PR monitoring
    log "🔍 Starting PR review monitoring (Complexity: $complexity/10)"
    "$SCRIPTS_DIR/pr-review/pr-monitor.sh" monitor "$pr_number" "$complexity" &
    
    echo "✅ PR review monitoring started for PR #$pr_number"
    echo "   Monitor status: $SCRIPTS_DIR/pr-review/pr-monitor.sh status"
}

# Handle CI check
handle_ci_check() {
    log "🔍 CI status check requested"
    
    # Quick CI status
    local branch=$(git branch --show-current 2>/dev/null || echo "")
    if [ -n "$branch" ]; then
        local pr_number=$(gh pr list --head "$branch" --json number -q '.[0].number' 2>/dev/null || echo "")
        
        if [ -n "$pr_number" ]; then
            local checks=$(gh pr checks "$pr_number" --json name,status,conclusion 2>/dev/null || echo "[]")
            local total=$(echo "$checks" | jq '. | length')
            local passed=$(echo "$checks" | jq -r '.[] | select(.conclusion == "success")' | wc -l)
            local failed=$(echo "$checks" | jq -r '.[] | select(.conclusion == "failure")' | wc -l)
            local pending=$(echo "$checks" | jq -r '.[] | select(.status == "in_progress")' | wc -l)
            
            echo "📊 CI Status for PR #$pr_number:"
            echo "   ✅ Passed: $passed/$total"
            [ "$failed" -gt 0 ] && echo "   ❌ Failed: $failed"
            [ "$pending" -gt 0 ] && echo "   ⏳ Pending: $pending"
            
            # Show failed checks
            if [ "$failed" -gt 0 ]; then
                echo ""
                echo "Failed checks:"
                echo "$checks" | jq -r '.[] | select(.conclusion == "failure") | "  - " + .name'
            fi
        fi
    fi
}

# Main execution
main() {
    local command=${1:-}
    
    if [ -z "$command" ]; then
        log "No command provided"
        exit 0
    fi
    
    log "Processing command: $command"
    
    # Extract context from command
    local context=$(extract_context "$command")
    IFS=':' read -r action pr_number branch <<< "$context"
    
    case $action in
        push)
            handle_git_push "$pr_number" "$branch"
            ;;
        pr_create)
            handle_pr_create
            ;;
        review_request)
            handle_review_request "$pr_number"
            ;;
        ci_check)
            handle_ci_check
            ;;
        *)
            log "Unknown context: $context"
            ;;
    esac
}

# Run in background to avoid blocking
(
    main "$@"
) &

# Return immediately
exit 0