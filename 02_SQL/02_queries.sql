USE ecommerce_analytics;

-- Top 5 states by revenue (36 months)
SELECT
  st.state_name,
  st.zone,
  SUM(f.revenue) AS total_revenue
FROM fact_orders f
JOIN dim_state st ON st.state_id = f.state_id
GROUP BY st.state_name
ORDER BY total_revenue DESC
LIMIT 5;

-- Segmentation of revenue by state and customer_age_group
SELECT
  st.state_name,
  cd.customer_age_group,
  SUM(f.revenue) AS total_revenue,
  NTILE(4) OVER (PARTITION BY cd.customer_age_group ORDER BY SUM(f.revenue)) AS revenue_quartile
FROM fact_orders f
JOIN dim_state st ON st.state_id = f.state_id
JOIN dim_customer_demo cd ON cd.customer_demo_id = f.customer_demo_id
GROUP BY st.state_name, cd.customer_age_group;

-- Pricing Sensitivity:
SELECT
p.category,
p.brand_type,
CASE
    WHEN discount_percent <= 10 THEN 'Low Incentive'
    WHEN discount_percent <= 30 THEN 'Moderate Incentive'
    ELSE 'High Incentive'
END AS sensitivity_group,
SUM(f.units_sold) AS units,
ROUND(
    SUM(f.units_sold) /
    SUM(SUM(f.units_sold)) OVER (PARTITION BY p.category, p.brand_type),
4
) AS unit_share
FROM fact_orders f
JOIN dim_product p
    ON p.product_id = f.product_id
GROUP BY
p.category,
p.brand_type,
sensitivity_group;

-- Revenue Loss by Discount Brackets
SELECT
discount_band(discount_percent) AS discount_range,
SUM(revenue) AS revenue,
SUM(units_sold) AS units,
SUM(revenue_loss(base_price, discount_percent, units_sold)) AS revenue_forfeited
FROM fact_orders
GROUP BY discount_range
ORDER BY discount_range;

-- Revenue per Transaction: Festival vs Normal
WITH txn_metrics AS (
  SELECT
    e.sales_event,
    SUM(f.revenue) AS total_revenue,
    COUNT(DISTINCT f.order_id) AS total_transactions,
    SUM(f.revenue) / NULLIF(COUNT(DISTINCT f.order_id), 0) AS revenue_per_transaction
  FROM fact_orders f
  JOIN dim_event e
    ON e.event_id = f.event_id
  GROUP BY e.sales_event
)
SELECT
  ROUND(MAX(CASE WHEN sales_event = 'Festival' THEN total_revenue END), 2) AS festival_revenue,
  MAX(CASE WHEN sales_event = 'Festival' THEN total_transactions END) AS festival_transactions,
  ROUND(MAX(CASE WHEN sales_event = 'Festival' THEN revenue_per_transaction END), 2) AS festival_revenue_per_transaction,

  ROUND(MAX(CASE WHEN sales_event = 'Normal' THEN total_revenue END), 2) AS normal_revenue,
  MAX(CASE WHEN sales_event = 'Normal' THEN total_transactions END) AS normal_transactions,
  ROUND(MAX(CASE WHEN sales_event = 'Normal' THEN revenue_per_transaction END), 2) AS normal_revenue_per_transaction,

  ROUND(
    100 * (
      MAX(CASE WHEN sales_event = 'Festival' THEN revenue_per_transaction END) /
      NULLIF(MAX(CASE WHEN sales_event = 'Normal' THEN revenue_per_transaction END), 0) - 1
    ),
    2
  ) AS revenue_per_transaction_lift_pct
FROM txn_metrics;

-- Revenue per Transaction by Category: Festival vs Normal
WITH txn_metrics AS (
  SELECT
    p.category,
    e.sales_event,
    SUM(f.revenue) AS total_revenue,
    COUNT(DISTINCT f.order_id) AS total_transactions,
    SUM(f.revenue) / NULLIF(COUNT(DISTINCT f.order_id), 0) AS revenue_per_transaction
  FROM fact_orders f
  JOIN dim_product p
    ON p.product_id = f.product_id
  JOIN dim_event e
    ON e.event_id = f.event_id
  GROUP BY p.category, e.sales_event
)
SELECT
  category,
  ROUND(MAX(CASE WHEN sales_event = 'Festival' THEN total_revenue END), 2) AS festival_revenue,
  MAX(CASE WHEN sales_event = 'Festival' THEN total_transactions END) AS festival_transactions,
  ROUND(MAX(CASE WHEN sales_event = 'Festival' THEN revenue_per_transaction END), 2) AS festival_revenue_per_transaction,

  ROUND(MAX(CASE WHEN sales_event = 'Normal' THEN total_revenue END), 2) AS normal_revenue,
  MAX(CASE WHEN sales_event = 'Normal' THEN total_transactions END) AS normal_transactions,
  ROUND(MAX(CASE WHEN sales_event = 'Normal' THEN revenue_per_transaction END), 2) AS normal_revenue_per_transaction,

  ROUND(
    100 * (
      MAX(CASE WHEN sales_event = 'Festival' THEN revenue_per_transaction END) /
      NULLIF(MAX(CASE WHEN sales_event = 'Normal' THEN revenue_per_transaction END), 0) - 1
    ),
    2
  ) AS revenue_per_transaction_lift_pct
