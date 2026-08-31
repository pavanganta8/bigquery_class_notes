-- =========================================================================
-- PROJECT FILE: 02_dml.sql                                        (BigQuery)
-- DESCRIPTION: Inserts raw, uncleaned mock data into bronze landing tables
--              to simulate standard data quality challenges:
--              - leading/trailing spaces in names
--              - inconsistent date formats ('YYYY-MM-DD', 'DD-MM-YYYY')
--              - numeric fields formatted as currency strings ('$99.99')
--              - invalid/null rows, mixed genders ('m', 'Female', 'MALE', 'f')
--
-- PostgreSQL -> BigQuery notes:
--   - TRUNCATE TABLE works identically in BigQuery.
--   - Multi-row INSERT ... VALUES (...), (...), ...  is identical syntax.
--   - RAISE NOTICE at the end -> SELECT ... AS log_message (see
--     ../01_variables_and_datatypes.sql header for the full rationale).
-- =========================================================================

-- Clean up any existing data in bronze tables
TRUNCATE TABLE bronze.customer;
TRUNCATE TABLE bronze.products;
TRUNCATE TABLE bronze.sales;

-- 1. Insert raw mock data into bronze.customer
INSERT INTO bronze.customer (cust_id, cust_name, email, gender, created_date) VALUES
('1', '  John Doe  ', 'john.doe@example.com', 'MALE', '2026-01-15'),
('2', 'Alice Smith', 'alice.smith@example.com', 'f', '12-02-2026'),
('3', ' Bob Johnson ', 'bob.johnson@example.com', 'm', '2026/03/20'),
('4', 'Charlie Brown', 'charlie.b@example.com', 'M', '2026-04-05'),
('5', 'Eva Green', 'eva.green@example.com', 'Female', '05-05-2026'),
('6', 'Invalid Row', NULL, 'unknown', 'invalid_date'); -- data quality test row


-- 2. Insert raw mock data into bronze.products
INSERT INTO bronze.products (prod_id, prod_name, category, price) VALUES
('101', 'Standard Laptop', 'Electronics', '$1200.50'),
('102', 'Wireless Mouse', '  Electronics ', '$25.00'),
('103', 'Mechanical Keyboard', 'Electronics', '85.00'), -- normal format
('104', 'Ergonomic Chair', 'Furniture', '$350.00'),
('105', 'Water Bottle', 'Accessories', '$15.75'),
('106', 'Broken Product', 'Other', 'free'); -- price formatting issue row


-- 3. Insert raw mock data into bronze.sales
INSERT INTO bronze.sales (sale_id, cust_id, prod_id, qty, sale_date) VALUES
('5001', '1', '101', '1', '2026-06-01'),
('5002', '2', '102', ' 2 ', '2026-06-02'),
('5003', '3', '103', '1', '2026-06-03'),
('5004', '4', '104', '1', '2026-06-04'),
('5005', '5', '105', '5', '2026-06-05'),
('5006', '6', '101', '2', '2026-06-06'),   -- refers to customer 6 (which is invalid name)
('5007', '1', '106', '1', '2026-06-07');   -- refers to product 106 (invalid price)

SELECT 'Mock data successfully inserted into bronze tables.' AS log_message;
