#!/bin/bash
# MCTS Post-execution Hook for Oppie AutoNav
# Processes TDD results and updates MCTS tree

set -euo pipefail

MCTS_NODE=${1:-"$MCTS_NODE"}
PERFORMANCE_DELTA=${2:-""}
PR_STATUS=${3:-"unknown"}
BENCHMARK_RESULTS=${4:-""}

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🏁 MCTS Post-execution Hook${NC}"
echo -e "${YELLOW}   Node: $MCTS_NODE${NC}"
echo -e "${YELLOW}   Performance Delta: $PERFORMANCE_DELTA${NC}"
echo -e "${YELLOW}   PR Status: $PR_STATUS${NC}"

# Validate required inputs
if [[ -z "$MCTS_NODE" ]]; then
    echo -e "${RED}❌ Error: MCTS_NODE is required${NC}"
    exit 1
fi

# Navigate to helios-engine if available
if [[ -d "helios-engine" ]]; then
    cd helios-engine
elif [[ -d "../helios-engine" ]]; then
    cd ../helios-engine
else
    echo -e "${YELLOW}⚠️  helios-engine not found, working from current directory${NC}"
fi

# Load MCTS context
MCTS_CONTEXT_DIR=".mcts/contexts"
CONTEXT_FILE="$MCTS_CONTEXT_DIR/node_${MCTS_NODE}_context.json"

if [[ ! -f "$CONTEXT_FILE" ]]; then
    echo -e "${RED}❌ Error: MCTS context file not found: $CONTEXT_FILE${NC}"
    exit 1
fi

echo -e "${BLUE}📖 Loading MCTS context from: $CONTEXT_FILE${NC}"

# Extract context information
TARGET_SNAPSHOT=$(jq -r '.target_snapshot' "$CONTEXT_FILE")
PARENT_SNAPSHOT=$(jq -r '.parent_snapshot' "$PARENT_SNAPSHOT")
EXPLORATION_GOAL=$(jq -r '.exploration_goal' "$CONTEXT_FILE")

echo -e "${YELLOW}   Target Snapshot: $TARGET_SNAPSHOT${NC}"
echo -e "${YELLOW}   Exploration Goal: $EXPLORATION_GOAL${NC}"

# Collect final performance metrics if not provided
if [[ -z "$BENCHMARK_RESULTS" && -f "go.mod" ]]; then
    echo -e "${BLUE}📊 Collecting final performance metrics...${NC}"
    BENCHMARK_RESULTS=$(go test -bench=. -benchmem -benchtime=10s ./pkg/helios 2>/dev/null | grep -E "Benchmark|ns/op|B/op" || echo "final_collection_failed")
fi

# Calculate performance delta if not provided
if [[ -z "$PERFORMANCE_DELTA" && "$BENCHMARK_RESULTS" != "final_collection_failed" ]]; then
    echo -e "${BLUE}🧮 Calculating performance delta...${NC}"
    
    BASELINE_PERFORMANCE=$(jq -r '.baseline_performance' "$CONTEXT_FILE")
    if [[ "$BASELINE_PERFORMANCE" != "null" && "$BASELINE_PERFORMANCE" != "baseline_collection_failed" ]]; then
        # Simple delta calculation (you may want to enhance this)
        PERFORMANCE_DELTA=$(calculate_performance_improvement "$BASELINE_PERFORMANCE" "$BENCHMARK_RESULTS")
    else
        PERFORMANCE_DELTA="unknown"
    fi
fi

echo -e "${YELLOW}   Calculated Performance Delta: $PERFORMANCE_DELTA${NC}"

