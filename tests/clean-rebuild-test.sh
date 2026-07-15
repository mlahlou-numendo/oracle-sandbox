#!/usr/bin/env bash

#####################################################
# Oracle Sandbox - Clean Rebuild & Test Script
#####################################################
# Purpose: Complete environment cleanup, rebuild, and validation
# Usage: ./tests/clean-rebuild-test.sh [--schema hr|oe|pm|sh|all]
#
# This script performs:
# 1. Complete cleanup (containers, images, volumes, build cache)
# 2. Fresh Docker build
# 3. Container startup
# 4. Oracle schema installation testing
# 5. Validation of installed schemas
#####################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_header() {
    echo ""
    echo "============================================"
    echo "$1"
    echo "============================================"
}

# Parse arguments
SCHEMA_TO_TEST="${1:-hr}"  # Default to HR schema
if [[ "$SCHEMA_TO_TEST" == "--schema" ]]; then
    SCHEMA_TO_TEST="${2:-hr}"
fi

# Validate schema argument
VALID_SCHEMAS="hr oe pm sh all"
if [[ ! " $VALID_SCHEMAS " =~ " $SCHEMA_TO_TEST " ]]; then
    log_error "Invalid schema: $SCHEMA_TO_TEST"
    echo "Valid options: $VALID_SCHEMAS"
    exit 1
fi

log_header "Oracle Sandbox - Clean Rebuild & Test"
log_info "Schema to test: $SCHEMA_TO_TEST"
log_info "Working directory: $(pwd)"

# Step 1: Complete Cleanup
log_header "Step 1: Complete Environment Cleanup"

log_info "Stopping containers..."
docker compose down 2>/dev/null || true
log_success "Containers stopped"

log_info "Removing sandbox images..."
docker images | grep sandbox-oracle | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || true
log_success "Sandbox images removed"

log_info "Removing volumes..."
docker volume ls | grep oracle-sandbox | awk '{print $2}' | xargs -r docker volume rm -f 2>/dev/null || true
log_success "Volumes removed"

log_info "Cleaning build cache..."
docker builder prune -f 2>/dev/null || true
log_success "Build cache cleaned"

log_info "Cleaning dangling images..."
docker image prune -f 2>/dev/null || true
log_success "Dangling images removed"

# Display cleanup summary
log_header "Cleanup Summary"
RECLAIMED=$(docker system df | grep "Build Cache" | awk '{print $4}')
log_info "Total space available for reclaim: $RECLAIMED"

# Step 2: Fresh Build
log_header "Step 2: Fresh Docker Build"

log_info "Building sandbox-oracle-server image..."
BUILD_START=$(date +%s)

if docker compose build sandbox-oracle-server 2>&1 | tee /tmp/oracle-sandbox-build.log; then
    BUILD_END=$(date +%s)
    BUILD_TIME=$((BUILD_END - BUILD_START))
    log_success "Build completed in ${BUILD_TIME}s"
else
    log_error "Build failed! Check /tmp/oracle-sandbox-build.log"
    exit 1
fi

# Step 3: Start Containers
log_header "Step 3: Start Containers"

log_info "Starting Docker containers..."
if docker compose up -d 2>&1 | tee -a /tmp/oracle-sandbox-build.log; then
    log_success "Containers started"
else
    log_error "Container startup failed!"
    exit 1
fi

log_info "Waiting for containers to be healthy (30s)..."
sleep 30

# Check container status
ORACLE_DB_STATUS=$(docker inspect sandbox-oracle-database --format='{{.State.Status}}' 2>/dev/null || echo "not found")
ORACLE_SERVER_STATUS=$(docker inspect sandbox-oracle-server --format='{{.State.Status}}' 2>/dev/null || echo "not found")

if [[ "$ORACLE_DB_STATUS" == "running" && "$ORACLE_SERVER_STATUS" == "running" ]]; then
    log_success "Both containers are running"
else
    log_error "Container health check failed!"
    log_info "Database: $ORACLE_DB_STATUS"
    log_info "Server: $ORACLE_SERVER_STATUS"
    exit 1
fi

# Step 4: Schema Installation Testing
log_header "Step 4: Schema Installation & Validation"

