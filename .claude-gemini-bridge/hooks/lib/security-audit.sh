#!/bin/bash
# ABOUTME: Security audit and logging system for token operations and security events

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
source "$SCRIPT_DIR/debug-helpers.sh"

# Security configuration
readonly AUDIT_LOG_DIR="${AUDIT_LOG_DIR:-$HOME/.claude-gemini-bridge/security/audit}"
readonly SECURITY_LOG_FILE="${SECURITY_LOG_FILE:-$AUDIT_LOG_DIR/security.log}"
readonly ACCESS_LOG_FILE="${ACCESS_LOG_FILE:-$AUDIT_LOG_DIR/access.log}"
readonly ERROR_LOG_FILE="${ERROR_LOG_FILE:-$AUDIT_LOG_DIR/errors.log}"
readonly AUDIT_REPORT_FILE="${AUDIT_REPORT_FILE:-$AUDIT_LOG_DIR/audit_report.json}"

# Security event types
if [ -z "$EVENT_AUTH_SUCCESS" ]; then
    readonly EVENT_AUTH_SUCCESS="AUTH_SUCCESS"
    readonly EVENT_AUTH_FAILURE="AUTH_FAILURE"
    readonly EVENT_TOKEN_CREATED="TOKEN_CREATED"
    readonly EVENT_TOKEN_ROTATED="TOKEN_ROTATED"
    readonly EVENT_TOKEN_EXPIRED="TOKEN_EXPIRED"
    readonly EVENT_TOKEN_DELETED="TOKEN_DELETED"
    readonly EVENT_ACCESS_GRANTED="ACCESS_GRANTED"
    readonly EVENT_ACCESS_DENIED="ACCESS_DENIED"
    readonly EVENT_SECURITY_VIOLATION="SECURITY_VIOLATION"
    readonly EVENT_ENCRYPTION_FAILURE="ENCRYPTION_FAILURE"
    readonly EVENT_PERMISSION_ERROR="PERMISSION_ERROR"
fi

# Severity levels
if [ -z "$SEVERITY_INFO" ]; then
    readonly SEVERITY_INFO="INFO"
    readonly SEVERITY_WARNING="WARNING"
    readonly SEVERITY_ERROR="ERROR"
    readonly SEVERITY_CRITICAL="CRITICAL"
fi

# Audit configuration
if [ -z "$MAX_LOG_SIZE" ]; then
    readonly MAX_LOG_SIZE=10485760  # 10MB
    readonly LOG_ROTATION_COUNT=5
    readonly AUDIT_CHECK_INTERVAL=300  # 5 minutes
    readonly ALERT_THRESHOLD_FAILURES=5  # Alert after 5 auth failures
    readonly ALERT_THRESHOLD_VIOLATIONS=3  # Alert after 3 security violations
fi

# ============================================================================
# Initialization
# ============================================================================

# Initialize audit system
init_audit_system() {
    # Create audit directory with secure permissions
    if [ ! -d "$AUDIT_LOG_DIR" ]; then
        mkdir -p "$AUDIT_LOG_DIR"
        chmod 700 "$AUDIT_LOG_DIR"
    fi
    
    # Create log files with secure permissions
    for log_file in "$SECURITY_LOG_FILE" "$ACCESS_LOG_FILE" "$ERROR_LOG_FILE"; do
        if [ ! -f "$log_file" ]; then
            touch "$log_file"
            chmod 600 "$log_file"
        fi
    done
    
    # Initialize audit report
    if [ ! -f "$AUDIT_REPORT_FILE" ]; then
        cat > "$AUDIT_REPORT_FILE" << EOF
{
  "initialized": "$(date -Iseconds)",
  "last_check": null,
  "statistics": {
    "total_events": 0,
    "auth_successes": 0,
    "auth_failures": 0,
    "security_violations": 0,
    "token_rotations": 0
  },
  "alerts": []
}
EOF
        chmod 600 "$AUDIT_REPORT_FILE"
    fi
    
    return 0
}

# ============================================================================
# Security Logging Functions
# ============================================================================

