#!/bin/bash
################################################################################
# Oracle PM Sample Schema Installer
# This script runs FROM INSIDE the Docker container
# Installs the PM (Product Media) sample schema
#
# USAGE:
#   install-pm-schema.sh [pdb_name]
#
# PARAMETERS:
#   pdb_name  (optional) - Target PDB name (defaults to SANDBOX_PDB)
################################################################################

set -e

# Get the actual script location (resolves symlinks)
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Source utilities
source "/usr/sandbox/app/system/utils/banner.sh"
source "/usr/sandbox/app/system/utils/logging.sh"
source "/usr/sandbox/app/system/utils/colors.sh"

print_demasy_banner "Oracle PM Sample Schema Installation"

echo ""
log_info "Installing PM (Product Media) sample schema"
log_info "Expected: 2 tables with LOB data, ~288 media items"
echo ""

# Configuration
DB_HOST="${SANDBOX_DB_HOST}"
DB_PORT="${SANDBOX_DB_PORT}"
DB_PASSWORD="${SANDBOX_DB_PASSWORD}"
PDB_NAME="${1:-${SANDBOX_PM_SCHEMA_PDB:-SANDBOX_PDB}}"
SCHEMA_PATH="/opt/oracle/sample-schemas/pm"

################################################################################
# STEP 1: Prerequisites
################################################################################
log_section "Step 1: Prerequisites"

# Check SQLcl
if ! command -v sql &> /dev/null; then
    log_error "SQLcl not found"
    log_info "Run: install-sqlcl"
    exit 1
fi
log_success "SQLcl available"

# Check database connectivity
log_step "Testing database connectivity..."
if sql -S system/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << 'EOF' 2>&1 | grep -q "1"
SET HEADING OFF FEEDBACK OFF
SELECT 1 FROM DUAL;
EXIT
EOF
then
    log_success "Database connection successful"
else
    log_error "Cannot connect to database"
    exit 1
fi

################################################################################
# STEP 2: Download PM schema files
################################################################################
log_section "Step 2: Download PM Schema Files"

if [ ! -d "$SCHEMA_PATH" ] || [ -z "$(ls -A "$SCHEMA_PATH" 2>/dev/null)" ]; then
    log_info "PM schema files not found, downloading..."
    if bash /usr/sandbox/app/download/download-sample-schemas.sh pm; then
        log_success "PM schema files downloaded"
    else
        log_error "Failed to download PM schema files"
        exit 1
    fi
else
    log_success "PM schema files already available"
    log_info "Location: $SCHEMA_PATH"
fi

################################################################################
# STEP 3: Install schema
################################################################################
log_section "Step 3: Install PM Schema"

if bash "${SCRIPT_DIR}/install-sample-schema.sh" pm "$SCHEMA_PATH" "$PDB_NAME"; then
    log_success "PM schema installation completed"
else
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 2 ]; then
        log_warn "PM schema already installed"
    else
        log_error "PM schema installation failed"
        exit 1
    fi
fi

################################################################################
# STEP 4: Post-Install Verification
################################################################################
log_section "Step 4: Post-Install Verification"

# Expected tables
EXPECTED_TABLES=("PRINT_MEDIA" "ONLINE_MEDIA")

log_step "Verifying PM schema tables..."

# Count tables
TABLE_COUNT=$(sql -S system/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << 'EOF' 2>/dev/null | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM dba_tables WHERE owner = 'PM';
EXIT
EOF
)

log_info "Total tables: ${TABLE_COUNT:-0} (expected: 2)"

if [ "${TABLE_COUNT:-0}" -ge 2 ]; then
    log_success "✓ Table count verified"
else
    log_warn "⚠ Expected 2 tables, found ${TABLE_COUNT:-0}"
fi

# Verify PRINT_MEDIA table and row count
log_step "Verifying PRINT_MEDIA table..."

PRINT_MEDIA_COUNT=$(sql -S pm/${SANDBOX_PM_SCHEMA_PASSWORD:-${DB_PASSWORD}}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << 'EOF' 2>/dev/null | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM print_media;
EXIT
EOF
)

log_info "Print Media: ${PRINT_MEDIA_COUNT:-0} rows (expected: ~288)"

if [ "${PRINT_MEDIA_COUNT:-0}" -gt 0 ]; then
    log_success "✓ PRINT_MEDIA table populated"
else
    log_warn "⚠ PRINT_MEDIA table may be empty"
fi

# Check for LOB columns
log_step "Verifying LOB columns..."

LOB_COUNT=$(sql -S system/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << 'EOF' 2>/dev/null | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) 
FROM dba_lobs 
WHERE owner = 'PM';
EXIT
EOF
)

log_info "LOB columns: ${LOB_COUNT:-0}"

if [ "${LOB_COUNT:-0}" -gt 0 ]; then
    log_success "✓ LOB columns configured"
else
    log_warn "⚠ No LOB columns found"
fi

# List all tables with LOB info
log_step "PM schema tables:"
sql -S system/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << 'EOF'
SET PAGESIZE 100
SET FEEDBACK OFF
COL table_name FORMAT A20
COL num_rows FORMAT 999,999
COL has_lobs FORMAT A10
SELECT t.table_name, t.num_rows,
       CASE WHEN EXISTS (SELECT 1 FROM dba_lobs l WHERE l.owner = t.owner AND l.table_name = t.table_name)
            THEN 'Yes' ELSE 'No' END as has_lobs
FROM dba_tables t
WHERE t.owner = 'PM'
ORDER BY t.table_name;
EXIT
EOF

################################################################################
# COMPLETION SUMMARY
################################################################################
log_section "Installation Complete!"
log_success "PM (Product Media) sample schema installed successfully"

echo ""
log_info "Schema Information:"
echo "  • Schema: PM"
echo "  • PDB: $PDB_NAME"
echo "  • Tables: ${TABLE_COUNT:-0}"
echo "  • Print Media: ${PRINT_MEDIA_COUNT:-0}"
echo "  • LOB Columns: ${LOB_COUNT:-0}"
echo ""
log_info "Connection Examples:"
echo -e "  ${CYAN}sql pm/<password>@//${DB_HOST}:${DB_PORT}/${PDB_NAME}${NC}"
echo -e "  ${CYAN}sandbox run sqlcl${NC}"
echo ""
log_info "Sample Queries:"
echo -e "  ${CYAN}SELECT product_id, product_name FROM pm.print_media WHERE rownum <= 10;${NC}"
echo -e "  ${CYAN}SELECT table_name, column_name, data_type${NC}"
echo -e "  ${CYAN}FROM user_tab_columns${NC}"
echo -e "  ${CYAN}WHERE data_type LIKE '%LOB%';${NC}"
echo ""

log_success "Ready for PM schema queries! 🚀"
