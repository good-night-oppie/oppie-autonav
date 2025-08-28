#!/bin/bash
# ABOUTME: Enhanced main hook script with OAuth provider system support for Claude-Gemini Bridge

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# Module Loading and Initialization
# ============================================================================

# Load configuration system first
source "$SCRIPT_DIR/config/debug.conf"
source "$SCRIPT_DIR/lib/config-manager.sh"

# Initialize configuration
init_config

# Load core libraries
source "$SCRIPT_DIR/lib/debug-helpers.sh"
source "$SCRIPT_DIR/lib/path-converter.sh"
source "$SCRIPT_DIR/lib/json-parser.sh"
source "$SCRIPT_DIR/lib/gemini-wrapper.sh"
source "$SCRIPT_DIR/lib/oauth-handler.sh"
source "$SCRIPT_DIR/lib/enhanced-delegation.sh"

# Initialize provider system
source "$SCRIPT_DIR/providers/base-provider.sh"

# Discover and load available providers
AVAILABLE_PROVIDERS=()
for provider_script in "$SCRIPT_DIR/providers"/*-provider.sh; do
    if [ -f "$provider_script" ] && [ "$provider_script" != "$SCRIPT_DIR/providers/base-provider.sh" ]; then
        source "$provider_script"
        local provider_name=$(basename "$provider_script" | sed 's/-provider.sh//')
        provider_name="${provider_name//-/_}"
        AVAILABLE_PROVIDERS+=("$provider_name")
        debug_log 2 "Loaded provider: $provider_name"
    fi
done

# Set dynamic paths that aren't set in config
if [ -z "$CAPTURE_DIR" ]; then
    export CAPTURE_DIR="$SCRIPT_DIR/../debug/captured"
fi

# Initialize debug system
init_debug "gemini-bridge" "$SCRIPT_DIR/../logs/debug"

# Start performance measurement
start_timer "hook_execution"

debug_log 1 "Hook execution started with ${#AVAILABLE_PROVIDERS[@]} providers available"
debug_system_info

# ============================================================================
# Provider Selection and Authentication
# ============================================================================

# Select best available provider based on capabilities and auth status
select_provider() {
    local tool_name="$1"
    local file_count="$2"
    local estimated_tokens="$3"
    
    debug_log 2 "Selecting provider for tool: $tool_name, files: $file_count, tokens: $estimated_tokens"
    
    # Priority: 1) OAuth-enabled providers, 2) API key providers, 3) Gemini CLI fallback
    local selected_provider=""
    local selected_auth_type=""
    
    # Check each available provider
    for provider in "${AVAILABLE_PROVIDERS[@]}"; do
        # Check if provider has required function
        if declare -f "${provider}_get_capabilities" &>/dev/null; then
            local capabilities=$(${provider}_get_capabilities 2>/dev/null)
            
            # Check authentication status
            local auth_status=""
            if declare -f "${provider}_validate_auth" &>/dev/null; then
                auth_status=$(${provider}_validate_auth 2>/dev/null)
            fi
            
            if [ "$auth_status" = "valid" ]; then
                # Check if provider supports OAuth
                if echo "$capabilities" | grep -q '"oauth"'; then
                    selected_provider="$provider"
                    selected_auth_type="oauth"
                    debug_log 1 "Selected OAuth provider: $provider"
                    break
                elif echo "$capabilities" | grep -q '"api_key"'; then
                    if [ -z "$selected_provider" ]; then
                        selected_provider="$provider"
                        selected_auth_type="api_key"
                    fi
                fi
            fi
        fi
    done
    
    # Fallback to gemini-cli if available
    if [ -z "$selected_provider" ] && command -v gemini &>/dev/null; then
        selected_provider="gemini_cli"
        selected_auth_type="cli"
        debug_log 1 "Falling back to Gemini CLI"
    fi
    
    echo "$selected_provider:$selected_auth_type"
}

# Authenticate with selected provider
authenticate_provider() {
    local provider="$1"
    local auth_type="$2"
    
    debug_log 2 "Authenticating with provider: $provider ($auth_type)"
    
    case "$auth_type" in
        oauth)
            # Use OAuth authentication
            if declare -f "${provider}_authenticate" &>/dev/null; then
                local token=$(${provider}_authenticate 2>/dev/null)
                if [ -n "$token" ]; then
                    export PROVIDER_AUTH_TOKEN="$token"
                    debug_log 1 "OAuth authentication successful"
                    return 0
                fi
            fi
            ;;
        api_key)
            # Use API key authentication
            local api_key=$(get_config "auth.api_key" "")
            if [ -z "$api_key" ]; then
                api_key="${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}"
            fi
            if [ -n "$api_key" ]; then
                export PROVIDER_AUTH_TOKEN="$api_key"
                debug_log 1 "API key authentication successful"
                return 0
            fi
            ;;
        cli)
            # CLI handles its own authentication
            debug_log 1 "Using CLI authentication"
            return 0
            ;;
    esac
    
    debug_log 1 "Authentication failed for provider: $provider"
    return 1
}

# ============================================================================
# Main Hook Logic
# ============================================================================

# Read tool call JSON from stdin
TOOL_CALL_JSON=$(cat)

# Check for empty input
if [ -z "$TOOL_CALL_JSON" ]; then
    debug_log 1 "Empty input received, continuing with normal execution"
    create_hook_response "continue" "" "Empty input"
    exit 0
fi

debug_log 2 "Received tool call of size: $(echo "$TOOL_CALL_JSON" | wc -c) bytes"

# Save input for later analysis
if [ "$CAPTURE_INPUTS" = "true" ]; then
    CAPTURE_FILE=$(capture_input "$TOOL_CALL_JSON" "$CAPTURE_DIR")
    debug_log 1 "Input captured to: $CAPTURE_FILE"
fi

# Validate JSON
if ! validate_json "$TOOL_CALL_JSON"; then
    error_log "Invalid JSON received from Claude"
    create_hook_response "continue" "" "Invalid JSON input"
    exit 1
fi

# Determine working directory
WORKING_DIR=$(extract_working_directory "$TOOL_CALL_JSON")
if [ -z "$WORKING_DIR" ]; then
    WORKING_DIR=$(pwd)
    debug_log 1 "No working_directory in context, using: $WORKING_DIR"
else
    debug_log 2 "Working directory from context: $WORKING_DIR"
fi

# Extract tool type and parameters
TOOL_NAME=$(extract_tool_name "$TOOL_CALL_JSON")
TOOL_PARAMS=$(extract_parameters "$TOOL_CALL_JSON")

debug_log 1 "Processing tool: $TOOL_NAME"
debug_json "Tool parameters" "$TOOL_PARAMS"

# Extract file paths based on tool type
case "$TOOL_NAME" in
    "Read")
        FILE_PATH_RAW=$(extract_file_paths "$TOOL_PARAMS" "$TOOL_NAME")
        ABSOLUTE_PATH=$(convert_claude_paths "$FILE_PATH_RAW" "$WORKING_DIR")
        FILES="$ABSOLUTE_PATH"
        ORIGINAL_PROMPT="Read file: $FILE_PATH_RAW"
        ;;
    "Glob")
        PATTERN_RAW=$(extract_file_paths "$TOOL_PARAMS" "$TOOL_NAME")
        ABSOLUTE_PATTERN=$(convert_claude_paths "$PATTERN_RAW" "$WORKING_DIR")
        # Get search path from parameters
        SEARCH_PATH=$(echo "$TOOL_PARAMS" | jq -r '.path // empty')
        if [ -z "$SEARCH_PATH" ]; then
            SEARCH_PATH="$WORKING_DIR"
        fi
        # Expand glob pattern properly and safely
        cd "$SEARCH_PATH" 2>/dev/null || cd "$WORKING_DIR" 2>/dev/null || cd /tmp
        # Use find for safe glob expansion
        if [[ "$PATTERN_RAW" == "**/*"* ]]; then
            # Handle recursive patterns
            EXTENSION=$(echo "$PATTERN_RAW" | sed 's/.*\*\*\/\*\.\([^*]*\)$/\1/')
            if [ "$EXTENSION" != "$PATTERN_RAW" ]; then
                FILES=$(find . -name "*.${EXTENSION}" -type f 2>/dev/null | sed 's|^\./||' | head -$GEMINI_MAX_FILES)
            else
                FILES=$(find . -type f 2>/dev/null | sed 's|^\./||' | head -$GEMINI_MAX_FILES)
            fi
        else
            # Simple glob patterns
            FILES=$(ls $PATTERN_RAW 2>/dev/null | head -$GEMINI_MAX_FILES)
        fi
        # Convert to absolute paths
        ABSOLUTE_FILES=""
        for file in $FILES; do
            ABSOLUTE_FILES="$ABSOLUTE_FILES $(cd "$SEARCH_PATH" && pwd)/$file"
        done
        FILES="$ABSOLUTE_FILES"
        ORIGINAL_PROMPT="Find files matching: $PATTERN_RAW in $SEARCH_PATH"
        ;;
    "Grep")
        GREP_INFO=$(extract_file_paths "$TOOL_PARAMS" "$TOOL_NAME")
        GREP_PATH=$(echo "$GREP_INFO" | cut -d' ' -f1)
        ABSOLUTE_GREP_PATH=$(convert_claude_paths "$GREP_PATH" "$WORKING_DIR")
        # For Grep we use the search path as basis
        FILES="$ABSOLUTE_GREP_PATH"
        ORIGINAL_PROMPT="Search in: $GREP_INFO"
        ;;
    "Task")
        TASK_PROMPT=$(extract_task_prompt "$TOOL_PARAMS")
        CONVERTED_PROMPT=$(convert_claude_paths "$TASK_PROMPT" "$WORKING_DIR")
        # Extract file paths from prompt
        FILES=$(extract_files_from_text "$CONVERTED_PROMPT")
        ORIGINAL_PROMPT="$TASK_PROMPT"
        ;;
    *)
        debug_log 1 "Unknown tool type: $TOOL_NAME, continuing normally"
        create_hook_response "continue"
        exit 0
        ;;
