#!/bin/bash
# MCTS ↔ AutoNav Coordination Bridge
# Orchestrates the complete MCTS exploration cycle

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTONAV_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELIOS_ENGINE_PATH="${HELIOS_ENGINE_PATH:-../helios-engine}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Command: start_exploration
start_mcts_exploration() {
    local node_id=$1
    local exploration_goal=$2
    local parent_snapshot=${3:-"main"}
    local expected_improvement=${4:-"5%"}
    
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}  MCTS AutoNav Exploration Coordinator${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BLUE}📋 Exploration Parameters:${NC}"
    echo -e "   🎯 Node ID: $node_id"
    echo -e "   🚀 Goal: $exploration_goal"
    echo -e "   📸 Parent Snapshot: $parent_snapshot"
    echo -e "   📈 Expected Improvement: $expected_improvement"
    echo ""
    
    # Generate target snapshot name
    local target_snapshot="${parent_snapshot}.${node_id}"
    
    # Phase 1: MCTS Pre-execution
    echo -e "${BLUE}🚀 Phase 1: MCTS Pre-execution Setup${NC}"
    if ! "$AUTONAV_ROOT/.oppie-hooks/mcts-pre-execution.sh" \
        "$node_id" \
        "$target_snapshot" \
        "$parent_snapshot" \
        "$exploration_goal"; then
        
        echo -e "${RED}❌ Pre-execution failed${NC}"
        return 1
    fi
    
    # Phase 2: Trigger Claude Code TDD Workflow
    echo -e "${BLUE}⚡ Phase 2: Triggering Claude Code TDD Workflow${NC}"
    echo -e "   📞 Calling: @.claude/commands/otw/research-tdd-pr-review"
    echo -e "   🎛️  Parameters: --mcts-node $node_id --target-snapshot $target_snapshot"
    
    # Create a task description for Claude
    local task_description="MCTS Exploration: $exploration_goal for helios engine optimization"
    
    # Set environment variables for the TDD workflow
    export MCTS_NODE="$node_id"
    export TARGET_SNAPSHOT="$target_snapshot"
    export PARENT_SNAPSHOT="$parent_snapshot"
    export EXPLORATION_GOAL="$exploration_goal"
    export EXPECTED_IMPROVEMENT="$expected_improvement"
    
    echo -e "${YELLOW}🔧 Environment configured for TDD workflow${NC}"
    
    # The actual TDD workflow will be triggered by Claude Code
    # This bridge script prepares the environment and waits for completion
    
    # Phase 3: Monitor and coordinate
    echo -e "${BLUE}👁️  Phase 3: Monitoring TDD Workflow Progress${NC}"
    monitor_tdd_workflow "$node_id" "$target_snapshot"
}

# Monitor the TDD workflow progress
monitor_tdd_workflow() {
    local node_id=$1
    local target_snapshot=$2
    local max_wait_time=3600  # 1 hour timeout
    local check_interval=30   # Check every 30 seconds
    local elapsed=0
    
    echo -e "${YELLOW}⏱️  Monitoring TDD workflow (timeout: ${max_wait_time}s)${NC}"
    
    # Look for context file updates
    local context_file=""
    if [[ -d "$HELIOS_ENGINE_PATH/.mcts/contexts" ]]; then
        context_file="$HELIOS_ENGINE_PATH/.mcts/contexts/node_${node_id}_context.json"
    elif [[ -d "helios-engine/.mcts/contexts" ]]; then
        context_file="helios-engine/.mcts/contexts/node_${node_id}_context.json"
    fi
    
    while [[ $elapsed -lt $max_wait_time ]]; do
        # Check if context file shows completion
        if [[ -f "$context_file" ]]; then
            local status=$(jq -r '.status' "$context_file" 2>/dev/null || echo "unknown")
            case $status in
                "completed")
                    echo -e "${GREEN}✅ TDD workflow completed successfully${NC}"
                    local pr_status=$(jq -r '.pr_status' "$context_file" 2>/dev/null || echo "unknown")
                    local performance_delta=$(jq -r '.performance_delta' "$context_file" 2>/dev/null || echo "unknown")
                    
                    finalize_mcts_exploration "$node_id" "$pr_status" "$performance_delta"
                    return 0
                    ;;
                "failed"|"error")
                    echo -e "${RED}❌ TDD workflow failed${NC}"
                    finalize_mcts_exploration "$node_id" "failed" "0%"
                    return 1
                    ;;
                "ready"|"executing")
                    echo -e "${YELLOW}🔄 TDD workflow in progress... (${elapsed}s elapsed)${NC}"
                    ;;
            esac
        fi
        
        # Check for PR creation (alternative completion indicator)
        if command -v gh >/dev/null 2>&1; then
            local recent_pr=$(gh pr list --state all --limit 5 --json title,number --jq '.[] | select(.title | contains("'$node_id'")) | .number' 2>/dev/null || echo "")
            if [[ -n "$recent_pr" ]]; then
                echo -e "${BLUE}📋 Found PR #$recent_pr for node $node_id${NC}"
                monitor_pr_status "$recent_pr" "$node_id"
                return $?
            fi
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
        echo -n "."
    done
    
    echo -e "\n${RED}⏱️  Timeout reached waiting for TDD workflow${NC}"
    finalize_mcts_exploration "$node_id" "timeout" "unknown"
    return 1
}

