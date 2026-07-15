# Oracle Sample Schema Installation - Testing & Automation Guide

## Test Scripts Created

### 1. Complete Clean Rebuild Test
**File:** `tests/clean-rebuild-test.sh`

**Purpose:** Full environment cleanup, rebuild, and validation

**Features:**
- Complete cleanup (containers, images, volumes, build cache)
- Fresh Docker build from scratch
- Container startup and health checks
- Automated schema installation
- Comprehensive validation with expected table/row counts

**Usage:**
```bash
# Test single schema (HR recommended)
./tests/clean-rebuild-test.sh --schema hr

# Test all schemas
./tests/clean-rebuild-test.sh --schema all

# Test specific schema
./tests/clean-rebuild-test.sh --schema oe
./tests/clean-rebuild-test.sh --schema pm
./tests/clean-rebuild-test.sh --schema sh
```

**What it does:**
1. Stops all containers
2. Removes sandbox images
3. Removes volumes
4. Cleans build cache
5. Fresh `docker compose build`
6. Starts containers
7. Waits for health checks
8. Drops existing schema (clean slate)
9. Installs schema via `sandbox install schema --name`
10. Validates table count and row count
11. Reports pass/fail with timing

### 2. Quick Schema Test
**File:** `tests/quick-schema-test.sh`

**Purpose:** Quick test without cleanup/rebuild (for rapid iteration)

**Usage:**
```bash
./tests/quick-schema-test.sh hr
./tests/quick-schema-test.sh oe
```

**What it does:**
1. Drops existing schema
2. Installs schema
3. Quick validation
4. Reports results

## How to Evaluate: Complete Clean Slate Test

### Step-by-Step Manual Process

```bash
# 1. Stop containers
docker compose down

# 2. Remove images
docker images | grep sandbox-oracle | awk '{print $3}' | xargs docker rmi -f

# 3. Remove volumes
docker volume ls | grep oracle-sandbox | awk '{print $2}' | xargs docker volume rm -f

# 4. Clean build cache
docker builder prune -f

# 5. Clean system
docker system prune -f

# 6. Fresh build
docker compose build sandbox-oracle-server

# 7. Start containers
docker compose up -d

# 8. Wait for readiness
sleep 30

# 9. Test schema installation
docker exec sandbox-oracle-server sandbox install schema --name hr

# 10. Validate
docker exec sandbox-oracle-server bash -c 'sql -S hr/Demasy1986@//192.168.1.110:1521/SANDBOX_PDB <<EOF
SELECT COUNT(*) AS table_count FROM user_tables;
SELECT COUNT(*) AS employee_count FROM employees;
EXIT
EOF'
```

### Automated Process (Recommended)

```bash
# Complete automated test (all steps above in one command)
./tests/clean-rebuild-test.sh --schema hr
```

## Current Status

### ✅ Working: HR Schema
- **Tables:** 7 (REGIONS, COUNTRIES, LOCATIONS, DEPARTMENTS, JOBS, EMPLOYEES, JOB_HISTORY)
- **Rows:** ~107 employees with full data
- **Installation:** Fully automated
- **Validation:** Passes all checks
- **Scripts:** hr_create.sql, hr_populate.sql, hr_code.sql (no parameter dependencies)

### ⚠️ In Progress: OE Schema
- **Expected:** 12 tables, ~319 customers
- **Current:** 2 nested tables only
- **Issue:** OE scripts (oe_cre.sql, c*_v3.sql) all require SQL*Plus variable parameters
- **Root Cause:** Oracle sample schemas designed for interactive installation
- **Status:** Pattern matching updated to prioritize v3 scripts and skip problematic files

### ❌ Not Tested: PM & SH Schemas
- **PM:** Product Media (2 LOB tables)
- **SH:** Sales History (10+ tables, star schema)
- **Status:** Same parameter dependency issues expected

## Installation Script Improvements

### Pattern Matching Updates

**File:** `src/builder/scripts/oracle/admin/ddl/install-sample-schema.sh`

**Changes:**
1. Skipped master scripts (_main.sql, _install.sql) - they're designed for interactive use
2. Prioritized v3 scripts (c*_v3.sql, p*_v3.sql) for automation
3. Added exclusions for problematic scripts (oe_cre.sql, oc_main.sql)
4. Updated execution order: create → populate → code → idx → analz → comnt → drop

