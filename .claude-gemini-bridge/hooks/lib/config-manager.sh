#!/bin/bash
# ABOUTME: Enhanced JSON-based configuration management with secure storage

# Configuration storage (in-memory)
declare -A CONFIG_DATA
declare -A SECURE_CONFIG_DATA

# Configuration paths (XDG-compliant)
CONFIG_BASE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-gemini-bridge"
CONFIG_FILE="${CONFIG_FILE:-$CONFIG_BASE_DIR/config.json}"
PROVIDERS_DIR="$CONFIG_BASE_DIR/providers"
AUTH_DIR="$CONFIG_BASE_DIR/auth"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-gemini-bridge"

# Legacy configuration paths
LEGACY_CONFIG_DIR="$HOME/.claude-gemini-bridge"
LEGACY_CONFIG_FILE="$LEGACY_CONFIG_DIR/config"

# Security settings
SECURE_PERMS_DIR="700"
SECURE_PERMS_FILE="600"
ENCRYPTION_ALGORITHM="aes-256-cbc"

# Configuration schema version
CONFIG_SCHEMA_VERSION="1.0.0"

# ============================================================================
# Core Initialization
# ============================================================================

# Initialize configuration system
init_config() {
    CONFIG_DATA=()
    SECURE_CONFIG_DATA=()
    
    # Create XDG-compliant directory structure
    mkdir -p "$CONFIG_BASE_DIR" "$PROVIDERS_DIR" "$AUTH_DIR" "$CACHE_DIR"
    
    # Set secure permissions
    chmod "$SECURE_PERMS_DIR" "$CONFIG_BASE_DIR" "$AUTH_DIR"
    chmod "$SECURE_PERMS_DIR" "$PROVIDERS_DIR" 2>/dev/null || true
    
    # Check for legacy configuration and migrate if needed
    if [ -d "$LEGACY_CONFIG_DIR" ] && [ ! -f "$CONFIG_FILE" ]; then
        migrate_legacy_config
    fi
    
    # Load default configuration if no config exists
    if [ ! -f "$CONFIG_FILE" ]; then
        create_default_config
    fi
}

# Create default configuration
create_default_config() {
    cat > "$CONFIG_FILE" << 'EOF'
{
  "version": "1.0.0",
  "global": {
    "log_level": "info",
    "cache_ttl": 3600,
    "rate_limit_enabled": true,
    "secure_mode": true
  },
  "providers": {
    "default": "gemini-cli",
    "fallback": "api_key"
  },
  "paths": {
    "logs": "${XDG_STATE_HOME:-$HOME/.local/state}/claude-gemini-bridge/logs",
    "cache": "${XDG_CACHE_HOME:-$HOME/.cache}/claude-gemini-bridge",
    "data": "${XDG_DATA_HOME:-$HOME/.local/share}/claude-gemini-bridge"
  }
}
EOF
    chmod "$SECURE_PERMS_FILE" "$CONFIG_FILE"
}

# ============================================================================
# Configuration Loading and Saving
# ============================================================================

# Load configuration from file with validation
load_config() {
    local file="${1:-$CONFIG_FILE}"
    
    if [ ! -f "$file" ]; then
        echo "Error: Configuration file not found: $file" >&2
        return 1
    fi
    
    # Validate JSON structure
    if ! validate_json "$file"; then
        echo "Error: Invalid JSON in configuration file: $file" >&2
        return 1
    fi
    
    # Validate schema
    if ! validate_config_schema "$file"; then
        echo "Error: Configuration does not match schema" >&2
        return 1
    fi
    
    CONFIG_FILE="$file"
    
    # Parse JSON and load into CONFIG_DATA
    _parse_json_to_config "$file"
    
    # Apply environment overrides
    apply_env_overrides
    
    return 0
}

# Save configuration to file with atomic write
save_config() {
    local file="${1:-$CONFIG_FILE}"
    local temp_file="$file.tmp.$$"
    
    # Create directory if needed
    local dir=$(dirname "$file")
    mkdir -p "$dir"
    
    # Build JSON structure from CONFIG_DATA
    if ! _build_json_from_config > "$temp_file"; then
        echo "Error: Failed to build JSON configuration" >&2
        rm -f "$temp_file"
        return 1
    fi
    
    # Validate generated JSON
    if ! validate_json "$temp_file"; then
        echo "Error: Generated invalid JSON" >&2
        rm -f "$temp_file"
        return 1
    fi
    
    # Atomic move
    mv -f "$temp_file" "$file"
    chmod "$SECURE_PERMS_FILE" "$file"
    
    return 0
}

