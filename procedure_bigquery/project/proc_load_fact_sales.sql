-- =========================================================================
-- PROCEDURE: silver.load_fact_sales                               (BigQuery)
-- DESCRIPTION: Loads and maps fact sales from bronze.sales to
--              silver.fact_products_sales.
--
-- *** THIS IS THE KEY CURSOR -> SET-BASED REWRITE ***
-- The PostgreSQL original (procedure_pgsql/project/proc_load_fact_sales.sql)
-- OPENs a cursor over bronze.sales and, for every single row, runs two
-- lookup SELECTs (customer, product), a safe-cast of qty, a date parse, and
-- an IF/ELSIF validation chain before deciding whether to INSERT. BigQuery
-- has NO cursor object (see ../06_cursors.sql) and row-by-row processing
-- would be extremely slow on a columnar engine anyway, so the whole loop
-- body is rewritten as:
--   1. one JOIN pass that resolves every row's customer_key/product_key/
--      cleaned qty/parsed date at once (replaces the two per-row lookup
--      SELECTs + the cast/parse calls), staged into a TEMP TABLE,
--   2. one set-based INSERT ... SELECT ... WHERE that keeps only the rows
--      passing every validation the IF/ELSIF chain used to check (replaces
--      the per-row branch-and-insert),
--   3. one FOR loop over just the *rejected* rows, to reproduce the
--      cursor's per-row RAISE WARNING skip messages without re-processing
--      every accepted row one at a time.
--
-- Other PostgreSQL -> BigQuery notes:
--   - OUT p_inserted_rows INTEGER -> OUT p_inserted_rows INT64
--   - No sale_key SERIAL column -> ROW_NUMBER() at insert time (safe here:
--     full DELETE-then-INSERT reload, never incremental)
--   - EXCEPTION WHEN OTHERS -> EXCEPTION WHEN ERROR
-- =========================================================================

CREATE OR REPLACE PROCEDURE silver.load_fact_sales(
    IN p_proc_name STRING,
    OUT p_inserted_rows INT64
)
BEGIN
    DECLARE v_skipped_rows INT64 DEFAULT 0;

    BEGIN
        SET p_inserted_rows = 0;

        -- Idempotency: clear existing sales before the full reload.
        DELETE FROM silver.fact_products_sales WHERE TRUE;

        -- Step 1: resolve every row's lookups/parsing in one JOIN pass --
        -- this replaces the cursor's two per-row lookup SELECTs plus the
        -- per-row qty cast and date parse.
        CREATE TEMP TABLE _staged_sales AS
        SELECT
            CAST(TRIM(s.sale_id) AS INT64)        AS sale_id,
            cu.customer_key,
            pr.product_key,
            pr.price                              AS unit_price,
            SAFE_CAST(TRIM(s.qty) AS INT64)        AS qty,
            silver.parse_date_safe(s.sale_date)    AS sale_date,
            s.cust_id                              AS raw_cust_id,
            s.prod_id                              AS raw_prod_id,
            s.qty                                  AS raw_qty,
            s.sale_date                            AS raw_sale_date
        FROM bronze.sales s
        LEFT JOIN silver.dim_customer cu ON cu.cust_id = SAFE_CAST(TRIM(s.cust_id) AS INT64)
        LEFT JOIN silver.dim_products pr ON pr.prod_id = SAFE_CAST(TRIM(s.prod_id) AS INT64);

        -- Step 2: single set-based INSERT, equivalent to the cursor loop's
        -- ELSE branch (all validations passed).
        INSERT INTO silver.fact_products_sales (
            sale_key, sale_id, customer_key, product_key, qty, total_price, sale_date
        )
        SELECT
            ROW_NUMBER() OVER (ORDER BY sale_id) AS sale_key,
            sale_id,
            customer_key,
            product_key,
            qty,
            qty * unit_price AS total_price,
            sale_date
        FROM _staged_sales
        WHERE customer_key IS NOT NULL
          AND product_key IS NOT NULL
          AND qty IS NOT NULL AND qty > 0
          AND sale_date IS NOT NULL;

        SET p_inserted_rows = @@row_count;

        -- Step 3: report the rejected rows -- the set-based replacement for
        -- the cursor loop's per-row RAISE WARNING calls. Only rows that
        -- failed validation are iterated here (typically a small subset),
        -- not the whole table.
        FOR skip_reason IN (
            SELECT
                sale_id,
                CASE
                    WHEN customer_key IS NULL
                        THEN FORMAT('Customer ID %s does not exist in silver.dim_customer', raw_cust_id)
                    WHEN product_key IS NULL
                        THEN FORMAT('Product ID %s does not exist in silver.dim_products', raw_prod_id)
                    WHEN qty IS NULL OR qty <= 0
                        THEN FORMAT('Invalid quantity value (%s)', raw_qty)
                    WHEN sale_date IS NULL
                        THEN FORMAT('Invalid sale date value (%s)', raw_sale_date)
                END AS reason
            FROM _staged_sales
            WHERE customer_key IS NULL
               OR product_key IS NULL
               OR qty IS NULL OR qty <= 0
               OR sale_date IS NULL
        )
        DO
            SET v_skipped_rows = v_skipped_rows + 1;
            SELECT FORMAT('Skipping sale_id %d: %s', skip_reason.sale_id, skip_reason.reason) AS log_message;
        END FOR;

        DROP TABLE _staged_sales;

        -- Log success
        INSERT INTO audit.load_logs (procedure_name, step_name, status, records_loaded)
        VALUES (p_proc_name, 'LOAD_FACT_SALES', 'SUCCESS', p_inserted_rows);

    EXCEPTION WHEN ERROR THEN
        INSERT INTO audit.load_logs (procedure_name, step_name, status, error_message, error_state)
        VALUES (p_proc_name, 'LOAD_FACT_SALES', 'FAILED', @@error.message, @@error.formatted_stack_trace);
        SELECT FORMAT('Failed to load fact_sales: %s', @@error.message) AS log_message;
    END;
END;
