#!/bin/bash
# SPDX-FileCopyrightText: 2025 Good Night Oppie
# SPDX-License-Identifier: MIT

# Optimized CI monitoring hook for Claude Code
# Performance-focused with caching and async operations

set -euo pipefail

# Performance configuration
readonly CACHE_DIR="/tmp/ci-monitor-cache"
readonly CACHE_TTL=30  # Cache validity in seconds
readonly MAX_PARALLEL_JOBS=4
readonly QUICK_CHECK_TIMEOUT=5
readonly FULL_CHECK_TIMEOUT=60

# Create cache directory
mkdir -p "$CACHE_DIR"

# Colors (minimal for performance)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Performance metrics
PERF_START=$(date +%s%3N)

# Function to cache results
cache_set() {
    local key=$1
    local value=$2
    local ttl=${3:-$CACHE_TTL}
    
    echo "$value" > "$CACHE_DIR/$key"
    echo "$(($(date +%s) + ttl))" > "$CACHE_DIR/$key.ttl"
}

# Function to get cached results
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

# Fast CI status check with caching
quick_ci_check() {
    local cache_key="ci_status_$(date +%s -d '30 seconds ago')"
    
    # Try cache first
    if cache_get "$cache_key" 2>/dev/null; then
        return 0
    fi
    
    # Quick API call with timeout
    local status=$(timeout "$QUICK_CHECK_TIMEOUT" gh run list \
        --repo good-night-oppie/oppie-thunder \
        --limit 1 \
        --json status,conclusion,databaseId \
        2>/dev/null || echo '{"status":"unknown"}')
    
    cache_set "$cache_key" "$status"
    echo "$status"
}

# Detect failure patterns efficiently
detect_failure_type() {
    local run_id=$1
    local cache_key="failure_type_$run_id"
    
    # Check cache
    if cache_get "$cache_key" 2>/dev/null; then
        return 0
    fi
    
    # Get only relevant log sections (last 200 lines)
    local logs=$(timeout 10 gh run view "$run_id" \
        --repo good-night-oppie/oppie-thunder \
        --log 2>/dev/null | tail -200 || echo "")
    
    local error_type="unknown"
    
    # Fast pattern matching with early exit
    if echo "$logs" | grep -q "permission denied" 2>/dev/null; then
        error_type="permission"
    elif echo "$logs" | grep -q "Resource not accessible" 2>/dev/null; then
        error_type="token"
    elif echo "$logs" | grep -q "golangci-lint.*error" 2>/dev/null; then
        error_type="lint"
    elif echo "$logs" | grep -q "FAIL.*go test" 2>/dev/null; then
        error_type="test"
    elif echo "$logs" | grep -q "Cannot open: File exists" 2>/dev/null; then
        error_type="cache"
    fi
    
    cache_set "$cache_key" "$error_type" 300  # Cache for 5 minutes
    echo "$error_type"
}

# Apply fixes asynchronously
apply_fix_async() {
    local error_type=$1
    local pr_number=${2:-}
    
    case "$error_type" in
        "permission"|"cache")
            # Quick fix for CI workflow
            cat > /tmp/ci_fix_patch.yaml << 'EOF'
      - name: Fix cache directory permissions
        run: |
          if [ -d "/opt/runner-cache" ]; then
            sudo rm -rf /opt/runner-cache/* 2>/dev/null || true
            sudo mkdir -p /opt/runner-cache/{go-build,go-mod,golangci-lint}
            sudo chmod -R 777 /opt/runner-cache
          fi
EOF
            echo -e "${GREEN}✓ Generated permission fix${NC}"
            return 0
            ;;
            
        "lint")
            # Fast lint fix
            (
                cd /home/dev/workspace/oppie-thunder 2>/dev/null || exit 1
                timeout 30 golangci-lint run --fix --fast ./... 2>/dev/null
                timeout 10 gofmt -w . 2>/dev/null
            ) &
            echo -e "${GREEN}✓ Lint fixes running in background${NC}"
            return 0
            ;;
            
        *)
            echo -e "${YELLOW}⚠ Manual intervention needed for $error_type${NC}"
            return 1
            ;;
    esac
}

# Main monitoring function (optimized)
monitor_ci() {
    local mode=${1:-quick}
    local pr_number=${2:-}
    
    echo -e "${GREEN}⚡ CI Monitor (Optimized)${NC}"
    
    # Quick status check
    local status_json=$(quick_ci_check)
    local status=$(echo "$status_json" | jq -r '.[0].status' 2>/dev/null || echo "unknown")
    local conclusion=$(echo "$status_json" | jq -r '.[0].conclusion // "pending"' 2>/dev/null)
    local run_id=$(echo "$status_json" | jq -r '.[0].databaseId' 2>/dev/null)
    
    echo "Status: $status - $conclusion"
    
    # Only process failures
    if [ "$status" = "completed" ] && [ "$conclusion" = "failure" ]; then
        echo -e "${RED}❌ CI Failed - Analyzing...${NC}"
        
        # Detect and fix in parallel
        local error_type=$(detect_failure_type "$run_id")
        echo "Error type: $error_type"
        
        if [ "$mode" = "autofix" ]; then
            apply_fix_async "$error_type" "$pr_number"
        fi
    elif [ "$status" = "completed" ] && [ "$conclusion" = "success" ]; then
        echo -e "${GREEN}✅ CI Passed${NC}"
    else
        echo -e "${YELLOW}⏳ CI Running...${NC}"
    fi
    
    # Performance metrics
    PERF_END=$(date +%s%3N)
    PERF_DURATION=$((PERF_END - PERF_START))
    echo "⚡ Completed in ${PERF_DURATION}ms"
}

# Handle different invocation modes
case "${1:-monitor}" in
    "quick")
        # Fast check only (< 1 second)
        monitor_ci quick
        ;;
        
    "autofix")
        # Check and auto-fix if needed
        monitor_ci autofix "${2:-}"
        ;;
        
    "background")
        # Run in background with minimal output
        (monitor_ci autofix "${2:-}" > "$CACHE_DIR/last_run.log" 2>&1) &
        echo "PID: $!"
        ;;
        
    "clean")
        # Clean cache
        rm -rf "$CACHE_DIR"/*
        echo "Cache cleaned"
        ;;
        
    *)
        # Default quick check
        monitor_ci quick
        ;;
esac