-- =========================================================================
-- TUTORIAL: Functions in BigQuery (SQL UDFs, Table Functions, Procedures)
-- DESCRIPTION: How to create and execute user-defined routines. Covers
--              scalar functions, "multi-return" logic, and table-returning
--              functions.
-- USAGE: Run the CREATE statements first, then the SELECT/CALL test queries.
--
-- IMPORTANT PostgreSQL -> BigQuery difference:
--   A PL/pgSQL FUNCTION body is a full procedural block (DECLARE/IF/loops/
--   RETURN anywhere). A persistent BigQuery SQL FUNCTION body is a SINGLE
--   SQL EXPRESSION -- no DECLARE, no IF statement, no early RETURN. Any
--   procedural branching has to be rewritten as CASE-expression logic, and
--   any "raise an error" logic uses the ERROR() function *inside* that
--   expression instead of RAISE EXCEPTION. If a routine genuinely needs
--   OUT/INOUT parameters or multi-statement procedural logic, it has to
--   become a PROCEDURE instead of a FUNCTION -- BigQuery functions never
--   support OUT/INOUT params (see Example 2).
-- =========================================================================

-- -------------------------------------------------------------------------
-- Example 1: Basic Scalar Function
-- Calculates the final grade based on theory and lab scores.
-- PL/pgSQL used DECLARE + IF + RAISE EXCEPTION + RETURN; BigQuery expresses
-- the same logic as one CASE expression, using ERROR() for validation.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION calculate_final_score(
    p_theory_score NUMERIC,
    p_lab_score NUMERIC
)
RETURNS NUMERIC
AS (
    CASE
        WHEN p_theory_score < 0 OR p_lab_score < 0
            THEN ERROR('Scores cannot be negative')
        -- Theory carries 60% weight, Lab carries 40% weight
        ELSE (p_theory_score * 0.60) + (p_lab_score * 0.40)
    END
);

-- Testing Example 1:
SELECT calculate_final_score(80, 90) AS calculated_score;


-- -------------------------------------------------------------------------
-- Example 2: "Function" with IN, OUT, and INOUT Parameters
-- BigQuery SQL functions cannot declare OUT/INOUT parameters at all, so a
-- routine that needs to return multiple values is written as a PROCEDURE
-- (BigQuery procedures DO support IN / OUT / INOUT, one-for-one with
-- PL/pgSQL) instead of a FUNCTION.
-- -------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE get_student_stats(
    IN p_student_id INT64,
    OUT p_name STRING,
    OUT p_status STRING,
    INOUT p_gpa NUMERIC
)
BEGIN
    IF p_student_id = 1 THEN
        SET p_name = 'Alice Vance';
        SET p_status = 'Active';
        -- Modify the INOUT parameter
        SET p_gpa = p_gpa + 0.2; -- Add bonus GPA
    ELSE
        SET p_name = 'Unknown Student';
        SET p_status = 'Inactive';
    END IF;
END;

-- Testing Example 2:
-- Calling a procedure with OUT/INOUT params requires session-scoped
-- variables to receive the results -- unlike PostgreSQL's
-- "SELECT * FROM get_student_stats(1, 3.5);", BigQuery cannot return
-- OUT params from a plain SELECT.
DECLARE v_name STRING;
DECLARE v_status STRING;
DECLARE v_gpa NUMERIC DEFAULT 3.5;

CALL get_student_stats(1, v_name, v_status, v_gpa);
SELECT v_name AS name, v_status AS status, v_gpa AS gpa;


-- -------------------------------------------------------------------------
-- Example 3: Function Returning a Table (RETURNS TABLE -> TABLE FUNCTION)
-- PostgreSQL's "RETURNS TABLE(...) ... RETURN QUERY SELECT ..." maps to a
-- BigQuery "CREATE TABLE FUNCTION", whose body is a single SELECT (no
-- RETURN QUERY keyword needed -- the SELECT result *is* the return value).
-- -------------------------------------------------------------------------
CREATE OR REPLACE TABLE FUNCTION get_high_performers(p_min_grade NUMERIC)
AS (
    SELECT * FROM (
        SELECT 101 AS s_id, 'Alice' AS s_name, 95.5 AS s_grade
        UNION ALL
        SELECT 102, 'Bob', 88.0
        UNION ALL
        SELECT 103, 'Charlie', 72.0
    )
    WHERE s_grade >= p_min_grade
);

-- Testing Example 3:
SELECT * FROM get_high_performers(85.0);


-- -------------------------------------------------------------------------
-- Clean up (optional commands to drop the routines)
-- -------------------------------------------------------------------------
-- DROP FUNCTION calculate_final_score;
-- DROP PROCEDURE get_student_stats;
-- DROP TABLE FUNCTION get_high_performers;
