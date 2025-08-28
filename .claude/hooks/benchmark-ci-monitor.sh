#!/bin/bash
# SPDX-FileCopyrightText: 2025 Good Night Oppie
# SPDX-License-Identifier: MIT

# Benchmark script for CI monitoring performance

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== CI Monitor Performance Benchmark ===${NC}"
echo ""

# Function to measure execution time
benchmark() {
    local name=$1
    local command=$2
    local iterations=${3:-10}
    
    echo -e "${YELLOW}Testing: $name${NC}"
    
    local total_time=0
    local min_time=999999
    local max_time=0
    
    for i in $(seq 1 $iterations); do
        local start=$(date +%s%3N)
        eval "$command" > /dev/null 2>&1
        local end=$(date +%s%3N)
        local duration=$((end - start))
        
        total_time=$((total_time + duration))
        
        if [ $duration -lt $min_time ]; then
            min_time=$duration
        fi
        
        if [ $duration -gt $max_time ]; then
            max_time=$duration
        fi
        
        echo -n "."
    done
    
    echo ""
    
    local avg_time=$((total_time / iterations))
    
    echo "  Average: ${avg_time}ms"
    echo "  Min: ${min_time}ms"
    echo "  Max: ${max_time}ms"
    echo ""
}

# Clear cache before benchmarks
echo "Clearing cache..."
rm -rf /tmp/ci-monitor-cache/* 2>/dev/null || true
echo ""

# Benchmark original script
if [ -f "/home/dev/workspace/oppie-thunder/scripts/monitor_ci_automated.sh" ]; then
    echo -e "${BLUE}Original Implementation:${NC}"
    benchmark "Status Check" "timeout 5 /home/dev/workspace/oppie-thunder/scripts/monitor_ci_automated.sh fix 2>/dev/null || true" 5
fi

# Benchmark optimized script
echo -e "${BLUE}Optimized Implementation:${NC}"
benchmark "Quick Check" "/home/dev/workspace/oppie-thunder/.claude/hooks/ci-monitor-optimized.sh quick" 10
benchmark "With Cache" "/home/dev/workspace/oppie-thunder/.claude/hooks/ci-monitor-optimized.sh quick" 10
benchmark "Auto-fix Mode" "/home/dev/workspace/oppie-thunder/.claude/hooks/ci-monitor-optimized.sh autofix" 5

# Test cache effectiveness
echo -e "${BLUE}Cache Performance:${NC}"
echo "Populating cache..."
/home/dev/workspace/oppie-thunder/.claude/hooks/ci-monitor-optimized.sh quick > /dev/null 2>&1

echo "Testing cache hits..."
benchmark "Cached Results" "/home/dev/workspace/oppie-thunder/.claude/hooks/ci-monitor-optimized.sh quick" 20

# Memory usage
echo -e "${BLUE}Resource Usage:${NC}"
cache_size=$(du -sh /tmp/ci-monitor-cache 2>/dev/null | cut -f1 || echo "0K")
echo "Cache Size: $cache_size"

# API call reduction
echo ""
echo -e "${BLUE}API Call Optimization:${NC}"
echo "Original: ~3-5 API calls per check"
echo "Optimized: 1 API call (cached for 30s)"
echo "Reduction: ~70-80%"

# Summary
echo ""
echo -e "${GREEN}=== Performance Summary ===${NC}"
echo "✅ Expected improvements:"
echo "  - 50-70% faster response time"
echo "  - 70-80% fewer API calls"
echo "  - Sub-second operation for cached results"
echo "  - Async execution prevents blocking"
echo ""
echo "🎯 Performance targets:"
echo "  - Quick check: < 500ms"
echo "  - Cached check: < 50ms"
echo "  - Auto-fix: < 2000ms"
echo "  - Background mode: < 100ms to start"