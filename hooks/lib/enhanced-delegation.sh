#!/bin/bash

# Enhanced delegation logic with keyword matching and complexity scoring

# Check if prompt contains trigger keywords
check_keyword_triggers() {
    local prompt="$1"
    
    # Check if keyword matching is enabled
    if [ "${KEYWORD_MATCHING_ENABLED:-true}" != "true" ]; then
        return 1
    fi
    
    # Get keywords from config or use defaults
    local keywords="${GEMINI_TRIGGER_KEYWORDS:-deep|depth|think|all files|plan|design|PR review|gemini|analyze everything|comprehensive|thorough|detailed analysis|architecture|system design}"
    
    # Convert prompt to lowercase for case-insensitive matching
    local prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')
    
    # Check for keyword matches
    if echo "$prompt_lower" | grep -qE "$keywords"; then
        debug_log 1 "Keyword trigger detected in prompt"
        return 0
    fi
    
    return 1
}

# Calculate task complexity score (0-10)
calculate_complexity_score() {
    local tool="$1"
    local files="$2"
    local prompt="$3"
    local file_count="$4"
    local total_size="$5"
    
    local score=0
    
    # Check if complexity scoring is enabled
    if [ "${COMPLEXITY_SCORING_ENABLED:-true}" != "true" ]; then
        return 0
    fi
    
    # Tool complexity (0-3 points)
    case "$tool" in
        Task)
            score=$((score + 3))  # Task operations are inherently complex
            ;;
        Grep|Glob)
            score=$((score + 2))  # Search operations are moderately complex
            ;;
        Read)
            score=$((score + 1))  # Read operations are simpler
            ;;
    esac
    
    # File count complexity (0-3 points)
    if [ "$file_count" -ge 10 ]; then
        score=$((score + 3))
    elif [ "$file_count" -ge 5 ]; then
        score=$((score + 2))
    elif [ "$file_count" -ge 2 ]; then
        score=$((score + 1))
    fi
    
    # Size complexity (0-2 points)
    if [ "$total_size" -gt 100000 ]; then  # >100KB
        score=$((score + 2))
    elif [ "$total_size" -gt 50000 ]; then  # >50KB
        score=$((score + 1))
    fi
    
    # Prompt complexity indicators (0-2 points)
    local prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')
    
    # Complex task indicators
    if echo "$prompt_lower" | grep -qE "refactor|redesign|optimize|analyze all|review entire|comprehensive|architecture"; then
        score=$((score + 2))
    elif echo "$prompt_lower" | grep -qE "analyze|review|check|inspect|audit"; then
        score=$((score + 1))
    fi
    
    debug_log 2 "Calculated complexity score: $score/10"
    echo "$score"
}

# Enhanced delegation decision function
should_delegate_to_provider_enhanced() {
    local tool="$1"
    local files="$2"
    local prompt="$3"
    
    # Count files and calculate total size
    local file_count=$(echo "$files" | wc -w)
    local total_size=0
    
    for file in $files; do
        if [ -f "$file" ]; then
            local file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
            total_size=$((total_size + file_size))
        fi
    done
    
    local estimated_tokens=$((total_size / 4))
    
    debug_log 2 "Enhanced delegation check - Files: $file_count, Size: $total_size bytes, Tokens: ~$estimated_tokens"
    
    # 1. Check keyword triggers first (highest priority)
    if check_keyword_triggers "$prompt"; then
        debug_log 1 "Keyword trigger matched - delegating to Gemini"
        return 0
    fi
    
    # 2. Check complexity score
    local complexity=$(calculate_complexity_score "$tool" "$files" "$prompt" "$file_count" "$total_size")
    local threshold="${COMPLEXITY_THRESHOLD:-6}"
    
    if [ "$complexity" -gt "$threshold" ]; then
        debug_log 1 "Complexity score $complexity > $threshold - delegating to Gemini"
        return 0
    fi
    
    # 3. Check token limits (existing logic)
    local claude_token_limit="${CLAUDE_TOKEN_LIMIT:-50000}"
    local gemini_token_limit="${GEMINI_TOKEN_LIMIT:-800000}"
    
    if [ "$estimated_tokens" -gt "$claude_token_limit" ] && [ "$estimated_tokens" -le "$gemini_token_limit" ]; then
        debug_log 1 "Token limit exceeded ($estimated_tokens > $claude_token_limit) - delegating to Gemini"
        return 0
    fi
    
    # 4. Check file count threshold
    local min_files="${MIN_FILES_FOR_GEMINI:-2}"
    
    if [ "$file_count" -ge "$min_files" ] && [[ "$tool" == "Task" ]]; then
        debug_log 1 "Multi-file Task ($file_count >= $min_files) - delegating to Gemini"
        return 0
    fi
    
    debug_log 2 "No delegation triggers met - continuing with Claude"
    return 1
}

# Export functions for use in main script
export -f check_keyword_triggers
export -f calculate_complexity_score
export -f should_delegate_to_provider_enhanced