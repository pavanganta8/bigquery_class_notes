-- =========================================================================
-- TUTORIAL: Basic Exception Handling in BigQuery Scripting
-- DESCRIPTION: How to catch runtime errors using BEGIN ... EXCEPTION WHEN
--              ERROR THEN ... END, preventing the whole script from failing.
-- USAGE: Run the whole block in the BigQuery console Editor tab.
--
-- PostgreSQL -> BigQuery mapping:
--   EXCEPTION WHEN division_by_zero THEN ...   -> BigQuery has no named
--       exception classes at all (no division_by_zero, no unique_violation,
--       etc). There is exactly ONE catch-all handler per BEGIN block:
--       "EXCEPTION WHEN ERROR THEN". Branch on the error text yourself
--       (see example 1) if you need different handling per failure type.
--   SQLSTATE / SQLERRM                          -> @@error.message,
--       @@error.statement_text, @@error.formatted_stack_trace
--       (system variables, only readable inside an EXCEPTION block)
--   1 / 0 integer division                      -> BigQuery INT64 "/" always
--       returns a FLOAT64 and 10/0 raises an error just like Postgres,
--       so the demo below still works unmodified.
-- =========================================================================

BEGIN
    DECLARE v_numerator   INT64 DEFAULT 10;
    DECLARE v_denominator INT64 DEFAULT 0; -- Will cause a division-by-zero error
    DECLARE v_result      FLOAT64;

    BEGIN
        SELECT '--- 1. Attempting division by zero ---' AS log_message;

        -- The following statement raises a runtime error
        SET v_result = v_numerator / v_denominator;

        -- This line will not run: control jumps straight to EXCEPTION
        SELECT FORMAT('Result: %f', v_result) AS log_message;

    EXCEPTION WHEN ERROR THEN
        -- BigQuery has only one catch-all handler; inspect the message text
        -- to tell error types apart (there is no `division_by_zero` class).
        IF STRPOS(@@error.message, 'division by zero') > 0 THEN
            SELECT 'An error occurred: Cannot divide by zero!' AS log_message;
            SET v_result = 0; -- Provide a fallback/default value
            SELECT FORMAT('Handled exception. Assigned fallback result: %f', v_result) AS log_message;
        ELSE
            SELECT 'An unexpected error occurred.' AS log_message;
        END IF;
    END;
END;


-- -------------------------------------------------------------------------
-- Example 2: Accessing system error details (@@error.* system variables)
-- -------------------------------------------------------------------------
BEGIN
    DECLARE v_number INT64;

    BEGIN
        SELECT '--- 2. Retrieving Error Details ---' AS log_message;

        -- Attempting to cast a non-numeric string to INT64.
        -- (PostgreSQL's `::INTEGER` cast     -> BigQuery's `CAST(... AS INT64)`;
        --  a hard CAST still raises on bad input, same as Postgres. Use
        --  SAFE_CAST instead if you want NULL-on-failure -- see 08_functions.sql.)
        SET v_number = CAST('NotANumber' AS INT64);

    EXCEPTION WHEN ERROR THEN
        -- @@error.message is the BigQuery analog of SQLERRM.
        -- BigQuery has no SQLSTATE 5-char code; @@error.statement_text and
        -- @@error.formatted_stack_trace give you the equivalent diagnostic
        -- detail instead.
        SELECT FORMAT('Error Message (@@error.message): %s', @@error.message) AS log_message;
        SELECT FORMAT('Failing Statement (@@error.statement_text): %s', @@error.statement_text) AS log_message;
    END;
END;
