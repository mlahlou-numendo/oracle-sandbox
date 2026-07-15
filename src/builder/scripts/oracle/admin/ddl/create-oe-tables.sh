#!/usr/bin/env bash

######################################################################
# OE Schema Creation Script (Standalone)
######################################################################
# Purpose: Create OE schema tables without variable dependencies
# This script extracts CREATE TABLE statements from OE v3 scripts
# and executes them directly to avoid parameter complexity
######################################################################

set -e

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../system/utils/colors.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../../system/utils/logging.sh" 2>/dev/null || true

# Configuration
SCHEMA_NAME="OE"
SCHEMA_PASSWORD="${SANDBOX_OE_SCHEMA_PASSWORD:-Demasy1986}"
PDB_NAME="${SANDBOX_PDB_NAME:-SANDBOX_PDB}"
DB_HOST="${SANDBOX_DB_HOST:-192.168.1.110}"
DB_PORT="${SANDBOX_DB_PORT:-1521}"

log_info "Creating OE schema tables directly..."

# Execute table creation SQL directly
sql -S ${SCHEMA_NAME}/${SCHEMA_PASSWORD}@//${DB_HOST}:${DB_PORT}/${PDB_NAME} <<'EOSQL'
-- Create object types first
CREATE TYPE cust_address_typ AS OBJECT
    ( street_address     VARCHAR2(40)
    , postal_code        VARCHAR2(10)
    , city               VARCHAR2(30)
    , state_province     VARCHAR2(10)
    , country_id         CHAR(2)
    );
/

CREATE TYPE phone_list_typ AS VARRAY(5) OF VARCHAR2(25);
/

CREATE TYPE warehouse_typ AS OBJECT
    ( warehouse_id       NUMBER(3)
    , warehouse_name     VARCHAR2(35)
    , location_id        NUMBER(4)
    );
/

CREATE TYPE inventory_typ AS OBJECT
    ( product_id         NUMBER(6)
    , warehouse           warehouse_typ
    , quantity_on_hand   NUMBER(8)
    );
/

CREATE TYPE inventory_list_typ AS TABLE OF inventory_typ;
/

-- Create tables
CREATE TABLE warehouses
    ( warehouse_id       NUMBER(3)
    , warehouse_name     VARCHAR2(35)
    , location_id        NUMBER(4)
    )
    STORAGE (INITIAL 100K NEXT 50K);
/

CREATE TABLE order_items
    ( order_id           NUMBER(12)
    , line_item_id       NUMBER(3)  NOT NULL
    , product_id         NUMBER(6)  NOT NULL
    , unit_price         NUMBER(8,2)
    , quantity           NUMBER(8)
    , CONSTRAINT order_items_pk 
        PRIMARY KEY (order_id, line_item_id)
    );
/

CREATE TABLE orders
    ( order_id           NUMBER(12)
    , order_date         TIMESTAMP WITH LOCAL TIME ZONE
        CONSTRAINT order_date_nn NOT NULL
    , order_mode         VARCHAR2(8)
    , customer_id        NUMBER(6)
        CONSTRAINT order_customer_id_nn NOT NULL
    , order_status       NUMBER(2)
    , order_total        NUMBER(8,2)
    , sales_rep_id       NUMBER(6)
    , promotion_id       NUMBER(6)
    , CONSTRAINT order_pk 
        PRIMARY KEY (order_id)
    , CONSTRAINT order_mode_lov
        CHECK (order_mode in ('direct','online'))
    , CONSTRAINT order_total_min
        CHECK (order_total >= 0)
    )
    STORAGE (INITIAL 100K NEXT 50K) COMPRESS;
/

CREATE TABLE inventories
  ( product_id         NUMBER(6)
  , warehouse_id       NUMBER(3)
       CONSTRAINT inventory_warehouse_id_nn NOT NULL
  , quantity_on_hand   NUMBER(8)
       CONSTRAINT inventory_qoh_nn NOT NULL
  , CONSTRAINT inventory_pk
      PRIMARY KEY (product_id, warehouse_id)
  )
  STORAGE (INITIAL 100K NEXT 50K);
/

CREATE TABLE customers
  ( customer_id        NUMBER(6)
  , cust_first_name    VARCHAR2(20)
       CONSTRAINT cust_fname_nn NOT NULL
  , cust_last_name     VARCHAR2(20)
       CONSTRAINT cust_lname_nn NOT NULL
  , cust_address       cust_address_typ
  , phone_numbers      phone_list_typ
  , nls_language       VARCHAR2(3)
  , nls_territory      VARCHAR2(30)
  , credit_limit       NUMBER(9,2)
  , cust_email         VARCHAR2(40)
  , account_mgr_id     NUMBER(6)
  , CONSTRAINT customer_credit_limit_max
      CHECK (credit_limit <= 100000)
  , CONSTRAINT customer_id_min
      CHECK (customer_id > 0)
  , CONSTRAINT customer_pk
      PRIMARY KEY (customer_id)
  );
/

CREATE TABLE product_information
    ( product_id          NUMBER(6)
    , product_name        VARCHAR2(50)
    , product_description VARCHAR2(2000)
    , category_id         NUMBER(2)
    , weight_class        NUMBER(1)
    , warranty_period     INTERVAL YEAR TO MONTH
    , supplier_id         NUMBER(6)
    , product_status      VARCHAR2(20)
    , list_price          NUMBER(8,2)
    , min_price           NUMBER(8,2)
    , catalog_url         VARCHAR2(50)
    , CONSTRAINT          product_information_pk
                          PRIMARY KEY (product_id)
    , CONSTRAINT          product_status_lov
                          CHECK (product_status in ('orderable'
                                                  ,'planned'
                                                  ,'under development'
                                                  ,'obsolete')
 )
    ) NESTED TABLE product_ref_list STORE AS product_ref_list_nestedtab;
/

CREATE TABLE product_descriptions
  ( product_id          NUMBER(6)
  , language_id         VARCHAR2(3)
  , translated_name     NVARCHAR2(50)
  , translated_description      NVARCHAR2(2000)
  , CONSTRAINT product_descriptions_pk
      PRIMARY KEY (product_id, language_id)
  );
/

CREATE TABLE promotions
    ( promo_id             NUMBER(6)
    , promo_name           VARCHAR2(20)
    , CONSTRAINT promo_id_pk PRIMARY KEY (promo_id)
    );
/

EXIT
EOSQL

log_success "OE schema tables created successfully"
