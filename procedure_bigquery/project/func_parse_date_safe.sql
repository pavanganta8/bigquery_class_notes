-- =========================================================================
-- FUNCTION: silver.parse_date_safe                                (BigQuery)
-- DESCRIPTION: Safely parses dates formatted as YYYY-MM-DD, DD-MM-YYYY, or
--              YYYY/MM/DD.
--
-- PostgreSQL -> BigQuery notes:
--   The PL/pgSQL version tried TO_DATE() three times inside three nested
--   BEGIN...EXCEPTION blocks, falling through to the next format on failure.
--   BigQuery's SQL-function body can't contain BEGIN/EXCEPTION at all, but
--   `SAFE.PARSE_DATE(...)` already returns NULL instead of erroring on a
--   format mismatch -- so the three attempts collapse into one
--   COALESCE(SAFE.PARSE_DATE(...), SAFE.PARSE_DATE(...), SAFE.PARSE_DATE(...))
--   expression, tried left-to-right exactly like the nested EXCEPTION
--   fallbacks were.
-- =========================================================================

CREATE OR REPLACE FUNCTION silver.parse_date_safe(p_date_str STRING)
RETURNS DATE
AS (
    CASE
        WHEN p_date_str IS NULL OR TRIM(p_date_str) = '' THEN NULL
        ELSE COALESCE(
                SAFE.PARSE_DATE('%Y-%m-%d', TRIM(p_date_str)),  -- YYYY-MM-DD
                SAFE.PARSE_DATE('%d-%m-%Y', TRIM(p_date_str)),  -- DD-MM-YYYY
                SAFE.PARSE_DATE('%Y/%m/%d', TRIM(p_date_str))   -- YYYY/MM/DD
             )
    END
);
