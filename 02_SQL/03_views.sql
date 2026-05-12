USE ecommerce_analytics;

DROP VIEW IF EXISTS v_monthly_revenue_summary;

CREATE OR REPLACE VIEW v_monthly_revenue_summary AS
WITH monthly AS (
    SELECT
        dd.year,
        dd.month_name,
        dd.month_start,
        SUM(f.revenue) AS total_revenue,
        SUM(f.units_sold) AS total_units,
        ROUND(
            SUM(f.discount_percent * f.units_sold) / NULLIF(SUM(f.units_sold), 0),
            2
        ) AS w_avg_discount
    FROM fact_orders f
    JOIN dim_date dd
        ON dd.date_id = f.date_id
    GROUP BY
        dd.year,
        dd.month_name,
        dd.month_start
),
lagged AS (
    SELECT
        *,
        LAG(total_units) OVER (ORDER BY month_start) AS prev_units,
        LAG(total_revenue) OVER (ORDER BY month_start) AS prev_revenue
    FROM monthly
)
SELECT
    year,
    month_name,
    month_start,

    total_revenue,
    total_units,
    w_avg_discount,

    prev_units,
    prev_revenue,

    ROUND(
        CASE
            WHEN prev_units IS NULL OR prev_units = 0 THEN NULL
            ELSE (total_units - prev_units) * 100.0 / prev_units
        END,
        2
    ) AS unit_growth_pct,

    ROUND(
        CASE
            WHEN prev_revenue IS NULL OR prev_revenue = 0 THEN NULL
            ELSE (total_revenue - prev_revenue) * 100.0 / prev_revenue
        END,
        2
    ) AS revenue_growth_pct

FROM lagged;

-- Quick checks:
SELECT * FROM v_monthly_revenue_summary;

DROP VIEW IF EXISTS v_event_uplift_by_category;
CREATE OR REPLACE VIEW v_event_uplift_by_category AS
WITH monthly_event AS (
    SELECT
        dd.month_start,
        p.category,
        p.brand_type,
        e.sales_event,
        SUM(f.revenue) AS total_revenue,
        SUM(f.units_sold) AS total_units,
        ROUND(SUM(f.discount_percent * f.units_sold) / NULLIF(SUM(f.units_sold), 0)) AS avg_discount_percent
    FROM fact_orders f
    JOIN dim_date dd
        ON dd.date_id = f.date_id
    JOIN dim_product p
        ON p.product_id = f.product_id
    JOIN dim_event e
        ON e.event_id = f.event_id
    GROUP BY
        dd.month_start,
        p.category,
        p.brand_type,
        e.sales_event
),
baseline AS (
    SELECT
        category,
        brand_type,
        AVG(CASE WHEN sales_event = 'Normal' THEN total_revenue END) AS normal_avg_revenue,
        AVG(CASE WHEN sales_event = 'Normal' THEN total_units END) AS normal_avg_units
    FROM monthly_event
    GROUP BY
        category,
        brand_type
)
SELECT
    me.month_start,
    me.category,
    me.brand_type,
    me.sales_event,
    me.total_revenue,
    me.total_units,
    ROUND(me.avg_discount_percent, 4) AS avg_discount_percent,
    b.normal_avg_revenue,
    b.normal_avg_units,
    ROUND(me.total_revenue - b.normal_avg_revenue, 2) AS revenue_uplift_vs_normal,
    ROUND(me.total_units - b.normal_avg_units, 2) AS unit_uplift_vs_normal
FROM monthly_event me
JOIN baseline b
    ON me.category = b.category
   AND me.brand_type = b.brand_type;

-- Quick checks:
SELECT * FROM v_event_uplift_by_category;
SELECT * FROM v_event_uplift_by_category WHERE sales_event = "Festival";

-- Revenue by Discount Over Time
DROP VIEW IF EXISTS v_monthly_discount_band;
CREATE VIEW v_monthly_discount_band AS
SELECT
  dd.year,
  dd.month,
  dd.month_start,
  discount_band(f.discount_percent) AS discount_band,
  SUM(f.revenue) AS total_revenue,
  SUM(f.units_sold) AS total_units,
  ROUND(SUM(f.revenue) / NULLIF(SUM(f.units_sold), 0), 2) AS revenue_per_unit,
  ROUND(SUM(f.discount_percent * f.units_sold) / NULLIF(SUM(f.units_sold), 0), 2) AS w_avg_discount
FROM fact_orders f
JOIN dim_date dd ON dd.date_id = f.date_id
GROUP BY dd.year, dd.month, dd.month_start, discount_band;

-- Quick checks:
SELECT * FROM v_monthly_discount_band;

