-- =========================================================================
-- bronze.sql -- Prepare bronze tables for a Composer-orchestrated load
-- Converted from: PGSQL PROJECT/Scrpit/bronze.txt
-- =========================================================================
-- In PostgreSQL + Airflow, this procedure only truncates: the actual
-- streaming-in of rows happened in a separate Airflow task (the MinIO
-- Python operator). The BigQuery + Composer pipeline keeps exactly the same
-- split of responsibilities:
--   - THIS procedure prepares (truncates) the bronze tables.
--   - dag_gcs_to_bronze.py's GCSToBigQueryOperator tasks stream the CSVs in
--     from GCS afterwards (replacing the old MinIO PythonOperator task).
-- =========================================================================
CREATE OR REPLACE PROCEDURE bronze.dwh_load_crm_erp_bronze()
BEGIN
    -- In Postgres + Airflow, the Procedure only handled prep/post-load
    -- logic; the same is true here in BigQuery + Composer.
    TRUNCATE TABLE bronze.crm_cust_info;
    TRUNCATE TABLE bronze.crm_prd_info;
    TRUNCATE TABLE bronze.crm_sales_details;
    TRUNCATE TABLE bronze.erp_loc_a101;
    TRUNCATE TABLE bronze.erp_px_cat_g1v2;
    TRUNCATE TABLE bronze.erp_cust_az12;

    SELECT 'Bronze tables truncated. Ready for GCSToBigQueryOperator streaming.' AS log_message;
END;
