#!/bin/bash
################################################################################
# Oracle OE Sample Schema Installer
# This script runs FROM INSIDE the Docker container
# Installs the OE (Order Entry) sample schema
#
# NOTE: OE schema has dependencies on HR schema (foreign key references)
#       If HR is not installed, the installer will prompt to install it first
#
# USAGE:
#   install-oe-schema.sh [pdb_name]
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

print_demasy_banner "Oracle OE Sample Schema Installation"

echo ""
log_info "Installing OE (Order Entry) sample schema"
log_info "Expected: 12 tables, ~319 customers"
echo ""

# Configuration
DB_HOST="${SANDBOX_DB_HOST}"
DB_PORT="${SANDBOX_DB_PORT}"
DB_PASSWORD="${SANDBOX_DB_PASSWORD}"
PDB_NAME="${1:-${SANDBOX_OE_SCHEMA_PDB:-SANDBOX_PDB}}"
SCHEMA_PATH="/opt/oracle/sample-schemas/oe"

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
# STEP 1.5: Check HR Schema Dependency
################################################################################
log_section "Step 1.5: Checking HR Schema Dependency"

log_info "OE schema has foreign key references to HR schema"
log_step "Checking if HR schema exists..."

HR_EXISTS=$(sql -S system/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << 'EOF' 2>/dev/null | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM dba_users WHERE username = 'HR';
EXIT
EOF
)

if [ "${HR_EXISTS}" = "1" ]; then
    log_success "✓ HR schema exists"
    
    # Check if HR has tables
    HR_TABLE_COUNT=$(sql -S system/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << 'EOF' 2>/dev/null | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM dba_tables WHERE owner = 'HR';
EXIT
EOF
    )
    
    if [ "${HR_TABLE_COUNT:-0}" -ge 7 ]; then
        log_success "✓ HR schema populated with ${HR_TABLE_COUNT} tables"
    else
        log_warn "⚠ HR schema exists but may not be fully populated"
        log_warn "  Expected: 7 tables, Found: ${HR_TABLE_COUNT:-0}"
        log_info "Consider reinstalling HR schema if OE installation fails"
    fi
else
    log_warn "⚠ HR schema not found"
    log_warn "OE schema requires HR schema for foreign key references"
    echo ""
    log_info "To install HR schema first:"
    echo "  ${CYAN}sandbox install schema --name hr${NC}"
    echo ""
    read -p "Do you want to continue anyway? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled"
        exit 0
    fi
    log_warn "Continuing without HR schema - some constraints may fail"
fi

echo ""

################################################################################
# STEP 2: Download OE schema files
################################################################################
log_section "Step 2: Download OE Schema Files"

if [ ! -d "$SCHEMA_PATH" ] || [ -z "$(ls -A "$SCHEMA_PATH" 2>/dev/null)" ]; then
    log_info "OE schema files not found, downloading..."
    if bash /usr/sandbox/app/download/download-sample-schemas.sh oe; then
        log_success "OE schema files downloaded"
    else
        log_error "Failed to download OE schema files"
        exit 1
    fi
else
    log_success "OE schema files already available"
    log_info "Location: $SCHEMA_PATH"
fi

################################################################################
# STEP 3: Install schema
################################################################################
log_section "Step 3: Install OE Schema"

if bash "${SCRIPT_DIR}/install-sample-schema.sh" oe "$SCHEMA_PATH" "$PDB_NAME"; then
    log_success "OE schema installation completed"
else
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 2 ]; then
        log_warn "OE schema already installed"
    else
        log_error "OE schema installation failed"
        exit 1
    fi
fi

################################################################################
# STEP 4: Post-Install Verification
################################################################################
log_section "Step 4: Post-Install Verification"

# Expected tables
EXPECTED_TABLES=("CUSTOMERS" "ORDERS" "ORDER_ITEMS" "PRODUCT_INFORMATION" "INVENTORIES" "WAREHOUSES" "PRODUCT_DESCRIPTIONS" "PROMOTIONS")