# Determine MCTS reward based on results
calculate_mcts_reward() {
    local pr_status=$1
    local perf_delta=$2
    
    case $pr_status in
        "approved"|"merged"|"success")
            if [[ "$perf_delta" =~ ^[0-9]+\.?[0-9]*%$ ]]; then
                # Extract percentage and convert to reward
                local pct=$(echo "$perf_delta" | sed 's/%//')
                local reward=$(echo "1.0 + ($pct / 100) * 2.0" | bc -l)
                echo "$reward"
            else
                echo "1.0"  # Default positive reward for approval
            fi
            ;;
        "rejected"|"failed"|"error")
            echo "-1.0"  # Negative reward for failure
            ;;
        *)
            echo "0.0"   # Neutral for unknown status
            ;;
    esac
}

MCTS_REWARD=$(calculate_mcts_reward "$PR_STATUS" "$PERFORMANCE_DELTA")
echo -e "${YELLOW}   MCTS Reward: $MCTS_REWARD${NC}"

# Update MCTS context with results
jq --arg status "$PR_STATUS" \
   --arg perf_delta "$PERFORMANCE_DELTA" \
   --arg benchmark_results "$BENCHMARK_RESULTS" \
   --arg reward "$MCTS_REWARD" \
   --arg completion_time "$(date -Iseconds)" \
   '.status = "completed" | 
    .pr_status = $status | 
    .performance_delta = $perf_delta | 
    .final_performance = $benchmark_results | 
    .mcts_reward = ($reward | tonumber) |
    .completion_time = $completion_time' \
   "$CONTEXT_FILE" > "${CONTEXT_FILE}.tmp" && mv "${CONTEXT_FILE}.tmp" "$CONTEXT_FILE"

echo -e "${GREEN}✅ Updated MCTS context with results${NC}"

# Update learning patterns
LEARNINGS_DIR=".mcts/learnings"
PATTERNS_FILE="$LEARNINGS_DIR/${EXPLORATION_GOAL}_patterns.json"

if [[ -f "$PATTERNS_FILE" ]]; then
    echo -e "${BLUE}🧠 Updating learning patterns...${NC}"
    
    # Increment exploration count
    jq '.exploration_count += 1 | .last_updated = "'$(date -Iseconds)'"' "$PATTERNS_FILE" > "${PATTERNS_FILE}.tmp"
    
    if (( $(echo "$MCTS_REWARD > 0" | bc -l) )); then
        # Record successful pattern
        PATTERN_DESCRIPTION="Goal: $EXPLORATION_GOAL, Delta: $PERFORMANCE_DELTA, Context: node_$MCTS_NODE"
        jq --arg pattern "$PATTERN_DESCRIPTION" \
           --arg reward "$MCTS_REWARD" \
           '.successful_patterns += [{pattern: $pattern, reward: ($reward | tonumber), timestamp: "'$(date -Iseconds)'"}] |
            .avg_improvement = ((.avg_improvement * (.exploration_count - 1)) + ($reward | tonumber)) / .exploration_count' \
           "${PATTERNS_FILE}.tmp" > "$PATTERNS_FILE"
        
        echo -e "${GREEN}✅ Recorded successful pattern (reward: $MCTS_REWARD)${NC}"
    else
        # Record failure pattern
        FAILURE_REASON="PR_status: $PR_STATUS, Performance: $PERFORMANCE_DELTA"
        jq --arg pattern "$EXPLORATION_GOAL" \
           --arg reason "$FAILURE_REASON" \
           '.failure_patterns += [{pattern: $pattern, reason: $reason, timestamp: "'$(date -Iseconds)'"}]' \
           "${PATTERNS_FILE}.tmp" > "$PATTERNS_FILE"
        
        echo -e "${RED}❌ Recorded failure pattern (reward: $MCTS_REWARD)${NC}"
    fi
    
    rm "${PATTERNS_FILE}.tmp"
else
    echo -e "${YELLOW}⚠️  Patterns file not found: $PATTERNS_FILE${NC}"
fi