# ============================================================================
# Configuration Validation
# ============================================================================

# Validate JSON file
validate_json() {
    local file="$1"
    
    if command -v jq &>/dev/null; then
        jq empty "$file" 2>/dev/null
    elif command -v python3 &>/dev/null; then
        python3 -m json.tool "$file" >/dev/null 2>&1
    elif command -v python &>/dev/null; then
        python -m json.tool "$file" >/dev/null 2>&1
    else
        # Basic validation - check for valid JSON brackets
        local content=$(cat "$file")
        [[ "$content" =~ ^\{.*\}$ ]] || [[ "$content" =~ ^\[.*\]$ ]]
    fi
}

# Validate configuration against schema
validate_config_schema() {
    local file="$1"
    
    # Check required top-level fields
    if command -v jq &>/dev/null; then
        local version=$(jq -r '.version // empty' "$file")
        local global=$(jq -r '.global // empty' "$file")
        
        if [ -z "$version" ]; then
            echo "Error: Missing required field: version" >&2
            return 1
        fi
        
        if [ -z "$global" ]; then
            echo "Error: Missing required field: global" >&2
            return 1
        fi
    fi
    
    return 0
}

# ============================================================================
# Configuration Accessors
# ============================================================================

# Get configuration value with nested path support
get_config() {
    local path="$1"
    local default="${2:-}"
    
    # Check CONFIG_DATA first
    if [ -n "${CONFIG_DATA[$path]+exists}" ]; then
        echo "${CONFIG_DATA[$path]}"
        return 0
    fi
    
    # Check if it's in secure storage
    if [ -n "${SECURE_CONFIG_DATA[$path]+exists}" ]; then
        echo "${SECURE_CONFIG_DATA[$path]}"
        return 0
    fi
    
    # Return default
    echo "$default"
}

# Set configuration value
set_config() {
    local path="$1"
    local value="$2"
    local secure="${3:-false}"
    
    if [ "$secure" = "true" ]; then
        SECURE_CONFIG_DATA["$path"]="$value"
    else
        CONFIG_DATA["$path"]="$value"
    fi
}

# Check if configuration key exists
has_config() {
    local path="$1"
    
    if [ -n "${CONFIG_DATA[$path]+exists}" ] || [ -n "${SECURE_CONFIG_DATA[$path]+exists}" ]; then
        echo "true"
        return 0
    else
        echo "false"
        return 1
    fi
}

# Delete configuration value
delete_config() {
    local path="$1"
    
    unset CONFIG_DATA["$path"]
    unset SECURE_CONFIG_DATA["$path"]
}

# ============================================================================
# Secure Storage Functions
# ============================================================================

# Get encryption key from system properties
get_encryption_key() {
    local machine_id=""
    local user_salt="$USER-claude-gemini-bridge"
    
    # Try to get machine ID from various sources
    if [ -f "/etc/machine-id" ]; then
        machine_id=$(cat /etc/machine-id)
    elif [ -f "/var/lib/dbus/machine-id" ]; then
        machine_id=$(cat /var/lib/dbus/machine-id)
    else
        # Fallback to hostname + user
        machine_id="$(hostname)-$(id -u)"
    fi
    
    # Generate key using SHA256
    echo -n "${machine_id}${user_salt}" | sha256sum | cut -d' ' -f1
}

# Encrypt sensitive data
encrypt_credentials() {
    local data="$1"
    local key=$(get_encryption_key)
    
    if ! command -v openssl &>/dev/null; then
        echo "Warning: OpenSSL not available, storing without encryption" >&2
        echo "$data"
        return 0
    fi
    
    # Encrypt using OpenSSL
    echo -n "$data" | openssl enc -"$ENCRYPTION_ALGORITHM" -base64 -pass pass:"$key" 2>/dev/null
}

# Decrypt sensitive data
decrypt_credentials() {
    local encrypted="$1"
    local key=$(get_encryption_key)
    
    if ! command -v openssl &>/dev/null; then
        echo "$encrypted"
        return 0
    fi
    
    # Decrypt using OpenSSL
    echo -n "$encrypted" | openssl enc -d -"$ENCRYPTION_ALGORITHM" -base64 -pass pass:"$key" 2>/dev/null
}

