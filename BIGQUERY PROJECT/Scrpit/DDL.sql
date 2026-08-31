-- =========================================================================
-- DDL.sql -- Full warehouse setup (BigQuery)
-- Converted from: PGSQL PROJECT/Scrpit/DDL.txt
-- =========================================================================
-- PostgreSQL -> BigQuery notes:
--   - CREATE DATABASE data_ware_house;  -> a BigQuery "database" is the GCP
--     project itself; there is nothing to CREATE here. Just make sure you
--     are running these statements against the right project (console
--     project selector, or `bq query --project_id=your_gcp_project`).
--   - CREATE SCHEMA IF NOT EXISTS      -> datasets must be created out of
--     band before running this script (SQL cannot create a dataset):
--         bq mk --dataset --location=US your_gcp_project:bronze
--         bq mk --dataset --location=US your_gcp_project:silver
--         bq mk --dataset --location=US your_gcp_project:gold
--   - "PostgreSQL has no internal STAGE object" note carries over unchanged
--     -- BigQuery doesn't have one either; GCS is the staging area (see
--     ../../gcs_load/).
--   - "CREATE TABLE ... AS SELECT" (CTAS) for the gold layer is identical
--     syntax in BigQuery.
--   - SERIAL PRIMARY KEY -> STRING DEFAULT GENERATE_UUID() (see log_id
--     below); there is no auto-increment integer type in BigQuery.
-- =========================================================================

-- Datasets created out-of-band -- see the `bq mk` commands above.

-- =============================================
-- BRONZE LAYER OBJECTS
-- =============================================

CREATE TABLE IF NOT EXISTS bronze.crm_cust_info (
    cst_id              INT64,
    cst_key             STRING,
    cst_firstname       STRING,
    cst_lastname        STRING,
    cst_marital_status  STRING,
    cst_gndr            STRING,
    cst_create_date     DATE
);

CREATE TABLE IF NOT EXISTS bronze.crm_prd_info (
    prd_id       INT64,
    prd_key      STRING,
    prd_nm       STRING,
    prd_cost     INT64,
    prd_line     STRING,
    prd_start_dt TIMESTAMP,
    prd_end_dt   TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bronze.crm_sales_details (
    sls_ord_num  STRING,
    sls_prd_key  STRING,
    sls_cust_id  INT64,
    sls_order_dt INT64,
    sls_ship_dt  INT64,
    sls_due_dt   INT64,
    sls_sales    INT64,
    sls_quantity INT64,
    sls_price    INT64
);

CREATE TABLE IF NOT EXISTS bronze.erp_cust_az12 (
    cid    STRING,
    bdate  DATE,
    gen    STRING
);

CREATE TABLE IF NOT EXISTS bronze.erp_px_cat_g1v2 (
    id           STRING,
    cat          STRING,
    subcat       STRING,
    maintenance  STRING
);

CREATE TABLE IF NOT EXISTS bronze.erp_loc_a101 (
    cid    STRING,
    cntry  STRING
);

-- =============================================
-- SILVER LAYER OBJECTS
-- =============================================

CREATE TABLE IF NOT EXISTS silver.crm_cust_info (
    cst_id             INT64,
    cst_key            STRING,
    cst_firstname      STRING,
    cst_lastname       STRING,
    cst_marital_status STRING,
    cst_gndr           STRING,
    cst_create_date    DATE,
    dwh_create_date    TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS silver.crm_prd_info (
    prd_id          INT64,
    cat_id          STRING,
    prd_key         STRING,
    prd_nm          STRING,
    prd_cost        INT64,
    prd_line        STRING,
    prd_start_dt    DATE,
    prd_end_dt      DATE,
    dwh_create_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS silver.crm_sales_details (
    sls_ord_num     STRING,
    sls_prd_key     STRING,
    sls_cust_id     INT64,
    sls_order_dt    DATE,
    sls_ship_dt     DATE,
    sls_due_dt      DATE,
    sls_sales       INT64,
    sls_quantity    INT64,
    sls_price       INT64,
    dwh_create_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS silver.erp_px_cat_g1v2 (
    id              STRING,
    cat             STRING,
    subcat          STRING,
    maintenance     STRING,
    dwh_create_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS silver.erp_cust_az12 (
    cid             STRING,
    bdate           DATE,
    gen             STRING,
    dwh_create_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS silver.erp_loc_a101 (
    cid             STRING,
    cntry           STRING,
    dwh_create_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- =============================================
-- GOLD LAYER (DIMENSIONS & FACTS)
-- =============================================

DROP TABLE IF EXISTS gold.dim_customers;
CREATE TABLE gold.dim_customers AS
SELECT
    ROW_NUMBER() OVER (ORDER BY ci.cst_id) AS customer_key,
    ci.cst_id                          AS customer_id,
    ci.cst_key                         AS customer_number,
    ci.cst_firstname                   AS first_name,
    ci.cst_lastname                    AS last_name,
    la.cntry                           AS country,
    ci.cst_marital_status              AS marital_status,
    CASE
        WHEN ci.cst_gndr != 'n/a' THEN ci.cst_gndr
        ELSE COALESCE(ca.gen, 'n/a')
    END                                AS gender,
    ca.bdate                           AS birthdate,
    ci.cst_create_date                 AS create_date
FROM silver.crm_cust_info ci
LEFT JOIN silver.erp_cust_az12 ca ON ci.cst_key = ca.cid
LEFT JOIN silver.erp_loc_a101 la  ON ci.cst_key = la.cid;


DROP TABLE IF EXISTS gold.dim_products;
CREATE TABLE gold.dim_products AS
SELECT
    ROW_NUMBER() OVER (ORDER BY pn.prd_start_dt, pn.prd_key) AS product_key,
    pn.prd_id       AS product_id,
    pn.prd_key      AS product_number,
    pn.prd_nm       AS product_name,
    pn.cat_id       AS category_id,
    pc.cat          AS category,
    pc.subcat       AS subcategory,
    pc.maintenance  AS maintenance,
    pn.prd_cost     AS cost,
    pn.prd_line     AS product_line,
    pn.prd_start_dt AS start_date
FROM silver.crm_prd_info pn
LEFT JOIN silver.erp_px_cat_g1v2 pc ON pn.cat_id = pc.id
WHERE pn.prd_end_dt IS NULL;


DROP TABLE IF EXISTS gold.fact_sales;
CREATE TABLE gold.fact_sales AS
SELECT
    sd.sls_ord_num  AS order_number,
    pr.product_key  AS product_key,
    cu.customer_key AS customer_key,
    sd.sls_order_dt AS order_date,
    sd.sls_ship_dt  AS shipping_date,
    sd.sls_due_dt   AS due_date,
    sd.sls_sales    AS sales_amount,
    sd.sls_quantity AS quantity,
    sd.sls_price    AS price
FROM silver.crm_sales_details sd
LEFT JOIN gold.dim_products pr ON sd.sls_prd_key = pr.product_number
LEFT JOIN gold.dim_customers cu ON sd.sls_cust_id = cu.customer_id;

-- =============================================
-- AUDIT LOGGING
-- =============================================

CREATE TABLE IF NOT EXISTS bronze.load_audit_log (
    log_id          STRING DEFAULT GENERATE_UUID(),
    procedure_name  STRING,
    table_name      STRING,
    rows_loaded     INT64,
    load_status     STRING,
    start_time      TIMESTAMP,
    end_time        TIMESTAMP,
    error_message   STRING,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

SELECT * FROM bronze.load_audit_log;