**Execution Order:**
```
1. c*_v3.sql or *_create.sql    (Create tables)
2. p*_v3.sql or *_populate.sql  (Populate data - BEFORE triggers!)
3. cidx_v3.sql or *_idx.sql     (Create indexes)
4. *_code.sql                   (Procedures/triggers)
5. *_analz.sql                  (Analyze/statistics)
6. *_comnt.sql                  (Comments)
7. *_drop.sql                   (Cleanup examples)
8. *.sql                        (Everything else)
```

## Validation Criteria

### HR Schema
```bash
Table Count:    >= 7
Employee Count: > 100
Expected:       107 employees with salary data
```

### OE Schema
```bash
Table Count:    >= 12
Customer Count: > 300
Expected:       319 customers, order history
Dependencies:   HR schema (foreign keys to HR.EMPLOYEES, HR.COUNTRIES)
```

### PM Schema  
```bash
Table Count:    >= 2
Row Count:      > 200
Expected:       288 product media entries with LOB data
```

### SH Schema
```bash
Table Count:    >= 10
Row Count:      > 50000
Expected:       55,500 sales records (star schema)
```

##Files Modified

### Core Installation Scripts
1. `src/builder/scripts/oracle/admin/ddl/install-sample-schema.sh` - Pattern matching & execution order
2. `src/builder/scripts/download/download-sample-schemas.sh` - Already uses GitHub tar.gz source ✓
3. `src/builder/scripts/oracle/admin/ddl/install-{hr|oe|pm|sh}-schema.sh` - Schema-specific wrappers ✓

### Test Automation (New)
1. `tests/clean-rebuild-test.sh` - Complete clean slate testing ✓
2. `tests/quick-schema-test.sh` - Rapid iteration testing ✓

### Configuration
1. `.env` - Schema passwords and PDB mappings ✓
2. `docker-compose.yml` - Environment variable passthrough ✓
3. `Dockerfile` - /opt/oracle/sample-schemas directory creation ✓

## Next Steps to Fix OE Schema

### Option 1: Parameter Injection
Modify `install-sample-schema.sh` to detect parameter requirements and provide them via printf piping:

```bash
if [[ -f "oe_install.sql" ]]; then
    printf "%s\n" "v3" "$SCHEMA_PASSWORD" "USERS" "TEMP" "$HR_PASSWORD" "$DB_PASSWORD" "/opt/oracle/oradata" "/tmp" "v3" "" | \
        sql ${SCHEMA_NAME}/${SCHEMA_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} @oe_install.sql
fi
```

### Option 2: Direct SQL Execution
Create `create-oe-tables.sh` with hardcoded CREATE TABLE statements (no variables):
- Already started in `src/builder/scripts/oracle/admin/ddl/create-oe-tables.sh`
- Extract all CREATE TABLE/TYPE statements from OE scripts
- Execute directly without parameter dependencies

### Option 3: SQL*Plus DEFINE
Set all required variables before execution:

```sql
DEFINE vrs = "v3"
DEFINE pwd_oe = "Demasy1986"  
DEFINE pass_sys = "Demasy1986"
DEFINE connect_string = ""
@coe_v3.sql
```

## Recommended Testing Workflow

### Phase 1: Validate Automation (Current)
```bash
./tests/clean-rebuild-test.sh --schema hr
```
**Expected:** HR installation passes with 7 tables, 107 employees

### Phase 2: Fix OE (In Progress)
```bash
# After implementing fix
./tests/quick-schema-test.sh oe
./tests/clean-rebuild-test.sh --schema oe
```
**Expected:** OE installation passes with 12 tables, 319 customers

### Phase 3: Extend to PM & SH
```bash
./tests/clean-rebuild-test.sh --schema pm
./tests/clean-rebuild-test.sh --schema sh
```

### Phase 4: Full Validation
```bash
./tests/clean-rebuild-test.sh --schema all
```
**Expected:** All 4 schemas install successfully

### Phase 5: Git Commit
Only after all schemas pass validation (per user requirement: "NO git commit test and check first!")

## Log Files

All installation logs available at:
- `/tmp/install-sample-schema-hr.log`
- `/tmp/install-sample-schema-oe.log`
- `/tmp/install-sample-schema-pm.log`
- `/tmp/install-sample-schema-sh.log`
- `/tmp/oracle-sandbox-build.log` (Docker build)
- `/tmp/clean-rebuild-hr.log` (Test script output)

## Summary

**Automated:** ✅
- Complete cleanup process
- Fresh Docker build
- Container startup & health checks
- HR schema installation & validation
- Comprehensive test scripts

**In Progress:** ⚠️
- OE, PM, SH schema installation (parameter dependency issues)

**Blocked:** ❌
- Git commit (waiting for all schemas to validate)