esac

debug_vars "extracted" TOOL_NAME FILES WORKING_DIR ORIGINAL_PROMPT

# ============================================================================
# Provider-Aware Decision Engine
# ============================================================================

# Enhanced decision function with provider capabilities
should_delegate_to_provider() {
    local tool="$1"
    local files="$2"
    local prompt="$3"
    
    # Dry-run mode - always delegate for tests
    if [ "$DRY_RUN" = "true" ]; then
        debug_log 1 "DRY_RUN mode: would delegate to provider"
        return 0
    fi
    
    # Calculate estimated token count (rough estimate: 4 chars = 1 token)
    local total_size=0
    local file_count=0
    
    if [ -n "$files" ]; then
        file_count=$(count_files "$files")
        for file in $files; do
            if [ -f "$file" ]; then
                local file_size=$(debug_file_size "$file")
                total_size=$((total_size + file_size))
            fi
        done
    fi
    
    # Rough token estimation: 4 characters ≈ 1 token
    local estimated_tokens=$((total_size / 4))
    
    debug_log 2 "File count: $file_count, Total size: $total_size bytes, Estimated tokens: $estimated_tokens"
    
    # Get configuration values with fallback to legacy env vars
    local claude_token_limit=$(get_config "limits.claude_tokens" "${CLAUDE_TOKEN_LIMIT:-50000}")
    local gemini_token_limit=$(get_config "limits.gemini_tokens" "${GEMINI_TOKEN_LIMIT:-800000}")
    local min_files_threshold=$(get_config "limits.min_files" "${MIN_FILES_FOR_GEMINI:-3}")
    local max_total_size=$(get_config "limits.max_size" "${MAX_TOTAL_SIZE_FOR_GEMINI:-10485760}")
    
    # Check if total size exceeds maximum limit
    if [ "$total_size" -gt "$max_total_size" ]; then
        debug_log 1 "Content too large ($total_size bytes > $max_total_size) - exceeds maximum size limit"
        return 1
    fi
    
    # Check for excluded file patterns
    for file in $files; do
        local filename=$(basename "$file")
        if [[ "$filename" =~ $GEMINI_EXCLUDE_PATTERNS ]]; then
            debug_log 2 "Excluded file pattern detected: $filename"
            return 1
        fi
    done
    
    # If estimated tokens exceed Claude's comfortable limit, delegate
    if [ "$estimated_tokens" -gt "$claude_token_limit" ]; then
        if [ "$estimated_tokens" -le "$gemini_token_limit" ]; then
            debug_log 1 "Large content ($estimated_tokens tokens > $claude_token_limit) - delegating to provider"
            return 0
        else
            debug_log 1 "Content too large even for providers ($estimated_tokens tokens > $gemini_token_limit)"
            return 1
        fi
    fi
    
    # For smaller content, check if it's a multi-file analysis task
    if [ "$file_count" -ge "$min_files_threshold" ] && [[ "$tool" == "Task" ]]; then
        debug_log 1 "Multi-file Task ($file_count files >= $min_files_threshold) - delegating to provider"
        return 0
    fi
    
    debug_log 2 "Content size manageable for Claude - no delegation needed"
    return 1
}

