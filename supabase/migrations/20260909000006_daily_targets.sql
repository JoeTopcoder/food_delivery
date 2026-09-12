-- Migration: daily targets with adaptive progression. Additive only.
--
-- NOT APPLIED YET — written for review per the deliverables order.
--
-- Reuses the contribution math from 20260909000005 rather than restating it:
-- daily_actuals is built on admin_order_economics(), the same function the KPI
-- RPCs use. There is one definition of what an order earns.
--
-- Nothing here touches order, payment, dispatch or status-transition logic.

-- ── 1. Targets. Append-only. ───────────────────────────────────────────────
-- Rows are never UPDATEd. A change inserts a new row pointing at the one it
-- supersedes, so the history of what was expected, and when it changed, stays
-- readable. The uniqueness rule therefore cannot be a plain unique key on
-- (target_date, vertical) — that would forbid the second row. It is a partial
-- unique index on the row that is currently in force.
CREATE TABLE IF NOT EXISTS public.daily_targets (
  id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target_date         DATE NOT NULL,
  vertical            TEXT NOT NULL CHECK (vertical IN ('food','grocery')),
  target_orders       INT  NOT NULL CHECK (target_orders >= 0),
  -- Nullable: deriving GMV from an order target needs an AOV assumption, and a
  -- guessed money figure on a dashboard is worse than an absent one.
  target_gmv          BIGINT,
  source              TEXT NOT NULL CHECK (source IN ('seed','auto','manual_override')),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by          UUID REFERENCES public.users(id) ON DELETE SET NULL,
  previous_target_id  BIGINT REFERENCES public.daily_targets(id) ON DELETE SET NULL,
  superseded_at       TIMESTAMPTZ,
  notes               TEXT
);

-- One live target per date per vertical; superseded rows are unconstrained.
CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_targets_active
  ON public.daily_targets (target_date, vertical)
  WHERE superseded_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_daily_targets_date
  ON public.daily_targets (target_date DESC, vertical);

ALTER TABLE public.daily_targets ENABLE ROW LEVEL SECURITY;
-- No policy: reached only through SECURITY DEFINER RPCs, like
-- order_status_events. Base-table access stays closed.

