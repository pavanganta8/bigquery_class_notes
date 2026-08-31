-- =========================================================================
-- FUNCTION: silver.clean_gender                                   (BigQuery)
-- DESCRIPTION: Standardizes dirty raw gender values into 'Male', 'Female',
--              or 'n/a'.
--
-- PostgreSQL -> BigQuery notes:
--   The PL/pgSQL version used DECLARE + IF/ELSIF/RETURN (a full procedural
--   body). A persistent BigQuery SQL function body must be a single
--   expression, so the whole IF/ELSIF chain becomes one CASE expression.
-- =========================================================================

CREATE OR REPLACE FUNCTION silver.clean_gender(p_gender_str STRING)
RETURNS STRING
AS (
    CASE
        WHEN p_gender_str IS NULL THEN 'n/a'
        WHEN LOWER(TRIM(p_gender_str)) IN ('m', 'male') THEN 'Male'
        WHEN LOWER(TRIM(p_gender_str)) IN ('f', 'female') THEN 'Female'
        ELSE 'n/a'
    END
);
