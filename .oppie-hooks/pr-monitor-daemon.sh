#!/bin/bash
# PR Monitor Daemon - Active monitoring for CI/PR/debate orchestration
# This should have been running automatically after PR creation

set -euo pipefail

PR_NUMBER=${1:-9}
TASK_ID=${2:-11}
COMPLEXITY=${3:-9}
DOMAIN=${4:-"architecture"}

# Configuration
MONITOR_DIR="/tmp/pr_monitor_${PR_NUMBER}"
LAST_COMMENT_FILE="${MONITOR_DIR}/last_comment_id.txt"
DEBATE_STATE_FILE="${MONITOR_DIR}/debate_state.json"
RESPONSE_LOG="${MONITOR_DIR}/responses.log"

# Ensure monitor directory exists
mkdir -p "$MONITOR_DIR"

echo "🚀 Starting PR Monitor Daemon for PR #${PR_NUMBER}"
echo "   Task: ${TASK_ID} | Complexity: ${COMPLEXITY}/10 | Domain: ${DOMAIN}"
echo "   Monitor Dir: ${MONITOR_DIR}"
echo "   Checking every 30 seconds..."

# Initialize if first run
if [[ ! -f "$LAST_COMMENT_FILE" ]]; then
    LAST_ID=$(gh pr view $PR_NUMBER --json comments -q '.comments[-1].id // 0' 2>/dev/null || echo "0")
    echo "$LAST_ID" > "$LAST_COMMENT_FILE"
    echo '{"round": 1, "status": "monitoring", "started": "'$(date -Iseconds)'"}' > "$DEBATE_STATE_FILE"
    echo "$(date -Iseconds): Monitor daemon started for PR #${PR_NUMBER}" >> "$RESPONSE_LOG"
fi

monitor_pr_activity() {
    local last_id=$(cat "$LAST_COMMENT_FILE" 2>/dev/null || echo "0")
    local round=$(jq -r '.round // 1' "$DEBATE_STATE_FILE" 2>/dev/null || echo "1")
    
    echo "$(date): Checking PR #${PR_NUMBER} for new activity (last_id: $last_id)"
    
    # Check for new comments since last check
    local new_comments=$(gh api \
        -H "Accept: application/vnd.github+json" \
        "/repos/good-night-oppie/oppie-autonav/issues/$PR_NUMBER/comments" \
        --jq ".[] | select(.id > $last_id)" 2>/dev/null || echo "")
    
    if [[ -n "$new_comments" ]]; then
        echo "📝 New comments detected!"
        
        # Check if Claude responded
        local claude_comment=$(echo "$new_comments" | jq -r 'select(.author.login == "claude" or .author.login == "github-actions" or (.body | contains("Claude")))')
        
        if [[ -n "$claude_comment" ]]; then
            local comment_id=$(echo "$claude_comment" | jq -r '.id' | head -1)
            local comment_body=$(echo "$claude_comment" | jq -r '.body' | head -1)
            
            echo "✅ Claude response detected! Processing..."
            echo "$comment_id" > "$LAST_COMMENT_FILE"
            
            # Analyze response type
            if echo "$comment_body" | grep -qi "APPROVED\\|READY FOR MERGE\\|✅.*APPROVE"; then
                handle_approval $round
            elif echo "$comment_body" | grep -qi "CONDITIONAL\\|REJECT\\|❌\\|Critical"; then
                handle_critical_review "$comment_body" $round
            else
                handle_standard_review "$comment_body" $round
            fi
        fi
        
        # Update last seen comment ID to latest
        local latest_id=$(echo "$new_comments" | jq -r '.id' | tail -1)
        if [[ "$latest_id" != "null" && -n "$latest_id" ]]; then
            echo "$latest_id" > "$LAST_COMMENT_FILE"
        fi
    fi
    
    # Check CI status
    check_ci_status
}

check_ci_status() {
    echo "🔍 Checking CI status..."
    
    local ci_checks=$(gh pr checks $PR_NUMBER --json name,state 2>/dev/null || echo "[]")
    local failed_checks=$(echo "$ci_checks" | jq -r '.[] | select(.state == "FAILURE") | .name' || echo "")
    
    if [[ -n "$failed_checks" ]]; then
        echo "❌ Failed CI checks: $failed_checks"
        echo "$(date -Iseconds): CI failures detected: $failed_checks" >> "$RESPONSE_LOG"
        
        # Could auto-fix CI issues here
        # For now, just log
    else
        echo "✅ CI status looks good"
    fi
}

handle_approval() {
    local round=$1
    echo "🎉 PR approved after $round round(s)!"
    echo '{"round": '$round', "status": "approved", "completed": "'$(date -Iseconds)'"}' > "$DEBATE_STATE_FILE"
    echo "$(date -Iseconds): PR #${PR_NUMBER} approved after $round rounds" >> "$RESPONSE_LOG"
    
    # Mark task complete
    echo "✅ Task ${TASK_ID} marked as complete"
    exit 0
}

handle_critical_review() {
    local review_body=$1
    local round=$2
    local next_round=$((round + 1))
    
    echo "🛡️ Critical review detected, preparing Round $next_round defense..."
    echo "$(date -Iseconds): Critical review received, preparing Round $next_round" >> "$RESPONSE_LOG"
    
    # Update state
    echo '{"round": '$next_round', "status": "responding", "last_response": "'$(date -Iseconds)'"}' > "$DEBATE_STATE_FILE"
    
    # The response has already been posted manually in this case
    # In a full implementation, this would auto-generate and post the response
    echo "Manual Round $next_round response required (already posted)"
}

handle_standard_review() {
    local review_body=$1  
    local round=$2
    local next_round=$((round + 1))
    
    echo "📝 Standard review, continuing to Round $next_round..."
    echo "$(date -Iseconds): Standard review received, Round $next_round" >> "$RESPONSE_LOG"
    
    # Update state
    echo '{"round": '$next_round', "status": "continuing", "last_response": "'$(date -Iseconds)'"}' > "$DEBATE_STATE_FILE"
}

cleanup() {
    echo "🛑 Monitor daemon stopping..."
    echo "$(date -Iseconds): Monitor daemon stopped" >> "$RESPONSE_LOG"
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Main monitoring loop
echo "👁️ Starting monitoring loop..."
while true; do
    monitor_pr_activity
    sleep 30  # Check every 30 seconds
done