-- ── 2. Change log ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.target_change_log (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target_date   DATE NOT NULL,
  vertical      TEXT NOT NULL CHECK (vertical IN ('food','grocery')),
  before_target INT,
  after_target  INT NOT NULL,
  rule_applied  TEXT NOT NULL,
  reasoning     JSONB NOT NULL DEFAULT '{}'::jsonb,
  actor         TEXT NOT NULL CHECK (actor IN ('scheduler','admin')),
  actor_id      UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_target_change_log_date
  ON public.target_change_log (target_date DESC, vertical);

ALTER TABLE public.target_change_log ENABLE ROW LEVEL SECURITY;

-- ── 3. Job run log ─────────────────────────────────────────────────────────
-- The project has no alerting utility, so per the spec failures land in a table
-- admins can see. A job that fails silently is indistinguishable from a day
-- with no orders, which is the failure mode worth avoiding.
CREATE TABLE IF NOT EXISTS public.scheduled_job_runs (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  job_name    TEXT NOT NULL,
  ran_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  succeeded   BOOLEAN NOT NULL,
  detail      TEXT,
  duration_ms INT
);

CREATE INDEX IF NOT EXISTS idx_scheduled_job_runs_recent
  ON public.scheduled_job_runs (job_name, ran_at DESC);

ALTER TABLE public.scheduled_job_runs ENABLE ROW LEVEL SECURITY;

-- ── 4. Progression config, per vertical ────────────────────────────────────
-- In app_config, keyed by vertical, for the same reason platform_config was
-- not created: one config store, already admin-editable, already hot-reloaded.
INSERT INTO public.app_config (key, value, value_type, description) VALUES
  ('target_growth_rate_on_hit_food',     '0.05', 'number', 'Food: target increase when yesterday hit (0.05 = +5%)'),
  ('target_growth_rate_on_hit_grocery',  '0.05', 'number', 'Grocery: target increase when yesterday hit'),
  ('target_hold_on_miss_food',           'true', 'boolean','Food: hold target on a miss rather than stepping down'),
  ('target_hold_on_miss_grocery',        'true', 'boolean','Grocery: hold target on a miss'),
  ('target_step_down_rate_on_miss_food',    '0', 'number', 'Food: reduction on a miss when hold is false'),
  ('target_step_down_rate_on_miss_grocery', '0', 'number', 'Grocery: reduction on a miss when hold is false'),
  ('target_min_food',                       '1', 'number', 'Food: target floor'),
  ('target_min_grocery',                    '1', 'number', 'Grocery: target floor'),
  ('target_max_daily_increase_food',        '5', 'number', 'Food: largest absolute one-day jump'),
  ('target_max_daily_increase_grocery',     '5', 'number', 'Grocery: largest absolute one-day jump'),
  ('target_smoothing_window_days_food',     '1', 'number', 'Food: days of actuals to average. 1 = yesterday only'),
  ('target_smoothing_window_days_grocery',  '1', 'number', 'Grocery: days of actuals to average'),
  ('platform_timezone',      'America/Jamaica', 'string', 'Timezone for period boundaries and the 00:05 target job')
ON CONFLICT (key) DO UPDATE
  SET value_type  = EXCLUDED.value_type,
      description = EXCLUDED.description;

-- ── 5. Actuals, from the SAME primitives as the KPI RPCs ───────────────────
-- A plain view, not materialized. The spec allows a materialized view with a
-- documented refresh cadence; at this volume a refresh job would be more
-- moving parts than the query costs, and a target card showing stale actuals
-- is worse than one that takes an extra moment. Revisit if it gets slow.
CREATE OR REPLACE VIEW public.daily_actuals AS
WITH d AS (
  SELECT DISTINCT (o.ordered_at AT TIME ZONE COALESCE(
           (SELECT value FROM public.app_config WHERE key='platform_timezone'),
           'America/Jamaica'))::date AS target_date
  FROM public.orders o
  WHERE o.ordered_at IS NOT NULL
),
v AS (SELECT unnest(ARRAY['food','grocery']) AS vertical)
SELECT d.target_date,
       v.vertical,
       COALESCE(e.n, 0)::bigint            AS orders_count,
       COALESCE(e.gmv, 0)::bigint          AS gmv,
       COALESCE(e.contribution, 0)::bigint AS contribution_total,
       CASE WHEN COALESCE(e.n,0) > 0 THEN (e.gmv / e.n)::bigint ELSE 0::bigint END
         AS aov,
       CASE WHEN COALESCE(e.n,0) > 0 THEN (e.gross / e.n)::bigint ELSE 0::bigint END
         AS gross_revenue_per_order,
       CASE WHEN COALESCE(e.n,0) > 0 THEN (e.contribution / e.n)::bigint ELSE 0::bigint END
         AS net_contribution_per_order
FROM d
CROSS JOIN v
LEFT JOIN LATERAL (
  SELECT count(*)::bigint AS n,
         COALESCE(sum(x.gmv),0)::bigint AS gmv,
         -- Gross revenue counts only the components that apply to the vertical:
         -- food has no customer service fee line, grocery does.
         COALESCE(sum(x.commission + x.delivery_fee
                    + CASE WHEN v.vertical='grocery' THEN x.service_fee ELSE 0 END
                  ),0)::bigint AS gross,
         COALESCE(sum(x.commission + x.delivery_fee - x.rider_payout
                    + CASE WHEN v.vertical='grocery' THEN x.service_fee ELSE 0 END
                  ),0)::bigint AS contribution
  FROM public.admin_order_economics(
         (d.target_date::timestamp AT TIME ZONE COALESCE(
            (SELECT value FROM public.app_config WHERE key='platform_timezone'),
            'America/Jamaica')),
         ((d.target_date + 1)::timestamp AT TIME ZONE COALESCE(
            (SELECT value FROM public.app_config WHERE key='platform_timezone'),
            'America/Jamaica')),
         (v.vertical = 'grocery')
       ) x
) e ON TRUE;

REVOKE ALL ON public.daily_actuals FROM PUBLIC, anon;
GRANT SELECT ON public.daily_actuals TO service_role;

NOTIFY pgrst, 'reload schema';
