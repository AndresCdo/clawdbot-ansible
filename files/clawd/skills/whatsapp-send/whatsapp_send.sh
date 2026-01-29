#!/bin/bash
# whatsapp-send tool implementation
# This script is called by the Clawdbot agent with tool parameters

set -e

# Parse JSON input from stdin
input=$(cat)

# Extract phone and message using jq (or fallback to basic parsing)
if command -v jq &> /dev/null; then
    phone=$(echo "$input" | jq -r '.phone // .target // empty')
    message=$(echo "$input" | jq -r '.message // empty')
else
    # Fallback: basic grep/sed parsing (less reliable)
    phone=$(echo "$input" | grep -o '"phone"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/' || echo "")
    message=$(echo "$input" | grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/' || echo "")
fi

# Validate inputs
if [ -z "$phone" ]; then
    echo '{"error": "Missing required parameter: phone (E.164 format required, e.g., +31684550488)"}'
    exit 1
fi

if [ -z "$message" ]; then
    echo '{"error": "Missing required parameter: message"}'
    exit 1
fi

# Validate phone format (basic E.164 check)
if [[ ! "$phone" =~ ^\+[1-9][0-9]{1,14}$ ]]; then
    echo "{\"error\": \"Invalid phone format: $phone. Must be E.164 format (e.g., +31684550488)\"}"
    exit 1
fi

# Find clawdbot binary
CLAWDBOT_BIN=""
if command -v clawdbot &> /dev/null; then
    CLAWDBOT_BIN="clawdbot"
elif [ -f "/home/andres/.nvm/versions/node/v22.20.0/bin/clawdbot" ]; then
    CLAWDBOT_BIN="/home/andres/.nvm/versions/node/v22.20.0/bin/clawdbot"
else
    echo '{"error": "clawdbot command not found in PATH"}'
    exit 1
fi

# Send the message
output=$("$CLAWDBOT_BIN" message send \
    --channel whatsapp \
    --target "$phone" \
    --message "$message" \
    --json 2>&1)

exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo "{\"success\": true, \"phone\": \"$phone\", \"message_length\": ${#message}, \"output\": $(echo "$output" | jq -Rs .)}"
else
    echo "{\"success\": false, \"error\": \"Failed to send message\", \"exit_code\": $exit_code, \"output\": $(echo "$output" | jq -Rs .)}"
    exit 1
fi
