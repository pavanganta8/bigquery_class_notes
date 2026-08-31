-- =========================================================================
-- PROCEDURE: silver.load_silver_data                              (BigQuery)
-- DESCRIPTION: Master orchestrator procedure. Sequentially triggers
--              individual cleanse procedures, runs count validations, and
--              prints summaries.
-- CONCEPTS SHOWN: Main orchestration, variable declaration, sub-block
--                 exceptions, OUT-parameter procedure calls.
--
-- PostgreSQL -> BigQuery notes:
--   - CALL silver.load_dim_customer(v_proc_name, v_inserted_rows);  is
--     identical syntax in BigQuery -- CALL works the same way, including
--     passing a variable positionally to receive an OUT parameter.
--   - CONSTANT keyword -> not available; v_proc_name is declared once and
--     never reassigned by convention (see 01_variables_and_datatypes.sql).
-- =========================================================================

CREATE OR REPLACE PROCEDURE silver.load_silver_data()
BEGIN
    DECLARE v_proc_name      STRING DEFAULT 'silver.load_silver_data';
    DECLARE v_run_start_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP();
    DECLARE v_inserted_rows  INT64 DEFAULT 0;

    SELECT 'Starting Orchestrated ETL pipeline from Bronze to Silver...' AS log_message;

    -- Log pipeline start
    INSERT INTO audit.load_logs (procedure_name, step_name, status, error_message)
    VALUES (v_proc_name, 'START_PIPELINE', 'INFO', 'Pipeline loading sequence initiated.');

    -- =========================================================================
    -- STEP 1: Load Dimension Customer (Isolating Exceptions)
    -- =========================================================================
    BEGIN
        CALL silver.load_dim_customer(v_proc_name, v_inserted_rows);
    EXCEPTION WHEN ERROR THEN
        INSERT INTO audit.load_logs (procedure_name, step_name, status, error_message, error_state)
        VALUES (v_proc_name, 'LOAD_DIM_CUSTOMER_ORCHESTRATOR', 'FAILED', @@error.message, @@error.formatted_stack_trace);
        SELECT FORMAT('Master orchestrator caught dim_customer failure: %s', @@error.message) AS log_message;
    END;

    -- =========================================================================
    -- STEP 2: Load Dimension Products (Isolating Exceptions)
    -- =========================================================================
    BEGIN
        CALL silver.load_dim_products(v_proc_name, v_inserted_rows);
    EXCEPTION WHEN ERROR THEN
        INSERT INTO audit.load_logs (procedure_name, step_name, status, error_message, error_state)
        VALUES (v_proc_name, 'LOAD_DIM_PRODUCTS_ORCHESTRATOR', 'FAILED', @@error.message, @@error.formatted_stack_trace);
        SELECT FORMAT('Master orchestrator caught dim_products failure: %s', @@error.message) AS log_message;
    END;

    -- =========================================================================
    -- STEP 3: Load Fact Product Sales (Isolating Exceptions)
    -- =========================================================================
    BEGIN
        CALL silver.load_fact_sales(v_proc_name, v_inserted_rows);
    EXCEPTION WHEN ERROR THEN
        INSERT INTO audit.load_logs (procedure_name, step_name, status, error_message, error_state)
        VALUES (v_proc_name, 'LOAD_FACT_SALES_ORCHESTRATOR', 'FAILED', @@error.message, @@error.formatted_stack_trace);
        SELECT FORMAT('Master orchestrator caught fact_sales failure: %s', @@error.message) AS log_message;
    END;

    -- =========================================================================
    -- STEP 4: Post-Load Table Validation (WHILE Loop Procedure)
    -- =========================================================================
    BEGIN
        CALL silver.validate_load();
    EXCEPTION WHEN ERROR THEN
        SELECT FORMAT('Validation execution encountered error: %s', @@error.message) AS log_message;
    END;

    -- =========================================================================
    -- STEP 5: Final Report Printing (FOR Loop Procedure)
    -- =========================================================================
    BEGIN
        CALL silver.print_load_summary(v_run_start_time);
    EXCEPTION WHEN ERROR THEN
        SELECT FORMAT('Report generation encountered error: %s', @@error.message) AS log_message;
    END;

END;