# Monitor PR status for completion
monitor_pr_status() {
    local pr_number=$1
    local node_id=$2
    local max_pr_wait=1800  # 30 minutes for PR review
    local elapsed=0
    
    echo -e "${BLUE}👁️  Monitoring PR #$pr_number status${NC}"
    
    while [[ $elapsed -lt $max_pr_wait ]]; do
        if command -v gh >/dev/null 2>&1; then
            local pr_status=$(gh pr view "$pr_number" --json state,mergeable --jq '.state' 2>/dev/null || echo "unknown")
            local pr_mergeable=$(gh pr view "$pr_number" --json mergeable --jq '.mergeable' 2>/dev/null || echo "unknown")
            
            case $pr_status in
                "MERGED")
                    echo -e "${GREEN}✅ PR #$pr_number merged successfully${NC}"
                    finalize_mcts_exploration "$node_id" "merged" "success"
                    return 0
                    ;;
                "CLOSED")
                    echo -e "${RED}❌ PR #$pr_number was closed without merging${NC}"
                    finalize_mcts_exploration "$node_id" "rejected" "0%"
                    return 1
                    ;;
                "OPEN")
                    # Check for approval in comments
                    local approval=$(gh pr view "$pr_number" --json comments --jq '.comments[] | select(.body | contains("APPROVED") or contains("LGTM") or contains("✅")) | .body' 2>/dev/null || echo "")
                    if [[ -n "$approval" ]]; then
                        echo -e "${GREEN}✅ PR #$pr_number approved${NC}"
                        finalize_mcts_exploration "$node_id" "approved" "pending_measurement"
                        return 0
                    fi
                    echo -e "${YELLOW}🔄 PR #$pr_number still under review... (${elapsed}s)${NC}"
                    ;;
            esac
        fi
        
        sleep 30
        elapsed=$((elapsed + 30))
    done
    
    echo -e "${YELLOW}⏱️  PR review timeout - treating as pending${NC}"
    finalize_mcts_exploration "$node_id" "pending" "unknown"
    return 1
}

# Finalize MCTS exploration and run post-execution hook
finalize_mcts_exploration() {
    local node_id=$1
    local pr_status=$2
    local performance_delta=$3
    
    echo -e "${BLUE}🏁 Finalizing MCTS exploration${NC}"
    echo -e "   Node: $node_id"
    echo -e "   PR Status: $pr_status"
    echo -e "   Performance: $performance_delta"
    
    # Run post-execution hook
    if ! "$AUTONAV_ROOT/.oppie-hooks/mcts-post-execution.sh" \
        "$node_id" \
        "$performance_delta" \
        "$pr_status"; then
        
        echo -e "${RED}❌ Post-execution hook failed${NC}"
        return 1
    fi
    
    # Generate final report
    generate_exploration_report "$node_id" "$pr_status" "$performance_delta"
    
    echo -e "${GREEN}✅ MCTS exploration completed${NC}"
}

