#!/usr/bin/env bash

#####################################################
# Oracle Sandbox - Quick Schema Test
#####################################################
# Purpose: Quick test of schema installation (no cleanup/rebuild)
# Usage: ./tests/quick-schema-test.sh [hr|oe|pm|sh]
#####################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

SCHEMA_NAME="${1:-hr}"
SCHEMA_UPPER=$(echo "$SCHEMA_NAME" | tr '[:lower:]' '[:upper:]')

echo "=========================================="
echo "Quick Schema Test: $SCHEMA_UPPER"
echo "=========================================="

# Drop existing schema
log_info "Dropping existing $SCHEMA_UPPER schema (if exists)..."
docker exec sandbox-oracle-server bash -c "sql -S sys/\${SANDBOX_DB_PASSWORD}@//192.168.1.110:1521/FREE as sysdba <<EOF
ALTER SESSION SET CONTAINER=SANDBOX_PDB;
BEGIN
    EXECUTE IMMEDIATE 'DROP USER $SCHEMA_UPPER CASCADE';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -1918 THEN RAISE; END IF;
END;
/
EXIT
EOF" 2>&1 | grep -v "^$" || true

# Install schema
log_info "Installing $SCHEMA_UPPER schema..."
docker exec sandbox-oracle-server sandbox install schema --name "$SCHEMA_NAME"

# Quick validation
log_info "Validating..."
SCHEMA_PASSWORD=$(docker exec sandbox-oracle-server bash -c "echo \$SANDBOX_${SCHEMA_UPPER}_SCHEMA_PASSWORD")

TABLE_COUNT=$(docker exec sandbox-oracle-server bash -c "sql -S $SCHEMA_NAME/${SCHEMA_PASSWORD}@//192.168.1.110:1521/SANDBOX_PDB <<EOF
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT COUNT(*) FROM user_tables;
EXIT
EOF" 2>&1 | tr -d ' ' | grep -E '^[0-9]+$' | head -1)

echo ""
log_info "Tables created: $TABLE_COUNT"

if [[ "$TABLE_COUNT" -gt 0 ]]; then
    log_success "$SCHEMA_UPPER schema installation succeeded! 🎉"
    exit 0
else
    log_error "$SCHEMA_UPPER schema installation failed"
    log_info "Check: /tmp/install-sample-schema-${SCHEMA_NAME}.log"
    exit 1
fi
