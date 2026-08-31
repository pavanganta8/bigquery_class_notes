-- =========================================================================
-- TUTORIAL: Triggers in BigQuery (there aren't any!)
-- DESCRIPTION: BigQuery has NO trigger object of any kind -- no BEFORE/AFTER,
--              no FOR EACH ROW / FOR EACH STATEMENT, no NEW/OLD row
--              variables, no TG_OP. It is a warehouse, not an OLTP database,
--              and row-level triggers are incompatible with the way it
--              executes bulk columnar DML. This file shows the three
--              standard replacement patterns.
-- USAGE: Reference-only reading + a runnable Pattern 1 example.
--
-- PostgreSQL construct                     BigQuery replacement
-- ----------------------------------------------------------------------------
-- BEFORE UPDATE trigger that stamps         Pattern 1: compute the value
--   NEW.updated_at := CURRENT_TIMESTAMP     inline in the UPDATE/MERGE
--                                            statement itself (no event
--                                            needed -- see below).
-- AFTER INSERT/UPDATE/DELETE trigger that    Pattern 2: write the audit row
--   inserts into an audit log table          explicitly, right after the
--                                             DML, in the same procedure
--                                             (this is exactly what
--                                             audit.load_logs already does
--                                             throughout this project --
--                                             see procedure_bigquery/project/).
-- Trigger that reacts to a write from any    Pattern 3: true event-driven
--   external client, not just your own       automation needs a service
--   procedures                               *outside* BigQuery: a Cloud
--                                             Function/Cloud Run service
--                                             subscribed via Eventarc to
--                                             BigQuery audit log events
--                                             (google.cloud.bigquery.v2.
--                                             JobService.InsertJob), or a
--                                             scheduled query / Dataform
--                                             assertion that polls on a
--                                             timer instead of firing
--                                             synchronously per row.
-- =========================================================================

-- 1. PREPARATION: Create a sample table and an audit log table
DROP TABLE IF EXISTS student_logs;
DROP TABLE IF EXISTS students_table;

CREATE TABLE students_table (
    student_id   INT64,
    student_name STRING NOT NULL,
    score        NUMERIC,
    updated_at   TIMESTAMP
);

CREATE TABLE student_logs (
    log_id            STRING DEFAULT GENERATE_UUID(),
    student_id        INT64,
    action_performed  STRING,
    old_score         NUMERIC,
    new_score         NUMERIC,
    changed_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);
-- Note: no SERIAL/IDENTITY auto-increment in BigQuery -- GENERATE_UUID() (or
-- a ROW_NUMBER()-derived surrogate key) replaces it. See ddl notes in
-- ../gold/ddl_gold.sql for the ROW_NUMBER() pattern used on real key columns.


-- =========================================================================
-- Pattern 1 + 2 combined: no trigger function/binding step exists in
-- BigQuery, so INSERT/UPDATE/DELETE and the audit-log write are just
-- ordinary statements placed one after another inside a PROCEDURE. This
-- procedure is what a client calls instead of running a bare INSERT/UPDATE/
-- DELETE against students_table directly -- the "trigger" behavior is now
-- explicit code in one place, not implicit engine behavior.
-- =========================================================================
CREATE OR REPLACE PROCEDURE upsert_student(
    IN p_student_id INT64,
    IN p_student_name STRING,
    IN p_new_score NUMERIC
)
BEGIN
    DECLARE v_old_score NUMERIC;
    DECLARE v_exists BOOL;

    SET v_exists = EXISTS(SELECT 1 FROM students_table WHERE student_id = p_student_id);

    IF NOT v_exists THEN
        -- INSERT branch (== TG_OP = 'INSERT')
        INSERT INTO students_table (student_id, student_name, score, updated_at)
        VALUES (p_student_id, p_student_name, p_new_score, CURRENT_TIMESTAMP());

        INSERT INTO student_logs (student_id, action_performed, old_score, new_score)
        VALUES (p_student_id, 'INSERT_STUDENT', NULL, p_new_score);
    ELSE
        -- UPDATE branch (== TG_OP = 'UPDATE'); read OLD.score ourselves
        -- since there is no implicit OLD row variable outside a trigger.
        SET v_old_score = (SELECT score FROM students_table WHERE student_id = p_student_id);

        -- Pattern 1: stamp updated_at inline instead of a BEFORE UPDATE trigger.
        UPDATE students_table
        SET score = p_new_score,
            updated_at = CURRENT_TIMESTAMP()
        WHERE student_id = p_student_id;

        -- Pattern 2: only log when the score actually changed, same guard
        -- the original trigger used (OLD.score IS DISTINCT FROM NEW.score).
        IF v_old_score IS DISTINCT FROM p_new_score THEN
            INSERT INTO student_logs (student_id, action_performed, old_score, new_score)
            VALUES (p_student_id, 'UPDATE_SCORE', v_old_score, p_new_score);
        END IF;
    END IF;
END;

CREATE OR REPLACE PROCEDURE delete_student(IN p_student_id INT64)
BEGIN
    DECLARE v_old_score NUMERIC;
    SET v_old_score = (SELECT score FROM students_table WHERE student_id = p_student_id);

    DELETE FROM students_table WHERE student_id = p_student_id;

    -- DELETE branch (== TG_OP = 'DELETE')
    INSERT INTO student_logs (student_id, action_performed, old_score, new_score)
    VALUES (p_student_id, 'DELETE_STUDENT', v_old_score, NULL);
END;


-- 4. TESTING: calling the procedures replaces "INSERT/UPDATE/DELETE and let
--    the trigger handle logging" -- in BigQuery, the procedure IS the logging.
SELECT '--- Testing trigger-replacement procedures ---' AS log_message;

CALL upsert_student(1, 'Alice Smith', 85.0);
CALL upsert_student(2, 'Bob Jones', 72.5);

SELECT * FROM students_table;
SELECT * FROM student_logs;

CALL upsert_student(1, 'Alice Smith', 90.0); -- score change -> logged

SELECT * FROM students_table;
SELECT * FROM student_logs;

CALL delete_student(2);

SELECT * FROM student_logs;