# Generate exploration report
generate_exploration_report() {
    local node_id=$1
    local pr_status=$2  
    local performance_delta=$3
    
    local report_dir=".mcts/reports"
    mkdir -p "$report_dir"
    
    local report_file="$report_dir/exploration_${node_id}_$(date +%Y%m%d_%H%M%S).md"
    
    cat > "$report_file" << EOF
# MCTS Exploration Report: Node $node_id

**Date**: $(date -Iseconds)
**Node ID**: $node_id
**Exploration Goal**: ${EXPLORATION_GOAL:-unknown}
**Target Snapshot**: ${TARGET_SNAPSHOT:-unknown}
**Parent Snapshot**: ${PARENT_SNAPSHOT:-unknown}

## Results

- **PR Status**: $pr_status
- **Performance Delta**: $performance_delta
- **MCTS Outcome**: $(if [[ "$pr_status" =~ ^(approved|merged|success)$ ]]; then echo "SUCCESS ✅"; else echo "FAILURE ❌"; fi)

## Context Files

$(if [[ -f "$HELIOS_ENGINE_PATH/.mcts/contexts/node_${node_id}_context.json" ]]; then
    echo "- Context: \`.mcts/contexts/node_${node_id}_context.json\`"
fi)
$(if [[ -f "$HELIOS_ENGINE_PATH/.mcts/snapshots/${TARGET_SNAPSHOT}.json" ]]; then
    echo "- Snapshot: \`.mcts/snapshots/${TARGET_SNAPSHOT}.json\`"  
fi)

## Next Steps

$(if [[ "$pr_status" =~ ^(approved|merged|success)$ ]]; then
    echo "- ✅ Snapshot $TARGET_SNAPSHOT can be used as baseline for further exploration"
    echo "- 📈 Pattern recorded for future MCTS learning"
    echo "- 🎯 Consider exploring child nodes of $node_id"
else
    echo "- 🔄 Backtrack to parent snapshot: $PARENT_SNAPSHOT"
    echo "- 📝 Failure pattern recorded to avoid similar approaches"
    echo "- 🎯 Consider alternative exploration strategies"
fi)

---
*Generated by MCTS AutoNav Bridge*
EOF

    echo -e "${GREEN}📋 Report generated: $report_file${NC}"
}

# Command dispatcher
main() {
    case "${1:-help}" in
        "start"|"explore")
            if [[ $# -lt 3 ]]; then
                echo "Usage: $0 start <node_id> <exploration_goal> [parent_snapshot] [expected_improvement]"
                echo "Example: $0 start 1.2.3 lock_free_optimization main 15%"
                exit 1
            fi
            start_mcts_exploration "$2" "$3" "${4:-main}" "${5:-5%}"
            ;;
        "monitor")
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 monitor <node_id>"
                exit 1  
            fi
            monitor_tdd_workflow "$2" "${3:-${2#*.}}"
            ;;
        "finalize")
            if [[ $# -lt 4 ]]; then
                echo "Usage: $0 finalize <node_id> <pr_status> <performance_delta>"
                exit 1
            fi
            finalize_mcts_exploration "$2" "$3" "$4"
            ;;
        "help"|*)
            cat << EOF
MCTS AutoNav Bridge - Coordinate MCTS exploration with Claude Code TDD

Commands:
  start <node_id> <goal> [parent] [improvement]  Start MCTS exploration
  monitor <node_id>                             Monitor ongoing exploration  
  finalize <node_id> <status> <delta>           Finalize exploration manually
  help                                          Show this help

Examples:
  $0 start 1.2.3 lock_free_optimization main 20%
  $0 monitor 1.2.3
  $0 finalize 1.2.3 approved 15%

Environment Variables:
  HELIOS_ENGINE_PATH    Path to helios-engine directory
  MCTS_NODE            Current MCTS node ID
  TARGET_SNAPSHOT      Target snapshot name
  EXPLORATION_GOAL     Current exploration goal
EOF
            ;;
    esac
}

# Execute main function with all arguments
main "$@"