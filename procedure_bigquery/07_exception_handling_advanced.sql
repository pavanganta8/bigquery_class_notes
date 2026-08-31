-- =========================================================================
-- TUTORIAL: Advanced Exception Handling in BigQuery Scripting
-- DESCRIPTION: Nested BEGIN blocks, raising user-defined errors, and reading
--              extended error detail.
-- USAGE: Run the whole block in the BigQuery console Editor tab.
--
-- PostgreSQL -> BigQuery mapping:
--   RAISE EXCEPTION 'msg' USING ERRCODE=.., DETAIL=.., HINT=..;
--       -> RAISE USING MESSAGE = 'msg';
--       BigQuery's RAISE only supports a MESSAGE clause -- there is no
--       ERRCODE/DETAIL/HINT and no custom SQLSTATE registry. Fold whatever
--       you would have put in DETAIL/HINT into the message text itself
--       (FORMAT() is handy for that, shown below).
--   WHEN invalid_parameter_value THEN ...
--       -> WHEN ERROR THEN ...   (BigQuery has exactly one catch-all
--          handler; branch on @@error.message text if you must
--          distinguish cases, as in 05_exception_handling_basic.sql)
--   GET STACKED DIAGNOSTICS v = MESSAGE_TEXT, PG_EXCEPTION_DETAIL, ...
--       -> read @@error.message / @@error.statement_text /
--          @@error.formatted_stack_trace directly, no GET DIAGNOSTICS step
--   PERFORM 10 / 0;    (PostgreSQL: run a query, discard the result)
--       -> BigQuery has no PERFORM statement. Either just execute the
--          expression via SET into a throwaway variable, or (as below)
--          drive the error off a real statement.
-- =========================================================================

BEGIN
    DECLARE v_age INT64 DEFAULT 16; -- Assume the age limit for a course is 18

    BEGIN
        SELECT '--- 1. Raising User-Defined Errors ---' AS log_message;

        -- Check custom validation condition
        IF v_age < 18 THEN
            -- RAISE ... USING MESSAGE is the only form BigQuery supports;
            -- fold what would have been DETAIL/HINT into the text itself.
            RAISE USING MESSAGE = FORMAT(
                'Student is underage for this course. Age provided: %d. '
                || 'Minimum required age: 18. Hint: enroll the student in a '
                || 'junior level course instead.',
                v_age
            );
        END IF;

    EXCEPTION WHEN ERROR THEN
        SELECT 'Caught Custom Exception!' AS log_message;
        -- @@error.message already contains everything RAISE was given --
        -- there is no separate GET STACKED DIAGNOSTICS step in BigQuery.
        SELECT FORMAT('Message: %s', @@error.message) AS log_message;
        SELECT FORMAT('Failing statement text: %s', @@error.statement_text) AS log_message;
    END;
END;


-- -------------------------------------------------------------------------
-- Example 2: Nested Block Exception Handling (Isolating Errors)
-- -------------------------------------------------------------------------
BEGIN
    SELECT '--- 2. Nested Blocks and Isolation ---' AS log_message;

    -- Outer block
    BEGIN
        -- Nested block A: might fail, but we want the outer block to continue
        BEGIN
            -- BigQuery requires all DECLAREs to come first in a block, before
            -- any other statement -- unlike PL/pgSQL's separate DECLARE section,
            -- a nested BEGIN that needs its own variable must declare it here.
            DECLARE v_throwaway FLOAT64;

            SELECT 'Starting Nested Block A...' AS log_message;
            -- Intentional error: division by zero
            SET v_throwaway = 10 / 0;
        EXCEPTION WHEN ERROR THEN
            SELECT 'Nested Block A failed, but the error was caught and handled locally.' AS log_message;
        END;

        -- Nested block B: runs successfully because block A's failure was caught
        BEGIN
            SELECT 'Starting Nested Block B...' AS log_message;
            SELECT 'Nested Block B executed successfully.' AS log_message;
        END;

        SELECT 'Outer block logic continues safely!' AS log_message;
    END;
END;
