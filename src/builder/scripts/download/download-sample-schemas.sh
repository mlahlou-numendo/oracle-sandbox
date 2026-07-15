#!/bin/bash
# ============================================
# Oracle Sample Schemas Downloader
# ============================================
# Downloads Oracle sample schemas (HR, OE, PM, SH) from Oracle documentation
# Usage: download-sample-schemas.sh [schema_name]
#   schema_name (optional): hr, oe, pm, sh - downloads specific schema
#                           If omitted, downloads all schemas
# ============================================

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "/usr/sandbox/app/system/utils/colors.sh"
source "/usr/sandbox/app/system/utils/logging.sh"
source "/usr/sandbox/app/system/utils/banner.sh"

print_demasy_banner "Oracle Sample Schemas Downloader"

echo ""

# Parse parameters
SCHEMA_FILTER="${1:-all}"
SCHEMA_FILTER=$(echo "$SCHEMA_FILTER" | tr '[:upper:]' '[:lower:]')

# Validate schema name if provided
if [[ "$SCHEMA_FILTER" != "all" && "$SCHEMA_FILTER" != "hr" && "$SCHEMA_FILTER" != "oe" && "$SCHEMA_FILTER" != "pm" && "$SCHEMA_FILTER" != "sh" ]]; then
    log_error "Invalid schema name: $SCHEMA_FILTER"
    echo ""
    log_info "Valid options: hr, oe, pm, sh, all"
    echo ""
    exit 1
fi

# Check if Instant Client is installed (required dependency)
if [ ! -d "/opt/oracle/instantclient" ] || [ -z "$(ls -A /opt/oracle/instantclient 2>/dev/null)" ]; then
    log_error "Oracle Instant Client is not installed"
    log_error "Sample schemas require Oracle Instant Client to be installed first"
    echo ""
    log_info "Please run: ${BOLD}${CYAN}install-client${RESET}"
    echo ""
    exit 1
fi

# Schema definitions - Using Oracle's official GitHub repository
# Source: https://github.com/oracle-samples/db-sample-schemas/releases
# Using tagged releases for stable, versioned schemas with data population scripts
SCHEMA_SOURCE_URL="${SANDBOX_SRC_ORACLE_SAMPLE_SCHEMAS:-https://github.com/oracle-samples/db-sample-schemas/archive/refs/tags/v23.3.tar.gz}"

declare -A SCHEMA_URLS=(
    ["hr"]="$SCHEMA_SOURCE_URL"
    ["oe"]="$SCHEMA_SOURCE_URL"
    ["pm"]="$SCHEMA_SOURCE_URL"
    ["sh"]="$SCHEMA_SOURCE_URL"
)

declare -A SCHEMA_NAMES=(
    ["hr"]="HR (Human Resources)"
    ["oe"]="OE (Order Entry)"
    ["pm"]="PM (Product Media)"
    ["sh"]="SH (Sales History)"
)

declare -A SCHEMA_TABLES=(
    ["hr"]="7 tables"
    ["oe"]="12 tables"
    ["pm"]="2 tables (with LOBs)"
    ["sh"]="10+ tables (star schema)"
)

# Determine which schemas to download
SCHEMAS_TO_DOWNLOAD=()
if [[ "$SCHEMA_FILTER" == "all" ]]; then
    SCHEMAS_TO_DOWNLOAD=("hr" "oe" "pm" "sh")
    log_info "Downloading all Oracle sample schemas"
else
    SCHEMAS_TO_DOWNLOAD=("$SCHEMA_FILTER")
    log_info "Downloading ${SCHEMA_NAMES[$SCHEMA_FILTER]} schema"
fi

echo ""
log_warn "By downloading, you accept Oracle's license terms"
echo ""

# Track download results
SUCCEEDED=()
FAILED=()
SKIPPED=()

