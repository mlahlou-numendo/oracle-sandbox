# ─── sandbox install ──────────────────────────────────────────────────────────
# Sourced by sandbox.sh — handles: sandbox install <resource>
# Variables inherited: ACTION, RESOURCE, PARAMS, logging/color functions
# Dependencies: sandbox-params.sh
# ─────────────────────────────────────────────────────────────────────────────

case "$RESOURCE" in
    apex)
        _if_dry_run "Would run: bash /usr/sandbox/app/oracle/apex/install.sh" && exit 0
        log_step "Installing APEX + ORDS..."
        bash /usr/sandbox/app/oracle/apex/install.sh
        ;;
    
    schema)
        # Parse --name parameter for schema selection
        SCHEMA_NAME=$(_parse_param_value "--name" $PARAMS)
        
        if [ -z "$SCHEMA_NAME" ]; then
            log_error "Schema name is required"
            echo ""
            echo "Usage: sandbox install schema --name <schema>"
            echo ""
            echo "Available schemas:"
            echo "  hr  - Human Resources (7 tables, ~107 employees)"
            echo "  oe  - Order Entry (12 tables, ~319 customers)"
            echo "  pm  - Product Media (2 tables with LOBs, ~288 media)"
            echo "  sh  - Sales History (10+ tables, ~55,500 sales)"
            echo ""
            echo "Example:"
            echo "  sandbox install schema --name hr"
            echo ""
            exit 1
        fi
        
        # Normalize schema name to lowercase
        SCHEMA_NAME=$(echo "$SCHEMA_NAME" | tr '[:upper:]' '[:lower:]')
        
        # Validate and route to appropriate installer
        case "$SCHEMA_NAME" in
            hr)
                _if_dry_run "Would run: bash /usr/sandbox/app/oracle/admin/ddl/install-hr-schema.sh" && exit 0
                bash /usr/sandbox/app/oracle/admin/ddl/install-hr-schema.sh
                ;;
            oe)
                _if_dry_run "Would run: bash /usr/sandbox/app/oracle/admin/ddl/install-oe-schema.sh" && exit 0
                bash /usr/sandbox/app/oracle/admin/ddl/install-oe-schema.sh
                ;;
            pm)
                _if_dry_run "Would run: bash /usr/sandbox/app/oracle/admin/ddl/install-pm-schema.sh" && exit 0
                bash /usr/sandbox/app/oracle/admin/ddl/install-pm-schema.sh
                ;;
            sh)
                _if_dry_run "Would run: bash /usr/sandbox/app/oracle/admin/ddl/install-sh-schema.sh" && exit 0
                bash /usr/sandbox/app/oracle/admin/ddl/install-sh-schema.sh
                ;;
            *)
                log_error "Invalid schema name: $SCHEMA_NAME"
                echo ""
                echo "Available schemas: hr, oe, pm, sh"
                echo ""
                exit 1
                ;;
        esac
        ;;
esac
