#!/bin/bash
################################################################################
# Start Oracle APEX/ORDS
################################################################################

ORDS_HOME="${SANDBOX_ORDS_HOME:-/opt/oracle/ords}"
ORDS_CONFIG="${SANDBOX_ORDS_CONFIG:-/opt/oracle/ords/config}"
ORDS_LOG="${SANDBOX_ORDS_LOG:-/tmp/ords.log}"
ORDS_PORT="${SANDBOX_ORDS_PORT:-8080}"
APEX_IMAGES_DIR="${SANDBOX_APEX_IMAGES_DIR:-/tmp/i}"

echo "🚀 Starting Oracle APEX/ORDS..."

# The running process is "java -jar .../ords.war ..." (the ords wrapper execs into
# java), so it never matches a pidof -x lookup against the wrapper script path.
if pgrep -f 'ords\.war' > /dev/null 2>&1; then
    echo "ℹ️  ORDS is already running"
    exit 0
fi

# Verify ORDS binary exists
if [ ! -f "${ORDS_HOME}/bin/ords" ]; then
    echo "❌ Error: ORDS binary not found at ${ORDS_HOME}/bin/ords"
    exit 1
fi

# Start ORDS in background
echo "Starting ORDS in background..."
cd "${ORDS_CONFIG}" 2>/dev/null || cd "${ORDS_HOME}"
"${ORDS_HOME}/bin/ords" --config "${ORDS_CONFIG}" serve --apex-images "${APEX_IMAGES_DIR}" --port "${ORDS_PORT}" > "${ORDS_LOG}" 2>&1 &

# Wait for ORDS to start
sleep 5

# Verify ORDS is running
if pgrep -f 'ords\.war' > /dev/null 2>&1; then
    echo "✅ Oracle APEX/ORDS started successfully"
    echo "🌐 ORDS available at: http://localhost:${ORDS_PORT}/ords/"
    exit 0
else
    echo "❌ Error: ORDS failed to start"
    echo "📋 Check logs: tail -50 ${ORDS_LOG}"
    tail -20 "${ORDS_LOG}"
    exit 1
fi
