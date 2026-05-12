-- create_db
CREATE DATABASE IF NOT EXISTS ecommerce_analytics;
USE ecommerce_analytics;

-- Import "stg_orders" table using Data Import Wizard.
-- Quick checks:
SELECT COUNT(*) rows_loaded FROM stg_orders;
SELECT MIN(order_date), MAX(order_date) FROM stg_orders;
SELECT sales_event, COUNT(*) FROM stg_orders GROUP BY sales_event;

-- Dimension Tables
DROP TABLE IF EXISTS dim_date;
CREATE TABLE dim_date (
  date_id INT AUTO_INCREMENT PRIMARY KEY,
  full_date DATE NOT NULL,
  year INT NOT NULL,
  month INT NOT NULL,
  month_name VARCHAR(10) NOT NULL,
  quarter INT NOT NULL,
  month_start DATE NOT NULL,
  UNIQUE KEY uq_dim_date_full_date (full_date),
  KEY ix_dim_date_year_month (year, month)
);

INSERT INTO dim_date (full_date, year, month, month_name, quarter, month_start)
SELECT
  d.full_date,
  YEAR(d.full_date),
  MONTH(d.full_date),
  DATE_FORMAT(d.full_date, '%b'),
  QUARTER(d.full_date),
  DATE_SUB(d.full_date, INTERVAL DAYOFMONTH(d.full_date)-1 DAY)
FROM (
  SELECT DISTINCT order_date AS full_date
  FROM stg_orders
) d;

-- Quick checks:
SELECT * FROM dim_date;

DROP TABLE IF EXISTS dim_state;
CREATE TABLE dim_state (
  state_id INT AUTO_INCREMENT PRIMARY KEY,
  state_name VARCHAR(100) NOT NULL,
  zone VARCHAR(50) NOT NULL,
  UNIQUE KEY uq_state (state_name)
);

INSERT INTO dim_state (state_name, zone)
SELECT state, MAX(zone)
FROM stg_orders
GROUP BY state;
-- Quick checks:
SELECT * FROM dim_state;

DROP TABLE IF EXISTS dim_product;
CREATE TABLE dim_product (
  product_id INT AUTO_INCREMENT PRIMARY KEY,
  category VARCHAR(100) NOT NULL,
  brand_type VARCHAR(20) NOT NULL,
  UNIQUE KEY uq_product (category, brand_type),
  KEY ix_product_category (category),
  KEY ix_product_brand (brand_type)
);

INSERT INTO dim_product (category, brand_type)
SELECT DISTINCT category, brand_type
FROM stg_orders
ORDER BY category;
-- Quick checks:
SELECT * FROM dim_product;

DROP TABLE IF EXISTS dim_customer_demo;
CREATE TABLE dim_customer_demo (
  customer_demo_id INT AUTO_INCREMENT PRIMARY KEY,
  customer_gender VARCHAR(10) NOT NULL,
  customer_age INT NOT NULL,
  customer_age_group VARCHAR(20) NOT NULL,
  UNIQUE KEY uq_demo (customer_gender, customer_age),
  KEY ix_demo_age_group (customer_age_group)
);

INSERT INTO dim_customer_demo (customer_gender, customer_age, customer_age_group)
SELECT DISTINCT
  customer_gender,
  customer_age,
  CASE
    WHEN customer_age BETWEEN 18 AND 24 THEN 'Youth'
    WHEN customer_age BETWEEN 25 AND 44 THEN 'Young Adult'
    WHEN customer_age BETWEEN 45 AND 59 THEN 'Middle-aged'
    ELSE 'Elderly'
  END AS customer_age_group
FROM stg_orders
ORDER BY customer_age;
-- Quick checks:
SELECT * FROM dim_customer_demo;

DROP TABLE IF EXISTS dim_event;
CREATE TABLE dim_event (
  event_id INT AUTO_INCREMENT PRIMARY KEY,
  sales_event VARCHAR(20) NOT NULL,
  UNIQUE KEY uq_event (sales_event)
);

INSERT INTO dim_event (sales_event)
SELECT DISTINCT sales_event FROM stg_orders;
-- Quick checks:
SELECT * FROM dim_event ORDER BY event_id;

-- Fact table
DROP TABLE IF EXISTS fact_orders;
CREATE TABLE fact_orders (
  fact_order_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  order_id VARCHAR (30) NOT NULL,
  date_id INT NOT NULL,
  state_id INT NOT NULL,
  product_id INT NOT NULL,
  customer_demo_id INT NOT NULL,
  event_id INT NOT NULL,

  base_price DECIMAL(10,2) NOT NULL,
  discount_percent DECIMAL(5,2) NOT NULL,
  final_price DECIMAL(10,2) NOT NULL,

  units_sold INT NOT NULL,
  revenue DECIMAL(12,2) NOT NULL,

  competition_intensity VARCHAR(20) NOT NULL,
  inventory_pressure VARCHAR(20) NOT NULL,

  UNIQUE KEY uq_order (order_id),
  KEY ix_fact_date (date_id),
  KEY ix_fact_state (state_id),
  KEY ix_fact_product (product_id),
  KEY ix_fact_event (event_id),
  KEY ix_fact_discount (discount_percent),
  KEY ix_fact_comp (competition_intensity),
  KEY ix_fact_inventory (inventory_pressure),

  CONSTRAINT fk_fact_date FOREIGN KEY (date_id) REFERENCES dim_date(date_id),
  CONSTRAINT fk_fact_state FOREIGN KEY (state_id) REFERENCES dim_state(state_id),
  CONSTRAINT fk_fact_product FOREIGN KEY (product_id) REFERENCES dim_product(product_id),
  CONSTRAINT fk_fact_demo FOREIGN KEY (customer_demo_id) REFERENCES dim_customer_demo(customer_demo_id),
  CONSTRAINT fk_fact_event FOREIGN KEY (event_id) REFERENCES dim_event(event_id)
);

INSERT INTO fact_orders (
  order_id, date_id, state_id, product_id, customer_demo_id, event_id,
  base_price, discount_percent, final_price, units_sold, revenue,
  competition_intensity, inventory_pressure
)
SELECT
  s.order_id,
  d.date_id,
  st.state_id,
  p.product_id,
  cd.customer_demo_id,
  e.event_id,
  s.base_price,
  s.discount_percent,
  s.final_price,
  s.units_sold,
  s.revenue,
  s.competition_intensity,
  s.inventory_pressure
FROM stg_orders s
JOIN dim_date d ON d.full_date = s.order_date
JOIN dim_state st ON st.state_name = s.state
JOIN dim_product p ON p.category = s.category AND p.brand_type = s.brand_type
JOIN dim_customer_demo cd ON cd.customer_gender = s.customer_gender AND cd.customer_age = s.customer_age
JOIN dim_event e ON e.sales_event = s.sales_event;
-- Quick checks:
SELECT * FROM fact_orders LIMIT 10;