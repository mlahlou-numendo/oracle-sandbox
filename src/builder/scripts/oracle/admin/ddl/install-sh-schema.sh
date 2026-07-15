#!/bin/bash
################################################################################
# Oracle SH Sample Schema Installer
# This script runs FROM INSIDE the Docker container
# Installs the SH (Sales History) sample schema
#
# USAGE:
#   install-sh-schema.sh [pdb_name]
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

print_demasy_banner "Oracle SH Sample Schema Installation"

echo ""
log_info "Installing SH (Sales History) sample schema"
log_info "Expected: 10+ tables (star schema), ~55,500 sales records"
echo ""

# Configuration
DB_HOST="${SANDBOX_DB_HOST}"
DB_PORT="${SANDBOX_DB_PORT}"
DB_PASSWORD="${SANDBOX_DB_PASSWORD}"
PDB_NAME="${1:-${SANDBOX_SH_SCHEMA_PDB:-SANDBOX_PDB}}"
SCHEMA_PATH="/opt/oracle/sample-schemas/sh"

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
# STEP 2: Download SH schema files
################################################################################
log_section "Step 2: Download SH Schema Files"

if [ ! -d "$SCHEMA_PATH" ] || [ -z "$(ls -A "$SCHEMA_PATH" 2>/dev/null)" ]; then
    log_info "SH schema files not found, downloading..."
    if bash /usr/sandbox/app/download/download-sample-schemas.sh sh; then
        log_success "SH schema files downloaded"
    else
        log_error "Failed to download SH schema files"
        exit 1
    fi
else
    log_success "SH schema files already available"
    log_info "Location: $SCHEMA_PATH"
fi

################################################################################
# STEP 3: Install schema
################################################################################
log_section "Step 3: Install SH Schema"

if bash "${SCRIPT_DIR}/install-sample-schema.sh" sh "$SCHEMA_PATH" "$PDB_NAME"; then
    log_success "SH schema installation completed"
else
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 2 ]; then
        log_warn "SH schema already installed"
    else
        log_error "SH schema installation failed"
        exit 1
    fi
fi

################################################################################
# STEP 4: Post-Install Verification
################################################################################
log_section "Step 4: Post-Install Verification"

# Expected tables (star schema pattern)
EXPECTED_TABLES=("SALES" "COSTS" "CUSTOMERS" "PRODUCTS" "CHANNELS" "PROMOTIONS" "COUNTRIES" "TIMES" "SUPPLEMENTARY_DEMOGRAPHICS" "CALENDAR_MONTH_DESC")

log_step "Verifying SH schema tables..."

# Count tables
TABLE_COUNT=$(sql -S system/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << 'EOF' 2>/dev/null | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM dba_tables WHERE owner = 'SH';
EXIT
EOF
)

log_info "Total tables: ${TABLE_COUNT:-0} (expected: 10+)"

if [ "${TABLE_COUNT:-0}" -ge 10 ]; then
    log_success "✓ Table count verified"
else
    log_warn "⚠ Expected 10+ tables, found ${TABLE_COUNT:-0}"
fi

# Verify SALES table (fact table)
log_step "Verifying SALES fact table..."

SALES_COUNT=$(sql -S sh/${SANDBOX_SH_SCHEMA_PASSWORD:-${DB_PASSWORD}}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << 'EOF' 2>/dev/null | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM sales;
EXIT
EOF
)

log_info "Sales records: ${SALES_COUNT:-0} (expected: ~55,500)"

if [ "${SALES_COUNT:-0}" -gt 0 ]; then
    log_success "✓ SALES table populated"
else
    log_warn "⚠ SALES table may be empty"
fi

# Check for dimension tables
log_step "Verifying dimension tables..."

DIMENSION_COUNT=$(sql -S system/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << 'EOF' 2>/dev/null | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) 
FROM dba_tables 
WHERE owner = 'SH' 
  AND table_name IN ('CUSTOMERS', 'PRODUCTS', 'CHANNELS', 'PROMOTIONS', 'TIMES');
EXIT
EOF
)

log_info "Dimension tables: ${DIMENSION_COUNT:-0} / 5"

if [ "${DIMENSION_COUNT:-0}" -eq 5 ]; then
    log_success "✓ All dimension tables present"
else
    log_warn "⚠ Missing dimension tables (found ${DIMENSION_COUNT:-0} / 5)"
fi

# List all tables with row counts
log_step "SH schema tables (star schema):"
sql -S system/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << 'EOF'
SET PAGESIZE 100
SET FEEDBACK OFF
COL table_name FORMAT A30
COL num_rows FORMAT 999,999,999
COL table_type FORMAT A15
SELECT t.table_name, t.num_rows,
       CASE 
           WHEN t.table_name IN ('SALES', 'COSTS') THEN 'Fact Table'
           WHEN t.table_name IN ('CUSTOMERS', 'PRODUCTS', 'CHANNELS', 'PROMOTIONS', 'TIMES', 'COUNTRIES') THEN 'Dimension'
           ELSE 'Other'
       END as table_type
FROM dba_tables t
WHERE t.owner = 'SH'
ORDER BY 
    CASE 
        WHEN t.table_name IN ('SALES', 'COSTS') THEN 1
        WHEN t.table_name IN ('CUSTOMERS', 'PRODUCTS', 'CHANNELS', 'PROMOTIONS', 'TIMES', 'COUNTRIES') THEN 2
        ELSE 3
    END,
    t.table_name;
EXIT
EOF

################################################################################
# COMPLETION SUMMARY
################################################################################
log_section "Installation Complete!"
log_success "SH (Sales History) sample schema installed successfully"

echo ""
log_info "Schema Information:"
echo "  • Schema: SH"
echo "  • PDB: $PDB_NAME"
echo "  • Tables: ${TABLE_COUNT:-0}"
echo "  • Sales Records: ${SALES_COUNT:-0}"
echo "  • Dimension Tables: ${DIMENSION_COUNT:-0} / 5"
echo "  • Schema Type: Star Schema (for data warehousing)"
echo ""
log_info "Connection Examples:"
echo -e "  ${CYAN}sql sh/<password>@//${DB_HOST}:${DB_PORT}/${PDB_NAME}${NC}"
echo -e "  ${CYAN}sandbox run sqlcl${NC}"
echo ""
log_info "Sample Queries (Data Warehouse Analytics):"
echo -e "  ${CYAN}-- Sales by product${NC}"
echo -e "  ${CYAN}SELECT p.prod_name, SUM(s.amount_sold) as total_sales${NC}"
echo -e "  ${CYAN}FROM sh.sales s JOIN sh.products p ON s.prod_id = p.prod_id${NC}"
echo -e "  ${CYAN}GROUP BY p.prod_name ORDER BY total_sales DESC FETCH FIRST 10 ROWS ONLY;${NC}"
echo ""
echo -e "  ${CYAN}-- Sales by channel and quarter${NC}"
echo -e "  ${CYAN}SELECT c.channel_desc, t.calendar_quarter_desc, SUM(s.amount_sold) as revenue${NC}"
echo -e "  ${CYAN}FROM sh.sales s${NC}"
echo -e "  ${CYAN}JOIN sh.channels c ON s.channel_id = c.channel_id${NC}"
echo -e "  ${CYAN}JOIN sh.times t ON s.time_id = t.time_id${NC}"
echo -e "  ${CYAN}GROUP BY c.channel_desc, t.calendar_quarter_desc${NC}"
echo -e "  ${CYAN}ORDER BY revenue DESC;${NC}"
echo ""

log_success "Ready for SH schema data warehouse queries! 🚀"
