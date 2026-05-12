USE ecommerce_analytics;

-- Discount Bracket Classification
CREATE FUNCTION discount_band(discount_percent DECIMAL(5,2))
RETURNS VARCHAR(20)
DETERMINISTIC
RETURN
CASE
		WHEN discount_percent <= 10 THEN '0-10%'
		WHEN discount_percent <= 20 THEN '11-20%'
		WHEN discount_percent <= 30 THEN '21-30%'
		WHEN discount_percent <= 40 THEN '31-40%'
		WHEN discount_percent <= 50 THEN '41-50%'
		WHEN discount_percent <= 60 THEN '51-60%'
		WHEN discount_percent <= 70 THEN '61-70%'
		WHEN discount_percent <= 80 THEN '71-80%'
		WHEN discount_percent <= 90 THEN '81-90%'
		ELSE '91%+'
END;

-- Revenue Impact
CREATE FUNCTION revenue_loss(base_price DECIMAL(10,2),
discount_percent DECIMAL(5,2),
units INT)
RETURNS DECIMAL(20,2)
DETERMINISTIC
RETURN (base_price * units) - ((base_price * (1 - (discount_percent / 100))) * units);