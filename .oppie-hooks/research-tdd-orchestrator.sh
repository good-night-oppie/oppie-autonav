#!/bin/bash
# Research-TDD PR Review Orchestrator 
# CRITICAL: This should automatically handle CI/PR/debate monitoring

set -euo pipefail

# Configuration
PR_NUMBER=${1:-9}
TASK_ID=${2:-11} 
COMPLEXITY=${3:-9}
DOMAIN=${4:-"architecture"}

ORCHESTRATOR_DIR="/tmp/research_tdd_orchestrator"
MONITOR_PID_FILE="$ORCHESTRATOR_DIR/pr_monitor.pid"
CI_MONITOR_PID_FILE="$ORCHESTRATOR_DIR/ci_monitor.pid"
STATE_FILE="$ORCHESTRATOR_DIR/orchestrator_state.json"

mkdir -p "$ORCHESTRATOR_DIR"

echo "═══════════════════════════════════════════════════════"
echo "  Research-TDD PR Review Orchestrator v2.0"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "📋 Configuration:"
echo "   PR Number: #$PR_NUMBER"
echo "   Task ID: $TASK_ID"
echo "   Complexity: $COMPLEXITY/10" 
echo "   Domain: $DOMAIN"
echo ""

# Check if already running
if [[ -f "$MONITOR_PID_FILE" ]] && kill -0 $(cat "$MONITOR_PID_FILE") 2>/dev/null; then
    echo "⚠️ Monitor already running (PID: $(cat $MONITOR_PID_FILE))"
    echo "   Use 'kill $(cat $MONITOR_PID_FILE)' to stop"
    exit 1
fi

# Initialize state
initialize_orchestration() {
    echo "🔧 Initializing orchestration state..."
    
    cat > "$STATE_FILE" << EOF
{
    "pr_number": $PR_NUMBER,
    "task_id": $TASK_ID,
    "complexity": $COMPLEXITY,
    "domain": "$DOMAIN",
    "status": "monitoring",
    "round": 1,
    "started_at": "$(date -Iseconds)",
    "last_check": "$(date -Iseconds)",
    "debate_active": true,
    "ci_status": "unknown",
    "monitors": {
        "pr_comments": "starting",
        "ci_checks": "starting",
        "debate_orchestration": "active"
    }
}
EOF

    echo "✅ State initialized at $STATE_FILE"
}

# Start PR comment monitoring
start_pr_monitor() {
    echo "👁️ Starting PR comment monitor..."
    
    # Run the PR monitor daemon in background
    nohup ./.oppie-hooks/pr-monitor-daemon.sh $PR_NUMBER $TASK_ID $COMPLEXITY $DOMAIN \
        > "$ORCHESTRATOR_DIR/pr_monitor.log" 2>&1 &
    
    local pid=$!
    echo $pid > "$MONITOR_PID_FILE"
    
    echo "✅ PR Monitor started (PID: $pid)"
    echo "   Logs: $ORCHESTRATOR_DIR/pr_monitor.log"
}

# Start CI monitoring
start_ci_monitor() {
    echo "🏗️ Starting CI monitor..."
    
    # Simple CI monitor - checks every minute
    (
        while true; do
            CI_STATUS=$(gh pr checks $PR_NUMBER --json name,state 2>/dev/null | jq -r '.[] | select(.state == "FAILURE") | .name' | wc -l)
            
            if [[ "$CI_STATUS" -gt 0 ]]; then
                echo "$(date): CI failures detected for PR #$PR_NUMBER" 
                
                # Update state
                jq --arg status "ci_failing" '.ci_status = $status | .last_check = "'$(date -Iseconds)'"' "$STATE_FILE" > "$STATE_FILE.tmp"
                mv "$STATE_FILE.tmp" "$STATE_FILE"
            else
                echo "$(date): CI status OK for PR #$PR_NUMBER"
                
                # Update state  
                jq --arg status "passing" '.ci_status = $status | .last_check = "'$(date -Iseconds)'"' "$STATE_FILE" > "$STATE_FILE.tmp"
                mv "$STATE_FILE.tmp" "$STATE_FILE"
            fi
            
            sleep 60
        done
    ) > "$ORCHESTRATOR_DIR/ci_monitor.log" 2>&1 &
    
    local pid=$!
    echo $pid > "$CI_MONITOR_PID_FILE"
    
    echo "✅ CI Monitor started (PID: $pid)"
    echo "   Logs: $ORCHESTRATOR_DIR/ci_monitor.log"
}

