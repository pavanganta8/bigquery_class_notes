-- =========================================================================
-- TUTORIAL: Cursors in BigQuery Scripting (there aren't any!)
-- DESCRIPTION: BigQuery is a columnar, massively-parallel OLAP engine, not a
--              row-store OLTP engine -- it has NO cursor object at all: no
--              REFCURSOR, no DECLARE ... CURSOR FOR, no OPEN/FETCH/CLOSE,
--              no bound/parameterized cursors, no "cursor FOR loop".
--              Row-by-row processing defeats the reason BigQuery is fast, so
--              the platform deliberately does not offer it.
-- USAGE: This file is reference-only reading -- run the set-based rewrite at
--        the bottom to see the same result produced without a cursor.
--
-- PostgreSQL construct                          BigQuery replacement
-- ----------------------------------------------------------------------------
-- DECLARE c CURSOR FOR SELECT ...;               Not available.
-- OPEN c; FETCH c INTO v; EXIT WHEN NOT FOUND;    Rewrite the whole loop body
-- CLOSE c;                                        as a single set-based
--                                                  INSERT ... SELECT ... JOIN,
--                                                  and use SELECT ... INTO
--                                                  only for single-row lookups.
-- FOR r IN cursor_name(args) LOOP ... END LOOP;   FOR r IN (SELECT ...) DO
--                                                  ... END FOR;  (this part
--                                                  DOES survive the port --
--                                                  see 03_for_loop.sql -- it
--                                                  is just not called a
--                                                  "cursor" in BigQuery, it's
--                                                  a plain query-result loop.)
--
-- The real-world example of this rewrite is
-- `procedure_bigquery/project/proc_load_fact_sales.sql`, which replaces the
-- PostgreSQL `c_sales_cursor` row-by-row loop (see pgsql's
-- procedure_pgsql/project/proc_load_fact_sales.sql) with one set-based
-- INSERT ... SELECT ... LEFT JOIN, plus an anti-join that reports which rows
-- would have been skipped by the cursor's IF/ELSIF validation checks. Read
-- that file side-by-side with the PostgreSQL original for the full pattern.
-- =========================================================================

-- -------------------------------------------------------------------------
-- Mini illustration: cursor-style row-by-row (PostgreSQL) vs. set-based
-- (BigQuery) doing the exact same job -- printing each mock student's name
-- and department.
-- -------------------------------------------------------------------------

-- PL/pgSQL (does NOT run in BigQuery -- shown only for comparison):
--   OPEN c_student_cursor FOR SELECT 'Alice' AS name, 'Physics' AS dept
--                              UNION ALL SELECT 'Bob', 'Chemistry';
--   LOOP
--       FETCH c_student_cursor INTO v_name, v_dept;
--       EXIT WHEN NOT FOUND;
--       RAISE NOTICE 'Student: %, Department: %', v_name, v_dept;
--   END LOOP;
--   CLOSE c_student_cursor;

-- BigQuery scripting: the FOR loop below reads the whole result set and
-- iterates it server-side -- no OPEN/FETCH/CLOSE bookkeeping needed, and the
-- engine is free to evaluate the query as a single columnar scan instead of
-- one round-trip per row.
BEGIN
    SELECT '--- Cursor-free row iteration (FOR loop over a query) ---' AS log_message;

    FOR v_row IN (
        SELECT 'Alice' AS name, 'Physics' AS dept
        UNION ALL
        SELECT 'Bob', 'Chemistry'
    )
    DO
        SELECT FORMAT('Student: %s, Department: %s', v_row.name, v_row.dept) AS log_message;
    END FOR;

    -- The PostgreSQL tutorial's *parameterized* cursor
    -- (c_course_cursor CURSOR(p_department VARCHAR) FOR ...) has no
    -- BigQuery equivalent either -- just filter with a WHERE clause using a
    -- normal scripting variable, which is simpler than a bound cursor:
    SELECT '--- Bound-cursor equivalent: WHERE clause with a scripting variable ---' AS log_message;
    DECLARE v_department STRING DEFAULT 'CS';

    FOR r_course IN (
        SELECT * FROM (
            SELECT 'Database Systems' AS course_name, 4 AS credit_hours, 'CS' AS dept
            UNION ALL
            SELECT 'Algorithms', 3, 'CS'
            UNION ALL
            SELECT 'Thermodynamics', 4, 'ME'
        )
        WHERE dept = v_department
    )
    DO
        SELECT FORMAT('Course: %s, Credits: %d', r_course.course_name, r_course.credit_hours) AS log_message;
    END FOR;

END;
