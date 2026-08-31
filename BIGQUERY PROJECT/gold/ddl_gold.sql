/*
===============================================================================
DDL Script: Create Gold Tables (BigQuery)
===============================================================================
PostgreSQL -> BigQuery notes:
    - "DROP TABLE ... CASCADE" -> BigQuery has no foreign-key enforcement, so
      CASCADE is dropped; a plain "DROP TABLE IF EXISTS" is enough.
    - Consider adding PARTITION BY / CLUSTER BY on the fact table for cost and
      performance at scale, e.g.:
          PARTITION BY order_date
          CLUSTER BY customer_key, product_key
      (left out below to keep this a direct structural mirror of the
      PostgreSQL DDL; add it once table sizes justify it).
===============================================================================
*/

-- =============================================================================
-- Create Dimension: gold.dim_customers
-- =============================================================================
DROP TABLE IF EXISTS gold.dim_customers;

CREATE TABLE gold.dim_customers (
    customer_key    INT64,
    customer_id     INT64,
    customer_number STRING,
    first_name      STRING,
    last_name       STRING,
    country         STRING,
    marital_status  STRING,
    gender          STRING,
    birthdate       DATE,
    create_date     DATE
);

-- =============================================================================
-- Create Dimension: gold.dim_products
-- =============================================================================
DROP TABLE IF EXISTS gold.dim_products;

CREATE TABLE gold.dim_products (
    product_key    INT64,
    product_id     INT64,
    product_number STRING,
    product_name   STRING,
    category_id    STRING,
    category       STRING,
    subcategory    STRING,
    maintenance    STRING,
    cost           INT64,
    product_line   STRING,
    start_date     DATE
);

-- =============================================================================
-- Create Fact Table: gold.fact_sales
-- =============================================================================
DROP TABLE IF EXISTS gold.fact_sales;

CREATE TABLE gold.fact_sales (
    order_number  STRING,
    product_key   INT64,
    customer_key  INT64,
    order_date    DATE,
    shipping_date DATE,
    due_date      DATE,
    sales_amount  INT64,
    quantity      INT64,
    price         INT64
);