# Download function
download_schema() {
    local schema="$1"
    local schema_upper=$(echo "$schema" | tr '[:lower:]' '[:upper:]')
    local schema_name="${SCHEMA_NAMES[$schema]}"
    local schema_url="${SCHEMA_URLS[$schema]}"
    local target_dir="/opt/oracle/sample-schemas/${schema}"
    
    log_step "[$schema_upper] ${schema_name}"
    
    # Check if already installed
    if [ -d "$target_dir" ] && [ -n "$(ls -A "$target_dir" 2>/dev/null)" ]; then
        log_success "[$schema_upper] Already installed at: $target_dir"
        log_info "[$schema_upper] ${SCHEMA_TABLES[$schema]} available"
        SKIPPED+=("$schema")
        return 0
    fi
    
    log_info "[$schema_upper] Downloading from: GitHub (oracle-samples/db-sample-schemas)"
    log_info "[$schema_upper] URL: $schema_url"
    
    # Map schema names to GitHub directory names
    local schema_dir_map
    case "$schema" in
        hr) schema_dir_map="human_resources" ;;
        oe) schema_dir_map="order_entry" ;;
        pm) schema_dir_map="product_media" ;;
        sh) schema_dir_map="sales_history" ;;
    esac
    
    # Download GitHub release once and reuse (all schemas use same tar.gz)
    local temp_file="/tmp/oracle_sample_schemas.tar.gz"
    if [ ! -f "$temp_file" ]; then
        if ! curl -L --retry 3 --retry-delay 2 -o "$temp_file" "$schema_url" 2>/dev/null; then
            log_error "[$schema_upper] Download failed"
            log_info "[$schema_upper] Please check your internet connection and try again"
            rm -f "$temp_file"
            FAILED+=("$schema")
            return 1
        fi
    fi
    
    log_step "[$schema_upper] Extracting..."
    
    # Create target directory
    mkdir -p "$target_dir"
    
    # Extract and find the schema directory (handles different version formats)
    # GitHub archive structure: db-sample-schemas-{version}/{human_resources,order_entry,product_media,sales_history}/
    tar -xzf "$temp_file" -C /tmp/ 2>/dev/null || {
        log_error "[$schema_upper] Extraction failed"
        rm -rf /tmp/db-sample-schemas-*
        FAILED+=("$schema")
        return 1
    }
    
    # Find the extracted directory (version-agnostic)
    local extracted_dir=$(find /tmp -maxdepth 1 -type d -name "db-sample-schemas-*" 2>/dev/null | head -n 1)
    
    if [ -z "$extracted_dir" ] || [ ! -d "$extracted_dir/${schema_dir_map}" ]; then
        log_error "[$schema_upper] Schema directory not found in archive"
        rm -rf /tmp/db-sample-schemas-*
        FAILED+=("$schema")
        return 1
    fi
    
    # Move schema files to target directory
    mv "$extracted_dir/${schema_dir_map}"/* "$target_dir/" 2>/dev/null || true
    
    # Clean up extraction temp dir
    rm -rf /tmp/db-sample-schemas-*
    
    # Verify extraction
    local file_count=$(find "$target_dir" -name "*.sql" -type f | wc -l)
    if [ "$file_count" -gt 0 ]; then
        log_success "[$schema_upper] Installed successfully!"
        log_info "[$schema_upper] Location: $target_dir"
        log_info "[$schema_upper] SQL files: $file_count"
        log_info "[$schema_upper] Expected: ${SCHEMA_TABLES[$schema]}"
        SUCCEEDED+=("$schema")
        return 0
    else
        log_error "[$schema_upper] No SQL files found after extraction"
        rm -rf "$target_dir"
        FAILED+=("$schema")
        return 1
    fi
}

# Download schemas
for schema in "${SCHEMAS_TO_DOWNLOAD[@]}"; do
    download_schema "$schema"
    echo ""
done

# Clean up the shared tar.gz file
if [ -f "/tmp/oracle_sample_schemas.tar.gz" ]; then
    rm -f /tmp/oracle_sample_schemas.tar.gz
fi

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ ${#SUCCEEDED[@]} -gt 0 ]; then
    log_success "Successfully downloaded ${#SUCCEEDED[@]} schema(s):"
    for schema in "${SUCCEEDED[@]}"; do
        echo "  ✓ ${SCHEMA_NAMES[$schema]}"
    done
    echo ""
fi

if [ ${#SKIPPED[@]} -gt 0 ]; then
    log_info "${#SKIPPED[@]} schema(s) already installed:"
    for schema in "${SKIPPED[@]}"; do
        echo "  ⊙ ${SCHEMA_NAMES[$schema]}"
    done
    echo ""
fi

if [ ${#FAILED[@]} -gt 0 ]; then
    log_error "${#FAILED[@]} schema(s) failed to download:"
    for schema in "${FAILED[@]}"; do
        echo "  ✗ ${SCHEMA_NAMES[$schema]}"
    done
    echo ""
    log_info "You can retry individual schemas:"
    for schema in "${FAILED[@]}"; do
        echo "  ${CYAN}download-sample-schemas $schema${NC}"
    done
    echo ""
    exit 1
fi

log_info "Installation location: /opt/oracle/sample-schemas/"
echo ""
log_info "Next steps:"
echo "  1. Install schema into database: ${BOLD}${CYAN}sandbox install schema --name <schema>${NC}"
echo "  2. Available schemas: hr, oe, pm, sh"
echo ""
log_info "Examples:"
echo "  ${CYAN}sandbox install schema --name hr${NC}  # Human Resources"
echo "  ${CYAN}sandbox install schema --name oe${NC}  # Order Entry"
echo "  ${CYAN}sandbox install schema --name pm${NC}  # Product Media"
echo "  ${CYAN}sandbox install schema --name sh${NC}  # Sales History"
echo ""

exit 0
