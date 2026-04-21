-- Signup Variant A/B Funnel Analysis
--
-- Measures 30-day paid conversion by signup variant (reverse_trial vs classic).
--
-- IMPORTANT: The users table stores `status` and `subscription_source` as integers
-- (Rails enums). This query uses the integer values directly.
--
-- Enum mappings (from app/models/user.rb):
--   status: { inactive: 0, active: 1, trial: 2, pending_payment: 3 }
--   subscription_source: { none: 0, paddle: 1, apple_iap: 2, google_play: 3 }
--
-- "Subscribed" = status IN (active, trial) AND subscription_source != none.
-- This counts users who have a real subscription source attached, regardless of
-- whether they are currently in the trial window or past it.
--
-- Usage:
--   psql -v start_date="'2026-04-01'" -v end_date="'2026-05-01'" \
--        -f signup_variant_funnel.sql
--
-- Or inline the dates when running ad-hoc.

SELECT
  signup_variant,
  COUNT(*) AS signups,
  COUNT(*) FILTER (
    WHERE status IN (1, 2)          -- 1 = active, 2 = trial
      AND subscription_source != 0  -- 0 = none
  ) AS subscribed,
  ROUND(
    100.0 * COUNT(*) FILTER (
      WHERE status IN (1, 2)
        AND subscription_source != 0
    ) / NULLIF(COUNT(*), 0),
    2
  ) AS conversion_pct
FROM users
WHERE created_at BETWEEN :start_date AND :end_date
  AND signup_variant IS NOT NULL
GROUP BY signup_variant
ORDER BY signup_variant;