# Log security event
log_security_event() {
    local event_type="$1"
    local severity="$2"
    local message="$3"
    local details="${4:-}"
    
    local timestamp=$(date -Iseconds)
    local user="${USER:-unknown}"
    local pid=$$
    local session_id="${SESSION_ID:-$(uuidgen 2>/dev/null || echo "no-session")}"
    
    # Format log entry
    local log_entry=$(cat <<EOF
{
  "timestamp": "$timestamp",
  "event": "$event_type",
  "severity": "$severity",
  "user": "$user",
  "pid": "$pid",
  "session": "$session_id",
  "message": "$message",
  "details": "$details"
}
EOF
)
    
    # Write to appropriate log file
    case "$severity" in
        "$SEVERITY_ERROR"|"$SEVERITY_CRITICAL")
            echo "$log_entry" >> "$ERROR_LOG_FILE"
            ;;
        *)
            echo "$log_entry" >> "$SECURITY_LOG_FILE"
            ;;
    esac
    
    # Update statistics
    update_audit_statistics "$event_type"
    
    # Check for alert conditions
    check_alert_conditions "$event_type" "$severity"
    
    # Rotate logs if needed
    rotate_logs_if_needed
}

# Log access attempt
log_access_attempt() {
    local resource="$1"
    local action="$2"
    local result="$3"  # success/failure
    local details="${4:-}"
    
    local timestamp=$(date -Iseconds)
    local user="${USER:-unknown}"
    
    local access_entry=$(cat <<EOF
{
  "timestamp": "$timestamp",
  "user": "$user",
  "resource": "$resource",
  "action": "$action",
  "result": "$result",
  "details": "$details"
}
EOF
)
    
    echo "$access_entry" >> "$ACCESS_LOG_FILE"
    
    # Log security event if access denied
    if [ "$result" = "denied" ] || [ "$result" = "failure" ]; then
        log_security_event "$EVENT_ACCESS_DENIED" "$SEVERITY_WARNING" \
            "Access denied to $resource" "$details"
    fi
}

# ============================================================================
# Audit Functions
# ============================================================================

# Update audit statistics
update_audit_statistics() {
    local event_type="$1"
    
    if [ ! -f "$AUDIT_REPORT_FILE" ]; then
        init_audit_system
    fi
    
    if command -v jq &>/dev/null; then
        local report=$(cat "$AUDIT_REPORT_FILE")
        
        # Increment total events
        report=$(echo "$report" | jq '.statistics.total_events += 1')
        
        # Update specific counters
        case "$event_type" in
            "$EVENT_AUTH_SUCCESS")
                report=$(echo "$report" | jq '.statistics.auth_successes += 1')
                ;;
            "$EVENT_AUTH_FAILURE")
                report=$(echo "$report" | jq '.statistics.auth_failures += 1')
                ;;
            "$EVENT_SECURITY_VIOLATION")
                report=$(echo "$report" | jq '.statistics.security_violations += 1')
                ;;
            "$EVENT_TOKEN_ROTATED")
                report=$(echo "$report" | jq '.statistics.token_rotations += 1')
                ;;
        esac
        
        # Update last check time
        report=$(echo "$report" | jq ".last_check = \"$(date -Iseconds)\"")
        
        echo "$report" > "$AUDIT_REPORT_FILE"
    fi
}

# Check for alert conditions
check_alert_conditions() {
    local event_type="$1"
    local severity="$2"
    
    if [ ! -f "$AUDIT_REPORT_FILE" ]; then
        return 0
    fi
    
    if command -v jq &>/dev/null; then
        local report=$(cat "$AUDIT_REPORT_FILE")
        local should_alert=false
        local alert_message=""
        
        # Check authentication failures
        local auth_failures=$(echo "$report" | jq -r '.statistics.auth_failures')
        if [ "$auth_failures" -ge "$ALERT_THRESHOLD_FAILURES" ]; then
            should_alert=true
            alert_message="High number of authentication failures: $auth_failures"
        fi
        
        # Check security violations
        local violations=$(echo "$report" | jq -r '.statistics.security_violations')
        if [ "$violations" -ge "$ALERT_THRESHOLD_VIOLATIONS" ]; then
            should_alert=true
            alert_message="Security violations detected: $violations"
        fi
        
        # Check critical events
        if [ "$severity" = "$SEVERITY_CRITICAL" ]; then
            should_alert=true
            alert_message="Critical security event: $event_type"
        fi
        
        if [ "$should_alert" = "true" ]; then
            create_security_alert "$alert_message" "$event_type"
        fi
    fi
}

# Create security alert
create_security_alert() {
    local message="$1"
    local event_type="$2"
    
    local alert=$(cat <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "message": "$message",
  "event": "$event_type",
  "acknowledged": false
}
EOF
)
    
    if command -v jq &>/dev/null; then
        local report=$(cat "$AUDIT_REPORT_FILE")
        report=$(echo "$report" | jq ".alerts += [$alert]")
        echo "$report" > "$AUDIT_REPORT_FILE"
    fi
    
    # Log critical alert
    error_log "SECURITY ALERT: $message"
    
    # Could integrate with external alerting systems here
    # send_external_alert "$message"
}

