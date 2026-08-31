-- =========================================================================
-- gold.sql -- Incremental "today's data" gold load
-- Converted from: PGSQL PROJECT/Scrpit/gold.txt
-- =========================================================================
-- PostgreSQL -> BigQuery notes:
--   - dwh_create_date::DATE = CURRENT_DATE  -> DATE(dwh_create_date) = CURRENT_DATE()
--     (BigQuery uses DATE(timestamp_expr) rather than a "::DATE" cast
--     shorthand, and CURRENT_DATE needs the parentheses)
--   - The MAX(customer_key)+ROW_NUMBER() "next surrogate key" pattern is
--     unchanged -- it works identically in BigQuery since there is no
--     SERIAL/IDENTITY column to rely on there either (same as in
--     ddl_gold.sql / proc_load_gold.sql).
--   - RAISE NOTICE -> SELECT ... AS log_message
-- =========================================================================
CREATE OR REPLACE PROCEDURE gold.dwh_load_todays_data()
BEGIN

    ------------------------------------------------------
    -- Load Today's Customers
    ------------------------------------------------------
    INSERT INTO gold.dim_customers (
        customer_key,
        customer_id,
        customer_number,
        first_name,
        last_name,
        country,
        marital_status,
        gender,
        birthdate,
        create_date
    )
    SELECT
        -- Note: if customer_key were ever backed by an auto-generated
        -- value, this line and the MAX() lookup below would be unnecessary.
        (SELECT COALESCE(MAX(customer_key), 0) FROM gold.dim_customers) +
            ROW_NUMBER() OVER (ORDER BY ci.cst_id) AS customer_key,
        ci.cst_id,
        ci.cst_key,
        ci.cst_firstname,
        ci.cst_lastname,
        la.cntry AS country,
        ci.cst_marital_status,
        CASE
            WHEN ci.cst_gndr != 'n/a' THEN ci.cst_gndr
            ELSE COALESCE(ca.gen, 'n/a')
        END AS gender,
        ca.bdate AS birthdate,
        ci.cst_create_date AS create_date
    FROM silver.crm_cust_info ci
    LEFT JOIN silver.erp_cust_az12 ca ON ci.cst_key = ca.cid
    LEFT JOIN silver.erp_loc_a101 la ON ci.cst_key = la.cid
    WHERE DATE(ci.dwh_create_date) = CURRENT_DATE();

    ------------------------------------------------------
    -- Load Today's Products
    ------------------------------------------------------
    INSERT INTO gold.dim_products (
        product_key,
        product_id,
        product_number,
        product_name,
        category_id,
        category,
        subcategory,
        maintenance,
        cost,
        product_line,
        start_date
    )
    SELECT
        (SELECT COALESCE(MAX(product_key), 0) FROM gold.dim_products) +
            ROW_NUMBER() OVER (ORDER BY pn.prd_start_dt, pn.prd_key) AS product_key,
        pn.prd_id,
        pn.prd_key,
        pn.prd_nm,
        pn.cat_id,
        pc.cat,
        pc.subcat,
        pc.maintenance,
        pn.prd_cost,
        pn.prd_line,
        pn.prd_start_dt
    FROM silver.crm_prd_info pn
    LEFT JOIN silver.erp_px_cat_g1v2 pc ON pn.cat_id = pc.id
    WHERE pn.prd_end_dt IS NULL
      AND DATE(pn.dwh_create_date) = CURRENT_DATE();

    ------------------------------------------------------
    -- Load Today's Sales
    ------------------------------------------------------
    INSERT INTO gold.fact_sales (
        order_number,
        product_key,
        customer_key,
        order_date,
        shipping_date,
        due_date,
        sales_amount,
        quantity,
        price
    )
    SELECT
        sd.sls_ord_num,
        pr.product_key,
        cu.customer_key,
        sd.sls_order_dt,
        sd.sls_ship_dt,
        sd.sls_due_dt,
        sd.sls_sales,
        sd.sls_quantity,
        sd.sls_price
    FROM silver.crm_sales_details sd
    LEFT JOIN gold.dim_products pr ON sd.sls_prd_key = pr.product_number
    LEFT JOIN gold.dim_customers cu ON sd.sls_cust_id = cu.customer_id
    WHERE DATE(sd.dwh_create_date) = CURRENT_DATE();

    SELECT FORMAT('Gold layer loaded successfully for date: %t', CURRENT_DATE()) AS log_message;

END;

-- To call the procedure:
-- CALL gold.dwh_load_todays_data();
