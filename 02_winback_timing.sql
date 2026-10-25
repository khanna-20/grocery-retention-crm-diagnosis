/* =============================================================================
   02_winback_timing.sql
   QUESTION: When a regular customer stops ordering, how long should we wait
             before sending a win-back offer?

   Too early  -> we pay a discount to people who were coming back anyway.
   Too late   -> they have already settled with another store.

   Population : regular households (12+ shopping days in the year)
   Lapse      : any gap of 28+ days without a grocery purchase, where we can
                still see at least 120 more days of data after the last visit
   Output     : for each "days without an order" checkpoint, the share of
                lapsed customers who come back on their own within the next
                4 weeks, and the share still gone after 120 days

   PostgreSQL 13+ (also runs unchanged on DuckDB)
   ============================================================================= */

WITH
-- 1) One row per household per shopping day
grocery_visits AS (
    SELECT DISTINCT
        t.household_id,
        CAST(t.transaction_timestamp AS DATE) AS visit_date
    FROM transactions AS t
    JOIN products     AS p ON p.product_id = t.product_id
    WHERE p.department <> 'FUEL'
),

data_end AS (
    SELECT MAX(visit_date) AS last_date FROM grocery_visits
),

regulars AS (
    SELECT household_id
    FROM grocery_visits
    GROUP BY household_id
    HAVING COUNT(*) >= 12
),

-- 2) For every visit, when was the NEXT visit? (LEAD window function)
visit_gaps AS (
    SELECT
        v.household_id,
        v.visit_date,
        LEAD(v.visit_date) OVER (
            PARTITION BY v.household_id
            ORDER BY v.visit_date
        ) AS next_visit
    FROM grocery_visits AS v
    JOIN regulars       AS r ON r.household_id = v.household_id
),

-- 3) Lapse spells: 28+ days with no order (or no order ever again),
--    keeping only spells with 120+ days of data left to observe a return
lapses AS (
    SELECT
        g.household_id,
        g.visit_date,
        COALESCE(g.next_visit - g.visit_date, 9999) AS days_until_return
    FROM visit_gaps AS g
    CROSS JOIN data_end AS e
    WHERE g.visit_date <= e.last_date - 120
      AND (g.next_visit IS NULL OR g.next_visit - g.visit_date >= 28)
),

-- 4) Points in time at which a win-back message could fire
checkpoints AS (
    SELECT days_without_order
    FROM (VALUES (28), (35), (42), (49), (56), (63), (70), (77), (84)) AS c (days_without_order)
)

-- 5) Of customers still gone at each checkpoint, how many return on their own?
SELECT
    c.days_without_order,
    COUNT(*) AS lapsed_customers_still_gone,
    ROUND(100.0 * AVG(CASE WHEN l.days_until_return < c.days_without_order + 28
                           THEN 1 ELSE 0 END), 1) AS pct_back_on_own_next_4_weeks,
    ROUND(100.0 * AVG(CASE WHEN l.days_until_return >= 120
                           THEN 1 ELSE 0 END), 1) AS pct_still_gone_after_120_days
FROM checkpoints AS c
JOIN lapses      AS l ON l.days_until_return >= c.days_without_order
GROUP BY c.days_without_order
ORDER BY c.days_without_order;
