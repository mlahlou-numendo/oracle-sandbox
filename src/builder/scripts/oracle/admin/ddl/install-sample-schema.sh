#!/bin/bash
################################################################################
# Oracle Sample Schema Generic Installer
# This script runs FROM INSIDE the Docker container
# Installs any Oracle sample schema (HR, OE, PM, SH) into a PDB
#
# USAGE:
#   install-sample-schema.sh <schema_name> <schema_path> [pdb_name]
#
# PARAMETERS:
#   schema_name  (required) - Schema name (hr, oe, pm, sh)
#   schema_path  (required) - Path to schema DDL files
#   pdb_name     (optional) - Target PDB name (defaults to SANDBOX_PDB)
#
# EXAMPLES:
#   install-sample-schema.sh hr /opt/oracle/sample-schemas/hr
#   install-sample-schema.sh oe /opt/oracle/sample-schemas/oe SANDBOX_PDB
################################################################################

set -e

# Get the actual script location (resolves symlinks)
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Source utilities
source "/usr/sandbox/app/system/utils/banner.sh"
source "/usr/sandbox/app/system/utils/logging.sh"
source "/usr/sandbox/app/system/utils/colors.sh"

################################################################################
# PARSE PARAMETERS
################################################################################

if [ $# -lt 2 ]; then
    echo ""
    echo "Usage: $(basename "$0") <schema_name> <schema_path> [pdb_name]"
    echo ""
    echo "  schema_name  (required) Schema name (hr, oe, pm, sh)"
    echo "  schema_path  (required) Path to schema DDL files"
    echo "  pdb_name     (optional) Target PDB name (default: SANDBOX_PDB)"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") hr /opt/oracle/sample-schemas/hr"
    echo "  $(basename "$0") oe /opt/oracle/sample-schemas/oe SANDBOX_PDB"
    echo ""
    exit 1
fi

# Assign parameters
INPUT_SCHEMA="$1"
SCHEMA_PATH="$2"
INPUT_PDB="${3:-}"

# Normalize schema name
SCHEMA_NAME=$(echo "$INPUT_SCHEMA" | tr '[:lower:]' '[:upper:]')
SCHEMA_NAME_LOWER=$(echo "$INPUT_SCHEMA" | tr '[:upper:]' '[:lower:]')

# Validate schema path
if [ ! -d "$SCHEMA_PATH" ]; then
    log_error "Schema path does not exist: $SCHEMA_PATH"
    exit 1
fi

# Count SQL files
SQL_FILE_COUNT=$(find "$SCHEMA_PATH" -name "*.sql" -type f | wc -l)
if [ "$SQL_FILE_COUNT" -eq 0 ]; then
    log_error "No SQL files found in: $SCHEMA_PATH"
    log_info "Run: download-sample-schemas $SCHEMA_NAME_LOWER"
    exit 1
fi

################################################################################
# CONFIGURATION
################################################################################

DB_HOST="${SANDBOX_DB_HOST}"
DB_PORT="${SANDBOX_DB_PORT}"
DB_PASSWORD="${SANDBOX_DB_PASSWORD}"
DB_SID="${SANDBOX_DB_SID}"

# PDB determination (use env var specific to schema, or parameter, or default)
SCHEMA_PDB_VAR="SANDBOX_${SCHEMA_NAME}_SCHEMA_PDB"
PDB_NAME="${!SCHEMA_PDB_VAR:-${INPUT_PDB:-SANDBOX_PDB}}"

# User password (use schema-specific env var or default)
SCHEMA_PASSWORD_VAR="SANDBOX_${SCHEMA_NAME}_SCHEMA_PASSWORD"
SCHEMA_USER_PASSWORD="${!SCHEMA_PASSWORD_VAR:-${DB_PASSWORD}}"

# Validate required environment variables
log_step "Validating environment variables..."
MISSING_VARS=()

[[ -z "$DB_HOST" ]]     && MISSING_VARS+=("SANDBOX_DB_HOST")
[[ -z "$DB_PORT" ]]     && MISSING_VARS+=("SANDBOX_DB_PORT")
[[ -z "$DB_PASSWORD" ]] && MISSING_VARS+=("SANDBOX_DB_PASSWORD")
[[ -z "$DB_SID" ]]      && MISSING_VARS+=("SANDBOX_DB_SID")

if [ ${#MISSING_VARS[@]} -ne 0 ]; then
    log_error "Missing required environment variables:"
    for var in "${MISSING_VARS[@]}"; do
        echo "  ✗ $var"
    done
    exit 1
fi

log_success "All required environment variables present"

# Log file
LOG_FILE="/tmp/install-sample-schema-${SCHEMA_NAME_LOWER}.log"
: > "$LOG_FILE"  # Truncate log file

################################################################################
# STEP 1: Check if user already exists
################################################################################
log_section "Step 1: Checking if user ${SCHEMA_NAME} exists"

USER_EXISTS=$(sql -S system/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << EOF 2>/dev/null | grep -v "^$" | tail -1 | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM dba_users WHERE username = '${SCHEMA_NAME}';
EXIT
EOF
)

if [ "${USER_EXISTS}" = "1" ]; then
    log_warn "User ${SCHEMA_NAME} already exists in PDB ${PDB_NAME}"
    
    # Check if schema has objects
    TABLE_COUNT=$(sql -S system/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << EOF 2>/dev/null | grep -v "^$" | tail -1 | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM dba_tables WHERE owner = '${SCHEMA_NAME}';
EXIT
EOF
    )
    
    if [ "${TABLE_COUNT:-0}" -gt 0 ]; then
        log_info "${SCHEMA_NAME} schema already has ${TABLE_COUNT} tables"
        log_warn "Schema appears to be already installed"
        echo ""
        log_info "If you want to reinstall, first drop the user:"
        echo "  sql system/\${SANDBOX_DB_PASSWORD}@//\${SANDBOX_DB_HOST}:\${SANDBOX_DB_PORT}/${PDB_NAME}"
        echo "  DROP USER ${SCHEMA_NAME} CASCADE;"
        echo ""
        exit 2  # Partial success - user exists
    fi
    
    log_info "User exists but has no tables, proceeding with DDL installation..."
else
    log_info "User ${SCHEMA_NAME} does not exist, creating..."
    
    # Call create-user.sh
    if bash "${SCRIPT_DIR}/create-user.sh" "$SCHEMA_NAME" "$SCHEMA_USER_PASSWORD" "$PDB_NAME"; then
        log_success "User ${SCHEMA_NAME} created successfully"
    else
        log_error "Failed to create user ${SCHEMA_NAME}"
        exit 1
    fi
fi

################################################################################
# STEP 2: Grant privileges
################################################################################
log_section "Step 2: Granting privileges to ${SCHEMA_NAME}"

if bash "${SCRIPT_DIR}/grant-privileges.sh" "$SCHEMA_NAME" "normal" "$PDB_NAME"; then
    log_success "Privileges granted successfully"
else
    log_error "Failed to grant privileges to ${SCHEMA_NAME}"
    exit 1
fi

################################################################################
# STEP 3: Execute DDL scripts
################################################################################
log_section "Step 3: Executing DDL scripts"

log_info "Schema path: $SCHEMA_PATH"
log_info "SQL files: $SQL_FILE_COUNT"
log_info "Target: ${SCHEMA_NAME}@${PDB_NAME}"
log_info "Log file: $LOG_FILE"
echo ""

# Oracle sample schemas use a master script (*_main.sql or *_install.sql) that orchestrates the installation
# The master script calls sub-scripts in the correct order:
# 1. *_main.sql / *_install.sql - Master orchestrator (calls all others)
# 2. *_cre.sql / *_create.sql - Create tables, sequences
# 3. *_code.sql - Create procedures, triggers
# 4. *_populate.sql / *_pop.sql - Insert data (THIS POPULATES THE TABLES!)
# 5. *_idx.sql - Create indexes
# 6. *_analz.sql - Analyze tables
# 
# We prioritize the main script, but fall back to ordered execution if it doesn't exist

# Check for master main/install script first (GitHub uses *_install.sql, Oracle docs use *_main.sql)
# NOTE: Master scripts (*_main.sql) are designed for interactive SQL*Plus sessions with user switching
# They contain CONNECT statements and expect specific working directories
# For container automation, we skip them and use individual script execution instead
MAIN_SCRIPT=$(find "$SCHEMA_PATH" -name "*_main.sql" -o -name "*_install.sql" -type f 2>/dev/null | head -1)

if [ -n "$MAIN_SCRIPT" ]; then
    log_info "Found master script: $(basename "$MAIN_SCRIPT")"
    log_info "Skipping master script (designed for interactive sessions)"
    log_info "Using individual script execution for container automation"
    MAIN_SCRIPT=""  # Clear to trigger fallback
fi

# Fallback: Execute individual scripts in order if no main script or it failed
if [ -z "$MAIN_SCRIPT" ]; then
    log_info "Using individual script execution mode"
    echo ""
    
    # Build ordered list of SQL files per Oracle's documented execution order:
    # 1. Create tables/sequences (c*_v3.sql for v3 scripts, or *_create.sql)
    # 2. Populate data (p*_v3.sql for v3 scripts, or *_populate.sql) ← MUST come before procedures/triggers!
    # 3. Create indexes (cidx_v3.sql or *_idx.sql)
    # 4. Create procedures/triggers (*_code.sql)
    # 5. Analyze tables (*_analz.sql)
    # 6. Add comments (*_comnt.sql or cmnt_v3.sql)
    # 7. Drop scripts (*_drop.sql or doe_v3.sql) - usually for cleanup examples
    # 8. Everything else (*.sql)
    #
    # Special handling: 
    # - v3 scripts (c*_v3.sql, p*_v3.sql) are preferred for automation (no variable dependencies)
    # - oe_*.sql must run before oc_*.sql in OE schema (oc = Online Catalog views depend on oe base tables)
    SQL_FILES=""
    for pattern in "c*_v3.sql" "*_create.sql" "p*_v3.sql" "*_populate.sql" "cidx_v3.sql" "*_idx.sql" "*_code.sql" "*_analz.sql" "*_comnt.sql" "*_drop.sql" "*.sql"; do
        found_files=$(find "$SCHEMA_PATH" -name "$pattern" -type f 2>/dev/null | sort)
        if [ -n "$found_files" ]; then
            # Avoid duplicates and handle special exclusions
            if [ "$pattern" = "*.sql" ]; then
                # Only add files not already in the list, skip master/uninstall scripts
                while IFS= read -r file; do
                    filename=$(basename "$file")
                    # Skip master install/uninstall scripts and known problematic scripts
                    [[ "$filename" =~ _install\.sql$|_uninstall\.sql$|_main\.sql$|oe_cre\.sql$|oc_main\.sql$ ]] && continue
                    if ! echo "$SQL_FILES" | grep -q "$filename"; then
                        SQL_FILES="${SQL_FILES}${file}"$'\n'
                    fi
                done <<< "$found_files"
            else
                # Add files from specific patterns, avoiding duplicates
                while IFS= read -r file; do
                    filename=$(basename "$file")
                    # Skip problematic scripts that have variable dependencies
                    [[ "$filename" =~ oe_cre\.sql$|oc_main\.sql$ ]] && continue
                    if ! echo "$SQL_FILES" | grep -q "$filename"; then
                        SQL_FILES="${SQL_FILES}${file}"$'\n'
                    fi
                done <<< "$found_files"
            fi
        fi
    done

    # Remove trailing newline and check if we have files
    SQL_FILES=$(echo "$SQL_FILES" | sed '/^$/d')

    if [ -z "$SQL_FILES" ]; then
        log_error "No SQL files found in $SCHEMA_PATH"
        exit 1
    fi

    EXECUTED_COUNT=0
    FAILED_COUNT=0

    # Execute each SQL file in order
    while IFS= read -r sql_file; do
        [ -z "$sql_file" ] && continue
        file_name=$(basename "$sql_file")
        log_step "Executing: $file_name"
        
        # Execute as the schema user
        if sql -S ${SCHEMA_NAME}/${SCHEMA_USER_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << EOF >> "$LOG_FILE" 2>&1
SET ECHO OFF
SET FEEDBACK OFF
SET HEADING OFF
@${sql_file}
EXIT
EOF
        then
            log_success "  ✓ $file_name"
            ((EXECUTED_COUNT++)) || true  # Avoid set -e exit when count is 0
        else
            EXIT_CODE=$?
            log_error "  ✗ $file_name (exit code: $EXIT_CODE, check $LOG_FILE)"
            ((FAILED_COUNT++)) || true  # Avoid set -e exit when count is 0
        fi
    done <<< "$SQL_FILES"

    echo ""
    log_info "Execution summary:"
    echo "  • Executed: $EXECUTED_COUNT"
    echo "  • Failed: $FAILED_COUNT"
    echo "  • Total: $SQL_FILE_COUNT"

    if [ $FAILED_COUNT -gt 0 ]; then
        log_warn "Some SQL files failed to execute"
        log_info "Check log file: $LOG_FILE"
        echo ""
    fi
fi  # End of fallback if-block

echo ""

################################################################################
# STEP 4: Validation
################################################################################
log_section "Step 4: Validation"

# Count tables
TABLE_COUNT=$(sql -S system/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << EOF 2>/dev/null | grep -v "^$" | tail -1 | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM dba_tables WHERE owner = '${SCHEMA_NAME}';
EXIT
EOF
)

# Count views
VIEW_COUNT=$(sql -S system/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << EOF 2>/dev/null | grep -v "^$" | tail -1 | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM dba_views WHERE owner = '${SCHEMA_NAME}';
EXIT
EOF
)

# Count indexes
INDEX_COUNT=$(sql -S system/${DB_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << EOF 2>/dev/null | grep -v "^$" | tail -1 | tr -d '[:space:]'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM dba_indexes WHERE owner = '${SCHEMA_NAME}';
EXIT
EOF
)

log_info "Database objects created:"
echo "  • Tables: ${TABLE_COUNT:-0}"
echo "  • Views: ${VIEW_COUNT:-0}"
echo "  • Indexes: ${INDEX_COUNT:-0}"
echo ""

if [ "${TABLE_COUNT:-0}" -eq 0 ]; then
    log_error "No tables created - installation may have failed"
    log_info "Check log file: $LOG_FILE"
    exit 1
fi

# Test connection as schema user
log_step "Testing connection as ${SCHEMA_NAME}..."
TEST_QUERY=$(sql -S ${SCHEMA_NAME}/${SCHEMA_USER_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} << 'EOF' 2>&1
SET HEADING OFF FEEDBACK OFF
SELECT 'Connection OK' FROM DUAL;
EXIT
EOF
)

if echo "$TEST_QUERY" | grep -q "Connection OK"; then
    log_success "Connection test successful"
else
    log_warn "Connection test failed: $TEST_QUERY"
fi

################################################################################
# COMPLETION SUMMARY
################################################################################
log_section "Installation Complete!"
log_success "${SCHEMA_NAME} sample schema installed successfully in PDB ${PDB_NAME}"

echo ""
log_info "Connection Details:"
echo "  • User: ${SCHEMA_NAME}"
echo "  • PDB: ${PDB_NAME}"
echo "  • Host: ${DB_HOST}:${DB_PORT}"
echo ""
log_info "Connect to schema:"
echo "  ${CYAN}sql ${SCHEMA_NAME}/${SCHEMA_USER_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME}${NC}"
echo ""

exit 0
