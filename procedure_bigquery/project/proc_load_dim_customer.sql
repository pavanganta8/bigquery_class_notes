-- =========================================================================
-- PROCEDURE: silver.load_dim_customer                             (BigQuery)
-- DESCRIPTION: Cleanses and loads customer records from bronze.customer to
--              silver.dim_customer. Demonstrates basic sub-block exception
--              handling and an OUT parameter.
--
-- PostgreSQL -> BigQuery notes:
--   - OUT p_inserted_rows INTEGER     -> OUT p_inserted_rows INT64 (BigQuery
--     procedures support OUT/INOUT parameters the same way PL/pgSQL does)
--   - SPLIT_PART(cust_name, ' ', 1)   -> SPLIT(cust_name, ' ')[SAFE_OFFSET(0)]
--     (BigQuery arrays are 0-indexed; SAFE_OFFSET returns NULL instead of
--     erroring when a name has no second "part", e.g. a single-word name)
--   - cust_id ~ '^[0-9]+$'            -> REGEXP_CONTAINS(cust_id, r'^[0-9]+$')
--   - CAST(TRIM(cust_id) AS INTEGER)  -> CAST(TRIM(cust_id) AS INT64)
--   - GET DIAGNOSTICS x = ROW_COUNT   -> SET x = @@row_count
--     (system variable, read immediately after the DML statement it refers to)
--   - No surrogate-key SERIAL column: customer_key is (re)computed with
--     ROW_NUMBER() every load, which is safe here because the table is
--     always fully replaced (DELETE-then-INSERT), never incrementally
--     appended.
--   - EXCEPTION WHEN OTHERS -> EXCEPTION WHEN ERROR
-- =========================================================================

CREATE OR REPLACE PROCEDURE silver.load_dim_customer(
    IN p_proc_name STRING,
    OUT p_inserted_rows INT64
)
BEGIN
    SET p_inserted_rows = 0;

    BEGIN
        -- Idempotency: clear existing customers before the full reload.
        -- BigQuery's DELETE requires a WHERE clause; WHERE TRUE deletes all rows.
        DELETE FROM silver.dim_customer WHERE TRUE;

        -- Ingest and clean customer records
        INSERT INTO silver.dim_customer (customer_key, cust_id, first_name, last_name, email, gender, created_date)
        SELECT
            ROW_NUMBER() OVER (ORDER BY CAST(TRIM(cust_id) AS INT64)) AS customer_key,
            CAST(TRIM(cust_id) AS INT64) AS cust_id,
            TRIM(SPLIT(cust_name, ' ')[SAFE_OFFSET(0)]) AS first_name,
            TRIM(SPLIT(cust_name, ' ')[SAFE_OFFSET(1)]) AS last_name,
            LOWER(TRIM(email)) AS email,
            silver.clean_gender(gender) AS gender,          -- standardizing function
            silver.parse_date_safe(created_date) AS created_date -- flexible date parser
        FROM bronze.customer
        WHERE cust_id IS NOT NULL
          AND REGEXP_CONTAINS(cust_id, r'^[0-9]+$') -- ensure it is a valid integer string
          AND cust_name IS NOT NULL AND TRIM(cust_name) != '';

        SET p_inserted_rows = @@row_count;

        -- Log success
        INSERT INTO audit.load_logs (procedure_name, step_name, status, records_loaded)
        VALUES (p_proc_name, 'LOAD_DIM_CUSTOMER', 'SUCCESS', p_inserted_rows);

    EXCEPTION WHEN ERROR THEN
        -- Log failure
        INSERT INTO audit.load_logs (procedure_name, step_name, status, error_message, error_state)
        VALUES (p_proc_name, 'LOAD_DIM_CUSTOMER', 'FAILED', @@error.message, @@error.formatted_stack_trace);
        SELECT FORMAT('Failed to load dim_customer: %s', @@error.message) AS log_message;
    END;
END;
