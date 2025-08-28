#!/bin/bash
# ABOUTME: OAuth handler for managing authentication tokens

# Default token directory - using auth instead of oauth for consistency
OAUTH_TOKEN_DIR="${OAUTH_TOKEN_DIR:-$HOME/.claude-gemini-bridge/auth}"

# Token file location
OAUTH_TOKEN_FILE="${OAUTH_TOKEN_FILE:-$OAUTH_TOKEN_DIR/tokens.json}"

# Source dependencies if available
[ -f "$(dirname "${BASH_SOURCE[0]}")/config-manager.sh" ] && source "$(dirname "${BASH_SOURCE[0]}")/config-manager.sh"
[ -f "$(dirname "${BASH_SOURCE[0]}")/debug-helpers.sh" ] && source "$(dirname "${BASH_SOURCE[0]}")/debug-helpers.sh"

# Token cache for validated tokens (avoids repeated API calls)
declare -A VALIDATED_TOKENS
declare -A VALIDATION_TIMESTAMPS

# Initialize OAuth system
init_oauth_system() {
    # Create token directory with secure permissions
    mkdir -p "$OAUTH_TOKEN_DIR"
    chmod 700 "$OAUTH_TOKEN_DIR"
    
    # Initialize token file if it doesn't exist
    if [ ! -f "$OAUTH_TOKEN_FILE" ]; then
        echo '{}' > "$OAUTH_TOKEN_FILE"
        chmod 600 "$OAUTH_TOKEN_FILE"
    fi
    
    # Clear validation cache
    VALIDATED_TOKENS=()
    VALIDATION_TIMESTAMPS=()
}

# Get token file path
oauth_get_token_file() {
    echo "$OAUTH_TOKEN_FILE"
}

# Ensure auth directory exists with proper permissions
oauth_ensure_auth_dir() {
    mkdir -p "$OAUTH_TOKEN_DIR"
    chmod 700 "$OAUTH_TOKEN_DIR"
    return 0
}

