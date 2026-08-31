/*
===============================================================================
Stored Procedure: Load Bronze Layer (GCS -> Bronze)                (BigQuery)
===============================================================================
PostgreSQL -> BigQuery conversion notes:
    - "CREATE OR REPLACE PROCEDURE ... LANGUAGE plpgsql AS $$ ... $$;"
       becomes "CREATE OR REPLACE PROCEDURE ... BEGIN ... END;"
       (BigQuery scripting, no LANGUAGE clause, no $$ delimiters).
    - "DECLARE x TIMESTAMP;" at the top of the block -> same DECLARE syntax,
      but BigQuery requires DECLAREs to come first inside the BEGIN block.
    - clock_timestamp() -> CURRENT_TIMESTAMP()
    - EXTRACT(EPOCH FROM (end - start))  -> TIMESTAMP_DIFF(end, start, SECOND)
    - RAISE NOTICE '...'                 -> BigQuery scripting has no NOTICE/
      PRINT statement. We SELECT the message as a one-row result set, which
      shows up in the BigQuery job "Results" tab (Console/`bq query`) and is
      also what Cloud Composer captures in the task log when the SQL runs via
      BigQueryInsertJobOperator. For a durable audit trail (recommended for
      anything scheduled), see bronze.load_audit_log used in
      `BIGQUERY PROJECT/Scrpit/DDL.sql` and `procedure_bigquery/project/`.
    - The Postgres COPY ... FROM 'local file path' statement has no BigQuery
      equivalent (BigQuery cannot read the Cloud Composer worker's local
      disk). The source CSVs must first live in Cloud Storage (GCS), then be
      loaded with the BigQuery DDL statement `LOAD DATA ... FROM FILES(...)`,
      which is what replaces COPY below. See `gcs_load/` for the GCS folder
      layout and the equivalent `bq load` CLI commands.
    - EXCEPTION WHEN OTHERS -> EXCEPTION WHEN ERROR (BigQuery only has one
      catch-all error handler per BEGIN block).
    - SQLERRM / SQLSTATE -> @@error.message / @@error.formatted_stack_trace
===============================================================================
*/
CREATE OR REPLACE PROCEDURE bronze.load_bronze()
BEGIN
    DECLARE start_time, end_time, batch_start_time, batch_end_time TIMESTAMP;

    BEGIN
        SET batch_start_time = CURRENT_TIMESTAMP();
        SELECT '================================================' AS log_message
        UNION ALL SELECT 'Loading Bronze Layer'
        UNION ALL SELECT '================================================'
        UNION ALL SELECT '------------------------------------------------'
        UNION ALL SELECT 'Loading CRM Tables'
        UNION ALL SELECT '------------------------------------------------';

        -- ---------------------------------------------------------------
        -- bronze.crm_cust_info
        -- ---------------------------------------------------------------
        SET start_time = CURRENT_TIMESTAMP();
        TRUNCATE TABLE bronze.crm_cust_info;
        LOAD DATA OVERWRITE bronze.crm_cust_info
        FROM FILES (
            format = 'CSV',
            skip_leading_rows = 1,
            uris = ['gs://your-bucket/datasets/source_crm/cust_info.csv']
        );
        SET end_time = CURRENT_TIMESTAMP();
        SELECT FORMAT('>> Loaded bronze.crm_cust_info in %d seconds',
                       TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS log_message;

        -- ---------------------------------------------------------------
        -- bronze.crm_prd_info
        -- ---------------------------------------------------------------
        SET start_time = CURRENT_TIMESTAMP();
        TRUNCATE TABLE bronze.crm_prd_info;
        LOAD DATA OVERWRITE bronze.crm_prd_info
        FROM FILES (
            format = 'CSV',
            skip_leading_rows = 1,
            uris = ['gs://your-bucket/datasets/source_crm/prd_info.csv']
        );
        SET end_time = CURRENT_TIMESTAMP();
        SELECT FORMAT('>> Loaded bronze.crm_prd_info in %d seconds',
                       TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS log_message;

        -- ---------------------------------------------------------------
        -- bronze.crm_sales_details
        -- ---------------------------------------------------------------
        SET start_time = CURRENT_TIMESTAMP();
        TRUNCATE TABLE bronze.crm_sales_details;
        LOAD DATA OVERWRITE bronze.crm_sales_details
        FROM FILES (
            format = 'CSV',
            skip_leading_rows = 1,
            uris = ['gs://your-bucket/datasets/source_crm/sales_details.csv']
        );
        SET end_time = CURRENT_TIMESTAMP();
        SELECT FORMAT('>> Loaded bronze.crm_sales_details in %d seconds',
                       TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS log_message;

        SELECT '------------------------------------------------' AS log_message
        UNION ALL SELECT 'Loading ERP Tables'
        UNION ALL SELECT '------------------------------------------------';

        -- ---------------------------------------------------------------
        -- bronze.erp_loc_a101
        -- ---------------------------------------------------------------
        SET start_time = CURRENT_TIMESTAMP();
        TRUNCATE TABLE bronze.erp_loc_a101;
        LOAD DATA OVERWRITE bronze.erp_loc_a101
        FROM FILES (
            format = 'CSV',
            skip_leading_rows = 1,
            uris = ['gs://your-bucket/datasets/source_erp/LOC_A101.csv']
        );
        SET end_time = CURRENT_TIMESTAMP();
        SELECT FORMAT('>> Loaded bronze.erp_loc_a101 in %d seconds',
                       TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS log_message;

        -- ---------------------------------------------------------------
        -- bronze.erp_cust_az12
        -- ---------------------------------------------------------------
        SET start_time = CURRENT_TIMESTAMP();
        TRUNCATE TABLE bronze.erp_cust_az12;
        LOAD DATA OVERWRITE bronze.erp_cust_az12
        FROM FILES (
            format = 'CSV',
            skip_leading_rows = 1,
            uris = ['gs://your-bucket/datasets/source_erp/CUST_AZ12.csv']
        );
        SET end_time = CURRENT_TIMESTAMP();
        SELECT FORMAT('>> Loaded bronze.erp_cust_az12 in %d seconds',
                       TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS log_message;

        -- ---------------------------------------------------------------
        -- bronze.erp_px_cat_g1v2
        -- ---------------------------------------------------------------
        SET start_time = CURRENT_TIMESTAMP();
        TRUNCATE TABLE bronze.erp_px_cat_g1v2;
        LOAD DATA OVERWRITE bronze.erp_px_cat_g1v2
        FROM FILES (
            format = 'CSV',
            skip_leading_rows = 1,
            uris = ['gs://your-bucket/datasets/source_erp/PX_CAT_G1V2.csv']
        );
        SET end_time = CURRENT_TIMESTAMP();
        SELECT FORMAT('>> Loaded bronze.erp_px_cat_g1v2 in %d seconds',
                       TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS log_message;

        SET batch_end_time = CURRENT_TIMESTAMP();
        SELECT '==========================================' AS log_message
        UNION ALL SELECT 'Loading Bronze Layer is Completed'
        UNION ALL SELECT FORMAT('   - Total Load Duration: %d seconds',
                                 TIMESTAMP_DIFF(batch_end_time, batch_start_time, SECOND))
        UNION ALL SELECT '==========================================';

    EXCEPTION WHEN ERROR THEN
        SELECT '==========================================' AS log_message
        UNION ALL SELECT 'ERROR OCCURRED DURING LOADING BRONZE LAYER'
        UNION ALL SELECT FORMAT('Error Message: %s', @@error.message)
        UNION ALL SELECT '==========================================';
        RAISE USING MESSAGE = @@error.message;
    END;
END;
