-- This query returns the total customer lifespan for each category (AHAs & Plans)
--
-- Add subscription category column, active status and filter unnecessary rows
WITH tab1 AS (
  SELECT
    invoices.id,
    invoices.customer_id,
    invoice_line_items.plan_id,
    plans.nickname,
    CASE
      WHEN plans.nickname IN ('Standard AHAs','Unlimited AHAs','AHAs: Basic','AHAs: Business','AHAs: Project',
                              'AHAs: Basic (combo)','AHAs: Business (combo)','AHAs: Project (combo)') THEN 'AHA'
      WHEN plans.nickname IN ('Standard Plans','Unlimited Plans','Plans: Basic','Plans: Business','Plans: Project',
                              'Plans: Basic (combo)','Plans: Business (combo)','Plans: Project (combo)') THEN 'Plans'
      ELSE 'Other'
    END AS subscription_category,
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
                                        'unlimited_subscription','gold_subscription')
    AND charges.amount_refunded <> charges.amount
  ORDER BY 2,7
),

-- Change incorrect labels to correct labels
tab2 AS (
  SELECT
    id,
    customer_id,
    CASE
      WHEN full_amount = 468
      AND CAST(start_date AS timestamp) < TIMESTAMP '2021-05-01' THEN 'standard_plan'
      WHEN full_amount = 588
      AND CAST(start_date AS timestamp) < TIMESTAMP '2021-05-01' THEN 'standard_aha'
      WHEN full_amount = 1495
      AND CAST(start_date AS timestamp) < TIMESTAMP '2021-05-01' THEN 'unlimited_plan'
      WHEN full_amount = 1695
      AND CAST(start_date AS timestamp) < TIMESTAMP '2021-05-01' THEN 'unlimited_aha'
      ELSE plan_id
    END AS plan_id,
    CASE
      WHEN full_amount = 468
      AND CAST(start_date AS timestamp) < TIMESTAMP '2021-05-01' THEN 'Standard Plans'
      WHEN full_amount = 588
      AND CAST(start_date AS timestamp) < TIMESTAMP '2021-05-01' THEN 'Standard AHAs'
      WHEN full_amount = 1495
      AND CAST(start_date AS timestamp) < TIMESTAMP '2021-05-01' THEN 'Unlimited Plans'
      WHEN full_amount = 1695
      AND CAST(start_date AS timestamp) < TIMESTAMP '2021-05-01' THEN 'Unlimited AHAs'
      ELSE nickname
    END AS nickname,
    subscription_category,
    subscription_status,
    start_date,
    end_date,
    full_amount
  FROM tab1
),

-- Separate customers and their subscriptions into categories and assign them a column with the previous date
-- Since this will be used to adjust the start date the same start date will be assigned if there is no previous end date
tab3 AS (
  SELECT
    *,
    COALESCE(LAG(end_date, 1) OVER (PARTITION BY customer_id, subscription_category ORDER BY start_date), start_date) as prev_end_date
  FROM tab2
),

-- Adjust start dates to negate for any overlapping time ranges
tab4 AS (
  SELECT
    *,
    CASE
      WHEN prev_end_date >= start_date THEN prev_end_date
      ELSE start_date
    END AS fixed_start_date
  FROM tab3
),

-- Calculate the total days each subscription has been active
tab5 AS (
  SELECT
    *,
    DATE_DIFF('day', fixed_start_date, end_date) AS total_days
  FROM tab4
),

-- Show the minimum and maximum date ranges and calculate customer lifespan in years per subscription
tab6 AS (
  SELECT
    customer_id,
    subscription_category,
    CASE
    	WHEN MAX(end_date) >= NOW() THEN 'active'
    	ELSE 'inactive'
  	END AS category_status,
    MIN(fixed_start_date) AS start_date,
    MAX(end_date) AS end_date,
    ROUND(SUM(total_days) / 365.25, 4) AS total_years,
  	SUM(full_amount) AS revenue
  FROM tab5
  GROUP BY 1,2
),

-- Create a variable that shows if a customer's specific subscription is active
active_tab AS (
  SELECT
    customer_id,
    CASE
      WHEN COALESCE(SUM(CASE WHEN subscription_status = 'active' THEN 1 ELSE 0 END), 0) > 0
      OR MAX(end_date) >= NOW() THEN 'active'
      ELSE 'inactive'
    END AS customer_status
  FROM tab2
  GROUP BY 1
)

-- Join the customer's active table to final table
SELECT 
	a.customer_id,
  b.customer_status,
  a.subscription_category, 
  a.category_status,
  DATE(a.start_date) AS start_date,
  DATE(a.end_date) AS end_date,
  a.total_years,
  a.revenue
FROM tab6 a
LEFT JOIN active_tab b
	ON a.customer_id = b.customer_id