# ============================================================================
# Security Validation Functions
# ============================================================================

# Validate file permissions
validate_permissions() {
    local file="$1"
    local expected_perms="$2"
    
    if [ ! -e "$file" ]; then
        log_security_event "$EVENT_PERMISSION_ERROR" "$SEVERITY_ERROR" \
            "File does not exist: $file"
        return 1
    fi
    
    local actual_perms=$(stat -c %a "$file" 2>/dev/null || stat -f %A "$file" 2>/dev/null)
    
    if [ "$actual_perms" != "$expected_perms" ]; then
        log_security_event "$EVENT_PERMISSION_ERROR" "$SEVERITY_WARNING" \
            "Incorrect permissions on $file" "Expected: $expected_perms, Actual: $actual_perms"
        return 1
    fi
    
    return 0
}

# Validate secure directory
validate_secure_directory() {
    local dir="$1"
    
    # Check existence
    if [ ! -d "$dir" ]; then
        log_security_event "$EVENT_PERMISSION_ERROR" "$SEVERITY_ERROR" \
            "Directory does not exist: $dir"
        return 1
    fi
    
    # Check permissions (should be 700)
    if ! validate_permissions "$dir" "700"; then
        return 1
    fi
    
    # Check ownership
    local dir_owner=$(stat -c %U "$dir" 2>/dev/null || stat -f %Su "$dir" 2>/dev/null)
    if [ "$dir_owner" != "$USER" ]; then
        log_security_event "$EVENT_SECURITY_VIOLATION" "$SEVERITY_CRITICAL" \
            "Directory ownership mismatch" "Directory: $dir, Owner: $dir_owner, Expected: $USER"
        return 1
    fi
    
    return 0
}

# ============================================================================
# Audit Report Generation
# ============================================================================

# Generate audit report
generate_audit_report() {
    local report_type="${1:-summary}"  # summary, detailed, compliance
    local output_file="${2:-}"
    
    if [ ! -f "$AUDIT_REPORT_FILE" ]; then
        echo "No audit data available"
        return 1
    fi
    
    local report=$(cat "$AUDIT_REPORT_FILE")
    
    case "$report_type" in
        summary)
            if command -v jq &>/dev/null; then
                echo "Security Audit Summary"
                echo "====================="
                echo "$report" | jq -r '
                    "Initialized: \(.initialized)",
                    "Last Check: \(.last_check // "Never")",
                    "",
                    "Statistics:",
                    "  Total Events: \(.statistics.total_events)",
                    "  Auth Successes: \(.statistics.auth_successes)",
                    "  Auth Failures: \(.statistics.auth_failures)",
                    "  Security Violations: \(.statistics.security_violations)",
                    "  Token Rotations: \(.statistics.token_rotations)",
                    "",
                    "Active Alerts: \(.alerts | map(select(.acknowledged == false)) | length)"
                '
            else
                cat "$AUDIT_REPORT_FILE"
            fi
            ;;
            
        detailed)
            echo "Detailed Security Audit Report"
            echo "============================="
            echo ""
            echo "Security Events:"
            tail -50 "$SECURITY_LOG_FILE" 2>/dev/null
            echo ""
            echo "Access Log:"
            tail -50 "$ACCESS_LOG_FILE" 2>/dev/null
            echo ""
            echo "Error Log:"
            tail -50 "$ERROR_LOG_FILE" 2>/dev/null
            ;;
            
        compliance)
            check_security_compliance
            ;;
    esac
    
    # Save to file if specified
    if [ -n "$output_file" ]; then
        generate_audit_report "$report_type" > "$output_file"
        chmod 600 "$output_file"
    fi
}

