#!/bin/bash

# Monitor Clawdbot and WhatsApp channel
# OPCIÓN B: Intelligent monitoring with error analysis and backoff
# Features:
#  - Dual-check for gateway (systemctl + process check)
#  - Error discrimination (network vs app crash)
#  - Exponential backoff for non-critical issues
#  - WhatsApp-specific health validation
#  - False positive prevention

LOGFILE="/home/andres/clawd/monitor_log.txt"
STATE_DIR="/tmp/clawdbot_monitor"
MAX_RESTART_ATTEMPTS=3
BACKOFF_BASE=60  # Start with 1 minute (60 seconds)

# Use explicit path to clawdbot (NVM)
CLAWDBOT="/home/andres/.nvm/versions/node/v22.20.0/bin/clawdbot"

# CRITICAL: Set up systemd user bus for cron execution
# This allows systemctl --user to work from cron jobs
export XDG_RUNTIME_DIR="/run/user/1000"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# Rotate log file if it gets too large
if [ -f "$LOGFILE" ] && [ $(stat -c%s "$LOGFILE" 2>/dev/null) -gt 10485760 ]; then
    mv "$LOGFILE" "$LOGFILE.$(date +%s)"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): Log rotated" >> "$LOGFILE"
fi

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "$LOGFILE"
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Deep cleanup: Kill orphaned browser/chromium processes that prevent fresh WhatsApp sessions
deep_cleanup_browsers() {
    log_message "[CLEANUP] Starting deep cleanup of orphaned browser processes"
    
    local killed_count=0
    
    # Strategy 1: Kill any stray chromium/chrome processes with "whatsapp" or "wwebjs" in command line
    for pid in $(pgrep -f "chromium.*whatsapp\|chrome.*whatsapp\|chromium.*wwebjs\|chrome.*wwebjs" 2>/dev/null); do
        log_message "[CLEANUP] Killing WhatsApp browser process: $pid"
        kill -9 "$pid" 2>/dev/null && killed_count=$((killed_count + 1))
    done
    
    # Strategy 2: Kill headless browsers that might be orphaned from previous sessions
    for pid in $(pgrep -f "chrome.*headless.*user-data-dir.*clawdbot\|chromium.*headless.*user-data-dir.*clawdbot" 2>/dev/null); do
        log_message "[CLEANUP] Killing orphaned clawdbot headless browser: $pid"
        kill -9 "$pid" 2>/dev/null && killed_count=$((killed_count + 1))
    done
    
    # Strategy 3: Find any chromium/chrome using clawdbot's data directory
    # This catches browsers that were spawned by previous clawdbot instances
    local clawdbot_data_dirs=$(find /home/andres/.clawdbot /tmp -name "*wwebjs*" -o -name "*whatsapp*" 2>/dev/null | head -10)
    if [ -n "$clawdbot_data_dirs" ]; then
        for data_dir in $clawdbot_data_dirs; do
            for pid in $(lsof +D "$data_dir" 2>/dev/null | awk 'NR>1 {print $2}' | sort -u); do
                # Double check it's a browser process before killing
                if ps -p "$pid" -o comm= 2>/dev/null | grep -qE "chrome|chromium"; then
                    log_message "[CLEANUP] Killing browser process using clawdbot data dir: $pid"
                    kill -9 "$pid" 2>/dev/null && killed_count=$((killed_count + 1))
                fi
            done
        done
    fi
    
    log_message "[CLEANUP] Deep cleanup completed. Killed $killed_count orphaned processes"
    
    # Give the system a moment to clean up file handles and sockets
    sleep 2
}

# Dual-check: Is gateway REALLY running and RESPONSIVE?
is_gateway_running() {
    # Check 1: systemctl status
    if ! systemctl --user is-active --quiet clawdbot-gateway 2>/dev/null; then
        return 1
    fi
    
    # Check 2: Process exists
    if ! pgrep -f "clawdbot.*gateway" > /dev/null 2>&1; then
        return 1
    fi
    
    # Check 3: Gateway is actually responsive (most important)
    # We check if we can reach the gateway port
    if ! timeout 3 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/18789" 2>/dev/null; then
        return 1
    fi
    
    # All checks passed
    return 0
}

