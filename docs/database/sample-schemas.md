# Oracle Sample Schemas

Oracle provides sample schemas that demonstrate various database features and serve as excellent learning resources for SQL, PL/SQL, and database design patterns.

## Available Schemas

The Oracle Sandbox supports four popular Oracle sample schemas:

### HR (Human Resources)
- **Tables**: 7
- **Records**: ~107 employees
- **Use Case**: Basic relational database concepts, joins, simple queries
- **Key Tables**: `EMPLOYEES`, `DEPARTMENTS`, `JOBS`, `JOB_HISTORY`, `LOCATIONS`, `COUNTRIES`, `REGIONS`
- **Best For**: Beginners learning SQL, testing simple queries

### OE (Order Entry)
- **Tables**: 12
- **Records**: ~319 customers, multiple orders
- **Use Case**: E-commerce, order management, customer relationships
- **Key Tables**: `CUSTOMERS`, `ORDERS`, `ORDER_ITEMS`, `PRODUCT_INFORMATION`, `INVENTORIES`, `WAREHOUSES`
- **Dependencies**: Has foreign key references to HR schema
- **Best For**: Intermediate SQL, complex joins, business logic

### PM (Product Media)
- **Tables**: 2
- **Records**: ~288 media items
- **Use Case**: LOB (Large Objects) handling, multimedia data
- **Key Tables**: `PRINT_MEDIA`, `ONLINE_MEDIA`
- **Features**: BLOB, CLOB columns for storing media content
- **Best For**: Advanced topics, LOB manipulation, media storage

### SH (Sales History)
- **Tables**: 10+
- **Records**: ~55,500 sales transactions
- **Use Case**: Data warehousing, OLAP, business intelligence
- **Schema Type**: Star schema (fact and dimension tables)
- **Key Tables**: `SALES` (fact), `CUSTOMERS`, `PRODUCTS`, `CHANNELS`, `PROMOTIONS`, `TIMES` (dimensions)
- **Best For**: Analytics, reporting, data warehouse concepts

## Quick Start

### Install a Schema

```bash
# Install HR schema (simplest)
sandbox install schema --name hr

# Install OE schema (has HR dependency)
sandbox install schema --name oe

# Install PM schema (with LOBs)
sandbox install schema --name pm

# Install SH schema (data warehouse)
sandbox install schema --name sh
```

### Connect to Schema

```bash
# Using SQLcl
sql hr/<password>@//localhost:1521/SANDBOX_PDB

# Or use the sandbox CLI to start SQLcl
sandbox run sqlcl
# Then connect: CONN hr/<password>@SANDBOX_PDB
```

### Verify Installation

```sql
-- Check tables
SELECT table_name, num_rows 
FROM user_tables 
ORDER BY table_name;

-- Sample query (HR schema)
SELECT first_name, last_name, department_id 
FROM employees 
WHERE rownum <= 10;
```

## Installation Process

The installation process for each schema:

1. **Download** - Fetches complete schema files from Oracle's GitHub repository (oracle-samples/db-sample-schemas) including structure DDL and data population scripts
2. **User Creation** - Creates dedicated schema user in target PDB
3. **Privilege Grant** - Grants 'normal' level privileges (CREATE/ALTER/DROP ANY, etc.)
4. **DDL Execution** - Runs SQL files in correct order:
   - `*_main.sql` - Creates tables, sequences, constraints
   - `*_code.sql` - Creates procedures, functions, triggers
   - `*_populate.sql` - **Inserts sample data** (employees, customers, sales, etc.)
   - `*_idx.sql` - Creates indexes for performance
   - `*_analz.sql` - Analyzes tables for optimizer statistics
5. **Validation** - Verifies table counts and row counts match expectations

**Note**: Schemas include actual data! HR schema will have ~107 employees, OE has ~319 customers, SH has ~55,500 sales records.

## Schema Dependencies

### OE → HR Dependency

The OE (Order Entry) schema has foreign key constraints referencing the HR schema. When installing OE:

- **Recommended**: Install HR schema first
- **Detection**: The installer checks for HR schema existence
- **Prompt**: You'll be prompted if HR is not found
- **Workaround**: You can proceed without HR, but some constraints may fail

