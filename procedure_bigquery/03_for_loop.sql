-- =========================================================================
-- TUTORIAL: FOR Loops in BigQuery Scripting
-- DESCRIPTION: BigQuery's FOR loop only iterates over the rows of a query
--              (there is no native "FOR i IN 1..5" integer-range loop like
--              PL/pgSQL's). We recreate ranges with GENERATE_ARRAY() +
--              UNNEST(), which is the idiomatic BigQuery substitute.
-- USAGE: Run the whole block in the BigQuery console Editor tab.
--
-- PostgreSQL -> BigQuery mapping:
--   FOR i IN 1..5 LOOP ... END LOOP;
--       -> FOR rec IN (SELECT i FROM UNNEST(GENERATE_ARRAY(1,5)) AS i) DO ... END FOR;
--   FOR i IN REVERSE 5..1 LOOP ... END LOOP;
--       -> GENERATE_ARRAY(5,1,-1)  (explicit -1 step walks it backwards)
--   FOR i IN 1..10 BY 2 LOOP ... END LOOP;
--       -> GENERATE_ARRAY(1,10,2) (3rd argument is the step)
--   CONTINUE / EXIT                 -> ITERATE / LEAVE (BigQuery keywords)
--   FOR v_row IN (SELECT ...) LOOP  -> FOR v_row IN (SELECT ...) DO ... END FOR;
-- =========================================================================

BEGIN
    SELECT '--- 1. Simple FOR Loop (1 to 5) ---' AS log_message;
    -- The loop variable's column is named "i" by the UNNEST alias below,
    -- and is accessed as rec.i inside the loop body.
    FOR rec IN (SELECT i FROM UNNEST(GENERATE_ARRAY(1, 5)) AS i)
    DO
        SELECT FORMAT('Iteration: %d', rec.i) AS log_message;
    END FOR;

    SELECT '--- 2. Reverse FOR Loop (5 down to 1) ---' AS log_message;
    -- GENERATE_ARRAY(start, stop, step) with a negative step walks backwards.
    FOR rec IN (SELECT i FROM UNNEST(GENERATE_ARRAY(5, 1, -1)) AS i)
    DO
        SELECT FORMAT('Reverse Iteration: %d', rec.i) AS log_message;
    END FOR;

    SELECT '--- 3. FOR Loop with Step Increment (BY 2) ---' AS log_message;
    FOR rec IN (SELECT i FROM UNNEST(GENERATE_ARRAY(1, 10, 2)) AS i)
    DO
        SELECT FORMAT('Step Iteration (BY 2): %d', rec.i) AS log_message;
    END FOR;

    SELECT '--- 4. FOR Loop control (LEAVE/ITERATE == EXIT/CONTINUE) ---' AS log_message;
    -- Loop 1 to 10 but skip 5, and terminate loop at 8.
    -- BigQuery loops can optionally be labelled; a label lets LEAVE/ITERATE
    -- target a specific (possibly outer) loop, similar to PL/pgSQL's
    -- labelled loops (<<my_loop>> LOOP ... EXIT my_loop; ... END LOOP;).
    demo_loop: FOR rec IN (SELECT i FROM UNNEST(GENERATE_ARRAY(1, 10)) AS i)
    DO
        IF rec.i = 5 THEN
            SELECT FORMAT('Skipping number %d using ITERATE', rec.i) AS log_message;
            ITERATE demo_loop; -- Skips the rest of the current iteration
        END IF;

        IF rec.i = 8 THEN
            SELECT FORMAT('Exiting loop at %d using LEAVE', rec.i) AS log_message;
            LEAVE demo_loop; -- Terminates the loop completely
        END IF;

        SELECT FORMAT('Processing number: %d', rec.i) AS log_message;
    END FOR;

    SELECT '--- 5. FOR Loop Over Query Results ---' AS log_message;
    -- v_row is implicitly a STRUCT matching the SELECT list of the query.
    FOR v_row IN (
        SELECT 'Mathematics' AS course_name, 30 AS students_enrolled
        UNION ALL
        SELECT 'Computer Science', 45
        UNION ALL
        SELECT 'Physics', 25
    )
    DO
        SELECT FORMAT('Course: %s, Enrolled: %d students',
                       v_row.course_name, v_row.students_enrolled) AS log_message;
    END FOR;

END;
