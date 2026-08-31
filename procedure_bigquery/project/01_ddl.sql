-- =========================================================================
-- PROJECT FILE: 01_ddl.sql                                        (BigQuery)
-- DESCRIPTION: Sets up the BigQuery datasets (bronze, silver, audit) and
--              creates the 6 required project tables and an audit logging
--              table.
-- DATASETS ("schema" in PostgreSQL terms):
--   - bronze: Holds raw, dirty, landing data from source systems.
--   - silver: Holds cleaned, validated, and structured dimensional models.
--   - audit:  Holds logs for procedure execution and record audit trails.
--
-- PostgreSQL -> BigQuery notes:
--   - CREATE SCHEMA IF NOT EXISTS -> datasets can't be created from inside a
--     query script; create them once beforehand (one-time, from the CLI):
--         bq mk --dataset --location=US your_project_id:bronze
--         bq mk --dataset --location=US your_project_id:silver
--         bq mk --dataset --location=US your_project_id:audit
--   - SERIAL PRIMARY KEY   -> no auto-increment exists in BigQuery.
--       * Surrogate integer keys (customer_key, product_key, sale_key) are
--         generated with ROW_NUMBER() at load time instead (see
--         proc_load_dim_customer.sql etc. in this folder).
--       * Non-sequential IDs (log_id) use STRING DEFAULT GENERATE_UUID().
--   - REFERENCES table(col)  -> BigQuery supports FOREIGN KEY, but it is
--       metadata-only and must be declared NOT ENFORCED (BigQuery never
--       rejects a write for violating it -- the ETL code itself is
--       responsible for referential integrity, exactly the way
--       proc_load_fact_sales.sql validates keys explicitly below).
--   - BOOLEAN                -> BOOL
--   - TEXT / VARCHAR(n)      -> STRING
-- =========================================================================

-- Datasets are created out-of-band (see the `bq mk` commands above) --
-- BigQuery has no in-SQL "CREATE SCHEMA" step to run here.

-- ==========================================
-- 1. BRONZE DATASET TABLES (Raw ingestion)
-- ==========================================

DROP TABLE IF EXISTS bronze.customer;
CREATE TABLE bronze.customer (
    cust_id      STRING,  -- deliberately STRING to simulate raw text
    cust_name    STRING,
    email        STRING,
    gender       STRING,
    created_date STRING   -- raw format e.g. '19-06-2026' or '2026/06/19'
);

DROP TABLE IF EXISTS bronze.products;
CREATE TABLE bronze.products (
    prod_id   STRING,
    prod_name STRING,
    category  STRING,
    price     STRING      -- raw format with potential symbols e.g. '$120.50'
);

DROP TABLE IF EXISTS bronze.sales;
CREATE TABLE bronze.sales (
    sale_id   STRING,
    cust_id   STRING,
    prod_id   STRING,
    qty       STRING,     -- STRING to allow handling raw data types
    sale_date STRING
);

-- ==========================================
-- 2. SILVER DATASET TABLES (Cleaned & Curated)
-- ==========================================

DROP TABLE IF EXISTS silver.dim_customer;
CREATE TABLE silver.dim_customer (
    customer_key INT64,   -- surrogate key, filled via ROW_NUMBER() at load time
    cust_id      INT64,   -- unenforced business key; uniqueness owned by the ETL
    first_name   STRING,
    last_name    STRING,
    email        STRING,
    gender       STRING,
    is_active    BOOL DEFAULT TRUE,
    created_date DATE,
    updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

DROP TABLE IF EXISTS silver.dim_products;
CREATE TABLE silver.dim_products (
    product_key INT64,
    prod_id     INT64,
    prod_name   STRING NOT NULL,
    category    STRING,
    price       NUMERIC,
    updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

DROP TABLE IF EXISTS silver.fact_products_sales;
CREATE TABLE silver.fact_products_sales (
    sale_key     INT64,
    sale_id      INT64,
    customer_key INT64,   -- FOREIGN KEY silver.dim_customer(customer_key) NOT ENFORCED
    product_key  INT64,   -- FOREIGN KEY silver.dim_products(product_key) NOT ENFORCED
    qty          INT64,
    total_price  NUMERIC,
    sale_date    DATE,
    loaded_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- ==========================================
-- 3. AUDIT DATASET TABLES (Metadata / Logging)
-- ==========================================

DROP TABLE IF EXISTS audit.load_logs;
CREATE TABLE audit.load_logs (
    log_id         STRING DEFAULT GENERATE_UUID(),
    procedure_name STRING NOT NULL,
    step_name      STRING NOT NULL,
    status         STRING NOT NULL, -- 'SUCCESS', 'FAILED', 'INFO'
    records_loaded INT64 DEFAULT 0,
    error_message  STRING,
    error_state    STRING,
    logged_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);