To install both schemas:

```bash
# Install HR first
sandbox install schema --name hr

# Then install OE
sandbox install schema --name oe
```

## Configuration

### Environment Variables

Configure schema settings in `.env` file:

```bash
# Sample Schemas Download Source
ENV_SRC_ORACLE_SAMPLE_SCHEMAS=https://github.com/oracle-samples/db-sample-schemas/archive/refs/tags/v23.3.tar.gz

# Sample Schemas Installation Directory
ENV_SAMPLE_SCHEMAS_HOME=/opt/oracle/sample-schemas
# Note: Available in container as SANDBOX_SAMPLE_SCHEMAS_HOME

# HR Schema
SANDBOX_HR_SCHEMA_PDB=SANDBOX_PDB
SANDBOX_HR_SCHEMA_PASSWORD=YourPassword123

# OE Schema
SANDBOX_OE_SCHEMA_PDB=SANDBOX_PDB
SANDBOX_OE_SCHEMA_PASSWORD=YourPassword123

# PM Schema
SANDBOX_PM_SCHEMA_PDB=SANDBOX_PDB
SANDBOX_PM_SCHEMA_PASSWORD=YourPassword123

# SH Schema
SANDBOX_SH_SCHEMA_PDB=SANDBOX_PDB
SANDBOX_SH_SCHEMA_PASSWORD=YourPassword123
```

### Default Values

If not specified in `.env`:
- **PDB**: Defaults to `SANDBOX_PDB`
- **Password**: Uses `SANDBOX_DB_PASSWORD`

## Sample Queries

### HR Schema Queries

```sql
-- List all employees with their department
SELECT e.first_name, e.last_name, d.department_name
FROM hr.employees e
JOIN hr.departments d ON e.department_id = d.department_id
ORDER BY d.department_name, e.last_name;

-- Employee count by department
SELECT d.department_name, COUNT(e.employee_id) as emp_count
FROM hr.departments d
LEFT JOIN hr.employees e ON d.department_id = e.department_id
GROUP BY d.department_name
ORDER BY emp_count DESC;

-- Salary statistics
SELECT 
    MIN(salary) as min_salary,
    MAX(salary) as max_salary,
    AVG(salary) as avg_salary,
    COUNT(*) as total_employees
FROM hr.employees;
```

### OE Schema Queries

```sql
-- Top customers by order count
SELECT 
    c.customer_id,
    c.cust_first_name,
    c.cust_last_name,
    COUNT(o.order_id) as order_count
FROM oe.customers c
LEFT JOIN oe.orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.cust_first_name, c.cust_last_name
ORDER BY order_count DESC
FETCH FIRST 10 ROWS ONLY;

-- Order details with product information
SELECT 
    o.order_id,
    o.order_date,
    p.product_name,
    oi.quantity,
    oi.unit_price,
    (oi.quantity * oi.unit_price) as line_total
FROM oe.orders o
JOIN oe.order_items oi ON o.order_id = oi.order_id
JOIN oe.product_information p ON oi.product_id = p.product_id
WHERE o.order_date >= ADD_MONTHS(SYSDATE, -3)
ORDER BY o.order_date DESC, o.order_id;
```

### PM Schema Queries

```sql
-- List all media products
SELECT product_id, product_name 
FROM pm.print_media 
ORDER BY product_id;

-- Check LOB columns
SELECT table_name, column_name, data_type
FROM user_tab_columns
WHERE data_type LIKE '%LOB%'
ORDER BY table_name, column_name;
```

### SH Schema Queries (Data Warehouse)

