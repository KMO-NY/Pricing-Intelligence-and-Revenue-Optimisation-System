USE ecommerce_analytics;

-- Refresh monthly summary table
DROP TABLE IF EXISTS rpt_monthly_summary;
CREATE TABLE rpt_monthly_summary (
  year INT,
  month INT,
  month_start DATE,
  total_revenue DECIMAL(14,2),
  total_units BIGINT,
  avg_discount DECIMAL(6,2),
  PRIMARY KEY (month_start)
);

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_refresh_monthly_summary $$
CREATE PROCEDURE sp_refresh_monthly_summary()
BEGIN
  TRUNCATE TABLE rpt_monthly_summary;

  INSERT INTO rpt_monthly_summary (year, month, month_start, total_revenue, total_units, avg_discount)
  SELECT
    dd.year,
    dd.month,
    dd.month_start,
    SUM(f.revenue) AS total_revenue,
    SUM(f.units_sold) AS total_units,
    AVG(f.discount_percent) AS avg_discount
  FROM fact_orders f
  JOIN dim_date dd ON dd.date_id = f.date_id
  GROUP BY dd.year, dd.month, dd.month_start;
END $$

DELIMITER ;

-- Run it
CALL sp_refresh_monthly_summary();
SELECT * FROM rpt_monthly_summary ORDER BY month_start;

-- State performance report
DELIMITER $$

DROP PROCEDURE IF EXISTS sp_state_performance $$
CREATE PROCEDURE sp_state_performance(IN p_state VARCHAR(100))
BEGIN
  SELECT
    st.state_name,
    dd.year,
    dd.month_name,
    dd.month_start,
    SUM(f.revenue) AS revenue,
    SUM(f.units_sold) AS units,
    ROUND(AVG(f.discount_percent), 2) AS avg_discount
  FROM fact_orders f
  JOIN dim_state st ON st.state_id = f.state_id
  JOIN dim_date dd ON dd.date_id = f.date_id
  WHERE st.state_name = p_state
  GROUP BY st.state_name, dd.year, dd.month_name, dd.month_start
  ORDER BY dd.month_start;
END $$

DELIMITER ;

CALL sp_state_performance('Maharashtra');
CALL sp_state_performance('Delhi NCR');