# Store secure configuration
store_secure_config() {
    local key="$1"
    local value="$2"
    local file="$AUTH_DIR/secure.enc"
    
    # Encrypt value
    local encrypted=$(encrypt_credentials "$value")
    
    # Store in secure data
    SECURE_CONFIG_DATA["$key"]="$encrypted"
    
    # Save to file
    {
        echo "# Encrypted configuration - DO NOT EDIT"
        echo "# Generated: $(date -Iseconds)"
        for k in "${!SECURE_CONFIG_DATA[@]}"; do
            echo "$k=${SECURE_CONFIG_DATA[$k]}"
        done
    } > "$file"
    
    chmod "$SECURE_PERMS_FILE" "$file"
}

# Load secure configuration
load_secure_config() {
    local file="$AUTH_DIR/secure.enc"
    
    if [ ! -f "$file" ]; then
        return 0
    fi
    
    # Read encrypted values
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue
        
        # Decrypt and store
        local decrypted=$(decrypt_credentials "$value")
        SECURE_CONFIG_DATA["$key"]="$decrypted"
    done < "$file"
}

# Secure cleanup of sensitive data
secure_cleanup() {
    # Clear secure data from memory
    for key in "${!SECURE_CONFIG_DATA[@]}"; do
        SECURE_CONFIG_DATA["$key"]="0000000000000000000000000000"
        unset SECURE_CONFIG_DATA["$key"]
    done
    
    # Force garbage collection if possible
    if command -v sync &>/dev/null; then
        sync
    fi
}

# ============================================================================
# Provider Configuration Management
# ============================================================================

# Register a new provider
register_provider() {
    local provider_name="$1"
    local provider_config="$2"
    local provider_file="$PROVIDERS_DIR/${provider_name}.json"
    
    # Validate provider name
    if [[ ! "$provider_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Error: Invalid provider name" >&2
        return 1
    fi
    
    # Create provider configuration
    echo "$provider_config" > "$provider_file"
    chmod "$SECURE_PERMS_FILE" "$provider_file"
    
    # Update main config
    set_config "providers.available.$provider_name" "true"
    
    return 0
}

# Get provider configuration
get_provider_config() {
    local provider="$1"
    local key="$2"
    local default="${3:-}"
    
    # Try provider-specific config first
    local provider_file="$PROVIDERS_DIR/${provider}.json"
    if [ -f "$provider_file" ]; then
        local value=$(jq -r ".$key // empty" "$provider_file" 2>/dev/null)
        if [ -n "$value" ]; then
            echo "$value"
            return 0
        fi
    fi
    
    # Fall back to main config
    get_config "providers.$provider.$key" "$default"
}

# Update provider configuration
update_provider_config() {
    local provider="$1"
    local key="$2"
    local value="$3"
    local provider_file="$PROVIDERS_DIR/${provider}.json"
    
    if [ ! -f "$provider_file" ]; then
        echo "{}" > "$provider_file"
    fi
    
    # Update using jq if available
    if command -v jq &>/dev/null; then
        local temp_file="$provider_file.tmp"
        jq ".$key = \"$value\"" "$provider_file" > "$temp_file"
        mv "$temp_file" "$provider_file"
        chmod "$SECURE_PERMS_FILE" "$provider_file"
    else
        # Fallback to simple key-value storage
        set_config "providers.$provider.$key" "$value"
        save_config
    fi
}

# Validate provider configuration
validate_provider_config() {
    local provider="$1"
    local provider_file="$PROVIDERS_DIR/${provider}.json"
    
    if [ ! -f "$provider_file" ]; then
        return 1
    fi
    
    # Check for required fields based on provider type
    if command -v jq &>/dev/null; then
        local auth_type=$(jq -r '.auth_type // empty' "$provider_file")
        
        case "$auth_type" in
            oauth)
                local client_id=$(jq -r '.client_id // empty' "$provider_file")
                local client_secret=$(jq -r '.client_secret // empty' "$provider_file")
                [ -n "$client_id" ] && [ -n "$client_secret" ]
                ;;
            api_key)
                local api_key=$(jq -r '.api_key // empty' "$provider_file")
                [ -n "$api_key" ]
                ;;
            *)
                return 1
                ;;
        esac
    else
        # Basic validation
        [ -f "$provider_file" ] && [ -s "$provider_file" ]
    fi
}

# ============================================================================
# Environment Variable Support
# ============================================================================

