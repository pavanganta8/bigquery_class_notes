/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)             (BigQuery)
===============================================================================
PostgreSQL -> BigQuery conversion notes (function-by-function):
    - TRIM / UPPER / COALESCE / CASE WHEN            -> identical in BigQuery
    - SUBSTRING(col FROM 1 FOR 5)                    -> SUBSTR(col, 1, 5)
    - SUBSTRING(col FROM 7)                          -> SUBSTR(col, 7)
    - CAST(x AS DATE)                                -> identical
    - TO_DATE(text, 'YYYYMMDD')                      -> PARSE_DATE('%Y%m%d', text)
    - LEAD(x) OVER (...) - INTERVAL '1 day'          -> DATE_SUB(LEAD(x) OVER (...), INTERVAL 1 DAY)
    - LENGTH(x::VARCHAR)                              -> LENGTH(CAST(x AS STRING))
    - NULLIF(a, b)                                    -> identical
    - CURRENT_DATE                                    -> CURRENT_DATE()
    - ROW_NUMBER() OVER (PARTITION BY ... ORDER BY..) -> identical (window
      functions work the same way in BigQuery)
    - RAISE NOTICE                                    -> SELECT ... AS log_message
      (see proc_load_bronze.sql header for the full rationale)
===============================================================================
*/
CREATE OR REPLACE PROCEDURE silver.load_silver()
BEGIN
    DECLARE start_time, end_time, batch_start_time, batch_end_time TIMESTAMP;

    BEGIN
        SET batch_start_time = CURRENT_TIMESTAMP();
        SELECT '================================================' AS log_message
        UNION ALL SELECT 'Loading Silver Layer'
        UNION ALL SELECT '================================================'
        UNION ALL SELECT '------------------------------------------------'
        UNION ALL SELECT 'Loading CRM Tables'
        UNION ALL SELECT '------------------------------------------------';

        -- =====================================================================
        -- silver.crm_cust_info
        -- =====================================================================
        SET start_time = CURRENT_TIMESTAMP();

        TRUNCATE TABLE silver.crm_cust_info;
        INSERT INTO silver.crm_cust_info (
            cst_id,
            cst_key,
            cst_firstname,
            cst_lastname,
            cst_marital_status,
            cst_gndr,
            cst_create_date
        )
        SELECT
            cst_id,
            cst_key,
            TRIM(cst_firstname) AS cst_firstname,
            TRIM(cst_lastname)  AS cst_lastname,
            CASE
                WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
                WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
                ELSE 'n/a'
            END AS cst_marital_status,
            CASE
                WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
                WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
                ELSE 'n/a'
            END AS cst_gndr,
            cst_create_date
        FROM (
            SELECT
                *,
                ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
            FROM bronze.crm_cust_info
            WHERE cst_id IS NOT NULL
        )
        WHERE flag_last = 1;

        SET end_time = CURRENT_TIMESTAMP();
        SELECT FORMAT('>> Loaded silver.crm_cust_info in %d seconds',
                       TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS log_message;

        -- =====================================================================
        -- silver.crm_prd_info
        -- =====================================================================
        SET start_time = CURRENT_TIMESTAMP();

        TRUNCATE TABLE silver.crm_prd_info;
        INSERT INTO silver.crm_prd_info (
            prd_id,
            cat_id,
            prd_key,
            prd_nm,
            prd_cost,
            prd_line,
            prd_start_dt,
            prd_end_dt
        )
        SELECT
            prd_id,
            REPLACE(SUBSTR(prd_key, 1, 5), '-', '_') AS cat_id,
            SUBSTR(prd_key, 7)                       AS prd_key,
            prd_nm,
            COALESCE(prd_cost, 0) AS prd_cost,
            CASE
                WHEN UPPER(TRIM(prd_line)) = 'M' THEN 'Mountain'
                WHEN UPPER(TRIM(prd_line)) = 'R' THEN 'Road'
                WHEN UPPER(TRIM(prd_line)) = 'S' THEN 'Other Sales'
                WHEN UPPER(TRIM(prd_line)) = 'T' THEN 'Touring'
                ELSE 'n/a'
            END AS prd_line,
            CAST(prd_start_dt AS DATE) AS prd_start_dt,
            DATE_SUB(
                CAST(LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt) AS DATE),
                INTERVAL 1 DAY
            ) AS prd_end_dt
        FROM bronze.crm_prd_info;

        SET end_time = CURRENT_TIMESTAMP();
        SELECT FORMAT('>> Loaded silver.crm_prd_info in %d seconds',
                       TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS log_message;

        -- =====================================================================
        -- silver.crm_sales_details
        -- =====================================================================
        SET start_time = CURRENT_TIMESTAMP();

        TRUNCATE TABLE silver.crm_sales_details;
        INSERT INTO silver.crm_sales_details (
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            sls_order_dt,
            sls_ship_dt,
            sls_due_dt,
            sls_sales,
            sls_quantity,
            sls_price
        )
        SELECT
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            CASE
                WHEN sls_order_dt = 0 OR LENGTH(CAST(sls_order_dt AS STRING)) != 8 THEN NULL
                ELSE PARSE_DATE('%Y%m%d', CAST(sls_order_dt AS STRING))
            END AS sls_order_dt,
            CASE
                WHEN sls_ship_dt = 0 OR LENGTH(CAST(sls_ship_dt AS STRING)) != 8 THEN NULL
                ELSE PARSE_DATE('%Y%m%d', CAST(sls_ship_dt AS STRING))
            END AS sls_ship_dt,
            CASE
                WHEN sls_due_dt = 0 OR LENGTH(CAST(sls_due_dt AS STRING)) != 8 THEN NULL
                ELSE PARSE_DATE('%Y%m%d', CAST(sls_due_dt AS STRING))
            END AS sls_due_dt,
            CASE
                WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price)
                    THEN sls_quantity * ABS(sls_price)
                ELSE sls_sales
            END AS sls_sales,
            sls_quantity,
            CASE
                WHEN sls_price IS NULL OR sls_price <= 0
                    THEN SAFE_DIVIDE(sls_sales, NULLIF(sls_quantity, 0))
                ELSE sls_price
            END AS sls_price
        FROM bronze.crm_sales_details;

        SET end_time = CURRENT_TIMESTAMP();
        SELECT FORMAT('>> Loaded silver.crm_sales_details in %d seconds',
                       TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS log_message;

        -- =====================================================================
        -- silver.erp_cust_az12
        -- =====================================================================
        SET start_time = CURRENT_TIMESTAMP();

        TRUNCATE TABLE silver.erp_cust_az12;
        INSERT INTO silver.erp_cust_az12 (
            cid,
            bdate,
            gen
        )
        SELECT
            CASE
                WHEN cid LIKE 'NAS%' THEN SUBSTR(cid, 4)
                ELSE cid
            END AS cid,
            CASE
                WHEN bdate > CURRENT_DATE() THEN NULL
                ELSE bdate
            END AS bdate,
            CASE
                WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
                WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
                ELSE 'n/a'
            END AS gen
        FROM bronze.erp_cust_az12;

        SET end_time = CURRENT_TIMESTAMP();
        SELECT FORMAT('>> Loaded silver.erp_cust_az12 in %d seconds',
                       TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS log_message;

        SELECT '------------------------------------------------' AS log_message
        UNION ALL SELECT 'Loading ERP Tables'
        UNION ALL SELECT '------------------------------------------------';

        -- =====================================================================
        -- silver.erp_loc_a101
        -- =====================================================================
        SET start_time = CURRENT_TIMESTAMP();

        TRUNCATE TABLE silver.erp_loc_a101;
        INSERT INTO silver.erp_loc_a101 (
            cid,
            cntry
        )
        SELECT
            REPLACE(cid, '-', '') AS cid,
            CASE
                WHEN TRIM(cntry) = 'DE' THEN 'Germany'
                WHEN TRIM(cntry) IN ('US', 'USA') THEN 'United States'
                WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'n/a'
                ELSE TRIM(cntry)
            END AS cntry
        FROM bronze.erp_loc_a101;

        SET end_time = CURRENT_TIMESTAMP();
        SELECT FORMAT('>> Loaded silver.erp_loc_a101 in %d seconds',
                       TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS log_message;

        -- =====================================================================
        -- silver.erp_px_cat_g1v2
        -- =====================================================================
        SET start_time = CURRENT_TIMESTAMP();

        TRUNCATE TABLE silver.erp_px_cat_g1v2;
        INSERT INTO silver.erp_px_cat_g1v2 (
            id,
            cat,
            subcat,
            maintenance
        )
        SELECT
            id,
            cat,
            subcat,
            maintenance
        FROM bronze.erp_px_cat_g1v2;

        SET end_time = CURRENT_TIMESTAMP();
        SELECT FORMAT('>> Loaded silver.erp_px_cat_g1v2 in %d seconds',
                       TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS log_message;

        SET batch_end_time = CURRENT_TIMESTAMP();
        SELECT '==========================================' AS log_message
        UNION ALL SELECT 'Loading Silver Layer is Completed'
        UNION ALL SELECT FORMAT('   - Total Load Duration: %d seconds',
                                 TIMESTAMP_DIFF(batch_end_time, batch_start_time, SECOND))
        UNION ALL SELECT '==========================================';

    EXCEPTION WHEN ERROR THEN
        SELECT '==========================================' AS log_message
        UNION ALL SELECT 'ERROR OCCURRED DURING LOADING SILVER LAYER'
        UNION ALL SELECT FORMAT('Error Message: %s', @@error.message)
        UNION ALL SELECT '==========================================';
        RAISE USING MESSAGE = @@error.message;
    END;
END;
