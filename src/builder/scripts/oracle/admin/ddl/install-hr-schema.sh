#!/bin/bash
################################################################################
# Oracle HR Sample Schema Installer
# This script runs FROM INSIDE the Docker container
# Installs the HR (Human Resources) sample schema
#
# USAGE:
#   install-hr-schema.sh [pdb_name]
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

print_demasy_banner "Oracle HR Sample Schema Installation"

echo ""
log_info "Installing HR (Human Resources) sample schema"
log_info "Expected: 7 tables, ~107 employees"
echo ""

# Configuration
DB_HOST="${SANDBOX_DB_HOST}"
DB_PORT="${SANDBOX_DB_PORT}"
DB_PASSWORD="${SANDBOX_DB_PASSWORD}"
PDB_NAME="${1:-${SANDBOX_HR_SCHEMA_PDB:-SANDBOX_PDB}}"
SCHEMA_PATH="/opt/oracle/sample-schemas/hr"

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
# STEP 2: Download HR schema files
################################################################################
log_section "Step 2: Download HR Schema Files"

if [ ! -d "$SCHEMA_PATH" ] || [ -z "$(ls -A "$SCHEMA_PATH" 2>/dev/null)" ]; then
    log_info "HR schema files not found, downloading..."
    if bash /usr/sandbox/app/download/download-sample-schemas.sh hr; then
        log_success "HR schema files downloaded"
    else
        log_error "Failed to download HR schema files"
        exit 1
    fi
else
    log_success "HR schema files already available"
    log_info "Location: $SCHEMA_PATH"
fi

################################################################################
# STEP 3: Install schema
################################################################################
log_section "Step 3: Install HR Schema"

if bash "${SCRIPT_DIR}/install-sample-schema.sh" hr "$SCHEMA_PATH" "$PDB_NAME"; then
    log_success "HR schema installation completed"
else
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 2 ]; then
        log_warn "HR schema already installed"
    else
        log_error "HR schema installation failed"
        exit 1
    fi
fi

################################################################################
# STEP 4: Post-Install Verification
################################################################################
log_section "Step 4: Post-Install Verification"

# Expected tables
EXPECTED_TABLES=("EMPLOYEES" "DEPARTMENTS" "JOBS" "JOB_HISTORY" "LOCATIONS" "COUNTRIES" "REGIONS")

log_step "Verifying HR schema tables..."

# Count tables
TABLE_COUNT=$(sql -S system/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << 'EOF' 2>/dev/null | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM dba_tables WHERE owner = 'HR';
EXIT
EOF
)

log_info "Total tables: ${TABLE_COUNT:-0} (expected: 7)"

if [ "${TABLE_COUNT:-0}" -ge 7 ]; then
    log_success "✓ Table count verified"
else
    log_warn "⚠ Expected 7 tables, found ${TABLE_COUNT:-0}"
fi

# Verify key table and row count
log_step "Verifying EMPLOYEES table..."

EMPLOYEE_COUNT=$(sql -S hr/${SANDBOX_HR_SCHEMA_PASSWORD:-${DB_PASSWORD}}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << 'EOF' 2>/dev/null | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM employees;
EXIT
EOF
)

log_info "Employees: ${EMPLOYEE_COUNT:-0} rows (expected: ~107)"

if [ "${EMPLOYEE_COUNT:-0}" -gt 0 ]; then
    log_success "✓ EMPLOYEES table populated"
else
    log_warn "⚠ EMPLOYEES table may be empty"
fi

# List all tables
log_step "HR schema tables:"
sql -S system/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << 'EOF'
SET PAGESIZE 100
SET FEEDBACK OFF
COL table_name FORMAT A30
COL num_rows FORMAT 999,999
SELECT table_name, num_rows
FROM dba_tables
WHERE owner = 'HR'
ORDER BY table_name;
EXIT
EOF

################################################################################
# COMPLETION SUMMARY
################################################################################
log_section "Installation Complete!"
log_success "HR (Human Resources) sample schema installed successfully"

echo ""
log_info "Schema Information:"
echo "  • Schema: HR"
echo "  • PDB: $PDB_NAME"
echo "  • Tables: ${TABLE_COUNT:-0}"
echo "  • Employees: ${EMPLOYEE_COUNT:-0}"
echo ""
log_info "Connection Examples:"
echo -e "  ${CYAN}sql hr/<password>@//${DB_HOST}:${DB_PORT}/${PDB_NAME}${NC}"
echo -e "  ${CYAN}sandbox run sqlcl${NC}"
echo ""
log_info "Sample Queries:"
echo -e "  ${CYAN}SELECT * FROM hr.employees WHERE rownum <= 10;${NC}"
echo -e "  ${CYAN}SELECT d.department_name, COUNT(e.employee_id) as emp_count${NC}"
echo -e "  ${CYAN}FROM hr.departments d LEFT JOIN hr.employees e ON d.department_id = e.department_id${NC}"
echo -e "  ${CYAN}GROUP BY d.department_name ORDER BY emp_count DESC;${NC}"
echo ""

log_success "Ready for HR schema queries! 🚀"