-- Discounting Impact:
DROP VIEW IF EXISTS v_discount_band_performance;
CREATE OR REPLACE VIEW v_discount_band_performance AS
WITH banded AS (
    SELECT
        dd.month_start,
        p.category,
        p.brand_type,
        st.state_name,
        discount_band(f.discount_percent) AS discount_range,
        SUM(f.units_sold) AS total_units,
        SUM(f.revenue) AS total_revenue,
        SUM(CAST(f.base_price * f.units_sold AS DECIMAL(20,2))) AS gross_base_revenue,
        SUM(CAST((f.base_price - f.final_price) * f.units_sold AS DECIMAL(20,2))) AS total_discount_cost,
        SUM(f.discount_percent * f.units_sold) / NULLIF(SUM(f.units_sold), 0) AS avg_discount_percent,
        SUM(f.final_price * f.units_sold) / NULLIF(SUM(f.units_sold), 0) AS avg_final_price
    FROM fact_orders f
    JOIN dim_date dd
        ON dd.date_id = f.date_id
    JOIN dim_product p
        ON p.product_id = f.product_id
    JOIN dim_state st
        ON st.state_id = f.state_id
    GROUP BY
        dd.month_start,
        p.category,
        p.brand_type,
        st.state_name,
        discount_band(f.discount_percent)
)
SELECT
    month_start,
    category,
    brand_type,
    state_name,
    discount_range,
    total_units,
    total_revenue,
    gross_base_revenue,
    total_discount_cost,
    ROUND(total_discount_cost / NULLIF(total_revenue, 0), 4) AS discount_cost_ratio,
    ROUND(avg_discount_percent, 4) AS avg_discount_percent,
    ROUND(avg_final_price, 2) AS avg_final_price
FROM banded;

SELECT *
FROM v_discount_band_performance;

-- Discount Impact Stability
DROP VIEW IF EXISTS v_discount_response_quality;

CREATE OR REPLACE VIEW v_discount_response_quality AS
WITH monthly AS (
    SELECT
        dd.month_start,
        p.category,
        p.brand_type,
        st.state_name,
        e.sales_event,
        ROUND(
            SUM(f.discount_percent * f.units_sold) / NULLIF(SUM(f.units_sold),0),
            2
        ) AS w_avg_discount,
        SUM(f.units_sold) AS units
    FROM fact_orders f
    JOIN dim_date dd ON dd.date_id = f.date_id
    JOIN dim_product p ON p.product_id = f.product_id
    JOIN dim_state st ON st.state_id = f.state_id
    JOIN dim_event e ON e.event_id = f.event_id
    GROUP BY
        dd.month_start,
        p.category,
        p.brand_type,
        st.state_name,
        e.sales_event
),
lagged AS (
    SELECT
        *,
        LAG(w_avg_discount) OVER (
            PARTITION BY category, brand_type, state_name, sales_event
            ORDER BY month_start
        ) AS prev_discount,
        LAG(units) OVER (
            PARTITION BY category, brand_type, state_name, sales_event
            ORDER BY month_start
        ) AS prev_units
    FROM monthly
)
SELECT
    category,
    brand_type,
    state_name,
    sales_event,

    COUNT(*) AS observations,

    SUM(
        CASE
            WHEN w_avg_discount > prev_discount AND units > prev_units THEN 1
            ELSE 0
        END
    ) AS discount_up_units_up,

    SUM(
        CASE
            WHEN w_avg_discount < prev_discount AND units < prev_units THEN 1
            ELSE 0
        END
    ) AS discount_down_units_down,

    ROUND(
        SUM(
            CASE
                WHEN w_avg_discount > prev_discount AND units > prev_units THEN 1
                ELSE 0
            END
        ) / NULLIF(COUNT(*),0),
        2
    ) AS positive_response_rate,

    ROUND(
        AVG(
            CASE
                WHEN prev_discount IS NOT NULL AND prev_units IS NOT NULL
                THEN ((units - prev_units) / NULLIF(prev_units,0)) /
                     NULLIF((w_avg_discount - prev_discount) / NULLIF(prev_discount,0), 0)
            END
        ),
        4
    ) AS avg_response_ratio

FROM lagged
GROUP BY
    category,
    brand_type,
    state_name,
    sales_event;

-- Quick Check:
SELECT * FROM v_discount_response_quality;