# Check orchestration status
check_orchestration_status() {
    echo ""
    echo "📊 Orchestration Status:"
    
    if [[ -f "$STATE_FILE" ]]; then
        local status=$(jq -r '.status' "$STATE_FILE")
        local round=$(jq -r '.round' "$STATE_FILE")
        local ci_status=$(jq -r '.ci_status' "$STATE_FILE")
        local last_check=$(jq -r '.last_check' "$STATE_FILE")
        
        echo "   Status: $status"
        echo "   Debate Round: $round"
        echo "   CI Status: $ci_status" 
        echo "   Last Check: $last_check"
    else
        echo "   ❌ No state file found"
    fi
    
    if [[ -f "$MONITOR_PID_FILE" ]] && kill -0 $(cat "$MONITOR_PID_FILE") 2>/dev/null; then
        echo "   ✅ PR Monitor: Running (PID: $(cat $MONITOR_PID_FILE))"
    else
        echo "   ❌ PR Monitor: Not running"
    fi
    
    if [[ -f "$CI_MONITOR_PID_FILE" ]] && kill -0 $(cat "$CI_MONITOR_PID_FILE") 2>/dev/null; then
        echo "   ✅ CI Monitor: Running (PID: $(cat $CI_MONITOR_PID_FILE))"
    else
        echo "   ❌ CI Monitor: Not running"
    fi
    echo ""
}

# Stop all monitoring
stop_orchestration() {
    echo "🛑 Stopping orchestration..."
    
    if [[ -f "$MONITOR_PID_FILE" ]]; then
        local pid=$(cat "$MONITOR_PID_FILE")
        if kill -0 $pid 2>/dev/null; then
            kill $pid
            echo "✅ PR Monitor stopped"
        fi
        rm -f "$MONITOR_PID_FILE"
    fi
    
    if [[ -f "$CI_MONITOR_PID_FILE" ]]; then
        local pid=$(cat "$CI_MONITOR_PID_FILE")
        if kill -0 $pid 2>/dev/null; then
            kill $pid
            echo "✅ CI Monitor stopped"
        fi
        rm -f "$CI_MONITOR_PID_FILE"
    fi
    
    # Update final state
    if [[ -f "$STATE_FILE" ]]; then
        jq '.status = "stopped" | .stopped_at = "'$(date -Iseconds)'"' "$STATE_FILE" > "$STATE_FILE.tmp"
        mv "$STATE_FILE.tmp" "$STATE_FILE"
    fi
    
    echo "✅ All monitors stopped"
}

# Handle script arguments - check if first arg is numeric (PR number)
if [[ "$1" =~ ^[0-9]+$ ]]; then
    # Arguments are: PR_NUMBER TASK_ID COMPLEXITY DOMAIN [COMMAND]
    PR_NUMBER=${1}
    TASK_ID=${2:-11}
    COMPLEXITY=${3:-9}
    DOMAIN=${4:-"architecture"}
    COMMAND=${5:-start}
else
    # Arguments are: [COMMAND]
    COMMAND=${1:-start}
fi

case "$COMMAND" in
    "start")
        initialize_orchestration
        start_pr_monitor
        start_ci_monitor
        check_orchestration_status
        
        echo "🚀 Research-TDD orchestration active!"
        echo "   Monitoring PR #$PR_NUMBER for Round 2+ responses"
        echo "   Use '$0 status' to check status"
        echo "   Use '$0 stop' to stop monitoring"
        ;;
        
    "status")
        check_orchestration_status
        ;;
        
    "stop")
        stop_orchestration
        ;;
        
    "logs")
        echo "📋 Recent PR Monitor logs:"
        tail -20 "$ORCHESTRATOR_DIR/pr_monitor.log" 2>/dev/null || echo "No PR monitor logs"
        echo ""
        echo "📋 Recent CI Monitor logs:"
        tail -20 "$ORCHESTRATOR_DIR/ci_monitor.log" 2>/dev/null || echo "No CI monitor logs"
        ;;
        
    *)
        echo "Usage: $0 [PR_NUMBER TASK_ID COMPLEXITY DOMAIN] {start|status|stop|logs}"
        echo "  start  - Start orchestration (default)"
        echo "  status - Check monitor status"
        echo "  stop   - Stop all monitors"
        echo "  logs   - Show recent logs"
        echo ""
        echo "Examples:"
        echo "  $0 start                    # Use defaults"
        echo "  $0 9 11 9 architecture      # Start with PR #9"
        echo "  $0 status                   # Check status"
        exit 1
        ;;
esac