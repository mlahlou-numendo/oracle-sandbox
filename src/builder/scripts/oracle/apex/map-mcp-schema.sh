#!/bin/bash
################################################################################
# Map MCP Schema to APEX Workspace
# Adds the MCP user's schema (sandbox_ai by default) to the default APEX
# workspace, so SQLcl's APEX commands work over the sandbox-ai-conn MCP
# connection. Idempotent — safe to run on every startup and after install-apex.
#
# Exit codes: 0 = mapped (or already mapped), 1 = error,
#             2 = skipped (APEX, workspace or schema not ready yet)
################################################################################

# Configuration - Use environment variables (with sensible fallbacks)
DB_HOST="${SANDBOX_DB_HOST}"
DB_PORT="${SANDBOX_DB_PORT}"
DB_SERVICE="${SANDBOX_DB_SERVICE}"
SYS_PASSWORD="${SANDBOX_DB_PASSWORD:-${SANDBOX_DB_PASS}}"
APEX_PDB="${SANDBOX_APEX_PDB:-FREEPDB1}"
APEX_PDB="${APEX_PDB^^}"
WORKSPACE_NAME="${SANDBOX_APEX_DEFAULT_WORKSPACE:-SANDBOX}"
WORKSPACE_NAME="${WORKSPACE_NAME^^}"
MCP_SCHEMA="${SANDBOX_DB_MCP_USER:-${SANDBOX_DB_USER}}"
MCP_SCHEMA="${MCP_SCHEMA^^}"
MCP_SERVICE="${SANDBOX_DB_MCP_SERVICE:-${DB_SERVICE}}"
MCP_SERVICE="${MCP_SERVICE^^}"

if [ -z "$DB_HOST" ] || [ -z "$DB_PORT" ] || [ -z "$DB_SERVICE" ] || [ -z "$SYS_PASSWORD" ] || [ -z "$MCP_SCHEMA" ]; then
    echo "Error: Required environment variables not set"
    echo "Please set: SANDBOX_DB_HOST, SANDBOX_DB_PORT, SANDBOX_DB_SERVICE, SANDBOX_DB_PASSWORD, SANDBOX_DB_MCP_USER"
    exit 1
fi

# Values are interpolated into SQL below, so only accept plain identifiers
for ident in "$APEX_PDB" "$WORKSPACE_NAME" "$MCP_SCHEMA"; do
    if [[ ! "$ident" =~ ^[A-Z][A-Z0-9_\$#]{0,127}$ ]]; then
        echo "Error: Invalid identifier '${ident}'"
        exit 1
    fi
done

# The MCP connection only sees APEX when it targets the PDB APEX lives in
if [ "$MCP_SERVICE" != "$APEX_PDB" ]; then
    echo "Skipped: MCP service ${MCP_SERVICE} differs from APEX PDB ${APEX_PDB} (set ENV_APEX_PDB = ENV_DB_MCP_SERVICE)"
    exit 2
fi

echo "Mapping schema ${MCP_SCHEMA} to APEX workspace ${WORKSPACE_NAME} in ${APEX_PDB}..."

# Check prerequisites first: the APEX views referenced in the mapping block
# don't exist until APEX is installed, and on startup this runs in parallel
# with install-apex and user provisioning. The concatenated marker can only
# appear in real query output.
READY_STATE=$(sql -S sys/\"${SYS_PASSWORD}\"@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba <<EOSQL 2>&1 | grep -o 'MAP_STATE=[A-Z_]*'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
ALTER SESSION SET CONTAINER=${APEX_PDB};
SELECT 'MAP_' || 'STATE=' ||
       CASE
           WHEN (SELECT COUNT(*) FROM dba_registry WHERE comp_id = 'APEX' AND status = 'VALID') = 0 THEN 'NO_APEX'
           WHEN (SELECT COUNT(*) FROM dba_users WHERE username = '${MCP_SCHEMA}') = 0 THEN 'NO_SCHEMA'
           ELSE 'READY'
       END
FROM dual;
EXIT
EOSQL
)

case "$READY_STATE" in
    MAP_STATE=READY) ;;
    MAP_STATE=NO_APEX)
        echo "Skipped: APEX is not installed (or not VALID) in ${APEX_PDB}"
        exit 2 ;;
    MAP_STATE=NO_SCHEMA)
        echo "Skipped: schema ${MCP_SCHEMA} does not exist in ${APEX_PDB}"
        exit 2 ;;
    *)
        echo "Error: Cannot query ${APEX_PDB} at ${DB_HOST}:${DB_PORT}/${DB_SERVICE}"
        exit 1 ;;
esac

MAP_OUTPUT=$(sql -S sys/\"${SYS_PASSWORD}\"@//${DB_HOST}:${DB_PORT}/${DB_SERVICE} as sysdba <<EOSQL 2>&1
SET SERVEROUTPUT ON FEEDBACK OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
ALTER SESSION SET CONTAINER=${APEX_PDB};

DECLARE
    v_ws_count      PLS_INTEGER;
    v_mapping_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_ws_count
    FROM apex_workspaces
    WHERE workspace = '${WORKSPACE_NAME}';

    IF v_ws_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('MAP_' || 'RESULT=NO_WORKSPACE');
        RETURN;
    END IF;

    SELECT COUNT(*) INTO v_mapping_count
    FROM apex_workspace_schemas
    WHERE workspace_name = '${WORKSPACE_NAME}'
      AND schema = '${MCP_SCHEMA}';

    IF v_mapping_count = 0 THEN
        APEX_INSTANCE_ADMIN.ADD_SCHEMA(
            p_workspace             => '${WORKSPACE_NAME}',
            p_schema                => '${MCP_SCHEMA}',
            p_grant_apex_privileges => TRUE
        );
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('MAP_' || 'RESULT=MAPPED');
    ELSE
        DBMS_OUTPUT.PUT_LINE('MAP_' || 'RESULT=ALREADY_MAPPED');
    END IF;
END;
/
EXIT
EOSQL
)

case "$(grep -o 'MAP_RESULT=[A-Z_]*' <<< "$MAP_OUTPUT")" in
    MAP_RESULT=MAPPED)
        echo "Mapped ${MCP_SCHEMA} to APEX workspace ${WORKSPACE_NAME}" ;;
    MAP_RESULT=ALREADY_MAPPED)
        echo "${MCP_SCHEMA} is already mapped to APEX workspace ${WORKSPACE_NAME}" ;;
    MAP_RESULT=NO_WORKSPACE)
        echo "Skipped: APEX workspace ${WORKSPACE_NAME} does not exist yet"
        exit 2 ;;
    *)
        echo "Error: Failed to map ${MCP_SCHEMA} to APEX workspace ${WORKSPACE_NAME}"
        echo "$MAP_OUTPUT" | grep -m3 -E 'ORA-|Error'
        exit 1 ;;
esac