# Handle snapshot management based on results
if (( $(echo "$MCTS_REWARD > 0" | bc -l) )); then
    echo -e "${BLUE}📸 Creating successful snapshot: $TARGET_SNAPSHOT${NC}"
    
    # Create git tag for successful snapshot
    if git status >/dev/null 2>&1; then
        git tag -a "$TARGET_SNAPSHOT" -m "MCTS Successful Exploration

Node: $MCTS_NODE
Exploration Goal: $EXPLORATION_GOAL
Performance Delta: $PERFORMANCE_DELTA
PR Status: $PR_STATUS
Reward: $MCTS_REWARD

Benchmark Results:
$BENCHMARK_RESULTS" 2>/dev/null || echo -e "${YELLOW}⚠️  Could not create git tag${NC}"
        
        echo -e "${GREEN}✅ Snapshot $TARGET_SNAPSHOT created${NC}"
    fi
    
    # Store snapshot metadata
    SNAPSHOTS_DIR=".mcts/snapshots"
    mkdir -p "$SNAPSHOTS_DIR"
    
    cat > "$SNAPSHOTS_DIR/${TARGET_SNAPSHOT}.json" << EOF
{
  "snapshot": "$TARGET_SNAPSHOT",
  "parent": "$PARENT_SNAPSHOT",
  "mcts_node": "$MCTS_NODE",
  "exploration_goal": "$EXPLORATION_GOAL",
  "performance_delta": "$PERFORMANCE_DELTA",
  "mcts_reward": $MCTS_REWARD,
  "pr_status": "$PR_STATUS",
  "benchmark_results": "$BENCHMARK_RESULTS",
  "created_at": "$(date -Iseconds)",
  "git_commit": "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')"
}
EOF
    
    echo -e "${GREEN}✅ Snapshot metadata stored${NC}"
    
else
    echo -e "${RED}🔄 Exploration failed - performing backtrack${NC}"
    
    # Backtrack to parent snapshot if it exists
    if git tag | grep -q "^$PARENT_SNAPSHOT$"; then
        git checkout "$PARENT_SNAPSHOT"
        echo -e "${YELLOW}⚠️  Backtracked to parent snapshot: $PARENT_SNAPSHOT${NC}"
    else
        echo -e "${YELLOW}⚠️  Parent snapshot not found, staying on current commit${NC}"
    fi
fi

# Generate summary report
echo -e "${BLUE}📋 MCTS Exploration Summary:${NC}"
echo -e "   Node ID: $MCTS_NODE"
echo -e "   Goal: $EXPLORATION_GOAL" 
echo -e "   Performance Delta: $PERFORMANCE_DELTA"
echo -e "   PR Status: $PR_STATUS"
echo -e "   MCTS Reward: $MCTS_REWARD"
echo -e "   Result: $(if (( $(echo "$MCTS_REWARD > 0" | bc -l) )); then echo -e "${GREEN}SUCCESS${NC}"; else echo -e "${RED}FAILURE${NC}"; fi)"

# Clean up temporary files (optional)
# rm -f /tmp/mcts_${MCTS_NODE}_*.tmp 2>/dev/null || true

echo -e "${BLUE}🎯 MCTS Post-execution completed${NC}"

# Return to oppie-autonav directory
cd - > /dev/null 2>&1 || true

exit 0

# Helper function for performance calculation
calculate_performance_improvement() {
    local baseline=$1
    local current=$2
    
    # This is a simplified calculation - enhance based on actual benchmark format
    # Extract the first benchmark time from each result
    local baseline_time=$(echo "$baseline" | grep -oE '[0-9]+\.[0-9]+' | head -1)
    local current_time=$(echo "$current" | grep -oE '[0-9]+\.[0-9]+' | head -1)
    
    if [[ -n "$baseline_time" && -n "$current_time" ]]; then
        local improvement=$(echo "scale=2; (($baseline_time - $current_time) / $baseline_time) * 100" | bc -l)
        echo "${improvement}%"
    else
        echo "calculation_failed"
    fi
}