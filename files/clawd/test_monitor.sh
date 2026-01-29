#!/bin/bash

# Test script for monitor_clawdbot.sh
# This script tests various scenarios to ensure monitor works correctly

MONITOR_SCRIPT="/home/andres/clawd/monitor_clawdbot.sh"
MONITOR_LOG="/home/andres/clawd/monitor_log.txt"
STATE_DIR="/tmp/clawdbot_monitor"

echo "========================================="
echo "Monitor Script Test Suite"
echo "========================================="
echo ""

# Test 1: Basic functionality
echo "[TEST 1] Basic monitor functionality"
echo "Running monitor script..."
bash "$MONITOR_SCRIPT"
if grep -q "\[END\] Monitoring cycle completed" "$MONITOR_LOG"; then
    echo "✓ PASS: Monitor executed successfully"
else
    echo "✗ FAIL: Monitor did not complete cycle"
fi
echo ""

# Test 2: Systemctl connectivity
echo "[TEST 2] Systemctl connectivity from script"
export XDG_RUNTIME_DIR="/run/user/1000"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
if systemctl --user is-active clawdbot-gateway >/dev/null 2>&1; then
    echo "✓ PASS: Systemctl connection successful"
else
    echo "✗ FAIL: Systemctl connection failed"
fi
echo ""

# Test 3: Gateway detection
echo "[TEST 3] Gateway dual-check detection"
if pgrep -f "clawdbot.*gateway" >/dev/null 2>&1; then
    echo "✓ PASS: Gateway process found"
else
    echo "✗ FAIL: Gateway process not found"
fi
echo ""

# Test 4: Port connectivity (port 18789)
echo "[TEST 4] Gateway port connectivity"
if timeout 3 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/18789" 2>/dev/null; then
    echo "✓ PASS: Gateway port 18789 is responsive"
else
    echo "✗ FAIL: Gateway port 18789 not responsive"
fi
echo ""

# Test 5: WhatsApp health check
echo "[TEST 5] WhatsApp health verification"
if timeout 15 clawdbot status 2>&1 | grep -qi "WhatsApp.*OK"; then
    echo "✓ PASS: WhatsApp channel is healthy"
else
    echo "✗ FAIL: WhatsApp channel is not healthy"
fi
echo ""

# Test 6: State directory
echo "[TEST 6] State directory and tracking"
if [ -d "$STATE_DIR" ]; then
    echo "✓ PASS: State directory exists: $STATE_DIR"
    ls -la "$STATE_DIR" 2>/dev/null || echo "  (directory empty)"
else
    echo "✗ FAIL: State directory not found"
fi
echo ""

# Test 7: Log file
echo "[TEST 7] Monitor log file"
if [ -f "$MONITOR_LOG" ]; then
    echo "✓ PASS: Log file exists"
    echo "  Recent entries:"
    tail -5 "$MONITOR_LOG" | sed 's/^/    /'
else
    echo "✗ FAIL: Log file not found"
fi
echo ""

# Test 8: Cron job
echo "[TEST 8] Cron job configuration"
if crontab -l 2>/dev/null | grep -q "monitor_clawdbot.sh"; then
    echo "✓ PASS: Monitor cron job configured"
    echo "  Entry:"
    crontab -l 2>/dev/null | grep "monitor_clawdbot.sh" | sed 's/^/    /'
else
    echo "✗ FAIL: Monitor cron job not found"
fi
echo ""

# Test 9: Deep cleanup function
echo "[TEST 9] Deep cleanup function integration"
if grep -q "deep_cleanup_browsers" "$MONITOR_SCRIPT"; then
    echo "✓ PASS: Deep cleanup function is present in monitor script"
    if grep -q "deep_cleanup_browsers" "$MONITOR_SCRIPT" | grep -A5 "Attempting gateway restart"; then
        echo "✓ PASS: Deep cleanup is integrated into restart logic"
    else
        echo "⚠ WARN: Deep cleanup function exists but may not be integrated"
    fi
else
    echo "✗ FAIL: Deep cleanup function not found"
fi
echo ""

# Test 10: Recent restart activity
echo "[TEST 10] Recent monitoring activity"
RECENT_RESTARTS=$(grep -c "\[ACTION\] Attempting gateway restart" "$MONITOR_LOG" 2>/dev/null || echo "0")
RECENT_CLEANUPS=$(grep -c "\[CLEANUP\]" "$MONITOR_LOG" 2>/dev/null || echo "0")
echo "  Gateway restarts detected: $RECENT_RESTARTS"
echo "  Cleanup operations detected: $RECENT_CLEANUPS"
if [ "$RECENT_CLEANUPS" -gt 0 ]; then
    echo "  Last cleanup activity:"
    grep "\[CLEANUP\]" "$MONITOR_LOG" 2>/dev/null | tail -3 | sed 's/^/    /'
fi
echo ""

echo "========================================="
echo "Test Suite Complete"
echo "========================================="