DROP VIEW IF EXISTS v_price_sensitivity_by_segment;
CREATE OR REPLACE VIEW v_price_sensitivity_by_segment AS
WITH seg AS (
    SELECT
        cd.customer_age_group,
        p.category,
        p.brand_type,
        st.state_name,
        CASE
            WHEN f.discount_percent < 10 THEN 'LOW'
            WHEN f.discount_percent >= 40 THEN 'HIGH'
            ELSE 'MID'
        END AS discount_group,
        SUM(f.final_price * f.units_sold) / NULLIF(SUM(f.units_sold), 0) AS avg_price,
        SUM(f.units_sold) AS total_units,
        SUM(f.revenue) AS total_revenue
    FROM fact_orders f
    JOIN dim_product p
        ON p.product_id = f.product_id
    JOIN dim_state st
        ON st.state_id = f.state_id
	JOIN dim_customer_demo cd
		ON cd.customer_demo_id = f.customer_demo_id
    GROUP BY
        cd.customer_age_group,
        p.category,
        p.brand_type,
        st.state_name,
        CASE
            WHEN f.discount_percent < 10 THEN 'LOW'
            WHEN f.discount_percent >= 40 THEN 'HIGH'
            ELSE 'MID'
        END
),
pivoted AS (
    SELECT
        customer_age_group,
        category,
        brand_type,
        state_name,
        MAX(CASE WHEN discount_group = 'LOW' THEN avg_price END) AS low_discount_price,
        MAX(CASE WHEN discount_group = 'MID' THEN avg_price END) AS mid_discount_price,
        MAX(CASE WHEN discount_group = 'HIGH' THEN avg_price END) AS high_discount_price,
        MAX(CASE WHEN discount_group = 'LOW' THEN total_units END) AS low_discount_units,
        MAX(CASE WHEN discount_group = 'MID' THEN total_units END) AS mid_discount_units,
        MAX(CASE WHEN discount_group = 'HIGH' THEN total_units END) AS high_discount_units,
        MAX(CASE WHEN discount_group = 'LOW' THEN total_revenue END) AS low_discount_revenue,
        MAX(CASE WHEN discount_group = 'MID' THEN total_revenue END) AS mid_discount_revenue,
        MAX(CASE WHEN discount_group = 'HIGH' THEN total_revenue END) AS high_discount_revenue
    FROM seg
    GROUP BY
        category,
        brand_type,
        state_name,
        customer_age_group
),
elasticity_calc AS (
	SELECT
		category,
		brand_type,
		state_name,
		customer_age_group,
		low_discount_price,
		mid_discount_price,
		high_discount_price,
		low_discount_units,
		mid_discount_units,
		high_discount_units,
		low_discount_revenue,
		mid_discount_revenue,
		high_discount_revenue,
		ROUND(
			(
				(high_discount_units - low_discount_units) / NULLIF(low_discount_units, 0)
			) /
			(
				(high_discount_price - low_discount_price) / NULLIF(low_discount_price, 0)
			)
		, 4) AS elasticity_proxy
	FROM pivoted)
SELECT
    *,
    CASE
        WHEN ABS(elasticity_proxy) >= 1 THEN 'Highly Sensitive'
        WHEN ABS(elasticity_proxy) >= 0.5 THEN 'Moderately Sensitive'
        ELSE 'Low Sensitivity'
    END AS sensitivity_segment
FROM elasticity_calc;

SELECT * 
FROM v_price_sensitivity_by_segment;

DROP VIEW IF EXISTS v_state_growth;
CREATE OR REPLACE VIEW v_state_growth AS
WITH monthly AS (
    SELECT
        st.state_name,
        dd.year,
        dd.month_name,
        dd.month_start,
        SUM(f.revenue) AS revenue
    FROM fact_orders f
    JOIN dim_state st ON st.state_id = f.state_id
    JOIN dim_date dd ON dd.date_id = f.date_id
    GROUP BY st.state_name, dd.year, dd.month_name, dd.month_start
)
SELECT
    state_name,
    year,
    month_name,
    month_start,
    revenue,

    -- Previous month revenue
    LAG(revenue) OVER (
        PARTITION BY state_name
        ORDER BY month_start
    ) AS prev_month_revenue,

    -- Absolute MoM change
    ROUND(
        revenue - LAG(revenue) OVER (
            PARTITION BY state_name
            ORDER BY month_start
        ), 2
    ) AS mom_change,

    -- % MoM growth
    ROUND(
        (
            revenue - LAG(revenue) OVER (
                PARTITION BY state_name
                ORDER BY month_start
            )
        ) /
        NULLIF(
            LAG(revenue) OVER (
                PARTITION BY state_name
                ORDER BY month_start
            ), 0
        ),
        4
    ) AS mom_growth_pct

FROM monthly;
-- Quick checks:
SELECT * FROM v_state_growth;