# Extract token from JSON response
oauth_extract_token() {
    local json_response="$1"
    local field="${2:-access_token}"
    
    if [ -z "$json_response" ]; then
        echo ""
        return 1
    fi
    
    # Try to extract the field value
    local value=$(echo "$json_response" | sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p")
    
    echo "$value"
}

# Check token expiry
oauth_check_expiry() {
    local expires_at="$1"
    
    if [ -z "$expires_at" ] || [ "$expires_at" = "null" ]; then
        echo "expired"  # No expiry means treat as expired
        return 1
    fi
    
    local current_time=$(date +%s)
    
    if [ "$expires_at" -gt "$current_time" ]; then
        echo "valid"
        return 0
    else
        echo "expired"
        return 1
    fi
}

# Cleanup sensitive memory
oauth_cleanup_memory() {
    unset ACCESS_TOKEN
    unset REFRESH_TOKEN
    unset CLIENT_SECRET
    unset AUTH_CODE
    return 0
}

# Store OAuth token securely (new format: all providers in one file)
store_oauth_token() {
    local provider="$1"
    local access_token="$2"
    local refresh_token="$3"
    local expires_in="${4:-3600}"  # Default 1 hour
    
    if [ -z "$provider" ] || [ -z "$access_token" ]; then
        echo "Error: Provider and access token are required" >&2
        return 1
    fi
    
    # Ensure token directory exists
    oauth_ensure_auth_dir
    
    local expiry=$(($(date +%s) + expires_in))
    local temp_file="${OAUTH_TOKEN_FILE}.tmp.$$"
    
    # Read existing tokens
    local existing_tokens="{}"
    if [ -f "$OAUTH_TOKEN_FILE" ]; then
        existing_tokens=$(cat "$OAUTH_TOKEN_FILE" 2>/dev/null || echo '{}')
    fi
    
    # Use Python for safe JSON manipulation if available
    if command -v python3 &> /dev/null || command -v python &> /dev/null; then
        local python_cmd=$(command -v python3 || command -v python)
        
        $python_cmd << PYTHON_SCRIPT > "$temp_file"
import json
import sys

try:
    existing = '''$existing_tokens'''
    tokens = json.loads(existing) if existing else {}
except:
    tokens = {}

tokens['$provider'] = {
    'access_token': '$access_token',
    'refresh_token': '$refresh_token',
    'expires_at': $expiry,
    'provider': '$provider',
    'updated_at': $(date +%s)
}

print(json.dumps(tokens, indent=2))
PYTHON_SCRIPT
    else
        # Fallback to sed/awk manipulation
        echo '{' > "$temp_file"
        echo "  \"$provider\": {" >> "$temp_file"
        echo "    \"access_token\": \"$access_token\"," >> "$temp_file"
        echo "    \"refresh_token\": \"$refresh_token\"," >> "$temp_file"
        echo "    \"expires_at\": $expiry," >> "$temp_file"
        echo "    \"provider\": \"$provider\"," >> "$temp_file"
        echo "    \"updated_at\": $(date +%s)" >> "$temp_file"
        echo "  }" >> "$temp_file"
        echo '}' >> "$temp_file"
    fi
    
    # Atomic write: write to temp, then move
    if [ -f "$temp_file" ]; then
        mv -f "$temp_file" "$OAUTH_TOKEN_FILE"
        chmod 600 "$OAUTH_TOKEN_FILE"
        return 0
    else
        echo "Error: Failed to write token file" >&2
        return 1
    fi
}

# Get OAuth token (from new JSON structure)
get_oauth_token() {
    local provider="$1"
    
    if [ -z "$provider" ]; then
        echo "Error: Provider name is required" >&2
        return 1
    fi
    
    if [ ! -f "$OAUTH_TOKEN_FILE" ]; then
        echo "Error: Token file not found" >&2
        return 1
    fi
    
    # Extract access token for specific provider
    local access_token
    
    # Use Python for safe JSON parsing if available
    if command -v python3 &> /dev/null || command -v python &> /dev/null; then
        local python_cmd=$(command -v python3 || command -v python)
        
        access_token=$($python_cmd << PYTHON_SCRIPT 2>/dev/null
import json
import sys

try:
    with open('$OAUTH_TOKEN_FILE', 'r') as f:
        tokens = json.load(f)
    
    if '$provider' in tokens:
        print(tokens['$provider'].get('access_token', ''))
except:
    pass
PYTHON_SCRIPT
)
    else
        # Fallback to grep/sed
        access_token=$(grep -A5 "\"$provider\"" "$OAUTH_TOKEN_FILE" | grep '"access_token"' | sed 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    fi
    
    if [ -z "$access_token" ]; then
        echo "Error: Token not found for provider '$provider'" >&2
        return 1
    fi
    
    echo "$access_token"
}

# Get refresh token (from new JSON structure)
get_refresh_token() {
    local provider="$1"
    
    if [ -z "$provider" ]; then
        echo "Error: Provider name is required" >&2
        return 1
    fi
    
    if [ ! -f "$OAUTH_TOKEN_FILE" ]; then
        echo "Error: Token file not found" >&2
        return 1
    fi
    
    # Extract refresh token for specific provider
    local refresh_token
    
    # Use Python for safe JSON parsing if available
    if command -v python3 &> /dev/null || command -v python &> /dev/null; then
        local python_cmd=$(command -v python3 || command -v python)
        
        refresh_token=$($python_cmd << PYTHON_SCRIPT 2>/dev/null
import json
import sys

try:
    with open('$OAUTH_TOKEN_FILE', 'r') as f:
        tokens = json.load(f)
    
    if '$provider' in tokens:
        print(tokens['$provider'].get('refresh_token', ''))
except:
    pass
PYTHON_SCRIPT
)
    else
        # Fallback to grep/sed
        refresh_token=$(grep -A5 "\"$provider\"" "$OAUTH_TOKEN_FILE" | grep '"refresh_token"' | sed 's/.*"refresh_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    fi
    
    echo "$refresh_token"
}

# Validate OAuth token
validate_oauth_token() {
    local token_json="$1"
    
    # Extract expiry timestamp
    local expires_at=$(echo "$token_json" | grep '"exp"' | sed 's/.*"exp"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/')
    
    if [ -z "$expires_at" ]; then
        # Try alternative field name
        expires_at=$(echo "$token_json" | grep '"expires_at"' | sed 's/.*"expires_at"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/')
    fi
    
    if [ -z "$expires_at" ]; then
        echo "false"
        return 1
    fi
    
    local current_time=$(date +%s)
    
    if [ "$expires_at" -gt "$current_time" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# Refresh OAuth token
refresh_oauth_token() {
    local provider="$1"
    local refresh_function="${2:-${provider}_refresh_token}"
    
    if [ -z "$provider" ]; then
        echo "Error: Provider name is required" >&2
        return 1
    fi
    
    # Get current refresh token
    local refresh_token=$(get_refresh_token "$provider" 2>/dev/null)
    
    if [ -z "$refresh_token" ]; then
        echo "Error: No refresh token available" >&2
        return 1
    fi
    
    # Call provider-specific refresh function
    if declare -f "$refresh_function" > /dev/null; then
        local new_token=$("$refresh_function" "$refresh_token")
        
        if [ -n "$new_token" ]; then
            # Update stored token
            store_oauth_token "$provider" "$new_token" "$refresh_token"
            echo "$new_token"
        else
            echo "Error: Failed to refresh token" >&2
            return 1
        fi
    else
        echo "Error: Refresh function '$refresh_function' not found" >&2
        return 1
    fi
}

# Initiate OAuth flow
initiate_oauth_flow() {
    local auth_url="$1"
    local client_id="$2"
    local redirect_uri="$3"
    local scope="${4:-}"
    local state="${5:-$(openssl rand -hex 16 2>/dev/null || echo "random-state")}"
    
    if [ -z "$auth_url" ] || [ -z "$client_id" ] || [ -z "$redirect_uri" ]; then
        echo "Error: Auth URL, client ID, and redirect URI are required" >&2
        return 1
    fi
    
    # Build authorization URL
    local full_auth_url="${auth_url}?client_id=${client_id}&redirect_uri=${redirect_uri}&response_type=code&state=${state}"
    
    if [ -n "$scope" ]; then
        full_auth_url="${full_auth_url}&scope=${scope}"
    fi
    
    # Open browser for user authorization
    if command -v xdg-open &> /dev/null; then
        xdg-open "$full_auth_url" 2>/dev/null
        echo "Opening browser for authorization"
    elif command -v open &> /dev/null; then
        open "$full_auth_url" 2>/dev/null
        echo "Opening browser for authorization"
    else
        echo "Please open the following URL in your browser:"
        echo "$full_auth_url"
    fi
    
    echo "$state"  # Return state for verification
}

# Handle OAuth callback
handle_oauth_callback() {
    local callback_data="$1"
    
    if [ -z "$callback_data" ]; then
        echo "Error: Callback data is required" >&2
        return 1
    fi
    
    # Extract authorization code
    local auth_code=$(echo "$callback_data" | grep -o 'code=[^&]*' | cut -d'=' -f2)
    
    if [ -z "$auth_code" ]; then
        echo "Error: No authorization code in callback" >&2
        return 1
    fi
    
    echo "$auth_code"
}

# OAuth login for providers
oauth_login() {
    local provider="$1"
    
    if [ -z "$provider" ]; then
        echo "Error: Provider name is required" >&2
        return 1
    fi
    
    # Ensure auth directory exists
    oauth_ensure_auth_dir
    
    case "$provider" in
        gemini|gemini-cli)
            # Use gemini CLI's built-in auth
            echo "Initiating Gemini OAuth login..." >&2
            
            # Execute gemini auth login and capture response
            local auth_response=$(gemini auth login 2>&1)
            
            if [ $? -ne 0 ]; then
                echo "Error: Gemini authentication failed" >&2
                echo "$auth_response" >&2
                return 1
            fi
            
            # Extract tokens from response (format may vary)
            local access_token=$(echo "$auth_response" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
            local refresh_token=$(echo "$auth_response" | grep -o '"refresh_token":"[^"]*' | cut -d'"' -f4)
            local expires_in=$(echo "$auth_response" | grep -o '"expires_in":[0-9]*' | cut -d':' -f2)
            
            # If tokens not in response, try to get from gemini config
            if [ -z "$access_token" ]; then
                # Try to extract from gemini's internal token storage
                local gemini_token_file="$HOME/.gemini/auth.json"
                if [ -f "$gemini_token_file" ]; then
                    access_token=$(grep '"access_token"' "$gemini_token_file" | sed 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
                    refresh_token=$(grep '"refresh_token"' "$gemini_token_file" | sed 's/.*"refresh_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
                fi
            fi
            
            if [ -z "$access_token" ]; then
                echo "Error: Failed to extract access token from Gemini response" >&2
                return 1
            fi
            
            # Store tokens
            store_oauth_token "gemini" "$access_token" "$refresh_token" "${expires_in:-3600}"
            
            echo "Successfully authenticated with Gemini" >&2
            echo "$access_token"
            return 0
            ;;
            
        google)
            # Google OAuth 2.0 Device Flow
            echo "Initiating Google OAuth device flow..." >&2
            
            # Device flow endpoint
            local device_endpoint="https://oauth2.googleapis.com/device/code"
            local client_id="${GOOGLE_CLIENT_ID:-}"
            
            if [ -z "$client_id" ]; then
                echo "Error: GOOGLE_CLIENT_ID environment variable not set" >&2
                return 1
            fi
            
            # Request device code
            local device_response=$(curl -s -X POST "$device_endpoint" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                -d "client_id=$client_id" \
                -d "scope=https://www.googleapis.com/auth/generative-ai" 2>/dev/null)
            
            local device_code=$(echo "$device_response" | grep -o '"device_code":"[^"]*' | cut -d'"' -f4)
            local user_code=$(echo "$device_response" | grep -o '"user_code":"[^"]*' | cut -d'"' -f4)
            local verification_url=$(echo "$device_response" | grep -o '"verification_url":"[^"]*' | cut -d'"' -f4)
            local interval=$(echo "$device_response" | grep -o '"interval":[0-9]*' | cut -d':' -f2)
            
            if [ -z "$device_code" ] || [ -z "$user_code" ]; then
                echo "Error: Failed to get device code" >&2
                echo "$device_response" >&2
                return 1
            fi
            
            # Display instructions to user
            echo "" >&2
            echo "To authorize, visit: $verification_url" >&2
            echo "Enter code: $user_code" >&2
            echo "" >&2
            echo "Waiting for authorization..." >&2
            
            # Poll for token
            local token_endpoint="https://oauth2.googleapis.com/token"
            local max_attempts=60
            local attempt=0
            
            while [ $attempt -lt $max_attempts ]; do
                sleep "${interval:-5}"
                
                local token_response=$(curl -s -X POST "$token_endpoint" \
                    -H "Content-Type: application/x-www-form-urlencoded" \
                    -d "client_id=$client_id" \
                    -d "client_secret=${GOOGLE_CLIENT_SECRET:-}" \
                    -d "device_code=$device_code" \
                    -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" 2>/dev/null)
                
                local access_token=$(echo "$token_response" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
                
                if [ -n "$access_token" ]; then
                    local refresh_token=$(echo "$token_response" | grep -o '"refresh_token":"[^"]*' | cut -d'"' -f4)
                    local expires_in=$(echo "$token_response" | grep -o '"expires_in":[0-9]*' | cut -d':' -f2)
                    
                    # Store tokens
                    store_oauth_token "google" "$access_token" "$refresh_token" "${expires_in:-3600}"
                    
                    echo "Successfully authenticated with Google" >&2
                    echo "$access_token"
                    return 0
                fi
                
                # Check for authorization_pending
                if echo "$token_response" | grep -q "authorization_pending"; then
                    attempt=$((attempt + 1))
                    continue
                fi
                
                # Other error
                echo "Error: Authentication failed" >&2
                echo "$token_response" >&2
                return 1
            done
            
            echo "Error: Authentication timeout" >&2
            return 1
            ;;
            
        *)
            echo "Error: Unsupported provider '$provider'" >&2
            return 1
            ;;
    esac
}

# Exchange authorization code for tokens
exchange_code_for_token() {
    local auth_code="$1"
    local client_id="$2"
    local client_secret="$3"
    local token_endpoint="${4:-https://oauth2.googleapis.com/token}"
    local redirect_uri="${5:-}"
    
    if [ -z "$auth_code" ] || [ -z "$client_id" ] || [ -z "$client_secret" ]; then
        echo "Error: Auth code, client ID, and client secret are required" >&2
        return 1
    fi
    
    # Make token exchange request
    local response=$(curl -s -X POST "$token_endpoint" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=authorization_code" \
        -d "code=$auth_code" \
        -d "client_id=$client_id" \
        -d "client_secret=$client_secret" \
        -d "redirect_uri=$redirect_uri" 2>/dev/null)
    
    if [ -z "$response" ]; then
        echo "Error: Failed to exchange code for token" >&2
        return 1
    fi
    
    echo "$response"
}

# List all OAuth tokens
list_oauth_tokens() {
    if [ ! -d "$OAUTH_TOKEN_DIR" ]; then
        return 0
    fi
    
    # List all token files
    for token_file in "$OAUTH_TOKEN_DIR"/*.token; do
        if [ -f "$token_file" ]; then
            local provider=$(basename "$token_file" .token)
            echo "$provider"
        fi
    done
}

# Delete OAuth token
delete_oauth_token() {
    local provider="$1"
    
    if [ -z "$provider" ]; then
        echo "Error: Provider name is required" >&2
        return 1
    fi
    
    local token_file="$OAUTH_TOKEN_DIR/${provider}.token"
    
    if [ -f "$token_file" ]; then
        rm -f "$token_file"
    fi
    
    return 0
}

# Check if token is expired (updated for new format)
is_token_expired() {
    local provider="$1"
    
    if [ -z "$provider" ]; then
        return 1
    fi
    
    if [ ! -f "$OAUTH_TOKEN_FILE" ]; then
        return 1
    fi
    
    # Get expiry time for provider
    local expires_at
    
    # Use Python for safe JSON parsing if available
    if command -v python3 &> /dev/null || command -v python &> /dev/null; then
        local python_cmd=$(command -v python3 || command -v python)
        
        expires_at=$($python_cmd << PYTHON_SCRIPT 2>/dev/null
import json
import sys

try:
    with open('$OAUTH_TOKEN_FILE', 'r') as f:
        tokens = json.load(f)
    
    if '$provider' in tokens:
        print(tokens['$provider'].get('expires_at', 0))
except:
    print(0)
PYTHON_SCRIPT
)
    else
        # Fallback to grep/sed
        expires_at=$(grep -A5 "\"$provider\"" "$OAUTH_TOKEN_FILE" | grep '"expires_at"' | sed 's/.*"expires_at"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/')
    fi
    
    # Check expiry
    local status=$(oauth_check_expiry "$expires_at")
    
    if [ "$status" = "valid" ]; then
        return 1  # Not expired
    else
        return 0  # Expired
    fi
}

# Validate token with test API call
oauth_validate_token() {
    local provider="$1"
    local token="${2:-$(get_oauth_token "$provider" 2>/dev/null)}"
    
    if [ -z "$provider" ] || [ -z "$token" ]; then
        echo "invalid"
        return 1
    fi
    
    # Check cache first
    local cache_key="${provider}_${token:0:10}"
    if [ -n "${VALIDATED_TOKENS[$cache_key]}" ]; then
        local cache_time="${VALIDATION_TIMESTAMPS[$cache_key]}"
        local current_time=$(date +%s)
        local cache_age=$((current_time - cache_time))
        
        # Cache valid for 5 minutes
        if [ $cache_age -lt 300 ]; then
            echo "valid"
            return 0
        fi
    fi
    
    # Perform validation based on provider
    local validation_result="invalid"
    
    case "$provider" in
        gemini|gemini-cli)
            # Test with models.list endpoint
            local test_response=$(curl -s -X GET \
                "https://generativelanguage.googleapis.com/v1/models" \
                -H "Authorization: Bearer $token" \
                -H "Content-Type: application/json" 2>/dev/null)
            
            if echo "$test_response" | grep -q '"models"'; then
                validation_result="valid"
            fi
            ;;
            
        google)
            # Test with userinfo endpoint
            local test_response=$(curl -s -X GET \
                "https://www.googleapis.com/oauth2/v1/userinfo" \
                -H "Authorization: Bearer $token" 2>/dev/null)
            
            if echo "$test_response" | grep -q '"email"'; then
                validation_result="valid"
            fi
            ;;
            
        *)
            # Generic validation - just check if token exists
            if [ -n "$token" ]; then
                validation_result="valid"
            fi
            ;;
    esac
    
    # Update cache if valid
    if [ "$validation_result" = "valid" ]; then
        VALIDATED_TOKENS[$cache_key]="$token"
        VALIDATION_TIMESTAMPS[$cache_key]=$(date +%s)
    fi
    
    echo "$validation_result"
    [ "$validation_result" = "valid" ] && return 0 || return 1
}

# Get valid token with automatic refresh
oauth_get_valid_token() {
    local provider="$1"
    local retry_count="${2:-3}"
    
    if [ -z "$provider" ]; then
        echo "Error: Provider name is required" >&2
        return 1
    fi
    
    # Check if token exists and is not expired
    if ! is_token_expired "$provider"; then
        local token=$(get_oauth_token "$provider" 2>/dev/null)
        
        # Validate the token
        if [ "$(oauth_validate_token "$provider" "$token")" = "valid" ]; then
            echo "$token"
            return 0
        fi
    fi
    
    # Token is expired or invalid, try to refresh
    local attempt=0
    while [ $attempt -lt $retry_count ]; do
        # Try refresh first
        local refresh_token=$(get_refresh_token "$provider" 2>/dev/null)
        
        if [ -n "$refresh_token" ]; then
            local new_token=$(oauth_refresh_token "$provider" 2>/dev/null)
            
            if [ -n "$new_token" ]; then
                # Validate new token
                if [ "$(oauth_validate_token "$provider" "$new_token")" = "valid" ]; then
                    echo "$new_token"
                    return 0
                fi
            fi
        fi
        
        # Refresh failed, try re-authentication
        if oauth_login "$provider" > /dev/null 2>&1; then
            local token=$(get_oauth_token "$provider" 2>/dev/null)
            
            if [ -n "$token" ] && [ "$(oauth_validate_token "$provider" "$token")" = "valid" ]; then
                echo "$token"
                return 0
            fi
        fi
        
        # Exponential backoff
        attempt=$((attempt + 1))
        sleep $((attempt * 2))
    done
    
    echo "Error: Failed to get valid token after $retry_count attempts" >&2
    return 1
}

# Enhanced token refresh with retry logic
oauth_refresh_token() {
    local provider="$1"
    
    if [ -z "$provider" ]; then
        echo "Error: Provider name is required" >&2
        return 1
    fi
    
    local refresh_token=$(get_refresh_token "$provider" 2>/dev/null)
    
    if [ -z "$refresh_token" ]; then
        echo "Error: No refresh token available" >&2
        return 1
    fi
    
    local new_token=""
    local new_refresh_token=""
    local expires_in=3600
    
    case "$provider" in
        gemini|gemini-cli)
            # Gemini refresh using CLI
            local refresh_response=$(gemini auth refresh "$refresh_token" 2>&1)
            
            if [ $? -eq 0 ]; then
                new_token=$(echo "$refresh_response" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
                new_refresh_token=$(echo "$refresh_response" | grep -o '"refresh_token":"[^"]*' | cut -d'"' -f4)
                expires_in=$(echo "$refresh_response" | grep -o '"expires_in":[0-9]*' | cut -d':' -f2)
            fi
            ;;
            
        google)
            # Google OAuth refresh
            local token_endpoint="https://oauth2.googleapis.com/token"
            
            local refresh_response=$(curl -s -X POST "$token_endpoint" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                -d "client_id=${GOOGLE_CLIENT_ID:-}" \
                -d "client_secret=${GOOGLE_CLIENT_SECRET:-}" \
                -d "refresh_token=$refresh_token" \
                -d "grant_type=refresh_token" 2>/dev/null)
            
            new_token=$(echo "$refresh_response" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
            new_refresh_token=$(echo "$refresh_response" | grep -o '"refresh_token":"[^"]*' | cut -d'"' -f4)
            expires_in=$(echo "$refresh_response" | grep -o '"expires_in":[0-9]*' | cut -d':' -f2)
            ;;
            
        *)
            echo "Error: Unsupported provider for refresh" >&2
            return 1
            ;;
    esac
    
    if [ -n "$new_token" ]; then
        # Use new refresh token if provided, otherwise keep old one
        [ -z "$new_refresh_token" ] && new_refresh_token="$refresh_token"
        
        # Update stored tokens
        store_oauth_token "$provider" "$new_token" "$new_refresh_token" "${expires_in:-3600}"
        
        echo "$new_token"
        return 0
    else
        echo "Error: Failed to refresh token" >&2
        return 1
    fi
}

# Token rotation for security
oauth_rotate_tokens() {
    local provider="${1:-all}"
    
    if [ "$provider" = "all" ]; then
        # Rotate all provider tokens
        for p in $(list_oauth_tokens); do
            oauth_rotate_tokens "$p"
        done
    else
        # Rotate specific provider token
        if oauth_login "$provider" > /dev/null 2>&1; then
            echo "Rotated token for provider: $provider" >&2
            return 0
        else
            echo "Error: Failed to rotate token for provider: $provider" >&2
            return 1
        fi
    fi
}

# Clear tokens securely
oauth_clear_tokens() {
    local provider="${1:-all}"
    
    if [ "$provider" = "all" ]; then
        # Clear all tokens
        if [ -f "$OAUTH_TOKEN_FILE" ]; then
            # Overwrite with random data before deletion
            dd if=/dev/urandom of="$OAUTH_TOKEN_FILE" bs=1024 count=10 2>/dev/null
            rm -f "$OAUTH_TOKEN_FILE"
        fi
        
        # Clear memory
        VALIDATED_TOKENS=()
        VALIDATION_TIMESTAMPS=()
        oauth_cleanup_memory
        
        echo "All tokens cleared" >&2
    else
        # Clear specific provider token
        if [ -f "$OAUTH_TOKEN_FILE" ]; then
            # Remove provider from JSON
            if command -v python3 &> /dev/null || command -v python &> /dev/null; then
                local python_cmd=$(command -v python3 || command -v python)
                local temp_file="${OAUTH_TOKEN_FILE}.tmp.$$"
                
                $python_cmd << PYTHON_SCRIPT > "$temp_file" 2>/dev/null
import json
import sys

try:
    with open('$OAUTH_TOKEN_FILE', 'r') as f:
        tokens = json.load(f)
    
    if '$provider' in tokens:
        del tokens['$provider']
    
    print(json.dumps(tokens, indent=2))
except:
    print('{}')
PYTHON_SCRIPT
                
                if [ -f "$temp_file" ]; then
                    mv -f "$temp_file" "$OAUTH_TOKEN_FILE"
                    chmod 600 "$OAUTH_TOKEN_FILE"
                fi
            fi
        fi
        
        # Clear from cache
        for key in "${!VALIDATED_TOKENS[@]}"; do
            if [[ "$key" == "${provider}_"* ]]; then
                unset VALIDATED_TOKENS[$key]
                unset VALIDATION_TIMESTAMPS[$key]
            fi
        done
        
        echo "Token cleared for provider: $provider" >&2
    fi
    
    return 0
}

# Load tokens from file
oauth_load_tokens() {
    local provider="${1:-all}"
    
    if [ ! -f "$OAUTH_TOKEN_FILE" ]; then
        echo "Error: Token file not found" >&2
        return 1
    fi
    
    if [ "$provider" = "all" ]; then
        # Display all tokens (without sensitive data)
        if command -v python3 &> /dev/null || command -v python &> /dev/null; then
            local python_cmd=$(command -v python3 || command -v python)
            
            $python_cmd << PYTHON_SCRIPT 2>/dev/null
import json
import sys
import time

try:
    with open('$OAUTH_TOKEN_FILE', 'r') as f:
        tokens = json.load(f)
    
    for provider, data in tokens.items():
        expires_at = data.get('expires_at', 0)
        current_time = time.time()
        
        if expires_at > current_time:
            status = 'valid'
            expires_in = int(expires_at - current_time)
            expires_str = f'{expires_in}s'
        else:
            status = 'expired'
            expires_str = 'expired'
        
        print(f'{provider}: {status} (expires: {expires_str})')
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
PYTHON_SCRIPT
        else
            echo "Provider tokens:"
            grep '"provider"' "$OAUTH_TOKEN_FILE" | sed 's/.*"provider"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/  - \1/'
        fi
    else
        # Check specific provider
        local token=$(get_oauth_token "$provider" 2>/dev/null)
        if [ -n "$token" ]; then
            if is_token_expired "$provider"; then
                echo "$provider: expired"
            else
                echo "$provider: valid"
            fi
        else
            echo "$provider: not found"
        fi
    fi
}

# Save tokens atomically
oauth_save_tokens() {
    local json_data="$1"
    
    if [ -z "$json_data" ]; then
        echo "Error: No data to save" >&2
        return 1
    fi
    
    oauth_ensure_auth_dir
    
    local temp_file="${OAUTH_TOKEN_FILE}.tmp.$$"
    
    # Write to temp file
    echo "$json_data" > "$temp_file"
    
    # Validate JSON
    if command -v python3 &> /dev/null || command -v python &> /dev/null; then
        local python_cmd=$(command -v python3 || command -v python)
        
        if ! $python_cmd -m json.tool "$temp_file" > /dev/null 2>&1; then
            echo "Error: Invalid JSON data" >&2
            rm -f "$temp_file"
            return 1
        fi
    fi
    
    # Atomic move
    mv -f "$temp_file" "$OAUTH_TOKEN_FILE"
    chmod 600 "$OAUTH_TOKEN_FILE"
    
    return 0
}

# Initialize OAuth system on source
init_oauth_system