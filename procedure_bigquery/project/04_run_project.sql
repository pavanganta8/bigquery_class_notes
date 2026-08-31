-- =========================================================================
-- PROJECT FILE: 04_run_project.sql                                (BigQuery)
-- DESCRIPTION: Educational script demonstrating how to run the entire ETL
--              pipeline, verify table counts, examine load logs, and review
--              the resulting cleansed dimensional model.
-- USAGE:
--   1. Run 01_ddl.sql to create the tables (datasets bronze/silver/audit
--      must already exist -- see the `bq mk --dataset` commands in that
--      file's header).
--   2. Run 02_dml.sql to populate raw bronze data.
--   3. Run all helper functions:
--        - func_clean_gender.sql
--        - func_clean_price.sql
--        - func_parse_date_safe.sql
--   4. Review trigger_update_timestamp.sql (reference only -- BigQuery has
--      no trigger to create; nothing to run).
--   5. Run all modular load procedures:
--        - proc_load_dim_customer.sql
--        - proc_load_dim_products.sql
--        - proc_load_fact_sales.sql
--        - proc_validate_load.sql
--        - proc_print_load_summary.sql
--   6. Run the master orchestrator load procedure:
--        - proc_load_silver_data.sql
--   7. Execute this file to run and inspect the results.
--
-- PostgreSQL -> BigQuery notes:
--   - CALL silver.load_silver_data();  -> identical syntax.
-- =========================================================================

-- =========================================================================
-- STEP 1: Execute the Stored Procedure to Run the ETL Pipeline
-- =========================================================================
SELECT 'Executing silver.load_silver_data()...' AS log_message;
CALL silver.load_silver_data();


-- =========================================================================
-- STEP 2: Query the Audit Log Table to Verify step logs
-- =========================================================================
SELECT
    log_id,
    step_name,
    status,
    records_loaded,
    error_message,
    logged_at
FROM audit.load_logs
ORDER BY logged_at ASC;


-- =========================================================================
-- STEP 3: Review Cleansed Customer Dimension (silver.dim_customer)
-- =========================================================================
-- Notice how names are split, emails are lowercase, gender is standardized,
-- and dates are properly formatted. Note that customer '6' (Invalid Row)
-- is NOT loaded due to invalid name constraints.
SELECT
    customer_key,
    cust_id,
    first_name,
    last_name,
    email,
    gender,
    created_date,
    updated_at
FROM silver.dim_customer;


-- =========================================================================
-- STEP 4: Review Cleansed Product Dimension (silver.dim_products)
-- =========================================================================
-- Notice how prices have had '$' removed and are converted to NUMERIC.
-- Product 106 (Broken Product) with price 'free' is standardized to 0.00.
SELECT
    product_key,
    prod_id,
    prod_name,
    category,
    price,
    updated_at
FROM silver.dim_products;


-- =========================================================================
-- STEP 5: Review Fact Products Sales (silver.fact_products_sales)
-- =========================================================================
-- Observe that surrogate keys (customer_key, product_key) are mapped from
-- dimensions, dates are formatted, and total_price (qty * price) is
-- dynamically computed.
-- Notice that sale_id 5006 was skipped because customer 6 didn't exist in
-- silver -- reported by proc_load_fact_sales.sql's rejected-rows FOR loop.
SELECT
    sale_key,
    sale_id,
    customer_key,
    product_key,
    qty,
    total_price,
    sale_date,
    loaded_at
FROM silver.fact_products_sales;
