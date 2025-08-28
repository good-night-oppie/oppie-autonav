#!/bin/bash
# ABOUTME: Token rotation and lifecycle management with automatic refresh and expiration handling

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
source "$SCRIPT_DIR/token-storage.sh"
source "$SCRIPT_DIR/oauth-handler.sh"

# Rotation configuration
if [ -z "$DEFAULT_ROTATION_INTERVAL" ]; then
    readonly DEFAULT_ROTATION_INTERVAL=3300     # 55 minutes (before typical 1-hour expiry)
    readonly DEFAULT_REFRESH_BUFFER=300         # 5 minutes before expiration
    readonly MAX_TOKEN_AGE=86400               # 24 hours maximum token age
    readonly ROTATION_CHECK_INTERVAL=60         # Check every minute for rotation needs
    readonly MAX_ROTATION_RETRIES=3            # Maximum rotation retry attempts
fi

# Rotation state file
ROTATION_STATE_FILE="${ROTATION_STATE_FILE:-$TOKEN_STORAGE_DIR/rotation_state.json}"
ROTATION_LOCK_FILE="${ROTATION_LOCK_FILE:-$TOKEN_STORAGE_DIR/.rotation.lock}"

# ============================================================================
# Rotation State Management
# ============================================================================

# Initialize rotation state
init_rotation_state() {
    if [ ! -f "$ROTATION_STATE_FILE" ]; then
        cat > "$ROTATION_STATE_FILE" << EOF
{
  "last_check": "$(date -Iseconds)",
  "rotations": {},
  "errors": {}
}
EOF
        chmod 600 "$ROTATION_STATE_FILE"
    fi
}

# Update rotation state
update_rotation_state() {
    local provider="$1"
    local action="$2"  # check, rotate, error
    local details="$3"
    
    if [ ! -f "$ROTATION_STATE_FILE" ]; then
        init_rotation_state
    fi
    
    local state=$(cat "$ROTATION_STATE_FILE")
    local timestamp=$(date -Iseconds)
    
    if command -v jq &>/dev/null; then
        case "$action" in
            check)
                state=$(echo "$state" | jq ".last_check = \"$timestamp\"")
                ;;
            rotate)
                state=$(echo "$state" | jq ".rotations.\"$provider\" = {
                    \"timestamp\": \"$timestamp\",
                    \"success\": true,
                    \"details\": \"$details\"
                }")
                ;;
            error)
                state=$(echo "$state" | jq ".errors.\"$provider\" = {
                    \"timestamp\": \"$timestamp\",
                    \"details\": \"$details\"
                }")
                ;;
        esac
        
        echo "$state" > "$ROTATION_STATE_FILE"
    fi
}

# ============================================================================
# Token Expiration Checking
# ============================================================================

# Check if token needs rotation
needs_rotation() {
    local provider="$1"
    local buffer="${2:-$DEFAULT_REFRESH_BUFFER}"
    
    # Check if token exists
    if ! retrieve_token "$provider" >/dev/null 2>&1; then
        echo "Error: No token found for provider: $provider" >&2
        return 0  # Need rotation if no token
    fi
    
    # Check if token is expired or near expiry
    if is_token_expired "$provider" "$buffer"; then
        debug_log 2 "Token for $provider is expired or near expiry"
        return 0
    fi
    
    # Check token age
    local token_age=$(get_token_age "$provider")
    if [ -n "$token_age" ] && [ "$token_age" -gt "$MAX_TOKEN_AGE" ]; then
        debug_log 2 "Token for $provider exceeds maximum age: $token_age seconds"
        return 0
    fi
    
    return 1  # No rotation needed
}

