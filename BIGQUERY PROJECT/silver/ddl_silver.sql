/*
===============================================================================
DDL Script: Create Silver Tables (BigQuery)
===============================================================================
PostgreSQL -> BigQuery notes:
    - TIMESTAMP DEFAULT CURRENT_TIMESTAMP -> BigQuery supports column DEFAULT
      expressions (GA), so `DEFAULT CURRENT_TIMESTAMP()` works the same way:
      the value is filled in automatically when a load/INSERT omits the column.
    - VARCHAR(n) -> STRING, INT -> INT64 (see ddl_bronze.sql for the full
      type-mapping table).
===============================================================================
*/

DROP TABLE IF EXISTS silver.crm_cust_info;
CREATE TABLE silver.crm_cust_info (
    cst_id             INT64,
    cst_key            STRING,
    cst_firstname      STRING,
    cst_lastname       STRING,
    cst_marital_status STRING,
    cst_gndr           STRING,
    cst_create_date    DATE,
    dwh_create_date    TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

DROP TABLE IF EXISTS silver.crm_prd_info;
CREATE TABLE silver.crm_prd_info (
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

DROP TABLE IF EXISTS silver.crm_sales_details;
CREATE TABLE silver.crm_sales_details (
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

DROP TABLE IF EXISTS silver.erp_loc_a101;
CREATE TABLE silver.erp_loc_a101 (
    cid             STRING,
    cntry           STRING,
    dwh_create_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

DROP TABLE IF EXISTS silver.erp_cust_az12;
CREATE TABLE silver.erp_cust_az12 (
    cid             STRING,
    bdate           DATE,
    gen             STRING,
    dwh_create_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

DROP TABLE IF EXISTS silver.erp_px_cat_g1v2;
CREATE TABLE silver.erp_px_cat_g1v2 (
    id              STRING,
    cat             STRING,
    subcat          STRING,
    maintenance     STRING,
    dwh_create_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);