# Analyze recent errors in logs to determine root cause
analyze_error_type() {
    # Check recent logs for network errors
    if grep -q "EAI_AGAIN\|getaddrinfo\|Connection was lost\|status 408" /tmp/clawdbot/clawdbot-*.log 2>/dev/null; then
        echo "network"
        return 0
    fi
    
    # Check for application crash patterns
    if grep -q "FATAL\|Segmentation\|signal\|core dumped" /tmp/clawdbot/clawdbot-*.log 2>/dev/null; then
        echo "app_crash"
        return 0
    fi
    
    # Check for authentication failures
    if grep -q "auth.*fail\|Unauthorized\|401\|403" /tmp/clawdbot/clawdbot-*.log 2>/dev/null; then
        echo "auth"
        return 0
    fi
    
    # Default to unknown
    echo "unknown"
    return 0
}

# Calculate exponential backoff time
calculate_backoff() {
    local error_type=$1
    local attempt_count=$2
    
    case "$error_type" in
        "network")
            # Network errors: back off more aggressively (wait longer)
            echo $((BACKOFF_BASE * (2 ** (attempt_count - 1))))
            ;;
        "app_crash")
            # App crashes: standard backoff
            echo $((BACKOFF_BASE * (attempt_count - 1)))
            ;;
        "auth")
            # Auth issues: even more aggressive backoff
            echo $((BACKOFF_BASE * (2 ** attempt_count)))
            ;;
        *)
            # Unknown: conservative approach
            echo $((BACKOFF_BASE * attempt_count))
            ;;
    esac
}

# Check if WhatsApp channel is specifically healthy
is_whatsapp_healthy() {
    if [ ! -f "$CLAWDBOT" ]; then
        log_message "[WARNING] clawdbot binary not found at $CLAWDBOT"
        return 1
    fi
    
    local status_output=$(timeout 15 "$CLAWDBOT" status 2>&1)
    
    if echo "$status_output" | grep -qi "WhatsApp.*OK"; then
        return 0  # Healthy
    fi
    return 1  # Unhealthy
}

