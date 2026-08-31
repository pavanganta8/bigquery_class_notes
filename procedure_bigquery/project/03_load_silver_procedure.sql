-- =========================================================================
-- PROJECT FILE: 03_load_silver_procedure.sql                      (BigQuery)
-- DESCRIPTION: Implements the ETL logic to load and cleanse data from
--              bronze to silver as ONE self-contained script -- the same
--              helper functions, "trigger" pattern, and main procedure that
--              live as separate files elsewhere in this folder, combined
--              here to match the layout of the original PostgreSQL tutorial
--              file. Prefer the separate files (func_*.sql, proc_*.sql) for
--              actual reuse; this file is the single-file teaching version.
-- CONCEPTS USED (BigQuery scripting names in brackets):
--   1. Variables & Data Types [DECLARE ... DEFAULT ...]
--   2. IF-ELSE Conditional Logic [IF / ELSEIF / END IF]
--   3. FOR Loop [FOR ... IN (query) DO ... END FOR]
--   4. WHILE Loop [WHILE ... DO ... END WHILE]
--   5. Exceptions [BEGIN ... EXCEPTION WHEN ERROR THEN ... END]
--   6. Cursors -> NOT AVAILABLE in BigQuery; replaced by a set-based JOIN +
--      staged TEMP TABLE (see ../06_cursors.sql and proc_load_fact_sales.sql
--      for the full rationale)
--   7. Functions [CREATE FUNCTION ... AS (single_expression)]
--   8. Triggers -> NOT AVAILABLE in BigQuery; replaced by inline stamping
--      (see ../09_triggers.sql and trigger_update_timestamp.sql)
-- =========================================================================

-- ==========================================
-- A. HELPER FUNCTIONS (Concept 7: Functions)
-- ==========================================

-- 1. Function to clean and standardize gender values
CREATE OR REPLACE FUNCTION silver.clean_gender(p_gender_str STRING)
RETURNS STRING
AS (
    CASE
        WHEN p_gender_str IS NULL THEN 'n/a'
        WHEN LOWER(TRIM(p_gender_str)) IN ('m', 'male') THEN 'Male'
        WHEN LOWER(TRIM(p_gender_str)) IN ('f', 'female') THEN 'Female'
        ELSE 'n/a'
    END
);

-- 2. Function to safely clean currency formatting and parse to numeric
--    (SAFE_CAST replaces the PL/pgSQL nested BEGIN...EXCEPTION fallback)
CREATE OR REPLACE FUNCTION silver.clean_price(p_price_str STRING)
RETURNS NUMERIC
AS (
    CASE
        WHEN p_price_str IS NULL OR TRIM(p_price_str) = '' OR LOWER(TRIM(p_price_str)) = 'free'
            THEN 0.00
        ELSE COALESCE(SAFE_CAST(REPLACE(TRIM(p_price_str), '$', '') AS NUMERIC), 0.00)
    END
);

-- 3. Function to dynamically parse multiple date formats safely
--    (COALESCE of SAFE.PARSE_DATE attempts replaces the triple nested
--    BEGIN...EXCEPTION fallback chain)
CREATE OR REPLACE FUNCTION silver.parse_date_safe(p_date_str STRING)
RETURNS DATE
AS (
    CASE
        WHEN p_date_str IS NULL OR TRIM(p_date_str) = '' THEN NULL
        ELSE COALESCE(
                SAFE.PARSE_DATE('%Y-%m-%d', TRIM(p_date_str)),
                SAFE.PARSE_DATE('%d-%m-%Y', TRIM(p_date_str)),
                SAFE.PARSE_DATE('%Y/%m/%d', TRIM(p_date_str))
             )
    END
);


-- ==========================================
-- B. "TRIGGERS" (Concept 8: no BigQuery equivalent)
-- ==========================================
-- BigQuery has no CREATE TRIGGER / trigger function at all. Because this
-- pipeline always does a full DELETE + INSERT reload (never a bare UPDATE),
-- the `updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()` column defined in
-- 01_ddl.sql already stamps every row on INSERT with no trigger required.
-- See trigger_update_timestamp.sql for the inline-stamping pattern to use
-- if an incremental UPDATE/MERGE path is ever added instead.


-- ===================================================
-- C. MAIN STORED PROCEDURE (Concepts 1-6 integration)
-- ===================================================

