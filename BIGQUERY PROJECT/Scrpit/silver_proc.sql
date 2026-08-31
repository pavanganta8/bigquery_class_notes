-- =========================================================================
-- silver_proc.sql -- Full bronze -> silver cleanse (single procedure)
-- Converted from: PGSQL PROJECT/Scrpit/silver_proc.txt
-- =========================================================================
-- PostgreSQL -> BigQuery notes:
--   - INITCAP(TRIM(x))          -> identical (BigQuery added INITCAP())
--   - SUBSTR(prd_key, 1, 5)      -> identical (BigQuery supports the
--     2/3-argument SUBSTR form the same way Postgres does)
--   - SUBSTRING(prd_key FROM 7)  -> SUBSTR(prd_key, 7)
--   - x::TEXT                    -> CAST(x AS STRING)
--   - TO_DATE(x::TEXT,'YYYYMMDD')-> PARSE_DATE('%Y%m%d', CAST(x AS STRING))
--   - prd_start_dt::DATE         -> CAST(prd_start_dt AS DATE)
--   - (LEAD(x) OVER (...) - INTERVAL '1 day')::DATE
--        -> DATE_SUB(CAST(LEAD(x) OVER (...) AS DATE), INTERVAL 1 DAY)
--   - sls_sales / NULLIF(sls_quantity, 0)
--        -> SAFE_DIVIDE(sls_sales, NULLIF(sls_quantity, 0)) (SAFE_DIVIDE
--           additionally protects against a divide-by-zero runtime error,
--           returning NULL instead, which NULLIF alone does not guarantee
--           for every BigQuery type)
--   - RAISE NOTICE                -> SELECT ... AS log_message
-- =========================================================================
CREATE OR REPLACE PROCEDURE silver.dwh_data_load_silver()
BEGIN
    -- 1. CRM CUSTOMER
    -- Note: we truncate before insert, matching the ERP logic / handling
    -- duplicates the same way the original PostgreSQL logic did.
    TRUNCATE TABLE silver.crm_cust_info;

    INSERT INTO silver.crm_cust_info (
        cst_id, cst_key, cst_firstname, cst_lastname,
        cst_marital_status, cst_gndr, cst_create_date, dwh_create_date
    )
    SELECT
        cst_id,
        cst_key,
        INITCAP(TRIM(cst_firstname)),
        INITCAP(TRIM(cst_lastname)),
        CASE
            WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
            WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
            ELSE 'n/a'
        END,
        CASE
            WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
            WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
            ELSE 'n/a'
        END,
        cst_create_date,
        CURRENT_TIMESTAMP()
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_id ASC) AS r_n
        FROM bronze.crm_cust_info
        WHERE cst_id IS NOT NULL
    )
    WHERE r_n = 1;


    -- 2. CRM PRODUCT
    TRUNCATE TABLE silver.crm_prd_info;

    INSERT INTO silver.crm_prd_info (
        prd_id, cat_id, prd_key, prd_nm, prd_cost,
        prd_line, prd_start_dt, prd_end_dt, dwh_create_date
    )
    SELECT
        prd_id,
        REPLACE(SUBSTR(prd_key, 1, 5), '-', '_') AS cat_id,
        SUBSTR(prd_key, 7) AS prd_key,
        prd_nm,
        COALESCE(prd_cost, 0) AS prd_cost,
        CASE
            WHEN UPPER(TRIM(prd_line)) = 'M' THEN 'Mountain'
            WHEN UPPER(TRIM(prd_line)) = 'R' THEN 'Road'
            WHEN UPPER(TRIM(prd_line)) = 'S' THEN 'Other Sales'
            WHEN UPPER(TRIM(prd_line)) = 'T' THEN 'Touring'
            ELSE 'n/a'
        END AS prd_line,
        CAST(prd_start_dt AS DATE),
        DATE_SUB(
            CAST(LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt) AS DATE),
            INTERVAL 1 DAY
        ) AS prd_end_dt,
        CURRENT_TIMESTAMP()
    FROM bronze.crm_prd_info;


    -- 3. CRM SALES DETAILS
    TRUNCATE TABLE silver.crm_sales_details;

    INSERT INTO silver.crm_sales_details (
        sls_ord_num, sls_prd_key, sls_cust_id, sls_order_dt,
        sls_ship_dt, sls_due_dt, sls_sales, sls_quantity, sls_price, dwh_create_date
    )
    SELECT
        sls_ord_num,
        sls_prd_key,
        sls_cust_id,
        CASE WHEN sls_order_dt = 0 OR LENGTH(CAST(sls_order_dt AS STRING)) != 8 THEN NULL
             ELSE PARSE_DATE('%Y%m%d', CAST(sls_order_dt AS STRING)) END,
        CASE WHEN sls_ship_dt = 0 OR LENGTH(CAST(sls_ship_dt AS STRING)) != 8 THEN NULL
             ELSE PARSE_DATE('%Y%m%d', CAST(sls_ship_dt AS STRING)) END,
        CASE WHEN sls_due_dt = 0 OR LENGTH(CAST(sls_due_dt AS STRING)) != 8 THEN NULL
             ELSE PARSE_DATE('%Y%m%d', CAST(sls_due_dt AS STRING)) END,
        CASE
            WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price)
            THEN sls_quantity * ABS(sls_price)
            ELSE sls_sales
        END,
        sls_quantity,
        CASE
            WHEN sls_price IS NULL OR sls_price <= 0 THEN SAFE_DIVIDE(sls_sales, NULLIF(sls_quantity, 0))
            ELSE sls_price
        END,
        CURRENT_TIMESTAMP()
    FROM bronze.crm_sales_details;


    -- 4. ERP CUSTOMER
    TRUNCATE TABLE silver.erp_cust_az12;

    INSERT INTO silver.erp_cust_az12 (cid, bdate, gen, dwh_create_date)
    SELECT
        CASE WHEN cid LIKE 'NAS%' THEN SUBSTR(cid, 4) ELSE cid END,
        CASE WHEN bdate > CURRENT_DATE() THEN NULL ELSE bdate END,
        CASE
            WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
            WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
            ELSE 'n/a'
        END,
        CURRENT_TIMESTAMP()
    FROM bronze.erp_cust_az12;


    -- 5. ERP LOCATION
    TRUNCATE TABLE silver.erp_loc_a101;

    INSERT INTO silver.erp_loc_a101 (cid, cntry, dwh_create_date)
    SELECT
        REPLACE(cid, '-', ''),
        CASE
            WHEN TRIM(cntry) = 'DE' THEN 'Germany'
            WHEN TRIM(cntry) IN ('US', 'USA') THEN 'United States'
            WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'n/a'
            ELSE TRIM(cntry)
        END,
        CURRENT_TIMESTAMP()
    FROM bronze.erp_loc_a101;


    -- 6. ERP PRODUCT CATEGORY
    TRUNCATE TABLE silver.erp_px_cat_g1v2;

    INSERT INTO silver.erp_px_cat_g1v2 (id, cat, subcat, maintenance, dwh_create_date)
    SELECT id, cat, subcat, maintenance, CURRENT_TIMESTAMP()
    FROM bronze.erp_px_cat_g1v2;

    SELECT 'Silver layer load completed successfully' AS log_message;
END;

-- To run the procedure:
-- CALL silver.dwh_data_load_silver();