# Apply environment variable overrides
apply_env_overrides() {
    # Process CLAUDE_GEMINI_* environment variables
    for var in $(env | grep '^CLAUDE_GEMINI_' | cut -d= -f1); do
        # Convert env var to config path
        # CLAUDE_GEMINI_PROVIDER_AUTH_TYPE -> provider.auth_type
        local key=$(echo "${var#CLAUDE_GEMINI_}" | tr '[:upper:]_' '[:lower:].')
        local value="${!var}"
        
        # Apply override
        CONFIG_DATA["env.$key"]="$value"
        
        # Also set in main config for precedence
        CONFIG_DATA["$key"]="$value"
    done
    
    # Process standard environment variables
    [ -n "${GEMINI_API_KEY:-}" ] && set_config "auth.gemini_api_key" "$GEMINI_API_KEY" true
    [ -n "${GOOGLE_API_KEY:-}" ] && set_config "auth.google_api_key" "$GOOGLE_API_KEY" true
    [ -n "${GOOGLE_CLIENT_ID:-}" ] && set_config "auth.google_client_id" "$GOOGLE_CLIENT_ID" true
    [ -n "${GOOGLE_CLIENT_SECRET:-}" ] && set_config "auth.google_client_secret" "$GOOGLE_CLIENT_SECRET" true
}

# Get configuration with environment override
get_env_config() {
    local path="$1"
    local default="${2:-}"
    
    # Check for environment override first
    local env_path="env.$path"
    if [ -n "${CONFIG_DATA[$env_path]+exists}" ]; then
        echo "${CONFIG_DATA[$env_path]}"
        return 0
    fi
    
    # Fall back to regular config
    get_config "$path" "$default"
}

# ============================================================================
# Legacy Migration
# ============================================================================

# Migrate legacy configuration format
migrate_legacy_config() {
    echo "Migrating legacy configuration..." >&2
    
    # Check for legacy config file
    if [ ! -f "$LEGACY_CONFIG_FILE" ] && [ ! -d "$LEGACY_CONFIG_DIR" ]; then
        return 0
    fi
    
    # Create new config structure
    local migration_data='{
  "version": "1.0.0",
  "migrated_from": "legacy",
  "migration_date": "'"$(date -Iseconds)"'",'
    
    # Migrate legacy settings if they exist
    if [ -f "$LEGACY_CONFIG_FILE" ]; then
        # Read legacy config (assuming key=value format)
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^#.*$ ]] && continue
            [[ -z "$key" ]] && continue
            
            # Map legacy keys to new structure
            case "$key" in
                api_key|gemini_api_key)
                    store_secure_config "auth.api_key" "$value"
                    ;;
                log_level)
                    set_config "global.log_level" "$value"
                    ;;
                cache_ttl)
                    set_config "global.cache_ttl" "$value"
                    ;;
                *)
                    set_config "legacy.$key" "$value"
                    ;;
            esac
        done < "$LEGACY_CONFIG_FILE"
    fi
    
    # Migrate OAuth tokens if present
    local legacy_tokens="$LEGACY_CONFIG_DIR/auth/tokens.json"
    if [ -f "$legacy_tokens" ]; then
        cp "$legacy_tokens" "$AUTH_DIR/tokens.json"
        chmod "$SECURE_PERMS_FILE" "$AUTH_DIR/tokens.json"
    fi
    
    # Save migrated configuration
    save_config
    
    # Create migration marker
    touch "$CONFIG_BASE_DIR/.migrated"
    
    echo "Legacy configuration migrated successfully" >&2
    return 0
}

# ============================================================================
# Utility Functions
# ============================================================================

# Merge configuration from another file
merge_config() {
    local merge_file="$1"
    local override="${2:-false}"
    
    if [ ! -f "$merge_file" ]; then
        echo "Error: Merge file not found: $merge_file" >&2
        return 1
    fi
    
    # Load merge file into temporary array
    local temp_file=$(mktemp)
    cp "$merge_file" "$temp_file"
    
    # Parse and merge
    if command -v jq &>/dev/null; then
        # Use jq for proper JSON merging
        local merged=$(jq -s 'add' "$CONFIG_FILE" "$temp_file" 2>/dev/null)
        if [ -n "$merged" ]; then
            echo "$merged" > "$CONFIG_FILE"
        fi
    else
        # Simple merge using bash
        _parse_json_to_config "$temp_file" "MERGE_"
        
        # Apply merged values
        for key in "${!MERGE_CONFIG_DATA[@]}"; do
            if [ "$override" = "true" ] || [ -z "${CONFIG_DATA[$key]}" ]; then
                CONFIG_DATA["$key"]="${MERGE_CONFIG_DATA[$key]}"
            fi
        done
    fi
    
    rm -f "$temp_file"
    return 0
}

