-- =========================================================================
-- PROCEDURE: silver.validate_load                                 (BigQuery)
-- DESCRIPTION: Runs a loop over the silver tables to verify record counts.
--              Demonstrates the WHILE loop control structure and dynamic SQL.
--
-- PostgreSQL -> BigQuery notes:
--   - WHILE ... LOOP ... END LOOP;   -> WHILE ... DO ... END WHILE;
--   - EXECUTE 'sql' INTO var;         -> EXECUTE IMMEDIATE 'sql' INTO var;
--     (BigQuery's dynamic-SQL statement is named EXECUTE IMMEDIATE, not bare
--     EXECUTE; syntax and purpose are otherwise identical)
-- =========================================================================

CREATE OR REPLACE PROCEDURE silver.validate_load()
BEGIN
    DECLARE v_check_index INT64 DEFAULT 1;
    DECLARE v_check_table STRING;
    DECLARE v_check_count INT64;

    SELECT '--- Post Load Verification checklist ---' AS log_message;

    WHILE v_check_index <= 3 DO
        -- Decide table to check based on loop index
        IF v_check_index = 1 THEN
            SET v_check_table = 'silver.dim_customer';
        ELSEIF v_check_index = 2 THEN
            SET v_check_table = 'silver.dim_products';
        ELSE
            SET v_check_table = 'silver.fact_products_sales';
        END IF;

        -- Dynamic SQL execution to get the count
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || v_check_table INTO v_check_count;

        IF v_check_count = 0 THEN
            SELECT FORMAT('Check Failed: %s has 0 rows!', v_check_table) AS log_message;
        ELSE
            SELECT FORMAT('Check Passed: %s contains %d records.', v_check_table, v_check_count) AS log_message;
        END IF;

        SET v_check_index = v_check_index + 1;
    END WHILE;
END;
