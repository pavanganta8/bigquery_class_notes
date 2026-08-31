-- =========================================================================
-- TUTORIAL: WHILE Loops in BigQuery Scripting
-- DESCRIPTION: How to use WHILE loops in BigQuery scripting to execute code
--              repeatedly while a condition remains true.
-- USAGE: Run the whole block in the BigQuery console Editor tab.
--
-- PostgreSQL -> BigQuery mapping:
--   WHILE cond LOOP ... END LOOP;   -> WHILE cond DO ... END WHILE;
--   EXIT WHEN cond;                  -> IF cond THEN LEAVE; END IF;
--                                        (BigQuery has no "EXIT WHEN"
--                                        shorthand -- wrap the break
--                                        condition in an IF + LEAVE)
--   WHILE TRUE LOOP ... END LOOP;   -> LOOP ... END LOOP; is also available
--                                        in BigQuery as a bare infinite loop,
--                                        used in section 2 below.
-- =========================================================================

BEGIN
    DECLARE v_counter INT64 DEFAULT 1;
    DECLARE v_sum     INT64 DEFAULT 0;
    DECLARE v_limit   INT64 DEFAULT 5;

    SELECT '--- 1. Simple WHILE Loop ---' AS log_message;
    -- Runs as long as v_counter is less than or equal to v_limit. As in
    -- PL/pgSQL, you must manually update the loop variable or you get an
    -- infinite loop (BigQuery scripting has no automatic iteration cap).
    WHILE v_counter <= v_limit DO
        SET v_sum = v_sum + v_counter;
        SELECT FORMAT('Counter: %d, Current Cumulative Sum: %d', v_counter, v_sum) AS log_message;

        -- Increment the counter (crucial step!)
        SET v_counter = v_counter + 1;
    END WHILE;

    SELECT FORMAT('Final Sum of numbers from 1 to 5 is: %d', v_sum) AS log_message;

    SELECT '--- 2. Infinite LOOP with LEAVE (EXIT WHEN equivalent) ---' AS log_message;
    -- Resetting values
    SET v_counter = 1;

    -- BigQuery's bare LOOP ... END LOOP runs forever until a LEAVE fires --
    -- the direct equivalent of PL/pgSQL's "WHILE TRUE LOOP".
    LOOP
        SELECT FORMAT('Loop iteration: %d', v_counter) AS log_message;

        -- Exit condition ("EXIT WHEN" has no direct keyword in BigQuery)
        IF v_counter >= 3 THEN
            LEAVE;
        END IF;

        SET v_counter = v_counter + 1;
    END LOOP;
    SELECT FORMAT('Exited infinite loop safely. Final counter value: %d', v_counter) AS log_message;

END;
