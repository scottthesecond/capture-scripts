#!/bin/bash

# ---- CONFIG ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

SENDER_IP="${SENDER_IP:-}"
STREAM_PORT="${STREAM_PORT:-1234}"

# ---- HELP ----
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  echo ""
  echo "Usage:"
  echo "  $0 [<sender_ip>]"
  echo ""
  echo "Arguments:"
  echo "  <sender_ip>  Optional. IP address of the capture machine. If omitted, will use SENDER_IP from .env file."
  echo ""
  echo "Environment Variables (can be set in .env file):"
  echo "  SENDER_IP    IP address of the capture machine (required if not provided as argument)"
  echo "  STREAM_PORT  Port number for the stream (default: 1234)"
  echo ""
  echo "Examples:"
  echo "  $0                    # Use SENDER_IP from .env file"
  echo "  $0 10.0.0.100        # Connect to specific IP"
  echo "  $0 192.168.1.50 8080 # Connect to IP on custom port"
  echo ""
  exit 0
fi

# ---- Get Sender IP ----
if [ -n "$1" ]; then
  SENDER_IP="$1"
fi

if [ -z "$SENDER_IP" ]; then
  echo "❌ Error: Sender IP address not specified!"
  echo ""
  echo "Please provide the sender IP in one of these ways:"
  echo "  1. As an argument: $0 <sender_ip>"
  echo "  2. Set SENDER_IP in your .env file"
  echo "  3. Set SENDER_IP environment variable"
  echo ""
  exit 1
fi

# Check if port was provided as second argument
if [ -n "$2" ]; then
  STREAM_PORT="$2"
fi

STREAM_URL="tcp://${SENDER_IP}:${STREAM_PORT}"

echo "📡 Connecting to sender at $STREAM_URL..."
echo "⏹ Press 'q' to quit."
echo ""

ffplay -fflags nobuffer -flags low_delay -framedrop -probesize 32 -analyzeduration 0 \
  -sync ext "$STREAM_URL?fifo_size=500000&overrun_nonfatal=1"
