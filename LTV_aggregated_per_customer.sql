-- This query returns the total customer lifespan for each category (AHAs & Plans)
--
-- Add columns for subscription category and active status and filter unnecessary rows
WITH tab1 AS (
  SELECT
    invoices.id,
    invoices.customer_id,
    invoice_line_items.plan_id,
    plans.nickname,
    -- Subscription_status will be used to create active_status since only
  	-- the most recent subscription(s) will be active for subscription_status
    CASE
      WHEN (subscriptions.canceled_at IS null AND subscriptions.ended_at IS null)
      OR invoice_line_items.period_end >= NOW() THEN 'active'
      ELSE 'inactive'
    END AS subscription_status,
    invoice_line_items.period_start AS start_date,
    CASE 
  		WHEN invoice_line_items.period_end > NOW() 
  		THEN NOW() 
  		ELSE invoice_line_items.period_end
  	END AS end_date,
    invoice_line_items.amount / 100 AS full_amount
  FROM invoices
  JOIN invoice_line_items 
  	ON invoices.id = invoice_line_items.invoice_id
  JOIN charges 
  	ON invoices.id = charges.invoice_id
  JOIN subscriptions 
  	ON invoices.subscription_id = subscriptions.id
  JOIN plans 
  	ON invoice_line_items.plan_id = plans.id
  WHERE
    charges.captured
    AND (invoice_line_items.source_type = 'subscription' OR invoice_line_items.subscription IS NOT null)
    AND invoice_line_items.plan_id NOT IN ('singles','aha_translation','extra_profiles','price_1HLCPhFojU55wgMGAzE6RuPW',
                                          'gold_subscription','unlimited_subscription')
    AND charges.amount_refunded <> charges.amount
  ORDER BY 2,6,7
),

-- Create column with the customer's previous subscription end date
-- Current end date will be used if there is no previous subscription
tab2 AS (
  SELECT
    *,
    COALESCE(LAG(end_date, 1) over (PARTITION BY customer_id ORDER BY start_date), start_date) as prev_end_date
  FROM tab1
), 

-- Adjust start dates to negate for any overlapping time ranges
tab3 AS (
  SELECT
    *,
    CASE
      WHEN prev_end_date >= start_date THEN prev_end_date
      ELSE start_date
    END AS fixed_start_date
  FROM tab2
), 

-- Calculate the total days subscribed for each customer
tab4 AS (
  SELECT
    *,
    DATE_DIFF('day', fixed_start_date, end_date) AS total_days
  FROM tab3
)

-- Add customer's active status, minimum start date, maximum end date, convert total days to total years, and total revenue
SELECT
  customer_id,
	CASE
    WHEN COALESCE(SUM(CASE  WHEN subscription_status = 'active' THEN 1 ELSE 0 END), 0) > 0
    OR MAX(end_date) >= NOW() THEN 'active'
    ELSE 'inactive'
  END AS active_status,
  DATE(MIN(fixed_start_date)) AS start_date,
  DATE(MAX(end_date)) AS end_date,
  ROUND(SUM(total_days) / 365.25, 4) AS total_years,
  SUM(full_amount) AS revenue
FROM tab4
GROUP BY 1