# Check security compliance
check_security_compliance() {
    echo "Security Compliance Check"
    echo "========================"
    
    local issues=0
    
    # Check file permissions
    echo "Checking file permissions..."
    for file in "$TOKEN_FILE" "$TOKEN_METADATA_FILE" "$AUDIT_REPORT_FILE"; do
        if [ -f "$file" ]; then
            if ! validate_permissions "$file" "600"; then
                echo "  ✗ $file has incorrect permissions"
                issues=$((issues + 1))
            else
                echo "  ✓ $file permissions OK"
            fi
        fi
    done
    
    # Check directory permissions
    echo ""
    echo "Checking directory permissions..."
    for dir in "$TOKEN_STORAGE_DIR" "$AUDIT_LOG_DIR"; do
        if [ -d "$dir" ]; then
            if ! validate_secure_directory "$dir"; then
                echo "  ✗ $dir security check failed"
                issues=$((issues + 1))
            else
                echo "  ✓ $dir security OK"
            fi
        fi
    done
    
    # Check for security violations
    echo ""
    echo "Checking security events..."
    if command -v jq &>/dev/null && [ -f "$AUDIT_REPORT_FILE" ]; then
        local violations=$(cat "$AUDIT_REPORT_FILE" | jq -r '.statistics.security_violations')
        if [ "$violations" -gt 0 ]; then
            echo "  ⚠ $violations security violations detected"
            issues=$((issues + 1))
        else
            echo "  ✓ No security violations"
        fi
    fi
    
    echo ""
    if [ "$issues" -eq 0 ]; then
        echo "Status: COMPLIANT ✓"
    else
        echo "Status: NON-COMPLIANT ✗ ($issues issues found)"
    fi
    
    return "$issues"
}

# ============================================================================
# Log Management
# ============================================================================

# Rotate logs if needed
rotate_logs_if_needed() {
    for log_file in "$SECURITY_LOG_FILE" "$ACCESS_LOG_FILE" "$ERROR_LOG_FILE"; do
        if [ -f "$log_file" ]; then
            local size=$(stat -c %s "$log_file" 2>/dev/null || stat -f %z "$log_file" 2>/dev/null)
            
            if [ "$size" -gt "$MAX_LOG_SIZE" ]; then
                rotate_log_file "$log_file"
            fi
        fi
    done
}

# Rotate single log file
rotate_log_file() {
    local log_file="$1"
    
    # Rotate existing backups
    for i in $(seq $((LOG_ROTATION_COUNT - 1)) -1 1); do
        if [ -f "${log_file}.$i" ]; then
            mv "${log_file}.$i" "${log_file}.$((i + 1))"
        fi
    done
    
    # Move current to .1
    mv "$log_file" "${log_file}.1"
    
    # Create new log file
    touch "$log_file"
    chmod 600 "$log_file"
    
    # Remove oldest if exists
    if [ -f "${log_file}.$LOG_ROTATION_COUNT" ]; then
        shred -vfz -n 1 "${log_file}.$LOG_ROTATION_COUNT" 2>/dev/null || \
        rm -f "${log_file}.$LOG_ROTATION_COUNT"
    fi
}

# Clean old audit logs
clean_old_audit_logs() {
    local max_age="${1:-604800}"  # Default 7 days
    
    find "$AUDIT_LOG_DIR" -type f -name "*.log.*" -mtime +7 -exec shred -vfz -n 1 {} \; 2>/dev/null || \
    find "$AUDIT_LOG_DIR" -type f -name "*.log.*" -mtime +7 -delete
}

# ============================================================================
# Utility Functions
# ============================================================================

# Show recent security events
show_recent_events() {
    local count="${1:-20}"
    local event_type="${2:-}"
    
    if [ -f "$SECURITY_LOG_FILE" ]; then
        if [ -n "$event_type" ]; then
            grep "\"event\": \"$event_type\"" "$SECURITY_LOG_FILE" | tail -"$count"
        else
            tail -"$count" "$SECURITY_LOG_FILE"
        fi
    else
        echo "No security log found"
    fi
}

# Export audit data
export_audit_data() {
    local output_dir="${1:-$HOME/security_audit_export}"
    
    mkdir -p "$output_dir"
    
    # Copy all audit files
    cp -p "$AUDIT_REPORT_FILE" "$output_dir/" 2>/dev/null
    cp -p "$SECURITY_LOG_FILE" "$output_dir/" 2>/dev/null
    cp -p "$ACCESS_LOG_FILE" "$output_dir/" 2>/dev/null
    cp -p "$ERROR_LOG_FILE" "$output_dir/" 2>/dev/null
    
    # Generate reports
    generate_audit_report "summary" > "$output_dir/summary.txt"
    generate_audit_report "detailed" > "$output_dir/detailed.txt"
    check_security_compliance > "$output_dir/compliance.txt"
    
    # Create archive
    tar -czf "$output_dir.tar.gz" -C "$(dirname "$output_dir")" "$(basename "$output_dir")"
    
    echo "Audit data exported to: $output_dir.tar.gz"
}

# ============================================================================
# Initialization
# ============================================================================

# Initialize audit system when sourced
init_audit_system