CREATE OR REPLACE PROCEDURE silver.load_silver_data()
BEGIN
    -- 1. Variables and Data Types declaration (Concept 1)
    DECLARE v_proc_name      STRING DEFAULT 'silver.load_silver_data';
    DECLARE v_run_start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
    DECLARE v_inserted_rows  INT64 DEFAULT 0;
    DECLARE v_skipped_rows   INT64 DEFAULT 0;

    -- Loop/checklist variables
    DECLARE v_check_index INT64 DEFAULT 1;
    DECLARE v_check_table STRING;
    DECLARE v_check_count INT64;

    SELECT 'Starting ETL pipeline from Bronze to Silver...' AS log_message;

    -- Log pipeline start
    INSERT INTO audit.load_logs (procedure_name, step_name, status, error_message)
    VALUES (v_proc_name, 'START_PIPELINE', 'INFO', 'Pipeline loading sequence initiated.');

    -- =========================================================================
    -- STEP 1: Load Dimension Customer (Uses EXCEPTION sub-block - Concept 5)
    -- =========================================================================
    BEGIN
        SELECT 'Step 1: Loading silver.dim_customer...' AS log_message;

        DELETE FROM silver.dim_customer WHERE TRUE;

        INSERT INTO silver.dim_customer (customer_key, cust_id, first_name, last_name, email, gender, created_date)
        SELECT
            ROW_NUMBER() OVER (ORDER BY CAST(TRIM(cust_id) AS INT64)) AS customer_key,
            CAST(TRIM(cust_id) AS INT64) AS cust_id,
            TRIM(SPLIT(cust_name, ' ')[SAFE_OFFSET(0)]) AS first_name,
            TRIM(SPLIT(cust_name, ' ')[SAFE_OFFSET(1)]) AS last_name,
            LOWER(TRIM(email)) AS email,
            silver.clean_gender(gender) AS gender,
            silver.parse_date_safe(created_date) AS created_date
        FROM bronze.customer
        WHERE cust_id IS NOT NULL
          AND REGEXP_CONTAINS(cust_id, r'^[0-9]+$')
          AND cust_name IS NOT NULL AND TRIM(cust_name) != '';

        SET v_inserted_rows = @@row_count;

        INSERT INTO audit.load_logs (procedure_name, step_name, status, records_loaded)
        VALUES (v_proc_name, 'LOAD_DIM_CUSTOMER', 'SUCCESS', v_inserted_rows);

    EXCEPTION WHEN ERROR THEN
        -- Handles errors locally without stopping the remaining steps (Concept 5)
        INSERT INTO audit.load_logs (procedure_name, step_name, status, error_message, error_state)
        VALUES (v_proc_name, 'LOAD_DIM_CUSTOMER', 'FAILED', @@error.message, @@error.formatted_stack_trace);
        SELECT FORMAT('Failed to load dim_customer: %s', @@error.message) AS log_message;
    END;


    -- =========================================================================
    -- STEP 2: Load Dimension Products (Uses EXCEPTION sub-block - Concept 5)
    -- =========================================================================
    BEGIN
        SELECT 'Step 2: Loading silver.dim_products...' AS log_message;

        DELETE FROM silver.dim_products WHERE TRUE;

        INSERT INTO silver.dim_products (product_key, prod_id, prod_name, category, price)
        SELECT
            ROW_NUMBER() OVER (ORDER BY CAST(TRIM(prod_id) AS INT64)) AS product_key,
            CAST(TRIM(prod_id) AS INT64) AS prod_id,
            TRIM(prod_name) AS prod_name,
            TRIM(category) AS category,
            silver.clean_price(price) AS price
        FROM bronze.products
        WHERE prod_id IS NOT NULL
          AND REGEXP_CONTAINS(prod_id, r'^[0-9]+$')
          AND prod_name IS NOT NULL AND TRIM(prod_name) != '';

        SET v_inserted_rows = @@row_count;

        INSERT INTO audit.load_logs (procedure_name, step_name, status, records_loaded)
        VALUES (v_proc_name, 'LOAD_DIM_PRODUCTS', 'SUCCESS', v_inserted_rows);

    EXCEPTION WHEN ERROR THEN
        INSERT INTO audit.load_logs (procedure_name, step_name, status, error_message, error_state)
        VALUES (v_proc_name, 'LOAD_DIM_PRODUCTS', 'FAILED', @@error.message, @@error.formatted_stack_trace);
        SELECT FORMAT('Failed to load dim_products: %s', @@error.message) AS log_message;
    END;


    -- =========================================================================
    -- STEP 3: Load Fact Product Sales
    -- (Cursor in PostgreSQL -> set-based JOIN + FOR loop in BigQuery - Concept 6, 2, 5, 3)
    -- =========================================================================
    BEGIN
        SELECT 'Step 3: Loading silver.fact_products_sales...' AS log_message;

        DELETE FROM silver.fact_products_sales WHERE TRUE;
        SET v_inserted_rows = 0;
        SET v_skipped_rows = 0;

        -- Resolve every row's lookups/parsing in one JOIN pass (replaces the
        -- cursor's per-row FETCH + two lookup SELECTs).
        CREATE TEMP TABLE _staged_sales AS
        SELECT
            CAST(TRIM(s.sale_id) AS INT64)     AS sale_id,
            cu.customer_key,
            pr.product_key,
            pr.price                           AS unit_price,
            SAFE_CAST(TRIM(s.qty) AS INT64)     AS qty,
            silver.parse_date_safe(s.sale_date) AS sale_date,
            s.cust_id                          AS raw_cust_id,
            s.prod_id                          AS raw_prod_id,
            s.qty                              AS raw_qty,
            s.sale_date                        AS raw_sale_date
        FROM bronze.sales s
        LEFT JOIN silver.dim_customer cu ON cu.cust_id = SAFE_CAST(TRIM(s.cust_id) AS INT64)
        LEFT JOIN silver.dim_products pr ON pr.prod_id = SAFE_CAST(TRIM(s.prod_id) AS INT64);

        -- IF-ELSE validation (Concept 2), applied set-wide via WHERE instead
        -- of once per cursor row.
        INSERT INTO silver.fact_products_sales (sale_key, sale_id, customer_key, product_key, qty, total_price, sale_date)
        SELECT
            ROW_NUMBER() OVER (ORDER BY sale_id) AS sale_key,
            sale_id, customer_key, product_key, qty,
            qty * unit_price AS total_price,
            sale_date
        FROM _staged_sales
        WHERE customer_key IS NOT NULL
          AND product_key IS NOT NULL
          AND qty IS NOT NULL AND qty > 0
          AND sale_date IS NOT NULL;

        SET v_inserted_rows = @@row_count;

        -- FOR loop over just the rejected rows (Concept 3), reproducing the
        -- cursor loop's per-row RAISE WARNING skip messages.
        FOR skip_reason IN (
            SELECT
                sale_id,
                CASE
                    WHEN customer_key IS NULL THEN FORMAT('Customer ID %s does not exist in silver.dim_customer', raw_cust_id)
                    WHEN product_key IS NULL THEN FORMAT('Product ID %s does not exist in silver.dim_products', raw_prod_id)
                    WHEN qty IS NULL OR qty <= 0 THEN FORMAT('Invalid quantity value (%s)', raw_qty)
                    WHEN sale_date IS NULL THEN FORMAT('Invalid sale date value (%s)', raw_sale_date)
                END AS reason
            FROM _staged_sales
            WHERE customer_key IS NULL OR product_key IS NULL
               OR qty IS NULL OR qty <= 0 OR sale_date IS NULL
        )
        DO
            SET v_skipped_rows = v_skipped_rows + 1;
            SELECT FORMAT('Skipping sale_id %d: %s', skip_reason.sale_id, skip_reason.reason) AS log_message;
        END FOR;

        DROP TABLE _staged_sales;

        INSERT INTO audit.load_logs (procedure_name, step_name, status, records_loaded)
        VALUES (v_proc_name, 'LOAD_FACT_SALES', 'SUCCESS', v_inserted_rows);

    EXCEPTION WHEN ERROR THEN
        INSERT INTO audit.load_logs (procedure_name, step_name, status, error_message, error_state)
        VALUES (v_proc_name, 'LOAD_FACT_SALES', 'FAILED', @@error.message, @@error.formatted_stack_trace);
        SELECT FORMAT('Failed to load fact_sales: %s', @@error.message) AS log_message;
    END;


    -- =========================================================================
    -- STEP 4: Post-Load Table Validation checklist (Concept 4: WHILE Loop)
    -- =========================================================================
    SELECT '--- Post Load Verification checklist ---' AS log_message;
    SET v_check_index = 1;

    WHILE v_check_index <= 3 DO
        IF v_check_index = 1 THEN
            SET v_check_table = 'silver.dim_customer';
        ELSEIF v_check_index = 2 THEN
            SET v_check_table = 'silver.dim_products';
        ELSE
            SET v_check_table = 'silver.fact_products_sales';
        END IF;

        -- Dynamic SQL to count rows in the current table
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || v_check_table INTO v_check_count;

        IF v_check_count = 0 THEN
            SELECT FORMAT('Check Failed: %s has 0 rows!', v_check_table) AS log_message;
        ELSE
            SELECT FORMAT('Check Passed: %s contains %d records.', v_check_table, v_check_count) AS log_message;
        END IF;

        SET v_check_index = v_check_index + 1;
    END WHILE;


    -- =========================================================================
    -- STEP 5: Print Summary Report of Load Logs (Concept 3: FOR Loop)
    -- =========================================================================
    SELECT '==================================================' AS log_message
    UNION ALL SELECT 'ETL COMPLETED. CURRENT PIPELINE EXECUTION SUMMARY:'
    UNION ALL SELECT '==================================================';

    FOR v_log_record IN (
        SELECT step_name, status, records_loaded, error_message
        FROM audit.load_logs
        WHERE logged_at >= v_run_start_time
        ORDER BY logged_at ASC
    )
    DO
        IF v_log_record.status = 'SUCCESS' THEN
            SELECT FORMAT('>> STEP: %s | STATUS: %s | RECORDS LOADED: %d',
                           RPAD(v_log_record.step_name, 22, ' '),
                           v_log_record.status,
                           v_log_record.records_loaded) AS log_message;
        ELSEIF v_log_record.status = 'FAILED' THEN
            SELECT FORMAT('>> STEP: %s | STATUS: %s | ERROR: %s',
                           RPAD(v_log_record.step_name, 22, ' '),
                           v_log_record.status,
                           v_log_record.error_message) AS log_message;
        ELSE
            SELECT FORMAT('>> STEP: %s | STATUS: %s | %s',
                           RPAD(v_log_record.step_name, 22, ' '),
                           v_log_record.status,
                           v_log_record.error_message) AS log_message;
        END IF;
    END FOR;

    SELECT '==================================================' AS log_message;

END;
