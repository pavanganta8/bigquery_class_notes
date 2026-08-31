-- =========================================================================
-- PROCEDURE: silver.load_dim_products                             (BigQuery)
-- DESCRIPTION: Cleanses and loads product records from bronze.products to
--              silver.dim_products. Demonstrates basic sub-block exception
--              handling and an OUT parameter.
--
-- PostgreSQL -> BigQuery notes: see proc_load_dim_customer.sql for the full
--   rationale behind each substitution (REGEXP_CONTAINS, ROW_NUMBER() as a
--   SERIAL replacement, @@row_count, EXCEPTION WHEN ERROR, DELETE ... WHERE
--   TRUE).
-- =========================================================================

CREATE OR REPLACE PROCEDURE silver.load_dim_products(
    IN p_proc_name STRING,
    OUT p_inserted_rows INT64
)
BEGIN
    SET p_inserted_rows = 0;

    BEGIN
        -- Idempotency: clear existing products before the full reload.
        DELETE FROM silver.dim_products WHERE TRUE;

        -- Ingest and clean product records
        INSERT INTO silver.dim_products (product_key, prod_id, prod_name, category, price)
        SELECT
            ROW_NUMBER() OVER (ORDER BY CAST(TRIM(prod_id) AS INT64)) AS product_key,
            CAST(TRIM(prod_id) AS INT64) AS prod_id,
            TRIM(prod_name) AS prod_name,
            TRIM(category) AS category,
            silver.clean_price(price) AS price -- parse formatted currency strings
        FROM bronze.products
        WHERE prod_id IS NOT NULL
          AND REGEXP_CONTAINS(prod_id, r'^[0-9]+$') -- ensure it is a valid integer string
          -- ignore broken rows with non-functional names/categories
          AND prod_name IS NOT NULL AND TRIM(prod_name) != '';

        SET p_inserted_rows = @@row_count;

        -- Log success
        INSERT INTO audit.load_logs (procedure_name, step_name, status, records_loaded)
        VALUES (p_proc_name, 'LOAD_DIM_PRODUCTS', 'SUCCESS', p_inserted_rows);

    EXCEPTION WHEN ERROR THEN
        INSERT INTO audit.load_logs (procedure_name, step_name, status, error_message, error_state)
        VALUES (p_proc_name, 'LOAD_DIM_PRODUCTS', 'FAILED', @@error.message, @@error.formatted_stack_trace);
        SELECT FORMAT('Failed to load dim_products: %s', @@error.message) AS log_message;
    END;
END;