DROP VIEW IF EXISTS v_revenue_concentration_state;
CREATE OR REPLACE VIEW v_revenue_concentration_state AS
WITH state_rev AS (
    SELECT
        dd.month_start,
        st.state_name,
        SUM(f.revenue) AS total_revenue
    FROM fact_orders f
    JOIN dim_date dd
        ON dd.date_id = f.date_id
    JOIN dim_state st
        ON st.state_id = f.state_id
    GROUP BY
        dd.month_start,
        st.state_name
)
SELECT
    month_start,
    state_name,
    total_revenue,
    ROUND(
        total_revenue / NULLIF(SUM(total_revenue) OVER (PARTITION BY month_start), 0)
    , 4) AS revenue_share,
    ROUND(
        SUM(total_revenue) OVER (
            PARTITION BY month_start
            ORDER BY total_revenue DESC, state_name
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / NULLIF(SUM(total_revenue) OVER (PARTITION BY month_start), 0)
    , 4) AS cumulative_revenue_share
FROM state_rev;

-- Quick checks:
SELECT * 
FROM v_revenue_concentration_state;

-- Inventory Pressure Pricing Behaviour
DROP VIEW IF EXISTS v_inventory_pricing_pressure;

CREATE OR REPLACE VIEW v_inventory_pricing_pressure AS
SELECT
    p.category,
    p.brand_type,
    f.inventory_pressure,
    discount_band(f.discount_percent) AS discount_band,

    SUM(f.units_sold) AS total_units,
    SUM(f.revenue) AS total_revenue,

    ROUND(
        SUM(f.discount_percent * f.units_sold) / NULLIF(SUM(f.units_sold), 0),
        2
    ) AS avg_discount_percent,

    ROUND(
        SUM(f.revenue) / NULLIF(SUM(f.units_sold), 0),
        2
    ) AS revenue_per_unit,

    ROUND(
        SUM(CAST(f.base_price * f.units_sold AS DECIMAL(20,2))),
        2
    ) AS gross_base_revenue,

    ROUND(
        SUM(CAST((f.base_price - f.final_price) * f.units_sold AS DECIMAL(20,2))),
        2
    ) AS total_discount_cost,

    ROUND(
        SUM(CAST((f.base_price - f.final_price) * f.units_sold AS DECIMAL(20,2)))
        / NULLIF(SUM(f.revenue), 0),
        4
    ) AS discount_cost_ratio,

    ROUND(
        SUM(CAST(f.final_price * f.units_sold AS DECIMAL(20,2)))
        / NULLIF(SUM(CAST(f.base_price * f.units_sold AS DECIMAL(20,2))), 0),
        4
    ) AS realization_ratio,

    ROUND(
        SUM(CAST(f.final_price * f.units_sold AS DECIMAL(20,2)))
        / NULLIF(SUM(f.units_sold), 0),
        2
    ) AS w_avg_final_price

FROM fact_orders f
JOIN dim_product p
    ON p.product_id = f.product_id
GROUP BY
    p.category,
    p.brand_type,
    f.inventory_pressure,
    discount_band(f.discount_percent);

-- Quick Check:
SELECT * FROM v_inventory_pricing_pressure;

DROP VIEW IF EXISTS v_revenue_quality_risk_hotspots;
CREATE OR REPLACE VIEW v_revenue_quality_risk_hotspots AS
WITH base AS (
    SELECT
        dd.month_start,
        p.category,
        p.brand_type,
        st.state_name,
        e.sales_event,
        f.competition_intensity,
        f.inventory_pressure,
        SUM(f.revenue) AS total_revenue,
        SUM(f.units_sold) AS total_units,
        SUM(discount_percent * units_sold) / NULLIF(SUM(units_sold), 0) AS avg_discount_percent,
        SUM(CAST((f.base_price - f.final_price) * f.units_sold AS DECIMAL(20,2))) AS total_discount_cost,
        SUM(CAST(f.final_price * f.units_sold AS DECIMAL(20,2))) /
            NULLIF(SUM(CAST(f.base_price * f.units_sold AS DECIMAL(20,2))), 0) AS realization_ratio
    FROM fact_orders f
    JOIN dim_date dd
        ON dd.date_id = f.date_id
    JOIN dim_product p
        ON p.product_id = f.product_id
    JOIN dim_state st
        ON st.state_id = f.state_id
    JOIN dim_event e
        ON e.event_id = f.event_id
    GROUP BY
        dd.month_start,
        p.category,
        p.brand_type,
        st.state_name,
        e.sales_event,
        f.competition_intensity,
        f.inventory_pressure
),
ranked AS (
    SELECT
        *,
        ROUND(total_discount_cost / NULLIF(total_revenue, 0), 4) AS discount_cost_ratio,
        DENSE_RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank,
        DENSE_RANK() OVER (
            ORDER BY
                (total_discount_cost / NULLIF(total_revenue, 0)) DESC,
                realization_ratio ASC
        ) AS margin_risk_rank
    FROM base
)
SELECT
    month_start,
    category,
    brand_type,
    state_name,
    sales_event,
    competition_intensity,
    inventory_pressure,
    total_revenue,
    total_units,
    ROUND(avg_discount_percent, 4) AS avg_discount_percent,
    total_discount_cost,
    ROUND(realization_ratio, 4) AS realization_ratio,
    discount_cost_ratio,
    revenue_rank,
    margin_risk_rank
FROM ranked;

SELECT *
FROM v_revenue_quality_risk_hotspots;

-- Risk Adjusted Performance
DROP VIEW IF EXISTS v_risk_adjusted_performance;
CREATE OR REPLACE VIEW v_risk_adjusted_performance AS
WITH base_seg AS (
    SELECT
        st.state_name,
        p.category,
        p.brand_type,
        dd.month_start,
        e.sales_event,
        SUM(f.revenue) AS revenue,
        SUM(f.units_sold) AS units,
        ROUND(SUM(discount_percent * units_sold) / NULLIF(SUM(units_sold), 0), 2) AS avg_discount,
        ROUND(
            SUM(f.final_price * f.units_sold) / NULLIF(SUM(f.base_price * f.units_sold), 0),
            3
        ) AS realization_ratio,

        ROUND(
            SUM(f.revenue) / NULLIF(SUM(f.units_sold), 0),
            2
        ) AS revenue_per_unit
    FROM fact_orders f
    JOIN dim_state st
        ON st.state_id = f.state_id
    JOIN dim_product p
        ON p.product_id = f.product_id
    JOIN dim_date dd
        ON dd.date_id = f.date_id
    JOIN dim_event e
        ON e.event_id = f.event_id
    GROUP BY
        st.state_name,
        p.category,
        p.brand_type,
        dd.month_start,
        e.sales_event
),

monthly_totals AS (
    SELECT
        state_name,
        category,
        brand_type,
        month_start,

        SUM(revenue) AS month_revenue,
        SUM(units) AS month_units,

        ROUND(AVG(avg_discount), 2) AS month_avg_discount,
        ROUND(AVG(realization_ratio), 3) AS month_realization_ratio,

        ROUND(
            SUM(revenue) / NULLIF(SUM(units), 0),
            2
        ) AS month_revenue_per_unit,

        SUM(
            CASE
                WHEN sales_event = 'festival' THEN revenue
                ELSE 0
            END
        ) AS festival_revenue,

        SUM(
            CASE
                WHEN sales_event = 'festival' THEN units
                ELSE 0
            END
        ) AS festival_units

    FROM base_seg
    GROUP BY
        state_name,
        category,
        brand_type,
        month_start
),

volatility_calc AS (
    SELECT
        state_name,
        category,
        brand_type,
        month_start,
        month_revenue,
        month_units,
        month_avg_discount,
        month_realization_ratio,
        month_revenue_per_unit,
        festival_revenue,
        festival_units,

        LAG(month_revenue) OVER (
            PARTITION BY state_name, category, brand_type
            ORDER BY month_start
        ) AS prev_month_revenue,

        LAG(month_units) OVER (
            PARTITION BY state_name, category, brand_type
            ORDER BY month_start
        ) AS prev_month_units
    FROM monthly_totals
),

volatility_scored AS (
    SELECT
        state_name,
        category,
        brand_type,
        month_start,
        month_revenue,
        month_units,
        month_avg_discount,
        month_realization_ratio,
        month_revenue_per_unit,
        festival_revenue,
        festival_units,

        ROUND(
            CASE
                WHEN prev_month_revenue IS NULL OR prev_month_revenue = 0 THEN NULL
                ELSE ABS((month_revenue - prev_month_revenue) * 100.0 / prev_month_revenue)
            END,
            2
        ) AS revenue_change_pct,

        ROUND(
            CASE
                WHEN prev_month_units IS NULL OR prev_month_units = 0 THEN NULL
                ELSE ABS((month_units - prev_month_units) * 100.0 / prev_month_units)
            END,
            2
        ) AS units_change_pct
    FROM volatility_calc
),

segment_rollup AS (
    SELECT
        state_name,
        category,
        brand_type,

        SUM(month_revenue) AS total_revenue,
        SUM(month_units) AS total_units,

        ROUND(AVG(month_avg_discount), 2) AS avg_discount,
        ROUND(AVG(month_realization_ratio), 3) AS realization_ratio,

        ROUND(
            SUM(month_revenue) / NULLIF(SUM(month_units), 0),
            2
        ) AS revenue_per_unit,

        SUM(festival_revenue) AS festival_revenue,
        SUM(festival_units) AS festival_units,

        ROUND(AVG(revenue_change_pct), 2) AS avg_abs_revenue_change_pct,
        ROUND(AVG(units_change_pct), 2) AS avg_abs_units_change_pct
    FROM volatility_scored
    GROUP BY
        state_name,
        category,
        brand_type
),

risk_inputs AS (
    SELECT
        state_name,
        category,
        brand_type,
        total_revenue,
        total_units,
        avg_discount,
        realization_ratio,
        revenue_per_unit,
        festival_revenue,
        festival_units,
        avg_abs_revenue_change_pct,
        avg_abs_units_change_pct,

        ROUND(
            (avg_discount * 0.50) +
            ((1 - realization_ratio) * 100 * 0.50),
            2
        ) AS discount_dependency_score,

        ROUND(
            (COALESCE(avg_abs_revenue_change_pct, 0) * 0.50) +
            (COALESCE(avg_abs_units_change_pct, 0) * 0.50),
            2
        ) AS demand_volatility_score,

        ROUND(
            festival_revenue * 100.0 / NULLIF(total_revenue, 0),
            2
        ) AS festival_dependency_score
    FROM segment_rollup
),

final_scored AS (
    SELECT
        state_name,
        category,
        brand_type,
        total_revenue,
        total_units,
        avg_discount,
        realization_ratio,
        revenue_per_unit,
        festival_revenue,
        festival_units,
        avg_abs_revenue_change_pct,
        avg_abs_units_change_pct,
        discount_dependency_score,
        demand_volatility_score,
        festival_dependency_score,

        ROUND(
            (discount_dependency_score * 0.40) +
            (demand_volatility_score * 0.35) +
            (festival_dependency_score * 0.25),
            2
        ) AS overall_risk_score
    FROM risk_inputs
)

SELECT
    state_name,
    category,
    brand_type,

    total_revenue,
    total_units,
    avg_discount,
    realization_ratio,
    revenue_per_unit,

    festival_revenue,
    festival_units,

    avg_abs_revenue_change_pct,
    avg_abs_units_change_pct,

    discount_dependency_score,
    demand_volatility_score,
    festival_dependency_score,
    overall_risk_score,

    CASE
        WHEN overall_risk_score >= 45 THEN 'High-Risk Revenue Pocket'
        WHEN discount_dependency_score >= 35 THEN 'Discount-Dependent'
        WHEN demand_volatility_score >= 35 THEN 'Volatile Growth'
        WHEN festival_dependency_score >= 50 THEN 'Festival-Reliant'
        ELSE 'Stable Core'
    END AS risk_segment
FROM final_scored; 

SELECT * 
FROM v_risk_adjusted_performance;

-- Risk Adjusted Summary
DROP VIEW IF EXISTS v_risk_adjusted_summary;
CREATE OR REPLACE VIEW v_risk_adjusted_summary AS
WITH base AS (
    SELECT
        state_name,
        category,
        brand_type,
        total_revenue,
        total_units,
        avg_discount,
        realization_ratio,
        revenue_per_unit,
        festival_revenue,
        festival_units,
        avg_abs_revenue_change_pct,
        avg_abs_units_change_pct,
        discount_dependency_score,
        demand_volatility_score,
        festival_dependency_score,
        overall_risk_score,
        risk_segment
    FROM v_risk_adjusted_performance
),
totals AS (
    SELECT
        SUM(total_revenue) AS grand_total_revenue
    FROM base
),
ranked AS (
    SELECT
        b.state_name,
        b.category,
        b.brand_type,

        b.total_revenue,
        b.total_units,
        ROUND(b.total_revenue * 100.0 / NULLIF(t.grand_total_revenue, 0), 2) AS revenue_share_pct,
        DENSE_RANK() OVER (ORDER BY b.total_revenue DESC) AS revenue_rank,
        NTILE(4) OVER (ORDER BY b.total_revenue DESC) AS revenue_quartile,

        b.avg_discount,
        b.realization_ratio,
        DENSE_RANK() OVER (ORDER BY b.realization_ratio DESC) AS realization_rank,
        b.revenue_per_unit,

        b.festival_revenue,
        b.festival_units,

        b.avg_abs_revenue_change_pct,
        b.avg_abs_units_change_pct,

        b.discount_dependency_score,
        DENSE_RANK() OVER (ORDER BY b.discount_dependency_score DESC) AS discount_dependency_rank,

        b.demand_volatility_score,
        DENSE_RANK() OVER (ORDER BY b.demand_volatility_score DESC) AS volatility_rank,

        b.festival_dependency_score,
        DENSE_RANK() OVER (ORDER BY b.festival_dependency_score DESC) AS festival_dependency_rank,

        b.overall_risk_score,
        DENSE_RANK() OVER (ORDER BY b.overall_risk_score DESC) AS risk_rank,

        b.risk_segment
    FROM base b
    CROSS JOIN totals t
)
SELECT
    state_name,
    category,
    brand_type,

    total_revenue,
    total_units,
    revenue_share_pct,
    revenue_rank,
    revenue_quartile,

    avg_discount,
    realization_ratio,
    realization_rank,
    revenue_per_unit,

    festival_revenue,
    festival_units,

    avg_abs_revenue_change_pct,
    avg_abs_units_change_pct,

    discount_dependency_score,
    discount_dependency_rank,

    demand_volatility_score,
    volatility_rank,

    festival_dependency_score,
    festival_dependency_rank,

    overall_risk_score,
    risk_rank,

    CASE
        WHEN overall_risk_score >= 45 THEN 'High'
        WHEN overall_risk_score >= 30 THEN 'Medium'
        ELSE 'Low'
    END AS risk_tier,

    risk_segment,

    CASE
        WHEN revenue_quartile = 1 AND overall_risk_score >= 45 THEN 'Urgent Review'
        WHEN revenue_quartile = 1 AND overall_risk_score < 30 THEN 'Protect and Scale'
        WHEN revenue_quartile > 1 AND overall_risk_score >= 45 THEN 'Low-Value Risk'
        ELSE 'Monitor'
    END AS priority_flag,

    CASE
        WHEN revenue_quartile = 1 AND overall_risk_score >= 45
            THEN 'High revenue but elevated risk; reduce discount pressure and stabilize demand'
        WHEN revenue_quartile = 1 AND overall_risk_score < 30
            THEN 'Healthy revenue and low risk; protect margins and expand strategically'
        WHEN revenue_quartile > 1 AND overall_risk_score >= 45
            THEN 'Lower contribution but elevated risk; reassess discount strategy'
        WHEN risk_segment = 'Discount-Dependent'
            THEN 'Revenue relies heavily on discounting; improve price realization'
        WHEN risk_segment = 'Volatile Growth'
            THEN 'Demand fluctuations are high; improve forecasting and demand stability'
        WHEN risk_segment = 'Festival-Reliant'
            THEN 'Sales concentrated during festival periods; strengthen normal-period demand'
        ELSE 'Stable segment; maintain pricing discipline and monitor performance'
    END AS strategic_action
FROM ranked;

SELECT * 
FROM v_risk_adjusted_summary;

-- Competition vs Discount Performance
DROP VIEW IF EXISTS v_competition_discount_performance;
CREATE OR REPLACE VIEW v_competition_discount_performance AS
SELECT
    p.category,
    p.brand_type,
    f.competition_intensity,
    discount_band(f.discount_percent) AS discount_band,

    SUM(f.units_sold) AS total_units,
    SUM(f.revenue) AS total_revenue,

    ROUND(
        SUM(f.discount_percent * f.units_sold) / NULLIF(SUM(f.units_sold), 0),
        2
    ) AS avg_discount_percent,

    ROUND(
        SUM(f.revenue) / NULLIF(SUM(f.units_sold), 0),
        2
    ) AS revenue_per_unit,

    ROUND(
        SUM(CAST(f.base_price * f.units_sold AS DECIMAL(20,2))),
        2
    ) AS gross_base_revenue,

    ROUND(
        SUM(CAST((f.base_price - f.final_price) * f.units_sold AS DECIMAL(20,2))),
        2
    ) AS total_discount_cost,

    ROUND(
        SUM(CAST((f.base_price - f.final_price) * f.units_sold AS DECIMAL(20,2)))
        / NULLIF(SUM(f.revenue), 0),
        4
    ) AS discount_cost_ratio,

    ROUND(
        SUM(CAST(f.final_price * f.units_sold AS DECIMAL(20,2)))
        / NULLIF(SUM(CAST(f.base_price * f.units_sold AS DECIMAL(20,2))), 0),
        4
    ) AS realization_ratio,

    ROUND(
        SUM(CAST(f.final_price * f.units_sold AS DECIMAL(20,2)))
        / NULLIF(SUM(f.units_sold), 0),
        2
    ) AS w_avg_final_price

FROM fact_orders f
JOIN dim_product p
    ON p.product_id = f.product_id
GROUP BY
    p.category,
    p.brand_type,
    f.competition_intensity,
    discount_band(f.discount_percent);

-- Quick checks:
SELECT * FROM v_competition_discount_performance;



-- Pricing Intelligence Table
DROP VIEW IF EXISTS v_pricing_intelligence;
CREATE OR REPLACE VIEW v_pricing_intelligence AS
WITH monthly_seg AS (
  SELECT
    dd.month_start,
    p.category,
    p.brand_type,
    SUM(f.revenue) AS revenue,
    SUM(f.units_sold) AS units,
    SUM(f.discount_percent * f.units_sold) / NULLIF(SUM(f.units_sold), 0) AS avg_discount,
    SUM(f.final_price * f.units_sold) / NULLIF(SUM(f.units_sold), 0) AS w_avg_final_price,
    SUM(f.final_price * f.units_sold) / NULLIF(SUM(f.base_price * f.units_sold), 0) AS realization_ratio
  FROM fact_orders f
  JOIN dim_date dd
    ON dd.date_id = f.date_id
  JOIN dim_product p
    ON p.product_id = f.product_id
  GROUP BY dd.month_start, p.category, p.brand_type
),

mom_sensitivity AS (
  SELECT
    month_start,
    category,
    brand_type,
    revenue,
    units,
    avg_discount,
    w_avg_final_price,
    realization_ratio,
    LAG(units) OVER (
      PARTITION BY category, brand_type
      ORDER BY month_start
    ) AS prev_units,
    LAG(w_avg_final_price) OVER (
      PARTITION BY category, brand_type
      ORDER BY month_start
    ) AS prev_price
  FROM monthly_seg
),

elasticity AS (
  SELECT
    category,
    brand_type,
    AVG(
      ABS(
        ((units - prev_units) / NULLIF(prev_units, 0)) /
        NULLIF(
          (w_avg_final_price - prev_price) / NULLIF(prev_price, 0),
          0
        )
      )
    ) AS avg_abs_elasticity_proxy,
    AVG(
      CASE
        WHEN prev_units IS NOT NULL
         AND prev_price IS NOT NULL
         AND w_avg_final_price < prev_price
         AND units > prev_units
        THEN 1 ELSE 0
      END
    ) AS pct_months_price_down_units_up
  FROM mom_sensitivity
  WHERE prev_units IS NOT NULL
    AND prev_price IS NOT NULL
  GROUP BY category, brand_type
),

discount_effectiveness AS (
  SELECT
    category,
    brand_type,
    COUNT(*) AS n_months,
    SUM(avg_discount) AS sum_x,
    SUM(revenue) AS sum_y,
    SUM(avg_discount * avg_discount) AS sum_x2,
    SUM(avg_discount * revenue) AS sum_xy
  FROM monthly_seg
  GROUP BY category, brand_type
),

segment_totals AS (
  SELECT
    category,
    brand_type,
    SUM(revenue) AS seg_revenue,
    SUM(units) AS seg_units,
    AVG(avg_discount) AS seg_avg_discount,
    AVG(realization_ratio) AS seg_realization_ratio,
    SUM(revenue) / NULLIF(SUM(units), 0) AS seg_revenue_per_unit
  FROM monthly_seg
  GROUP BY category, brand_type
),

overall AS (
  SELECT
    SUM(seg_revenue) AS total_revenue,
    SUM(seg_units) AS total_units
  FROM segment_totals
),

banded AS (
  SELECT
    p.category,
    p.brand_type,
    discount_band(f.discount_percent) AS discount_band,
    SUM(f.revenue) AS revenue,
    SUM(f.units_sold) AS units,
    SUM(f.final_price * f.units_sold) / NULLIF(SUM(f.base_price * f.units_sold), 0) AS realization_ratio
  FROM fact_orders f
  JOIN dim_product p
    ON p.product_id = f.product_id
  GROUP BY
    p.category,
    p.brand_type,
    discount_band(f.discount_percent)
),

band_ranked AS (
  SELECT
    *,
    DENSE_RANK() OVER (
      PARTITION BY category, brand_type
      ORDER BY revenue DESC
    ) AS revenue_rank,
    DENSE_RANK() OVER (
      PARTITION BY category, brand_type
      ORDER BY realization_ratio DESC
    ) AS margin_rank
  FROM banded
),

best_band AS (
  SELECT
    category,
    brand_type,
    discount_band AS optimal_discount_band,
    revenue AS band_revenue,
    realization_ratio AS band_realization_ratio,
    (revenue_rank + margin_rank) AS optimal_score
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (
        PARTITION BY category, brand_type
        ORDER BY
          (revenue_rank + margin_rank) ASC,
          revenue DESC,
          realization_ratio DESC,
          discount_band ASC
      ) AS rn
    FROM band_ranked
  ) ranked_bands
  WHERE rn = 1
)