# Get token age in seconds
get_token_age() {
    local provider="$1"
    
    if [ ! -f "$TOKEN_METADATA_FILE" ]; then
        return 1
    fi
    
    local stored_at
    if command -v jq &>/dev/null; then
        stored_at=$(cat "$TOKEN_METADATA_FILE" | jq -r ".\"$provider\".last_updated // empty")
    else
        stored_at=$(cat "$TOKEN_METADATA_FILE" | grep -o "\"$provider\".*last_updated.*\"[^\"]*\"" | \
                   grep -o "\"last_updated\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | cut -d'"' -f4)
    fi
    
    if [ -z "$stored_at" ]; then
        return 1
    fi
    
    local stored_timestamp=$(date -d "$stored_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "$stored_at" +%s 2>/dev/null)
    local current_timestamp=$(date +%s)
    
    echo $((current_timestamp - stored_timestamp))
}

# ============================================================================
# Token Rotation Functions
# ============================================================================

# Rotate token for provider
rotate_token() {
    local provider="$1"
    local force="${2:-false}"
    
    debug_log 1 "Starting token rotation for provider: $provider"
    
    # Acquire rotation lock
    if ! acquire_rotation_lock; then
        echo "Error: Could not acquire rotation lock" >&2
        return 1
    fi
    
    # Check if rotation is needed
    if [ "$force" != "true" ] && ! needs_rotation "$provider"; then
        debug_log 2 "Token rotation not needed for $provider"
        release_rotation_lock
        return 0
    fi
    
    # Get current refresh token
    local refresh_token=$(retrieve_token "$provider" "refresh_token")
    
    if [ -z "$refresh_token" ] || [ "$refresh_token" = "null" ]; then
        debug_log 1 "No refresh token available for $provider, attempting re-authentication"
        
        # Re-authenticate if no refresh token
        if ! reauthenticate_provider "$provider"; then
            error_log "Failed to re-authenticate provider: $provider"
            update_rotation_state "$provider" "error" "Re-authentication failed"
            release_rotation_lock
            return 1
        fi
    else
        # Use refresh token to get new access token
        if ! refresh_provider_token "$provider" "$refresh_token"; then
            error_log "Failed to refresh token for provider: $provider"
            
            # Fallback to re-authentication
            if ! reauthenticate_provider "$provider"; then
                update_rotation_state "$provider" "error" "Refresh and re-authentication failed"
                release_rotation_lock
                return 1
            fi
        fi
    fi
    
    update_rotation_state "$provider" "rotate" "Token rotated successfully"
    debug_log 1 "Token rotation completed for provider: $provider"
    
    release_rotation_lock
    return 0
}

# Refresh provider token using refresh token
refresh_provider_token() {
    local provider="$1"
    local refresh_token="$2"
    
    debug_log 2 "Refreshing token for provider: $provider"
    
    # Call provider-specific refresh function
    if declare -f "${provider}_refresh_token" &>/dev/null; then
        local response=$(${provider}_refresh_token "$refresh_token")
        
        if [ $? -eq 0 ] && [ -n "$response" ]; then
            # Parse response and store new tokens
            local access_token=$(echo "$response" | jq -r '.access_token // empty')
            local new_refresh_token=$(echo "$response" | jq -r '.refresh_token // empty')
            local expires_in=$(echo "$response" | jq -r '.expires_in // 3600')
            
            if [ -z "$access_token" ]; then
                error_log "No access token in refresh response"
                return 1
            fi
            
            # Use new refresh token if provided, otherwise keep old one
            if [ -z "$new_refresh_token" ] || [ "$new_refresh_token" = "null" ]; then
                new_refresh_token="$refresh_token"
            fi
            
            # Calculate expiration time
            local expires_at=$(date -d "+${expires_in} seconds" -Iseconds 2>/dev/null || \
                              date -v +${expires_in}S -Iseconds 2>/dev/null)
            
            # Store updated tokens
            if store_token "$provider" "oauth" "$access_token" "$expires_at" "$new_refresh_token"; then
                debug_log 1 "Token refreshed successfully for $provider"
                return 0
            fi
        fi
    else
        debug_log 1 "No refresh function for provider: $provider"
    fi
    
    return 1
}

# Re-authenticate with provider
reauthenticate_provider() {
    local provider="$1"
    
    debug_log 1 "Re-authenticating with provider: $provider"
    
    # Call provider-specific authentication
    if declare -f "${provider}_authenticate" &>/dev/null; then
        if ${provider}_authenticate; then
            debug_log 1 "Re-authentication successful for $provider"
            return 0
        fi
    fi
    
    # Fallback to OAuth flow
    if oauth_login "$provider"; then
        debug_log 1 "OAuth re-authentication successful for $provider"
        return 0
    fi
    
    return 1
}

# ============================================================================
# Automatic Rotation Management
# ============================================================================

# Start automatic rotation daemon
start_rotation_daemon() {
    local interval="${1:-$ROTATION_CHECK_INTERVAL}"
    local pid_file="$TOKEN_STORAGE_DIR/.rotation_daemon.pid"
    
    # Check if daemon is already running
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Rotation daemon already running with PID: $pid"
            return 0
        fi
    fi
    
    # Start daemon in background
    (
        echo $$ > "$pid_file"
        trap 'rm -f "$pid_file"; exit' EXIT INT TERM
        
        while true; do
            check_all_tokens
            sleep "$interval"
        done
    ) &
    
    echo "Started rotation daemon with PID: $!"
}

# Stop rotation daemon
stop_rotation_daemon() {
    local pid_file="$TOKEN_STORAGE_DIR/.rotation_daemon.pid"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill "$pid" 2>/dev/null; then
            echo "Stopped rotation daemon with PID: $pid"
            rm -f "$pid_file"
            return 0
        fi
    fi
    
    echo "No rotation daemon found"
    return 1
}

# Check all tokens for rotation
check_all_tokens() {
    update_rotation_state "" "check" "Checking all tokens"
    
    local providers=$(list_token_providers)
    
    for provider in $providers; do
        if needs_rotation "$provider"; then
            debug_log 1 "Token rotation needed for: $provider"
            
            # Attempt rotation with retries
            local retry_count=0
            local success=false
            
            while [ $retry_count -lt $MAX_ROTATION_RETRIES ]; do
                if rotate_token "$provider"; then
                    success=true
                    break
                fi
                
                retry_count=$((retry_count + 1))
                debug_log 2 "Rotation attempt $retry_count failed for $provider"
                sleep 5
            done
            
            if [ "$success" != "true" ]; then
                error_log "Failed to rotate token for $provider after $MAX_ROTATION_RETRIES attempts"
                update_rotation_state "$provider" "error" "Max retries exceeded"
            fi
        fi
    done
}

# ============================================================================
# Lock Management for Rotation
# ============================================================================

# Acquire rotation lock
acquire_rotation_lock() {
    local timeout="${1:-30}"
    local wait_time=0
    
    while [ $wait_time -lt "$timeout" ]; do
        if mkdir "$ROTATION_LOCK_FILE" 2>/dev/null; then
            echo $$ > "$ROTATION_LOCK_FILE/pid"
            return 0
        fi
        
        # Check for stale lock
        if [ -f "$ROTATION_LOCK_FILE/pid" ]; then
            local lock_pid=$(cat "$ROTATION_LOCK_FILE/pid" 2>/dev/null)
            if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
                rm -rf "$ROTATION_LOCK_FILE"
                continue
            fi
        fi
        
        sleep 1
        wait_time=$((wait_time + 1))
    done
    
    return 1
}

# Release rotation lock
release_rotation_lock() {
    if [ -d "$ROTATION_LOCK_FILE" ]; then
        local lock_pid=$(cat "$ROTATION_LOCK_FILE/pid" 2>/dev/null)
        if [ "$lock_pid" = "$$" ]; then
            rm -rf "$ROTATION_LOCK_FILE"
        fi
    fi
}

# ============================================================================
# Utility Functions
# ============================================================================

# Force rotation for all providers
force_rotate_all() {
    local providers=$(list_token_providers)
    local success_count=0
    local fail_count=0
    
    for provider in $providers; do
        echo "Rotating token for: $provider"
        if rotate_token "$provider" "true"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done
    
    echo "Rotation complete: $success_count successful, $fail_count failed"
}

# Show rotation status
rotation_status() {
    if [ ! -f "$ROTATION_STATE_FILE" ]; then
        echo "No rotation state found"
        return 1
    fi
    
    if command -v jq &>/dev/null; then
        cat "$ROTATION_STATE_FILE" | jq .
    else
        cat "$ROTATION_STATE_FILE"
    fi
}

# Clean expired rotation history
clean_rotation_history() {
    local max_age="${1:-86400}"  # Default 24 hours
    
    if [ ! -f "$ROTATION_STATE_FILE" ]; then
        return 0
    fi
    
    local current_timestamp=$(date +%s)
    local state=$(cat "$ROTATION_STATE_FILE")
    
    if command -v jq &>/dev/null; then
        # Remove old rotation entries
        state=$(echo "$state" | jq --arg max_age "$max_age" --arg now "$current_timestamp" '
            .rotations |= with_entries(
                select(
                    ($now | tonumber) - (.value.timestamp | sub("\\+.*"; "") | fromdateiso8601) < ($max_age | tonumber)
                )
            ) |
            .errors |= with_entries(
                select(
                    ($now | tonumber) - (.value.timestamp | sub("\\+.*"; "") | fromdateiso8601) < ($max_age | tonumber)
                )
            )
        ')
        
        echo "$state" > "$ROTATION_STATE_FILE"
    fi
}

# ============================================================================
# Initialization
# ============================================================================

# Initialize rotation system
init_rotation_state