# Function to test schema installation
test_schema() {
    local schema_name=$1
    local schema_upper=$(echo "$schema_name" | tr '[:lower:]' '[:upper:]')
    
    log_info "Testing $schema_upper schema installation..."
    
    # Drop schema if exists (clean slate)
    log_info "Ensuring clean slate for $schema_upper..."
    docker exec sandbox-oracle-server bash -c "sql -S sys/\${SANDBOX_DB_PASSWORD}@//192.168.1.110:1521/FREE as sysdba <<EOF
ALTER SESSION SET CONTAINER=SANDBOX_PDB;
BEGIN
    EXECUTE IMMEDIATE 'DROP USER $schema_upper CASCADE';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE != -1918 THEN RAISE; END IF;  -- Ignore user doesn't exist
END;
/
EXIT
EOF" 2>&1 | grep -v "^$" || true
    
    log_info "Installing $schema_upper schema..."
    INSTALL_START=$(date +%s)
    
    if docker exec sandbox-oracle-server sandbox install schema --name "$schema_name" > "/tmp/install-$schema_name.log" 2>&1; then
        INSTALL_END=$(date +%s)
        INSTALL_TIME=$((INSTALL_END - INSTALL_START))
        log_success "$schema_upper installation completed in ${INSTALL_TIME}s"
    else
        log_error "$schema_upper installation failed! Check /tmp/install-$schema_name.log"
        return 1
    fi
    
    # Validate installation
    log_info "Validating $schema_upper schema..."
    
    SCHEMA_PASSWORD=$(docker exec sandbox-oracle-server bash -c "echo \$SANDBOX_${schema_upper}_SCHEMA_PASSWORD")
    
    # Count tables
    TABLE_COUNT=$(docker exec sandbox-oracle-server bash -c "sql -S $schema_name/${SCHEMA_PASSWORD}@//192.168.1.110:1521/SANDBOX_PDB <<EOF
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT COUNT(*) FROM user_tables;
EXIT
EOF" 2>&1 | tr -d ' ' | grep -E '^[0-9]+$' | head -1)
    
    # Count rows from a key table for each schema
    case "$schema_name" in
        hr)
            ROW_COUNT=$(docker exec sandbox-oracle-server bash -c "sql -S $schema_name/${SCHEMA_PASSWORD}@//192.168.1.110:1521/SANDBOX_PDB <<EOF
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT COUNT(*) FROM employees;
EXIT
EOF" 2>&1 | tr -d ' ' | grep -E '^[0-9]+$' | head -1)
            ;;
        oe)
            ROW_COUNT=$(docker exec sandbox-oracle-server bash -c "sql -S $schema_name/${SCHEMA_PASSWORD}@//192.168.1.110:1521/SANDBOX_PDB <<EOF
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT COUNT(*) FROM customers;
EXIT
EOF" 2>&1 | tr -d ' ' | grep -E '^[0-9]+$' | head -1)
            ;;
        pm)
            ROW_COUNT=$(docker exec sandbox-oracle-server bash -c "sql -S $schema_name/${SCHEMA_PASSWORD}@//192.168.1.110:1521/SANDBOX_PDB <<EOF
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT COUNT(*) FROM print_media;
EXIT
EOF" 2>&1 | tr -d ' ' | grep -E '^[0-9]+$' | head -1)
            ;;
        sh)
            ROW_COUNT=$(docker exec sandbox-oracle-server bash -c "sql -S $schema_name/${SCHEMA_PASSWORD}@//192.168.1.110:1521/SANDBOX_PDB <<EOF
SET HEADING OFF
SET FEEDBACK OFF
SET PAGESIZE 0
SELECT COUNT(*) FROM sales;
EXIT
EOF" 2>&1 | tr -d ' ' | grep -E '^[0-9]+$' | head -1)
            ;;
    esac
    
    log_info "  Tables created: $TABLE_COUNT"
    log_info "  Total rows: $ROW_COUNT"
    
    # Schema-specific validation
    case "$schema_name" in
        hr)
            if [[ "$TABLE_COUNT" -ge 7 && "$ROW_COUNT" -gt 100 ]]; then
                log_success "$schema_upper schema validation passed (7 tables, ~107 employees)"
                return 0
            else
                log_error "$schema_upper validation failed (expected 7 tables, 100+ rows)"
                return 1
            fi
            ;;
        oe)
            if [[ "$TABLE_COUNT" -ge 12 && "$ROW_COUNT" -gt 300 ]]; then
                log_success "$schema_upper schema validation passed (12 tables, ~319 customers)"
                return 0
            else
                log_error "$schema_upper validation failed (expected 12 tables, 300+ rows)"
                return 1
            fi
            ;;
        pm)
            if [[ "$TABLE_COUNT" -ge 2 ]]; then
                log_success "$schema_upper schema validation passed (2 LOB tables)"
                return 0
            else
                log_error "$schema_upper validation failed (expected 2 tables)"
                return 1
            fi
            ;;
        sh)
            if [[ "$TABLE_COUNT" -ge 10 && "$ROW_COUNT" -gt 50000 ]]; then
                log_success "$schema_upper schema validation passed (10+ tables, 50K+ rows)"
                return 0
            else
                log_error "$schema_upper validation failed (expected 10+ tables, 50K+ rows)"
                return 1
            fi
            ;;
    esac
}

# Run schema tests
FAILED_SCHEMAS=()
if [[ "$SCHEMA_TO_TEST" == "all" ]]; then
    for schema in hr oe pm sh; do
        if ! test_schema "$schema"; then
            FAILED_SCHEMAS+=("$schema")
        fi
        echo ""
    done
else
    if ! test_schema "$SCHEMA_TO_TEST"; then
        FAILED_SCHEMAS+=("$SCHEMA_TO_TEST")
    fi
fi

# Step 5: Final Summary
log_header "Test Results Summary"

if [[ ${#FAILED_SCHEMAS[@]} -eq 0 ]]; then
    log_success "All schema tests passed! 🎉"
    log_info "Build time: ${BUILD_TIME}s"
    log_info "Logs available in /tmp/install-*.log"
    exit 0
else
    log_error "Some schema tests failed:"
    for failed in "${FAILED_SCHEMAS[@]}"; do
        log_error "  - $failed"
    done
    log_info "Check logs: /tmp/install-*.log"
    exit 1
fi
