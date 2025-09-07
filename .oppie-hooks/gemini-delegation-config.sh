#!/bin/bash
# Gemini Delegation Configuration for Oppie DevKit
# This configuration enhances the Gemini bridge to intelligently delegate analysis tasks

# ============================================
# Gemini Delegation Strategy Configuration
# ============================================

# Token limits for delegation decisions
export CLAUDE_TOKEN_LIMIT=50000      # Threshold for Claude comfort zone
export GEMINI_TOKEN_LIMIT=800000     # Gemini's maximum capacity
export OPTIMAL_DELEGATION_SIZE=100000 # Optimal size for Gemini delegation

# File count thresholds
export MIN_FILES_FOR_GEMINI=3        # Minimum files to trigger delegation
export MAX_FILES_FOR_GEMINI=100      # Maximum files Gemini should handle
export OPTIMAL_FILE_COUNT=20         # Optimal file count for analysis

# Size thresholds (in bytes)
export MIN_SIZE_FOR_DELEGATION=50000     # 50KB minimum for delegation
export MAX_TOTAL_SIZE_FOR_GEMINI=10485760 # 10MB maximum total size
export CHUNK_SIZE_LIMIT=2097152          # 2MB per chunk if splitting needed

# ============================================
# Task-Specific Delegation Rules
# ============================================

# Define which tasks should prioritize Gemini
declare -A GEMINI_PRIORITY_TASKS=(
    ["comprehensive_analysis"]=true
    ["multi_file_search"]=true
    ["codebase_overview"]=true
    ["dependency_analysis"]=true
    ["security_audit"]=true
    ["performance_review"]=true
    ["documentation_generation"]=true
)

# Define patterns that should always use Gemini
export GEMINI_ALWAYS_PATTERNS="(analyze.*all|review.*entire|scan.*project|audit.*security|comprehensive.*|systematic.*)"

# Define patterns that should avoid Gemini
export GEMINI_NEVER_PATTERNS="(single.*file|quick.*check|simple.*read|small.*change)"

# ============================================
# Content Type Rules
# ============================================

# File extensions that benefit from Gemini's analysis
export GEMINI_PREFERRED_EXTENSIONS="go|rs|java|cpp|c|h|tsx|jsx|vue|py|rb|swift|kt|scala"

# File patterns to exclude from Gemini
export GEMINI_EXCLUDE_PATTERNS="(node_modules|vendor|\.git|dist|build|target|\.pyc|\.class)"

# Binary and large file handling
export SKIP_BINARY_FILES=true
export BINARY_EXTENSIONS="exe|dll|so|dylib|pdf|jpg|png|gif|zip|tar|gz"

# ============================================
# Analysis Enhancement Rules
# ============================================

# Enable Gemini for specific analysis types
export ENABLE_GEMINI_FOR_COMPLEXITY=true   # Complex code analysis
export ENABLE_GEMINI_FOR_SECURITY=true     # Security vulnerability scanning
export ENABLE_GEMINI_FOR_PERFORMANCE=true  # Performance bottleneck detection
export ENABLE_GEMINI_FOR_ARCHITECTURE=true # Architecture review
export ENABLE_GEMINI_FOR_TESTING=true      # Test coverage analysis

# ============================================
# Intelligent Delegation Functions
# ============================================

# Function to determine if task should be delegated
should_delegate_task() {
    local tool_name="$1"
    local file_count="$2"
    local total_size="$3"
    local prompt="$4"
    
    # Check if prompt matches always-delegate patterns
    if [[ "$prompt" =~ $GEMINI_ALWAYS_PATTERNS ]]; then
        echo "true"
        return 0
    fi
    
    # Check if prompt matches never-delegate patterns
    if [[ "$prompt" =~ $GEMINI_NEVER_PATTERNS ]]; then
        echo "false"
        return 1
    fi
    
    # Check file count and size thresholds
    if [ "$file_count" -ge "$MIN_FILES_FOR_GEMINI" ] && [ "$total_size" -ge "$MIN_SIZE_FOR_DELEGATION" ]; then
        if [ "$total_size" -le "$MAX_TOTAL_SIZE_FOR_GEMINI" ]; then
            echo "true"
            return 0
        fi
    fi
    
    # Check for priority tasks
    local task_key=$(echo "$prompt" | grep -oE "[a-z_]+" | head -1)
    if [ "${GEMINI_PRIORITY_TASKS[$task_key]}" = "true" ]; then
        echo "true"
        return 0
    fi
    
    echo "false"
    return 1
}

# Function to prepare delegation context
prepare_delegation_context() {
    local tool_name="$1"
    local files="$2"
    local working_dir="$3"
    local original_prompt="$4"
    
    cat << EOF
{
  "delegation_reason": "Content exceeds optimal Claude processing threshold",
  "tool": "$tool_name",
  "working_directory": "$working_dir",
  "file_count": $(echo "$files" | wc -w),
  "analysis_type": "comprehensive",
  "original_prompt": "$original_prompt",
  "delegation_strategy": "gemini_primary",
  "fallback_strategy": "claude_chunked"
}
EOF
}

# Function to format Gemini response for Claude
format_gemini_response() {
    local gemini_output="$1"
    local tool_name="$2"
    local file_count="$3"
    local processing_time="$4"
    
    cat << EOF
🤖 Gemini Assistant here! I've analyzed this content for you since it exceeded your optimal processing size.

Tool: $tool_name
Files analyzed: $file_count
Processing time: ${processing_time}s
───────────────────────────────────────

$gemini_output

───────────────────────────────────────
✅ Analysis complete. You can now proceed with your task based on this analysis.
EOF
}

# ============================================
# Oppie DevKit Specific Rules
# ============================================

# Special handling for Oppie DevKit components
declare -A OPPIE_COMPONENT_RULES=(
    ["reconstruction/claudia"]=true     # Always use Gemini for Claudia analysis
    ["experiments"]=true                 # Use Gemini for experiment analysis
    ["templates"]=false                  # Simple templates, use Claude
    ["scripts"]=false                    # Shell scripts, use Claude
    ["docs"]=true                       # Documentation benefits from Gemini
)

# Function to check Oppie component rules
check_oppie_component() {
    local file_path="$1"
    
    for component in "${!OPPIE_COMPONENT_RULES[@]}"; do
        if [[ "$file_path" == *"$component"* ]]; then
            echo "${OPPIE_COMPONENT_RULES[$component]}"
            return
        fi
    done
    
    echo "default"
}

# ============================================
# Performance Optimization
# ============================================

# Cache configuration
export GEMINI_CACHE_ENABLED=true
export GEMINI_CACHE_TTL=3600  # 1 hour cache TTL
export GEMINI_CACHE_DIR="/home/dev/workspace/claude-gemini-bridge/cache/gemini"

# Parallel processing settings
export ENABLE_PARALLEL_PROCESSING=true
export MAX_PARALLEL_WORKERS=4

# ============================================
# Logging and Debugging
# ============================================

export GEMINI_DEBUG_LEVEL=2  # 0=off, 1=basic, 2=verbose, 3=trace
export GEMINI_LOG_DIR="/home/dev/workspace/claude-gemini-bridge/logs"
export CAPTURE_DELEGATION_METRICS=true

# ============================================
# Export Functions for Use
# ============================================

export -f should_delegate_task
export -f prepare_delegation_context
export -f format_gemini_response
export -f check_oppie_component

echo "✅ Gemini delegation configuration loaded for Oppie DevKit"