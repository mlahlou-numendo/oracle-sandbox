#!/bin/bash
################################################################################
# Stop Oracle APEX/ORDS
################################################################################

echo "🛑 Stopping Oracle APEX/ORDS..."

# The running process is "java -jar .../ords.war ..." (the ords wrapper execs into
# java), so it never matches a pidof -x lookup against the wrapper script path.
if ! pgrep -f 'ords\.war' > /dev/null 2>&1; then
    echo "ℹ️  ORDS is not currently running"
    exit 0
fi

# Kill ORDS process
echo "Terminating ORDS process..."
ORDS_PID=$(pgrep -f 'ords\.war' | head -1)
if [ -n "$ORDS_PID" ]; then
    kill $ORDS_PID
    sleep 2
    # Verify termination
    if kill -0 $ORDS_PID 2>/dev/null; then
        echo "⚠️  Force killing ORDS..."
        kill -9 $ORDS_PID
    fi
fi

echo "✅ Oracle APEX/ORDS stopped successfully"