# Backup configuration
backup_config() {
    local file="${1:-$CONFIG_FILE}"
    local backup_file="${file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    cp -p "$file" "$backup_file"
    echo "$backup_file"
}

# List all configuration keys
list_config_keys() {
    {
        for key in "${!CONFIG_DATA[@]}"; do
            echo "config: $key"
        done
        for key in "${!SECURE_CONFIG_DATA[@]}"; do
            echo "secure: $key"
        done
    } | sort
}

# Reset configuration to defaults
reset_config() {
    CONFIG_DATA=()
    SECURE_CONFIG_DATA=()
    create_default_config
    load_config
}

# ============================================================================
# JSON Parsing and Building
# ============================================================================

# Parse JSON file into CONFIG_DATA array
_parse_json_to_config() {
    local file="$1"
    local prefix="${2:-}"
    
    # Clear target array if no prefix
    if [ -z "$prefix" ]; then
        CONFIG_DATA=()
    fi
    
    # Use jq if available for accurate parsing
    if command -v jq &>/dev/null; then
        while IFS=$'\t' read -r key value; do
            if [ -n "$prefix" ]; then
                declare -g "${prefix}CONFIG_DATA[$key]=$value"
            else
                CONFIG_DATA["$key"]="$value"
            fi
        done < <(jq -r 'paths(scalars) as $p | "\($p | map(tostring) | join("."))	\(.[$p])"' "$file" 2>/dev/null || true)
    else
        # Fallback to Python parsing
        _flatten_json "$file" "$prefix"
    fi
}

# Build JSON from CONFIG_DATA
_build_json_from_config() {
    if command -v jq &>/dev/null; then
        # Build nested JSON using jq
        local json="{}"
        
        for key in "${!CONFIG_DATA[@]}"; do
            local value="${CONFIG_DATA[$key]}"
            # Escape value for JSON
            value=$(echo -n "$value" | jq -Rs .)
            # Build path array from dot-separated key
            local path_array=$(echo "$key" | jq -R 'split(".")')
            # Build path and set value
            json=$(echo "$json" | jq "setpath($path_array; $value)")
        done
        
        echo "$json" | jq .
    else
        # Simple JSON builder
        echo "{"
        local first=true
        for key in "${!CONFIG_DATA[@]}"; do
            if [ "$first" = true ]; then
                first=false
            else
                echo ","
            fi
            echo -n "  \"$key\": \"${CONFIG_DATA[$key]}\""
        done
        echo ""
        echo "}"
    fi
}

# Flatten JSON structure (Python fallback)
_flatten_json() {
    local file="$1"
    local prefix="${2:-}"
    
    if command -v python3 &>/dev/null || command -v python &>/dev/null; then
        local python_cmd=$(command -v python3 || command -v python)
        
        # Create temporary Python script
        local temp_script=$(mktemp)
        cat > "$temp_script" << 'PYTHON_SCRIPT'
import json
import sys

def flatten_json(data, parent_key='', sep='.'):
    items = []
    if isinstance(data, dict):
        for k, v in data.items():
            new_key = f'{parent_key}{sep}{k}' if parent_key else k
            if isinstance(v, dict):
                items.extend(flatten_json(v, new_key, sep=sep))
            elif isinstance(v, list):
                for i, item in enumerate(v):
                    items.append((f'{new_key}[{i}]', item))
            else:
                items.append((new_key, v))
    return items

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    
    for key, value in flatten_json(data):
        # Convert value to string
        if isinstance(value, bool):
            value_str = str(value).lower()
        elif value is None:
            value_str = ''
        else:
            value_str = str(value)
        
        # Use tab as separator
        print(f'{key}\t{value_str}')
except Exception as e:
    sys.stderr.write(f"Error: {e}\n")
    sys.exit(1)
PYTHON_SCRIPT
        
        # Execute script and process output
        while IFS=$'\t' read -r key value; do
            if [ -n "$prefix" ]; then
                declare -g "${prefix}CONFIG_DATA[$key]=$value"
            else
                CONFIG_DATA["$key"]="$value"
            fi
        done < <($python_cmd "$temp_script" "$file" 2>/dev/null)
        
        # Clean up
        rm -f "$temp_script"
    fi
}

# ============================================================================
# Cleanup on Exit
# ============================================================================

# Trap cleanup on exit
trap secure_cleanup EXIT

# Initialize configuration system on source
init_config