-- =========================================================================
-- PROCEDURE: silver.print_load_summary                            (BigQuery)
-- DESCRIPTION: Iterates over load logs created during the execution run.
--              Demonstrates the FOR loop control structure.
--
-- PostgreSQL -> BigQuery notes:
--   - RPAD(text, len, ' ')  -> RPAD works the same way in BigQuery (STRING
--     function, identical signature).
--   - v_log_record RECORD + FOR loop -> the FOR loop variable is implicitly
--     a STRUCT matching the SELECT list; no separate DECLARE is needed or
--     allowed for it.
-- =========================================================================

CREATE OR REPLACE PROCEDURE silver.print_load_summary(
    IN p_run_start_time TIMESTAMP
)
BEGIN
    SELECT '==================================================' AS log_message
    UNION ALL SELECT 'ETL COMPLETED. CURRENT PIPELINE EXECUTION SUMMARY:'
    UNION ALL SELECT '==================================================';

    FOR v_log_record IN (
        SELECT step_name, status, records_loaded, error_message
        FROM audit.load_logs
        WHERE logged_at >= p_run_start_time
        ORDER BY logged_at ASC
    )
    DO
        IF v_log_record.status = 'SUCCESS' THEN
            SELECT FORMAT('>> STEP: %s | STATUS: %s | RECORDS LOADED: %d',
                           RPAD(v_log_record.step_name, 22, ' '),
                           v_log_record.status,
                           v_log_record.records_loaded) AS log_message;
        ELSEIF v_log_record.status = 'FAILED' THEN
            SELECT FORMAT('>> STEP: %s | STATUS: %s | ERROR: %s',
                           RPAD(v_log_record.step_name, 22, ' '),
                           v_log_record.status,
                           v_log_record.error_message) AS log_message;
        ELSE
            SELECT FORMAT('>> STEP: %s | STATUS: %s | %s',
                           RPAD(v_log_record.step_name, 22, ' '),
                           v_log_record.status,
                           v_log_record.error_message) AS log_message;
        END IF;
    END FOR;

    SELECT '==================================================' AS log_message;
END;
