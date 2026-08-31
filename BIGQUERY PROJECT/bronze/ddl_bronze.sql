/*
===============================================================================
DDL Script: Create Bronze Tables (BigQuery)
===============================================================================
Script Purpose:
    This script creates tables in the 'bronze' DATASET, dropping existing
    tables if they already exist.

PostgreSQL -> BigQuery notes:
    - PostgreSQL "schema"        -> BigQuery "dataset"
      Create the dataset first (one-time, run from bq CLI or console):
          bq mk --dataset --location=US your_project_id:bronze
    - INT                        -> INT64
    - VARCHAR(n)                 -> STRING   (BigQuery STRING has no length limit,
                                               the (n) is dropped)
    - TIMESTAMP                  -> TIMESTAMP (UTC, same semantics as PG "timestamptz")
    - DATE                       -> DATE (unchanged)
    - Replace every "bronze."    -> "`your_project_id.bronze.`" (backtick-quoted,
      fully qualified table path). Below we use the 2-part form
      "bronze.table_name" which works as long as the query/session default
      project is set to your GCP project (console project selector, or
      `bq query --project_id=...`, or Composer's `gcp_conn_id`).
===============================================================================
*/

DROP TABLE IF EXISTS bronze.crm_cust_info;
CREATE TABLE bronze.crm_cust_info (
    cst_id              INT64,
    cst_key             STRING,
    cst_firstname       STRING,
    cst_lastname        STRING,
    cst_marital_status  STRING,
    cst_gndr            STRING,
    cst_create_date     DATE
);

DROP TABLE IF EXISTS bronze.crm_prd_info;
CREATE TABLE bronze.crm_prd_info (
    prd_id       INT64,
    prd_key      STRING,
    prd_nm       STRING,
    prd_cost     INT64,
    prd_line     STRING,
    prd_start_dt TIMESTAMP,
    prd_end_dt   TIMESTAMP
);

DROP TABLE IF EXISTS bronze.crm_sales_details;
CREATE TABLE bronze.crm_sales_details (
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

DROP TABLE IF EXISTS bronze.erp_loc_a101;
CREATE TABLE bronze.erp_loc_a101 (
    cid    STRING,
    cntry  STRING
);

DROP TABLE IF EXISTS bronze.erp_cust_az12;
CREATE TABLE bronze.erp_cust_az12 (
    cid    STRING,
    bdate  DATE,
    gen    STRING
);

DROP TABLE IF EXISTS bronze.erp_px_cat_g1v2;
CREATE TABLE bronze.erp_px_cat_g1v2 (
    id           STRING,
    cat          STRING,
    subcat       STRING,
    maintenance  STRING
);