```sql
-- Sales by product (top 10)
SELECT 
    p.prod_name,
    SUM(s.amount_sold) as total_sales,
    COUNT(*) as transaction_count
FROM sh.sales s
JOIN sh.products p ON s.prod_id = p.prod_id
GROUP BY p.prod_name
ORDER BY total_sales DESC
FETCH FIRST 10 ROWS ONLY;

-- Sales by channel and quarter
SELECT 
    c.channel_desc,
    t.calendar_quarter_desc,
    SUM(s.amount_sold) as revenue,
    COUNT(*) as transactions
FROM sh.sales s
JOIN sh.channels c ON s.channel_id = c.channel_id
JOIN sh.times t ON s.time_id = t.time_id
GROUP BY c.channel_desc, t.calendar_quarter_desc
ORDER BY revenue DESC;

-- Customer demographics analysis
SELECT 
    cust.country_id,
    co.country_name,
    COUNT(DISTINCT cust.cust_id) as customer_count,
    SUM(s.amount_sold) as total_revenue
FROM sh.customers cust
JOIN sh.countries co ON cust.country_id = co.country_id
LEFT JOIN sh.sales s ON cust.cust_id = s.cust_id
GROUP BY cust.country_id, co.country_name
ORDER BY total_revenue DESC NULLS LAST;
```

## Advanced Usage

### Manual Download Only

To download schema files without installing:

```bash
# Download all schemas
docker exec sandbox-oracle-server bash /usr/sandbox/app/download/download-sample-schemas.sh

# Download specific schema
docker exec sandbox-oracle-server bash /usr/sandbox/app/download/download-sample-schemas.sh hr
```

### Install to Different PDB

```bash
# Set in .env file
SANDBOX_HR_SCHEMA_PDB=CUSTOM_PDB

# Or pass directly to installer script
docker exec sandbox-oracle-server bash /usr/sandbox/app/oracle/admin/ddl/install-hr-schema.sh CUSTOM_PDB
```

### Reinstall Schema

To reinstall a schema, first drop the user:

```bash
# Connect as system
sql system/<password>@//localhost:1521/SANDBOX_PDB

# Drop user with cascade
DROP USER HR CASCADE;

# Exit and reinstall
sandbox install schema --name hr
```

## Troubleshooting

### Schema Already Exists

**Error**: "User HR already exists in PDB SANDBOX_PDB"

**Solution**: Either use the existing schema or drop and recreate:
```sql
DROP USER HR CASCADE;
```

### Download Failures

**Error**: "Download failed - Please check your internet connection"

**Solution**: 
- Verify internet connectivity
- Check firewall/proxy settings
- Retry: `sandbox install schema --name hr`

### OE Foreign Key Errors

**Error**: Foreign key constraint violations during OE installation

**Solution**: Install HR schema first:
```bash
sandbox install schema --name hr
sandbox install schema --name oe
```

### SQLcl Not Found

**Error**: "SQLcl not found"

**Solution**: Install SQLcl first:
```bash
docker exec sandbox-oracle-server bash /usr/sandbox/app/install/oracle/install-sqlcl.sh
```

## File Locations

| Component | Path |
|-----------|------|
| Downloaded DDL Files | `/opt/oracle/sample-schemas/<schema>/` |
| Download Script | `/usr/sandbox/app/download/download-sample-schemas.sh` |
| Generic Installer | `/usr/sandbox/app/oracle/admin/ddl/install-sample-schema.sh` |
| HR Installer | `/usr/sandbox/app/oracle/admin/ddl/install-hr-schema.sh` |
| OE Installer | `/usr/sandbox/app/oracle/admin/ddl/install-oe-schema.sh` |
| PM Installer | `/usr/sandbox/app/oracle/admin/ddl/install-pm-schema.sh` |
| SH Installer | `/usr/sandbox/app/oracle/admin/ddl/install-sh-schema.sh` |
| Installation Logs | `/tmp/install-sample-schema-<schema>.log` |

## References

- [Oracle Sample Schemas Documentation](https://www.oracle.com/database/technologies/appdev/datamodels.html)
- [HR Schema Details](https://www.oracle.com/docs/tech/developer-tools/hr-30-ddl.zip)
- [OE Schema Details](https://www.oracle.com/docs/tech/developer-tools/oe-30-ddl.zip)
- [PM Schema Details](https://www.oracle.com/docs/tech/developer-tools/pm-30-ddl.zip)
- [SH Schema Details](https://www.oracle.com/docs/tech/developer-tools/sh-30-ddl.zip)

## Next Steps

- [Database Connectivity Guide](connectivity.md)
- [APEX Installation](apex-installation.md)
- [Security Considerations](../security/security.md)
- [Quick Reference](../quick-reference.md)