# ============================================================================
# Main Execution with Provider Support
# ============================================================================

# Check if we should delegate to a provider (using enhanced logic)
if should_delegate_to_provider_enhanced "$TOOL_NAME" "$FILES" "$ORIGINAL_PROMPT"; then
    debug_log 1 "Delegating to provider for tool: $TOOL_NAME"
    
    # Calculate metrics for provider selection
    FILE_COUNT=$(count_files "$FILES")
    TOTAL_SIZE=0
    for file in $FILES; do
        if [ -f "$file" ]; then
            TOTAL_SIZE=$((TOTAL_SIZE + $(debug_file_size "$file")))
        fi
    done
    ESTIMATED_TOKENS=$((TOTAL_SIZE / 4))
    
    # Select best provider
    PROVIDER_INFO=$(select_provider "$TOOL_NAME" "$FILE_COUNT" "$ESTIMATED_TOKENS")
    SELECTED_PROVIDER=$(echo "$PROVIDER_INFO" | cut -d: -f1)
    SELECTED_AUTH_TYPE=$(echo "$PROVIDER_INFO" | cut -d: -f2)
    
    if [ -z "$SELECTED_PROVIDER" ]; then
        error_log "No suitable provider available"
        create_hook_response "continue" "" "No provider available"
        exit 1
    fi
    
    # Authenticate with provider
    if ! authenticate_provider "$SELECTED_PROVIDER" "$SELECTED_AUTH_TYPE"; then
        error_log "Failed to authenticate with provider: $SELECTED_PROVIDER"
        
        # Try fallback to legacy Gemini wrapper if available
        if command -v gemini &>/dev/null && init_gemini_wrapper; then
            debug_log 1 "Falling back to legacy Gemini wrapper"
            SELECTED_PROVIDER="legacy_gemini"
        else
            create_hook_response "continue" "" "Authentication failed"
            exit 1
        fi
    fi
    
    # Execute request with provider
    start_timer "provider_processing"
    
    if [ "$SELECTED_PROVIDER" = "legacy_gemini" ]; then
        # Use legacy Gemini wrapper
        PROVIDER_RESULT=$(call_gemini "$TOOL_NAME" "$FILES" "$WORKING_DIR" "$ORIGINAL_PROMPT")
        PROVIDER_EXIT_CODE=$?
    elif declare -f "${SELECTED_PROVIDER}_execute_request" &>/dev/null; then
        # Use provider's execute method
        PROVIDER_RESULT=$(${SELECTED_PROVIDER}_execute_request "generateContent" "$ORIGINAL_PROMPT" "$FILES")
        PROVIDER_EXIT_CODE=$?
    else
        # Fallback to generic Gemini call
        PROVIDER_RESULT=$(call_gemini "$TOOL_NAME" "$FILES" "$WORKING_DIR" "$ORIGINAL_PROMPT")
        PROVIDER_EXIT_CODE=$?
    fi
    
    PROVIDER_DURATION=$(end_timer "provider_processing")
    
    if [ "$PROVIDER_EXIT_CODE" -eq 0 ] && [ -n "$PROVIDER_RESULT" ]; then
        # Successful provider response
        debug_log 1 "Provider processing successful via $SELECTED_PROVIDER (${PROVIDER_DURATION}s)"
        
        # Create structured response
        STRUCTURED_RESPONSE=$(create_gemini_response "$PROVIDER_RESULT" "$TOOL_NAME" "$FILE_COUNT" "$PROVIDER_DURATION")
        
        # Add provider metadata to response
        if [ "$SELECTED_AUTH_TYPE" = "oauth" ]; then
            STRUCTURED_RESPONSE=$(echo "$STRUCTURED_RESPONSE" | sed "s/via Gemini/via $SELECTED_PROVIDER (OAuth)/")
        else
            STRUCTURED_RESPONSE=$(echo "$STRUCTURED_RESPONSE" | sed "s/via Gemini/via $SELECTED_PROVIDER/")
        fi
        
        # Hook response with provider result
        create_hook_response "replace" "$STRUCTURED_RESPONSE"
    else
        # Provider error - continue normally
        error_log "Provider processing failed, continuing with normal tool execution"
        create_hook_response "continue" "" "Provider processing failed"
    fi
else
    # Continue normally without provider delegation
    debug_log 1 "Continuing with normal tool execution"
    create_hook_response "continue"
fi

# ============================================================================
# Cleanup and Finalization
# ============================================================================

# End performance measurement
TOTAL_DURATION=$(end_timer "hook_execution")
debug_log 1 "Hook execution completed in ${TOTAL_DURATION}s"

# Save performance metrics
if [ -n "$SELECTED_PROVIDER" ]; then
    echo "$(date -Iseconds)|$SELECTED_PROVIDER|$SELECTED_AUTH_TYPE|$TOOL_NAME|$FILE_COUNT|$ESTIMATED_TOKENS|$PROVIDER_DURATION" >> "$SCRIPT_DIR/../logs/provider_metrics.log"
fi

# Automatic cleanup
if [ "$AUTO_CLEANUP_CACHE" = "true" ]; then
    # Only clean occasionally (about 1 in 10 times)
    if [ $((RANDOM % 10)) -eq 0 ]; then
        cleanup_old_cache "$SCRIPT_DIR/../cache" 3600 &
        cleanup_old_logs "$SCRIPT_DIR/../logs" 86400 &
    fi
fi

# Ensure cleanup on exit
trap secure_cleanup EXIT