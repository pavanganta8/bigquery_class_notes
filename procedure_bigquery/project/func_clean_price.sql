-- =========================================================================
-- FUNCTION: silver.clean_price                                    (BigQuery)
-- DESCRIPTION: Cleans currency-formatted strings (e.g. $120.00) and
--              converts them to NUMERIC.
--
-- PostgreSQL -> BigQuery notes:
--   The PL/pgSQL version used a nested BEGIN...EXCEPTION WHEN OTHERS block
--   to fall back to 0.00 when CAST(... AS NUMERIC) failed to parse. BigQuery
--   SQL functions can't contain a BEGIN/EXCEPTION block at all (single
--   expression only) -- SAFE_CAST is the direct replacement: it returns NULL
--   instead of raising an error on a bad conversion, which COALESCE then
--   turns into the same 0.00 fallback.
-- =========================================================================

CREATE OR REPLACE FUNCTION silver.clean_price(p_price_str STRING)
RETURNS NUMERIC
AS (
    CASE
        WHEN p_price_str IS NULL
             OR TRIM(p_price_str) = ''
             OR LOWER(TRIM(p_price_str)) = 'free'
            THEN 0.00
        ELSE COALESCE(
                SAFE_CAST(REPLACE(TRIM(p_price_str), '$', '') AS NUMERIC),
                0.00
             )
    END
);
