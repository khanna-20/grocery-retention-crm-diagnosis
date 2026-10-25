/* =============================================================================
   01_produce_habit_retention.sql
   QUESTION: Do households with a regular fresh-produce habit stay regular
             customers longer than households that rarely buy produce?

   Population : households that shopped in at least 4 of the 13 weeks of Q1
                (weeks 1-13), i.e. people who were regular customers to begin with
   Habit      : share of their Q1 shopping weeks that included any PRODUCE item
                Low  = under 1 in 3 weeks
                Mid  = 1 in 3 to 2 in 3 weeks
                High = 2 in 3 weeks or more
   Outcome    : "lost as a regular" = shopped in fewer than 4 of the 13 weeks
                of Q4 (weeks 40-52)
   Fairness   : heavy shoppers buy more produce AND churn less, so we also
                compare habits inside the same Q1 visit-frequency band

   PostgreSQL 13+ (also runs unchanged on DuckDB)
   ============================================================================= */

WITH
-- 1) Grocery lines only (fuel purchases are not grocery trips)
grocery_lines AS (
    SELECT t.household_id, t.week, p.department
    FROM transactions AS t
    JOIN products     AS p ON p.product_id = t.product_id
    WHERE p.department <> 'FUEL'
),

-- 2) One row per household per week: did they shop, and did they buy produce?
household_weeks AS (
    SELECT
        household_id,
        week,
        MAX(CASE WHEN department = 'PRODUCE' THEN 1 ELSE 0 END) AS bought_produce
    FROM grocery_lines
    GROUP BY household_id, week
),

-- 3) Q1 behaviour (only households already shopping regularly)
q1 AS (
    SELECT
        household_id,
        COUNT(*)            AS q1_weeks,
        SUM(bought_produce) AS q1_produce_weeks
    FROM household_weeks
    WHERE week BETWEEN 1 AND 13
    GROUP BY household_id
    HAVING COUNT(*) >= 4
),

-- 4) Q4 behaviour
q4 AS (
    SELECT household_id, COUNT(*) AS q4_weeks
    FROM household_weeks
    WHERE week BETWEEN 40 AND 52
    GROUP BY household_id
),

-- 5) Label each household
labelled AS (
    SELECT
        q1.household_id,
        CASE WHEN 3 * q1.q1_produce_weeks < q1.q1_weeks     THEN '1. Low'
             WHEN 3 * q1.q1_produce_weeks < 2 * q1.q1_weeks THEN '2. Mid'
             ELSE                                                '3. High'
        END AS produce_habit,
        CASE WHEN q1.q1_weeks <= 7  THEN '1. 4-7 weeks'
             WHEN q1.q1_weeks <= 10 THEN '2. 8-10 weeks'
             ELSE                        '3. 11-13 weeks'
        END AS q1_visit_band,
        CASE WHEN COALESCE(q4.q4_weeks, 0) < 4 THEN 1 ELSE 0 END AS lost_regular,
        CASE WHEN COALESCE(q4.q4_weeks, 0) = 0 THEN 1 ELSE 0 END AS gone_completely
    FROM q1
    LEFT JOIN q4 ON q4.household_id = q1.household_id
),

-- 6) Rates for every habit, overall and within each visit band (GROUPING SETS)
rates AS (
    SELECT
        COALESCE(q1_visit_band, '0. All households') AS q1_visit_band,
        produce_habit,
        COUNT(*)                                   AS households,
        ROUND(100.0 * AVG(lost_regular), 1)        AS lost_regular_pct,
        ROUND(100.0 * AVG(gone_completely), 1)     AS gone_completely_pct
    FROM labelled
    GROUP BY GROUPING SETS ((produce_habit), (produce_habit, q1_visit_band))
)

-- 7) How many times more likely is each habit to be lost than the High habit?
SELECT
    q1_visit_band,
    produce_habit,
    households,
    lost_regular_pct,
    gone_completely_pct,
    ROUND(lost_regular_pct / NULLIF(FIRST_VALUE(lost_regular_pct) OVER (
        PARTITION BY q1_visit_band
        ORDER BY produce_habit DESC
    ), 0), 1) AS times_vs_high_habit
FROM rates
ORDER BY q1_visit_band, produce_habit;
