/* =============================================================================
   03_campaign_true_lift.sql
   QUESTION: Did the retailer's three mass CRM campaigns (Type A, sent to
             ~1,100 households each) actually make people spend more?

   The trap   : the retailer chose WHO to target, and it picked its best
                customers. Comparing targeted vs non-targeted spend during the
                campaign mostly measures that choice, not the campaign.
   The fix    : difference-in-differences. Compare how much each group's
                spend CHANGED from the period just before the campaign
                (same length) to the campaign period itself.

   naive_lift_pct    = targeted spend / non-targeted spend - 1   (misleading)
   true_lift_pct     = (targeted change - non-targeted change) / targeted pre-spend
   ci_low / ci_high  = 95% confidence interval for true_lift_pct

   PostgreSQL 13+ (also runs unchanged on DuckDB)
   ============================================================================= */

WITH
-- 1) Grocery spend per household per day
daily_spend AS (
    SELECT
        t.household_id,
        CAST(t.transaction_timestamp AS DATE) AS spend_date,
        SUM(t.sales_value)                    AS spend
    FROM transactions AS t
    JOIN products     AS p ON p.product_id = t.product_id
    WHERE p.department <> 'FUEL'
    GROUP BY t.household_id, CAST(t.transaction_timestamp AS DATE)
),

-- 2) Mass campaigns (Type A) and their length in days. A campaign is kept only
--    if a full "before" window of the same length exists inside the data
--    (this drops campaign 27, whose before-window would start in 2016)
mass_campaigns AS (
    SELECT
        cd.campaign_id,
        cd.start_date,
        cd.end_date,
        CAST((cd.end_date - cd.start_date) + 1 AS INT) AS campaign_days
    FROM campaign_descriptions AS cd
    WHERE cd.campaign_type = 'Type A'
      AND cd.start_date - CAST((cd.end_date - cd.start_date) + 1 AS INT)
          >= (SELECT MIN(spend_date) FROM daily_spend)
),

-- 3) Households already shopping before each campaign, flagged targeted or not
eligible AS (
    SELECT DISTINCT
        c.campaign_id,
        d.household_id,
        CASE WHEN ct.household_id IS NOT NULL THEN 1 ELSE 0 END AS targeted
    FROM mass_campaigns AS c
    JOIN daily_spend    AS d  ON d.spend_date < c.start_date
    LEFT JOIN campaigns AS ct ON ct.campaign_id  = c.campaign_id
                             AND ct.household_id = d.household_id
),

-- 4) Spend before vs during, per household
household_windows AS (
    SELECT
        e.campaign_id,
        e.household_id,
        e.targeted,
        SUM(CASE WHEN d.spend_date >= c.start_date - c.campaign_days
                  AND d.spend_date <  c.start_date
                 THEN d.spend ELSE 0 END) AS pre_spend,
        SUM(CASE WHEN d.spend_date BETWEEN c.start_date AND c.end_date
                 THEN d.spend ELSE 0 END) AS during_spend
    FROM eligible       AS e
    JOIN mass_campaigns AS c ON c.campaign_id  = e.campaign_id
    LEFT JOIN daily_spend AS d ON d.household_id = e.household_id
    GROUP BY e.campaign_id, e.household_id, e.targeted
),

-- 5) Group averages and the variance of each household's change
group_stats AS (
    SELECT
        campaign_id,
        targeted,
        COUNT(*)                              AS households,
        AVG(pre_spend)                        AS avg_pre,
        AVG(during_spend)                     AS avg_during,
        AVG(during_spend - pre_spend)         AS avg_change,
        VAR_SAMP(during_spend - pre_spend)    AS var_change
    FROM household_windows
    GROUP BY campaign_id, targeted
),

-- 6) Put targeted and non-targeted side by side
compared AS (
    SELECT
        t.campaign_id,
        c.start_date,
        c.end_date,
        t.households                          AS targeted_households,
        n.households                          AS other_households,
        t.avg_pre                             AS targeted_pre,
        n.avg_pre                             AS other_pre,
        t.avg_during                          AS targeted_during,
        n.avg_during                          AS other_during,
        t.avg_change - n.avg_change           AS did_spend,
        SQRT(t.var_change / t.households + n.var_change / n.households) AS did_se
    FROM group_stats    AS t
    JOIN group_stats    AS n ON n.campaign_id = t.campaign_id AND n.targeted = 0
    JOIN mass_campaigns AS c ON c.campaign_id = t.campaign_id
    WHERE t.targeted = 1
)

SELECT
    campaign_id,
    start_date,
    end_date,
    targeted_households,
    other_households,
    ROUND(CAST(targeted_pre    AS NUMERIC), 0) AS targeted_spend_before,
    ROUND(CAST(other_pre       AS NUMERIC), 0) AS other_spend_before,
    ROUND(CAST(targeted_during AS NUMERIC), 0) AS targeted_spend_during,
    ROUND(CAST(other_during    AS NUMERIC), 0) AS other_spend_during,
    ROUND(CAST(100 * (targeted_during / other_during - 1)           AS NUMERIC), 1) AS naive_lift_pct,
    ROUND(CAST(100 * did_spend / targeted_pre                       AS NUMERIC), 1) AS true_lift_pct,
    ROUND(CAST(100 * (did_spend - 1.96 * did_se) / targeted_pre     AS NUMERIC), 1) AS ci_low_pct,
    ROUND(CAST(100 * (did_spend + 1.96 * did_se) / targeted_pre     AS NUMERIC), 1) AS ci_high_pct
FROM compared
ORDER BY start_date;