FROM txn_metrics
GROUP BY category
ORDER BY revenue_per_transaction_lift_pct DESC;

-- Festival Lift by Category and Brand Type: Average Monthly Revenue in Festival vs Normal
WITH monthly_rev AS (
  SELECT
    p.brand_type,
    p.category,
    e.sales_event,
    d.full_date,
    SUM(f.revenue) AS monthly_revenue
  FROM fact_orders f
  JOIN dim_product p
    ON p.product_id = f.product_id
  JOIN dim_event e
    ON e.event_id = f.event_id
  JOIN dim_date d
    ON d.date_id = f.date_id
  GROUP BY
    p.brand_type,
    p.category,
    e.sales_event,
    d.full_date
),
avg_rev AS (
  SELECT
    brand_type,
    category,
    sales_event,
    AVG(monthly_revenue) AS avg_monthly_revenue
  FROM monthly_rev
  GROUP BY
    category,
	brand_type,
    sales_event
)
SELECT
  category,
  brand_type,
  ROUND(MAX(CASE WHEN sales_event = 'Festival' THEN avg_monthly_revenue END), 2) AS festival_avg_monthly_revenue,
  ROUND(MAX(CASE WHEN sales_event = 'Normal' THEN avg_monthly_revenue END), 2) AS normal_avg_monthly_revenue,
  ROUND(
    100 * (
      MAX(CASE WHEN sales_event = 'Festival' THEN avg_monthly_revenue END)
      / NULLIF(MAX(CASE WHEN sales_event = 'Normal' THEN avg_monthly_revenue END), 0) - 1
    ),
    2
  ) AS festival_lift_pct
FROM avg_rev
GROUP BY category, brand_type
ORDER BY category, festival_lift_pct DESC;

-- Festival Lift by Category + Discount Behaviour
WITH monthly_metrics AS (
  SELECT
    p.category,
    e.sales_event,
    d.full_date,
    SUM(f.revenue) AS monthly_revenue,
    AVG(f.discount_percent) AS avg_discount
  FROM fact_orders f
  JOIN dim_product p
    ON p.product_id = f.product_id
  JOIN dim_event e
    ON e.event_id = f.event_id
  JOIN dim_date d
    ON d.date_id = f.date_id
  GROUP BY
    p.category,
    e.sales_event,
    d.full_date
),

avg_metrics AS (
  SELECT
    category,
    sales_event,
    AVG(monthly_revenue) AS avg_monthly_revenue,
    AVG(avg_discount) AS avg_discount_pct
  FROM monthly_metrics
  GROUP BY
    category,
    sales_event
)

SELECT
  category,

  ROUND(MAX(CASE WHEN sales_event = 'Festival'
       THEN avg_monthly_revenue END),2) AS festival_avg_monthly_revenue,

  ROUND(MAX(CASE WHEN sales_event = 'Normal'
       THEN avg_monthly_revenue END),2) AS normal_avg_monthly_revenue,

  ROUND(
    100 * (
      MAX(CASE WHEN sales_event = 'Festival'
           THEN avg_monthly_revenue END)
      / NULLIF(MAX(CASE WHEN sales_event = 'Normal'
           THEN avg_monthly_revenue END),0) - 1
    ),2
  ) AS festival_lift_pct,

  ROUND(MAX(CASE WHEN sales_event = 'Festival'
       THEN avg_discount_pct END),2) AS festival_avg_discount,

  ROUND(MAX(CASE WHEN sales_event = 'Normal'
       THEN avg_discount_pct END),2) AS normal_avg_discount

FROM avg_metrics
GROUP BY category
ORDER BY festival_lift_pct DESC;

