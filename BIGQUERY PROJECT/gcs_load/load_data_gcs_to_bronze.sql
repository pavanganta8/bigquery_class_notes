/*
===============================================================================
LOAD DATA statements: GCS -> bronze                                (BigQuery)
===============================================================================
This is the BigQuery DDL equivalent of the PostgreSQL:

    COPY bronze.crm_cust_info
    FROM 'C:\sql\dwh_project\datasets\source_crm\cust_info.csv'
    WITH (FORMAT csv, HEADER true);

`LOAD DATA` is a real SQL statement (not a client-side command like psql's
`\copy`), so it can be run from the BigQuery console, `bq query`, or inside a
Cloud Composer `BigQueryInsertJobOperator`/`BigQueryInsertJobOperator` task.

Replace `gs://your-bucket/...` with your actual bucket + path before running.
`OVERWRITE` matches the PostgreSQL "TRUNCATE then COPY" pattern used in
bronze/proc_load_bronze.sql; use `LOAD DATA INTO` (no OVERWRITE) to append
instead of replace.
===============================================================================
*/

LOAD DATA OVERWRITE bronze.crm_cust_info
FROM FILES (
    format = 'CSV',
    skip_leading_rows = 1,
    uris = ['gs://your-bucket/datasets/source_crm/cust_info.csv']
);

LOAD DATA OVERWRITE bronze.crm_prd_info
FROM FILES (
    format = 'CSV',
    skip_leading_rows = 1,
    uris = ['gs://your-bucket/datasets/source_crm/prd_info.csv']
);

LOAD DATA OVERWRITE bronze.crm_sales_details
FROM FILES (
    format = 'CSV',
    skip_leading_rows = 1,
    uris = ['gs://your-bucket/datasets/source_crm/sales_details.csv']
);

LOAD DATA OVERWRITE bronze.erp_loc_a101
FROM FILES (
    format = 'CSV',
    skip_leading_rows = 1,
    uris = ['gs://your-bucket/datasets/source_erp/LOC_A101.csv']
);

LOAD DATA OVERWRITE bronze.erp_cust_az12
FROM FILES (
    format = 'CSV',
    skip_leading_rows = 1,
    uris = ['gs://your-bucket/datasets/source_erp/CUST_AZ12.csv']
);

LOAD DATA OVERWRITE bronze.erp_px_cat_g1v2
FROM FILES (
    format = 'CSV',
    skip_leading_rows = 1,
    uris = ['gs://your-bucket/datasets/source_erp/PX_CAT_G1V2.csv']
);