SELECT
  st.category,
  st.brand_type,
  ROUND(st.seg_revenue, 2) AS revenue,
  st.seg_units AS units,
  ROUND(100 * st.seg_revenue / NULLIF(o.total_revenue, 0), 2) AS revenue_share_pct,
  ROUND(st.seg_avg_discount, 2) AS avg_discount_pct,
  ROUND(st.seg_revenue_per_unit, 2) AS revenue_per_unit,
  ROUND(st.seg_realization_ratio, 3) AS realization_ratio,

  ROUND(
    (
      (de.n_months * de.sum_xy) - (de.sum_x * de.sum_y)
    ) /
    NULLIF(
      (de.n_months * de.sum_x2) - (de.sum_x * de.sum_x),
      0
    ),
    3
  ) AS discount_revenue_beta,

  ROUND(e.avg_abs_elasticity_proxy, 3) AS avg_abs_elasticity_proxy,
  ROUND(100 * e.pct_months_price_down_units_up, 1) AS pct_months_price_down_units_up,

  bb.optimal_discount_band,
  ROUND(bb.band_realization_ratio, 3) AS optimal_band_realization_ratio,
  bb.optimal_score,

  DENSE_RANK() OVER (ORDER BY st.seg_revenue DESC) AS revenue_rank,
  DENSE_RANK() OVER (ORDER BY st.seg_realization_ratio ASC) AS margin_risk_rank,
  DENSE_RANK() OVER (ORDER BY e.avg_abs_elasticity_proxy DESC) AS sensitivity_rank

FROM segment_totals st
CROSS JOIN overall o
LEFT JOIN discount_effectiveness de
  ON de.category = st.category
 AND de.brand_type = st.brand_type
LEFT JOIN elasticity e
  ON e.category = st.category
 AND e.brand_type = st.brand_type
LEFT JOIN best_band bb
  ON bb.category = st.category
 AND bb.brand_type = st.brand_type
ORDER BY st.seg_revenue DESC;

SELECT * 
FROM v_pricing_intelligence;