# Check if WhatsApp is in a timeout loop (connected but not processing messages)
is_whatsapp_stuck() {
    # Strategy 1: Check for very recent timeouts or connection errors (last 5 minutes)
    local last_error=$(grep -E "channel exited.*ETIMEDOUT|Connection.*[Tt]erminated|WebSocket.*error" /tmp/clawdbot/clawdbot-*.log 2>/dev/null | tail -1 | grep -o '"date":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$last_error" ]; then
        # Convert ISO date to timestamp
        local error_ts=$(date -d "$last_error" +%s 2>/dev/null)
        local now_ts=$(date +%s)
        local age=$((now_ts - error_ts))
        
        # If we had an error in the last 5 minutes (increased from 3)
        if [ "$age" -lt 300 ]; then
            log_message "[DETECTION] Recent WhatsApp connection error: ${age}s ago"
            return 0  # Stuck
        fi
    fi
    
    # Strategy 2: Count errors in last 15 minutes
    # If there are 2+ errors in 15 minutes, connection is unstable (reduced threshold from 3)
    local fifteen_min_ago=$(date -d '15 minutes ago' '+%Y-%m-%dT%H:%M' 2>/dev/null)
    local recent_errors=$(grep -E "channel exited.*ETIMEDOUT|Connection.*[Tt]erminated" /tmp/clawdbot/clawdbot-*.log 2>/dev/null | grep "$fifteen_min_ago" | wc -l)
    
    if [ "$recent_errors" -ge 2 ]; then
        log_message "[DETECTION] High error frequency: $recent_errors connection errors in last 15 min"
        return 0  # Stuck
    fi
    
    # Strategy 3: Check if NOT listening for messages (critical indicator)
    local listening_check=$(grep "Listening for personal WhatsApp inbound messages" /tmp/clawdbot/clawdbot-*.log 2>/dev/null | tail -1 | grep -o '"date":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$listening_check" ]; then
        local listen_ts=$(date -d "$listening_check" +%s 2>/dev/null)
        local listen_age=$((now_ts - listen_ts))
        
        # If last "Listening" message is older than 10 minutes, something is wrong
        if [ "$listen_age" -gt 600 ]; then
            log_message "[DETECTION] WhatsApp NOT listening for messages (last listener: ${listen_age}s ago)"
            return 0  # Stuck
        fi
    fi
    
    # Strategy 4: Check if status shows OK but no recent message activity
    # This catches the "zombie" state where status is OK but nothing works
    local status_output=$("$CLAWDBOT" status 2>&1)
    if echo "$status_output" | grep -qi "WhatsApp.*OK"; then
        local last_msg_handled=$(grep "messagesHandled" /tmp/clawdbot/clawdbot-*.log 2>/dev/null | tail -1 | grep -o '"lastMessageAt":[0-9]*' | cut -d':' -f2)
        
        if [ -n "$last_msg_handled" ] && [ "$last_msg_handled" != "null" ]; then
            local msg_ts=$((last_msg_handled / 1000))  # Convert from ms to seconds
            local msg_age=$((now_ts - msg_ts))
            
            # If last message was handled more than 30 minutes ago and we have recent errors, relogin
            if [ "$msg_age" -gt 1800 ] && [ "$age" -lt 600 ]; then
                log_message "[DETECTION] WhatsApp shows OK but no message activity for ${msg_age}s and recent errors"
                return 0  # Stuck
            fi
        fi
    fi
    
    return 1  # Not stuck
}

# Force WhatsApp relogin to fix stuck sessions
force_whatsapp_relogin() {
    log_message "[RECOVERY] Forcing WhatsApp relogin to fix stuck session"
    
    # First, check if we have basic internet connectivity
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log_message "[RECOVERY] No internet connectivity detected, skipping relogin (will retry next cycle)"
        return 1
    fi
    
    log_message "[RECOVERY] Internet connectivity confirmed, proceeding with relogin"
    
    # Stop the gateway to ensure clean state
    log_message "[RECOVERY] Stopping gateway for clean relogin"
    systemctl --user stop clawdbot-gateway.service >> "$LOGFILE" 2>&1
    sleep 3
    
    # Kill any lingering processes
    pkill -9 -f "clawdbot" >> "$LOGFILE" 2>&1
    sleep 2
    
    # Start the gateway
    log_message "[RECOVERY] Starting gateway"
    systemctl --user start clawdbot-gateway.service >> "$LOGFILE" 2>&1
    sleep 10
    
    # Run channels login to refresh the connection
    log_message "[RECOVERY] Executing WhatsApp relogin"
    timeout 30 "$CLAWDBOT" channels login --non-interactive >> "$LOGFILE" 2>&1
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_message "[RECOVERY] WhatsApp relogin successful"
        
        # Verify it's actually listening
        sleep 5
        if grep -q "Listening for personal WhatsApp inbound messages" /tmp/clawdbot/clawdbot-*.log | tail -5; then
            log_message "[RECOVERY] Confirmed: WhatsApp is now listening for messages"
            clear_restart_tracking  # Clear error counters on successful recovery
            return 0
        else
            log_message "[RECOVERY] Warning: Relogin succeeded but not yet listening"
            return 1
        fi
    else
        log_message "[RECOVERY] WhatsApp relogin failed with exit code $exit_code"
        return 1
    fi
}

# Check last restart time and determine if we're in backoff
check_backoff_status() {
    local error_type=$1
    local restart_file="$STATE_DIR/last_restart_time"
    local error_type_file="$STATE_DIR/last_error_type"
    local attempt_file="$STATE_DIR/restart_attempts"
    
    if [ ! -f "$restart_file" ]; then
        return 0  # Not in backoff
    fi
    
    local last_restart=$(cat "$restart_file")
    local last_error=$(cat "$error_type_file" 2>/dev/null || echo "unknown")
    local attempt_count=$(cat "$attempt_file" 2>/dev/null || echo "1")
    local backoff_seconds=$(calculate_backoff "$last_error" "$attempt_count")
    local seconds_elapsed=$(($(date +%s) - last_restart))
    
    if [ $seconds_elapsed -lt $backoff_seconds ]; then
        echo "$((backoff_seconds - seconds_elapsed))"
        return 1  # Still in backoff
    fi
    return 0  # Backoff expired
}

# Update restart tracking
update_restart_tracking() {
    local error_type=$1
    local attempt_file="$STATE_DIR/restart_attempts"
    local attempt_count=$(cat "$attempt_file" 2>/dev/null || echo "0")
    attempt_count=$((attempt_count + 1))
    
    echo $(date +%s) > "$STATE_DIR/last_restart_time"
    echo "$error_type" > "$STATE_DIR/last_error_type"
    echo $attempt_count > "$attempt_file"
}

# Clear restart tracking when healthy
clear_restart_tracking() {
    rm -f "$STATE_DIR/last_restart_time"
    rm -f "$STATE_DIR/last_error_type"
    rm -f "$STATE_DIR/restart_attempts"
}

# ============================================================================
# MAIN MONITORING LOGIC
# ============================================================================

log_message "[START] Monitoring cycle initiated"

# CHECK 1: Gateway process health
log_message "[CHECK] Gateway process status (dual-check: systemctl + pgrep)"

if is_gateway_running; then
    log_message "[OK] Gateway is running (dual-check confirmed)"
    clear_restart_tracking
else
    log_message "[ALERT] Gateway is DOWN (failed dual-check)"
    
    # Analyze what type of error caused this
    ERROR_TYPE=$(analyze_error_type)
    log_message "[ANALYSIS] Error type detected: $ERROR_TYPE"
    
    # Check if we're in exponential backoff
    BACKOFF_REMAINING=$(check_backoff_status "$ERROR_TYPE")
    BACKOFF_EXIT_CODE=$?
    
    if [ $BACKOFF_EXIT_CODE -ne 0 ]; then
        log_message "[BACKOFF] Waiting $BACKOFF_REMAINING seconds before next retry (error type: $ERROR_TYPE)"
        exit 0
    fi
    
    # Check if we've exceeded max attempts
    ATTEMPT_FILE="$STATE_DIR/restart_attempts"
    ATTEMPT_COUNT=$(cat "$ATTEMPT_FILE" 2>/dev/null || echo "0")
    
    if [ "$ATTEMPT_COUNT" -ge "$MAX_RESTART_ATTEMPTS" ]; then
        log_message "[CRITICAL] Max restart attempts ($MAX_RESTART_ATTEMPTS) exceeded. Manual intervention required."
        touch "$STATE_DIR/restart_disabled"
        exit 1
    fi
    
    # Safe to attempt restart - use systemctl directly instead of clawdbot gateway restart
    log_message "[ACTION] Attempting gateway restart (attempt $((ATTEMPT_COUNT + 1))/$MAX_RESTART_ATTEMPTS, error: $ERROR_TYPE)"
    
    # CRITICAL: Deep cleanup before restart to ensure fresh WhatsApp session
    log_message "[ACTION] Stopping gateway service before cleanup"
    systemctl --user stop clawdbot-gateway.service >> "$LOGFILE" 2>&1
    sleep 3  # Give it time to stop gracefully
    
    # Perform deep cleanup of orphaned browser processes
    deep_cleanup_browsers
    
    # Now restart the service
    if systemctl --user start clawdbot-gateway.service >> "$LOGFILE" 2>&1; then
        log_message "[SUCCESS] Gateway restart command executed via systemctl"
        update_restart_tracking "$ERROR_TYPE"
        
        # Give it more time to start and stabilize (gateway can be slow)
        # Extra time needed after deep cleanup to allow fresh browser session
        log_message "[WAIT] Allowing 15 seconds for gateway and browser initialization"
        sleep 15
        
        # Verify it actually started
        if is_gateway_running; then
            log_message "[VERIFIED] Gateway is now running (dual-check confirmed)"
            
            # Extra validation: Check WhatsApp specifically
            sleep 3
            if is_whatsapp_healthy; then
                log_message "[VERIFIED] WhatsApp channel is healthy post-restart"
                clear_restart_tracking
            else
                log_message "[WARNING] Gateway running but WhatsApp still unhealthy post-restart"
            fi
        else
            log_message "[ERROR] Gateway restart command succeeded but service not actually running"
        fi
    else
        log_message "[ERROR] Gateway restart command failed"
        update_restart_tracking "$ERROR_TYPE"
        exit 1
    fi
fi

# CHECK 2: WhatsApp channel health
log_message "[CHECK] WhatsApp channel health"

if is_whatsapp_healthy; then
    log_message "[OK] WhatsApp channel reports healthy"
    
    # Even if status says "OK", check if it's stuck in timeout loop
    if is_whatsapp_stuck; then
        log_message "[ALERT] WhatsApp is stuck in reconnect loop despite showing OK status"
        log_message "[ACTION] Attempting forced relogin to recover session"
        
        if force_whatsapp_relogin; then
            log_message "[SUCCESS] WhatsApp session recovered via relogin"
            sleep 5  # Give it time to stabilize
        else
            log_message "[ERROR] WhatsApp relogin failed, may need manual intervention"
        fi
    fi
else
    log_message "[WARNING] WhatsApp channel is not responding as expected"
    
    # Get detailed status for troubleshooting
    if [ -f "$CLAWDBOT" ]; then
        DETAILED_STATUS=$(timeout 15 "$CLAWDBOT" status 2>&1 | grep -i "WhatsApp" | head -1)
        log_message "[INFO] WhatsApp status detail: $DETAILED_STATUS"
    fi
    
    # Check if it's stuck in timeout loop
    if is_whatsapp_stuck; then
        log_message "[ACTION] WhatsApp appears stuck, attempting forced relogin"
        force_whatsapp_relogin
    else
        # For WhatsApp-specific issues, we DON'T auto-restart
        # These are usually transient network issues to web.whatsapp.com
        log_message "[INFO] Note: WhatsApp timeouts are usually transient. Monitor will check again in 1 minute."
    fi
fi

# CHECK 3: Safety mechanisms
log_message "[CHECK] Safety mechanisms and overload detection"

# Check if restart is disabled
if [ -f "$STATE_DIR/restart_disabled" ]; then
    DISABLE_TIME=$(stat -c %Y "$STATE_DIR/restart_disabled" 2>/dev/null)
    DISABLE_AGE=$(($(date +%s) - DISABLE_TIME))
    log_message "[CRITICAL] Auto-restart is DISABLED (disabled ${DISABLE_AGE}s ago). Manual intervention needed."
fi

# Count restarts in last hour (look at [ACTION] lines from last 60 minutes)
RESTART_COUNT=$(awk -v cutoff=$(date -d '-60 minutes' '+%s') '
    /\[ACTION\] Attempting gateway restart/ {
        # Parse timestamp from log: 2026-01-26 12:00:01
        gsub(/:/, " ", $2)  # Replace colons in time
        cmd = "date -d \""$1" "$2"\" +%s 2>/dev/null"
        cmd | getline timestamp
        close(cmd)
        if (timestamp >= cutoff) count++
    }
    END { print count }
' "$LOGFILE" 2>/dev/null)

if [ -z "$RESTART_COUNT" ]; then
    RESTART_COUNT=0
fi

log_message "[INFO] Restart count (last 60 minutes): $RESTART_COUNT"

if [ "$RESTART_COUNT" -gt 5 ]; then
    log_message "[ALERT] High restart frequency detected ($RESTART_COUNT restarts in last hour)"
    log_message "[ALERT] This indicates a persistent problem. Disabling auto-restart to prevent API spam."
    touch "$STATE_DIR/restart_disabled"
fi

log_message "[END] Monitoring cycle completed"
echo "---" >> "$LOGFILE"