-- Optimal Discount Range by Category (highest revenue bracket)
WITH band_perf AS (
  SELECT
    p.category,
    discount_band(f.discount_percent) AS discount_band,
    COUNT(DISTINCT f.order_id) AS total_transactions,
    SUM(f.units_sold) AS total_units,
    SUM(f.revenue) AS total_revenue,
    AVG(f.discount_percent) AS avg_discount_pct,
    SUM(f.revenue) / NULLIF(COUNT(DISTINCT f.order_id), 0) AS revenue_per_transaction,
    SUM(f.revenue) / NULLIF(SUM(f.units_sold), 0) AS revenue_per_unit
  FROM fact_orders f
  JOIN dim_product p
    ON p.product_id = f.product_id
  GROUP BY
    p.category,
    discount_band(f.discount_percent)
),
ranked AS (
  SELECT
    category,
    discount_band,
    total_transactions,
    total_units,
    total_revenue,
    avg_discount_pct,
    revenue_per_transaction,
    revenue_per_unit,
    ROW_NUMBER() OVER (
      PARTITION BY category
      ORDER BY total_revenue DESC
    ) AS revenue_rank
  FROM band_perf
)
SELECT
  category,
  discount_band AS optimal_discount_band,
  ROUND(avg_discount_pct, 2) AS avg_discount_pct_in_band,
  total_transactions,
  total_units,
  ROUND(total_revenue, 2) AS total_revenue,
  ROUND(revenue_per_transaction, 2) AS revenue_per_transaction,
  ROUND(revenue_per_unit, 2) AS revenue_per_unit
FROM ranked
WHERE revenue_rank = 1
ORDER BY total_revenue DESC;

-- Optimal Discount Range by Category using Revenue per Transaction
WITH band_perf AS (
  SELECT
    p.category,
    discount_band(f.discount_percent) AS discount_band,
    COUNT(DISTINCT f.order_id) AS total_transactions,
    SUM(f.units_sold) AS total_units,
    SUM(f.revenue) AS total_revenue,
    AVG(f.discount_percent) AS avg_discount_pct,
    SUM(f.revenue) / NULLIF(COUNT(DISTINCT f.order_id), 0) AS revenue_per_transaction,
    SUM(f.revenue) / NULLIF(SUM(f.units_sold), 0) AS revenue_per_unit
  FROM fact_orders f
  JOIN dim_product p
    ON p.product_id = f.product_id
  GROUP BY
    p.category,
    discount_band(f.discount_percent)
),
ranked AS (
  SELECT
    category,
    discount_band,
    total_transactions,
    total_units,
    total_revenue,
    avg_discount_pct,
    revenue_per_transaction,
    revenue_per_unit,
    ROW_NUMBER() OVER (
      PARTITION BY category
      ORDER BY revenue_per_transaction DESC
    ) AS rpt_rank
  FROM band_perf
)
SELECT
  category,
  discount_band AS optimal_discount_band,
  ROUND(avg_discount_pct, 2) AS avg_discount_pct_in_band,
  total_transactions,
  total_units,
  ROUND(total_revenue, 2) AS total_revenue,
  ROUND(revenue_per_transaction, 2) AS revenue_per_transaction,
  ROUND(revenue_per_unit, 2) AS revenue_per_unit
FROM ranked
WHERE rpt_rank = 1
ORDER BY revenue_per_transaction DESC;

-- Discount cannibalisation analysis by category
WITH discount_perf AS (
  SELECT
    p.category,
    discount_band(f.discount_percent) AS discount_band,
    COUNT(DISTINCT f.order_id) AS total_transactions,
    SUM(f.units_sold) AS total_units,
    SUM(f.revenue) AS total_revenue,
    AVG(f.discount_percent) AS avg_discount_pct,
    SUM(f.revenue) / NULLIF(COUNT(DISTINCT f.order_id), 0) AS revenue_per_transaction,
    SUM(f.revenue) / NULLIF(SUM(f.units_sold), 0) AS revenue_per_unit,
    SUM(f.units_sold) / NULLIF(COUNT(DISTINCT f.order_id), 0) AS units_per_transaction
  FROM fact_orders f
  JOIN dim_product p
    ON p.product_id = f.product_id
  GROUP BY
    p.category,
    discount_band(f.discount_percent)
),
band_compare AS (
  SELECT
    category,
    discount_band,
    avg_discount_pct,
    total_transactions,
    total_units,
    total_revenue,
    revenue_per_transaction,
    revenue_per_unit,
    units_per_transaction,
    LAG(revenue_per_transaction) OVER (
      PARTITION BY category
      ORDER BY avg_discount_pct
    ) AS prev_rpt,
    LAG(revenue_per_unit) OVER (
      PARTITION BY category
      ORDER BY avg_discount_pct
    ) AS prev_rpu,
    LAG(units_per_transaction) OVER (
      PARTITION BY category
      ORDER BY avg_discount_pct
    ) AS prev_upt
  FROM discount_perf
)
SELECT
  category,
  discount_band,
  ROUND(avg_discount_pct, 2) AS avg_discount_pct,
  total_transactions,
  total_units,
  ROUND(total_revenue, 2) AS total_revenue,
  ROUND(units_per_transaction, 2) AS units_per_transaction,
  ROUND(revenue_per_transaction, 2) AS revenue_per_transaction,
  ROUND(revenue_per_unit, 2) AS revenue_per_unit,
  ROUND(
    100 * (units_per_transaction / NULLIF(prev_upt, 0) - 1), 2
  ) AS upt_change_pct,
  ROUND(
    100 * (revenue_per_transaction / NULLIF(prev_rpt, 0) - 1), 2
  ) AS rpt_change_pct,
  ROUND(
    100 * (revenue_per_unit / NULLIF(prev_rpu, 0) - 1), 2
  ) AS rpu_change_pct,
  CASE
    WHEN units_per_transaction > prev_upt
         AND revenue_per_transaction < prev_rpt
         AND revenue_per_unit < prev_rpu
    THEN 'Cannibalisation Risk'
    WHEN units_per_transaction > prev_upt
         AND revenue_per_transaction < prev_rpt
    THEN 'Volume Up, Order Value Down'
    WHEN units_per_transaction <= prev_upt
         AND revenue_per_transaction < prev_rpt
    THEN 'Deeper Discount, No Demand Gain'
    ELSE 'No Clear Cannibalisation'
  END AS cannibalization_flag