log_step "Verifying OE schema tables..."

# Count tables
TABLE_COUNT=$(sql -S system/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << 'EOF' 2>/dev/null | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM dba_tables WHERE owner = 'OE';
EXIT
EOF
)

log_info "Total tables: ${TABLE_COUNT:-0} (expected: 12)"

if [ "${TABLE_COUNT:-0}" -ge 12 ]; then
    log_success "✓ Table count verified"
else
    log_warn "⚠ Expected 12 tables, found ${TABLE_COUNT:-0}"
fi

# Verify key table and row count
log_step "Verifying CUSTOMERS table..."

CUSTOMER_COUNT=$(sql -S oe/${SANDBOX_OE_SCHEMA_PASSWORD:-${DB_PASSWORD}}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << 'EOF' 2>/dev/null | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM customers;
EXIT
EOF
)

log_info "Customers: ${CUSTOMER_COUNT:-0} rows (expected: ~319)"

if [ "${CUSTOMER_COUNT:-0}" -gt 0 ]; then
    log_success "✓ CUSTOMERS table populated"
else
    log_warn "⚠ CUSTOMERS table may be empty"
fi

# Verify foreign key to HR schema
if [ "${HR_EXISTS}" = "1" ]; then
    log_step "Verifying HR-OE relationships..."
    
    FK_COUNT=$(sql -S system/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << 'EOF' 2>/dev/null | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) 
FROM dba_constraints 
WHERE owner = 'OE' 
  AND constraint_type = 'R'
  AND r_owner = 'HR';
EXIT
EOF
    )
    
    if [ "${FK_COUNT:-0}" -gt 0 ]; then
        log_success "✓ Foreign keys to HR schema: ${FK_COUNT}"
    else
        log_info "No foreign keys to HR schema found"
    fi
fi

# List all tables
log_step "OE schema tables:"
sql -S system/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << 'EOF'
SET PAGESIZE 100
SET FEEDBACK OFF
COL table_name FORMAT A30
COL num_rows FORMAT 999,999
SELECT table_name, num_rows
FROM dba_tables
WHERE owner = 'OE'
ORDER BY table_name;
EXIT
EOF

################################################################################
# COMPLETION SUMMARY
################################################################################
log_section "Installation Complete!"
log_success "OE (Order Entry) sample schema installed successfully"

echo ""
log_info "Schema Information:"
echo "  • Schema: OE"
echo "  • PDB: $PDB_NAME"
echo "  • Tables: ${TABLE_COUNT:-0}"
echo "  • Customers: ${CUSTOMER_COUNT:-0}"
if [ "${HR_EXISTS}" = "1" ]; then
    echo "  • HR Dependencies: ${FK_COUNT:-0} foreign keys"
fi
echo ""
log_info "Connection Examples:"
echo -e "  ${CYAN}sql oe/<password>@//${DB_HOST}:${DB_PORT}/${PDB_NAME}${NC}"
echo -e "  ${CYAN}sandbox run sqlcl${NC}"
echo ""
log_info "Sample Queries:"
echo -e "  ${CYAN}SELECT * FROM oe.customers WHERE rownum <= 10;${NC}"
echo -e "  ${CYAN}SELECT c.customer_id, c.cust_first_name, c.cust_last_name, COUNT(o.order_id) as order_count${NC}"
echo -e "  ${CYAN}FROM oe.customers c LEFT JOIN oe.orders o ON c.customer_id = o.customer_id${NC}"
echo -e "  ${CYAN}GROUP BY c.customer_id, c.cust_first_name, c.cust_last_name${NC}"
echo -e "  ${CYAN}ORDER BY order_count DESC FETCH FIRST 10 ROWS ONLY;${NC}"
echo ""

log_success "Ready for OE schema queries! 🚀"
