/*
===============================================================================
Stored Procedure: Load Gold Layer (Silver -> Gold)                 (BigQuery)
===============================================================================
PostgreSQL -> BigQuery conversion notes:
    - DATE_TRUNC('month', col)  -> DATE_TRUNC(col, MONTH)   (BigQuery swaps the
      argument order: unit comes second and is an unquoted date-part keyword,
      not a string literal.)
    - CURRENT_DATE               -> CURRENT_DATE()
    - Everything else (ROW_NUMBER() OVER, LEFT JOIN, CASE, COALESCE) is
      identical between PostgreSQL and BigQuery Standard SQL.
===============================================================================
*/
CREATE OR REPLACE PROCEDURE gold.load_gold()
BEGIN
    DECLARE start_time, end_time, batch_start_time, batch_end_time TIMESTAMP;

    BEGIN
        SET batch_start_time = CURRENT_TIMESTAMP();
        SELECT '================================================' AS log_message
        UNION ALL SELECT 'Loading Gold Layer'
        UNION ALL SELECT '================================================';

        -- =====================================================================
        -- gold.dim_customers
        -- =====================================================================
        SET start_time = CURRENT_TIMESTAMP();
        TRUNCATE TABLE gold.dim_customers;
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
            ROW_NUMBER() OVER (ORDER BY ci.cst_id) AS customer_key,
            ci.cst_id                              AS customer_id,
            ci.cst_key                             AS customer_number,
            ci.cst_firstname                       AS first_name,
            ci.cst_lastname                        AS last_name,
            la.cntry                               AS country,
            ci.cst_marital_status                  AS marital_status,
            CASE
                WHEN ci.cst_gndr != 'n/a' THEN ci.cst_gndr
                ELSE COALESCE(ca.gen, 'n/a')
            END                                     AS gender,
            ca.bdate                               AS birthdate,
            ci.cst_create_date                     AS create_date
        FROM silver.crm_cust_info ci
        LEFT JOIN silver.erp_cust_az12 ca
            ON ci.cst_key = ca.cid
        LEFT JOIN silver.erp_loc_a101 la
            ON ci.cst_key = la.cid;
        SET end_time = CURRENT_TIMESTAMP();
        SELECT FORMAT('>> Loaded gold.dim_customers in %d seconds',
                       TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS log_message;

        -- =====================================================================
        -- gold.dim_products
        -- =====================================================================
        SET start_time = CURRENT_TIMESTAMP();
        TRUNCATE TABLE gold.dim_products;
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
            ROW_NUMBER() OVER (ORDER BY pn.prd_start_dt, pn.prd_key) AS product_key,
            pn.prd_id       AS product_id,
            pn.prd_key      AS product_number,
            pn.prd_nm       AS product_name,
            pn.cat_id       AS category_id,
            pc.cat          AS category,
            pc.subcat       AS subcategory,
            pc.maintenance  AS maintenance,
            pn.prd_cost     AS cost,
            pn.prd_line     AS product_line,
            pn.prd_start_dt AS start_date
        FROM silver.crm_prd_info pn
        LEFT JOIN silver.erp_px_cat_g1v2 pc
            ON pn.cat_id = pc.id
        WHERE pn.prd_end_dt IS NULL;
        SET end_time = CURRENT_TIMESTAMP();
        SELECT FORMAT('>> Loaded gold.dim_products in %d seconds',
                       TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS log_message;

        -- =====================================================================
        -- gold.fact_sales
        -- =====================================================================
        SET start_time = CURRENT_TIMESTAMP();
        TRUNCATE TABLE gold.fact_sales;
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
            sd.sls_ord_num  AS order_number,
            pr.product_key  AS product_key,
            cu.customer_key AS customer_key,
            sd.sls_order_dt AS order_date,
            sd.sls_ship_dt  AS shipping_date,
            sd.sls_due_dt   AS due_date,
            sd.sls_sales    AS sales_amount,
            sd.sls_quantity AS quantity,
            sd.sls_price    AS price
        FROM silver.crm_sales_details sd
        LEFT JOIN gold.dim_products pr
            ON sd.sls_prd_key = pr.product_number
        LEFT JOIN gold.dim_customers cu
            ON sd.sls_cust_id = cu.customer_id
        WHERE DATE_TRUNC(sd.sls_order_dt, MONTH) = DATE_TRUNC(CURRENT_DATE(), MONTH);
        SET end_time = CURRENT_TIMESTAMP();
        SELECT FORMAT('>> Loaded gold.fact_sales in %d seconds',
                       TIMESTAMP_DIFF(end_time, start_time, SECOND)) AS log_message;

        SET batch_end_time = CURRENT_TIMESTAMP();
        SELECT '==========================================' AS log_message
        UNION ALL SELECT 'Loading Gold Layer is Completed'
        UNION ALL SELECT FORMAT('   - Total Load Duration: %d seconds',
                                 TIMESTAMP_DIFF(batch_end_time, batch_start_time, SECOND))
        UNION ALL SELECT '==========================================';

    EXCEPTION WHEN ERROR THEN
        SELECT '==========================================' AS log_message
        UNION ALL SELECT 'ERROR OCCURRED DURING LOADING GOLD LAYER'
        UNION ALL SELECT FORMAT('Error Message: %s', @@error.message)
        UNION ALL SELECT '==========================================';
        RAISE USING MESSAGE = @@error.message;
    END;
END;