FROM band_compare
ORDER BY category, avg_discount_pct;

-- Category-level Price Sensitivity (Elasticity Proxy)
WITH monthly_cat AS (
  SELECT
    dd.month_start,
    p.category,
    SUM(f.units_sold) AS units,
    -- weighted avg final price (better than simple AVG)
    SUM(f.final_price * f.units_sold) / NULLIF(SUM(f.units_sold), 0) AS w_avg_final_price,
    AVG(f.discount_percent) AS avg_discount
  FROM fact_orders f
  JOIN dim_date dd ON dd.date_id = f.date_id
  JOIN dim_product p ON p.product_id = f.product_id
  GROUP BY dd.month_start, p.category
),
chg AS (
  SELECT
    month_start,
    category,
    units,
    w_avg_final_price,
    avg_discount,
    LAG(units) OVER (PARTITION BY category ORDER BY month_start) AS prev_units,
    LAG(w_avg_final_price) OVER (PARTITION BY category ORDER BY month_start) AS prev_price
  FROM monthly_cat
)
SELECT
  month_start,
  category,
  units,
  ROUND(w_avg_final_price, 2) AS w_avg_final_price,
  ROUND(
    100 * (units - prev_units) / NULLIF(prev_units, 0), 2
  ) AS units_change_pct,
  ROUND(
    100 * (w_avg_final_price - prev_price) / NULLIF(prev_price, 0), 2
  ) AS price_change_pct,
  -- Elasticity proxy: %ΔUnits / %ΔPrice (negative is expected in real life)
  ROUND(
    ( (units - prev_units) / NULLIF(prev_units, 0) )
    /
    NULLIF( (w_avg_final_price - prev_price) / NULLIF(prev_price, 0), 0 )
  , 3) AS elasticity_proxy
FROM chg
WHERE prev_units IS NOT NULL
  AND prev_price IS NOT NULL
ORDER BY category, month_start;

-- Margin Risk Pockets
WITH seg AS (
  SELECT
    st.state_name,
    p.category,
    p.brand_type,
    e.sales_event,
    SUM(f.revenue) AS revenue,
    SUM(f.units_sold) AS units,
    ROUND(AVG(f.discount_percent), 2) AS avg_discount,
    -- proxy for margin health: how much of base price was actually realized
    ROUND(
      SUM(f.final_price * f.units_sold) / NULLIF(SUM(f.base_price * f.units_sold), 0)
    , 3) AS realization_ratio,
    ROUND(SUM(f.revenue) / NULLIF(SUM(f.units_sold), 0), 2) AS revenue_per_unit
  FROM fact_orders f
  JOIN dim_state st ON st.state_id = f.state_id
  JOIN dim_product p ON p.product_id = f.product_id
  JOIN dim_event e ON e.event_id = f.event_id
  GROUP BY st.state_name, p.category, p.brand_type, e.sales_event
),
ranked AS (
  SELECT
    *,
    DENSE_RANK() OVER (ORDER BY revenue DESC) AS revenue_rank,
    DENSE_RANK() OVER (ORDER BY realization_ratio ASC) AS margin_risk_rank
  FROM seg
)
SELECT
  state_name,
  category,
  brand_type,
  sales_event,
  revenue,
  units,
  avg_discount,
  realization_ratio,
  revenue_per_unit,
  -- high revenue + low realization ratio = where margin risk hides
  (revenue_rank + margin_risk_rank) AS risk_priority_score
FROM ranked
WHERE revenue_rank <= 30      -- focus on meaningful segments
ORDER BY risk_priority_score ASC, revenue DESC;