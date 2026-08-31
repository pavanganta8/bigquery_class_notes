-- =========================================================================
-- TUTORIAL: Variables and Data Types in BigQuery Scripting
-- DESCRIPTION: This file explains how to declare and use variables,
--              constants, and different data types within a BigQuery
--              scripting block (the BigQuery equivalent of PL/pgSQL).
-- USAGE: Run this whole script in the BigQuery console "Editor" tab, or via
--        `bq query --use_legacy_sql=false < 01_variables_and_datatypes.sql`
-- we are comparing pgsql with bigquery 
 -- PostgreSQL -> BigQuery mapping used in this file:
--   DO $$ DECLARE ... BEGIN ... END $$;   -> BEGIN DECLARE ... ... END;
--   RAISE NOTICE '...', var;              -> SELECT FORMAT('...', var) AS log_message;
--   INTEGER                               -> INT64
--   VARCHAR(n) / TEXT                     -> STRING
--   NUMERIC(3,2)                          -> NUMERIC   (BigQuery NUMERIC is
--                                            already fixed-precision; the
--                                            (p,s) qualifier is optional)
--   BOOLEAN                               -> BOOL
--   DATE                                  -> DATE (unchanged)
--   CONSTANT var TYPE := value            -> DECLARE var TYPE DEFAULT value
--                                            (BigQuery has no CONSTANT
--                                            keyword; declare-once + never
--                                            reassign is the convention)
--   %TYPE anchored types                  -> not supported; BigQuery has no
--                                            way to inherit a column's type,
--                                            so the target type is always
--                                            spelled out explicitly
--   RECORD variable + FOR loop over query  -> loop variable is implicitly a
--                                            STRUCT matching the row shape
--                                            (see section 4 below)
-- =========================================================================

BEGIN
    -- 1. Standard Data Types
    DECLARE v_student_id   INT64 DEFAULT 101;                 -- Integer variable
    DECLARE v_student_name STRING DEFAULT 'John Doe';         -- String variable
    DECLARE v_gpa          NUMERIC DEFAULT 3.75;               -- Numeric type
    DECLARE v_is_active    BOOL DEFAULT TRUE;                  -- Boolean variable
    DECLARE v_enroll_date  DATE DEFAULT CURRENT_DATE();        -- Date, current system date

    -- 2. "Constants" (BigQuery has no CONSTANT keyword -- declare once, never
    --    reassign; the naming convention `c_` signals intent to the reader)
    DECLARE c_max_gpa      NUMERIC DEFAULT 4.00;

    -- 3. Anchored types (%TYPE) have no BigQuery equivalent -- just repeat
    --    the type explicitly.
    DECLARE v_student_copy STRING DEFAULT 'Jane Smith';

    -- 4. There is no dedicated RECORD type; a FOR-loop variable is
    --    automatically typed as a STRUCT matching the query's row shape
    --    (used below).

    SELECT '--- 1. Variable Declarations & Initialization ---' AS log_message;
    SELECT FORMAT('Student ID: %d', v_student_id) AS log_message;
    SELECT FORMAT('Student Name: %s', v_student_name) AS log_message;
    SELECT FORMAT('GPA: %.2f / %.2f (Max GPA)', v_gpa, c_max_gpa) AS log_message;
    SELECT FORMAT('Is Active: %t', v_is_active) AS log_message;
    SELECT FORMAT('Enrollment Date: %t', v_enroll_date) AS log_message;

    -- Reassigning variables: PL/pgSQL "x := value" -> BigQuery "SET x = value"
    SET v_student_name = 'Johnathan Doe';
    SET v_gpa = 3.89;

    SELECT '--- 2. Variable Reassignment ---' AS log_message;
    SELECT FORMAT('Updated Student Name: %s', v_student_name) AS log_message;
    SELECT FORMAT('Updated GPA: %.2f', v_gpa) AS log_message;

    SELECT '--- 3. "Anchored Type" Example (no %TYPE in BigQuery) ---' AS log_message;
    SELECT FORMAT('Copied Student Name Value: %s', v_student_copy) AS log_message;

    -- Using a STRUCT-typed loop variable (the RECORD equivalent)
    SELECT '--- 4. STRUCT-typed FOR-loop variable (RECORD equivalent) ---' AS log_message;
    FOR v_record IN (SELECT 1 AS id, 'Math' AS subject, 'A' AS grade)
    DO
        SELECT FORMAT('Record ID: %d, Subject: %s, Grade: %s',
                       v_record.id, v_record.subject, v_record.grade) AS log_message;
    END FOR;

END;
