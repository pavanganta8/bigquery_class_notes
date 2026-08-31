-- =========================================================================
-- TUTORIAL: IF-ELSE Control Structures in BigQuery Scripting
-- DESCRIPTION: Conditional logic in BigQuery scripting using IF-THEN,
--              IF-THEN-ELSE, IF-THEN-ELSEIF, and the CASE statement.
-- USAGE: Run the whole block in the BigQuery console Editor tab.
--
-- PostgreSQL -> BigQuery mapping:
--   ELSIF                -> ELSEIF (one word, no second "S")
--   CHAR(1)               -> STRING (BigQuery has no fixed-width CHAR type)
--   CASE ... WHEN 'B','C' -> BigQuery's CASE statement also supports
--                             multi-value WHEN branches
-- =========================================================================

BEGIN
    DECLARE v_score       INT64 DEFAULT 85;
    DECLARE v_grade       STRING;
    DECLARE v_attendance  INT64 DEFAULT 92; -- Percentage of attendance
    DECLARE v_is_eligible BOOL;

    SELECT '--- 1. Simple IF-THEN-ELSE ---' AS log_message;
    -- Check if student has passing marks (>= 50)
    IF v_score >= 50 THEN
        SELECT FORMAT('Score: %d. Status: PASSED', v_score) AS log_message;
    ELSE
        SELECT FORMAT('Score: %d. Status: FAILED', v_score) AS log_message;
    END IF;

    SELECT '--- 2. IF-THEN-ELSEIF-ELSE Chain (Grade Calculation) ---' AS log_message;
    -- Calculate grade based on score
    IF v_score >= 90 THEN
        SET v_grade = 'A';
    ELSEIF v_score >= 80 THEN
        SET v_grade = 'B';
    ELSEIF v_score >= 70 THEN
        SET v_grade = 'C';
    ELSEIF v_score >= 60 THEN
        SET v_grade = 'D';
    ELSE
        SET v_grade = 'F';
    END IF;

    SELECT FORMAT('Score: %d, Grade: %s', v_score, v_grade) AS log_message;

    SELECT '--- 3. Nested IF Condition ---' AS log_message;
    -- Check eligibility for exam: Score >= 50 AND attendance >= 75
    IF v_score >= 50 THEN
        IF v_attendance >= 75 THEN
            SET v_is_eligible = TRUE;
            SELECT FORMAT('Eligible for graduation. Attendance: %d%%, Score: %d',
                           v_attendance, v_score) AS log_message;
        ELSE
            SET v_is_eligible = FALSE;
            SELECT FORMAT('Not eligible due to low attendance. Attendance: %d%%',
                           v_attendance) AS log_message;
        END IF;
    ELSE
        SET v_is_eligible = FALSE;
        SELECT FORMAT('Not eligible due to low score. Score: %d', v_score) AS log_message;
    END IF;

    SELECT '--- 4. CASE Statement ---' AS log_message;
    -- Same searched-CASE syntax as PL/pgSQL; BigQuery scripting supports it
    -- as a statement (not only as an expression).
    CASE v_grade
        WHEN 'A' THEN
            SELECT 'Excellent Performance!' AS log_message;
        WHEN 'B', 'C' THEN
            SELECT 'Good Performance.' AS log_message;
        WHEN 'D' THEN
            SELECT 'Needs Improvement.' AS log_message;
        ELSE
            SELECT 'Fail. Please retake the course.' AS log_message;
    END CASE;

END;
