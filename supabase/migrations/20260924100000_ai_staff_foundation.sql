-- ============================================================================
-- HotBite AI Staff — Stage 2: database foundation
-- ============================================================================
-- 24 AI staff roles that analyse business data, produce a daily report each,
-- raise up to three evidence-based operational suggestions, and surface urgent
-- alerts, consolidated into a single admin briefing per day.
--
-- Design principles:
--  * Read-only over the business. These tables are a NEW, self-contained
--    reporting layer. They do NOT touch orders, payments, payouts, floats or
--    any financial/order table — nothing here alters existing behaviour.
--  * Reuses the project's real permission model: admin access via the existing
--    SECURITY DEFINER public.is_admin() (users.role = 'admin'), exactly as
--    ai_agents / ai_agent_runs / daily_metrics already do. Customers, riders
--    and stores get no policy at all → RLS default-deny locks them out.
--  * Scheduled backend writes run as service_role, which bypasses RLS, so the
--    daily job can write without any client-writable policy existing.
--  * Fully idempotent (IF NOT EXISTS / ON CONFLICT / DROP POLICY IF EXISTS) so
--    it is safe to apply to the live production database and to re-run.
-- ============================================================================

-- ── 1. Role definitions & standing instructions ────────────────────────────
CREATE TABLE IF NOT EXISTS public.ai_staff_roles (
  id                            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug                          text NOT NULL UNIQUE,
  title                         text NOT NULL,
  department                    text,
  job_description               text NOT NULL,
  data_categories               text[] NOT NULL DEFAULT '{}',
  daily_reporting_requirements  text NOT NULL,
  max_suggestions               int  NOT NULL DEFAULT 3
                                  CHECK (max_suggestions BETWEEN 0 AND 3),
  model                         text NOT NULL DEFAULT 'gpt-4o-mini',
  status                        text NOT NULL DEFAULT 'active'
                                  CHECK (status IN ('active','paused','archived')),
  sort_order                    int  NOT NULL DEFAULT 0,
  created_at                    timestamptz NOT NULL DEFAULT now(),
  updated_at                    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ai_staff_roles_status ON public.ai_staff_roles(status);

-- ── 2. Daily report RUN (one batch per calendar day) ───────────────────────
CREATE TABLE IF NOT EXISTS public.ai_report_runs (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  report_date      date NOT NULL,
  status           text NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending','running','completed','partial','failed')),
  triggered_by     text NOT NULL DEFAULT 'cron',
  total_roles      int  NOT NULL DEFAULT 0,
  completed_roles  int  NOT NULL DEFAULT 0,
  failed_roles     int  NOT NULL DEFAULT 0,
  started_at       timestamptz,
  completed_at     timestamptz,
  error            text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  -- One run per day: prevents duplicate daily batches (re-run via upsert).
  CONSTRAINT ai_report_runs_date_unique UNIQUE (report_date)
);
CREATE INDEX IF NOT EXISTS idx_ai_report_runs_date ON public.ai_report_runs(report_date DESC);

-- ── 3. Individual AI staff report (one per role per run) ────────────────────
CREATE TABLE IF NOT EXISTS public.ai_staff_reports (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id       uuid NOT NULL REFERENCES public.ai_report_runs(id) ON DELETE CASCADE,
  role_id      uuid NOT NULL REFERENCES public.ai_staff_roles(id) ON DELETE CASCADE,
  report_date  date NOT NULL,
  status       text NOT NULL DEFAULT 'completed'
                 CHECK (status IN ('pending','completed','failed','skipped')),
  summary      text,
  metrics      jsonb NOT NULL DEFAULT '{}'::jsonb,   -- deterministic source metrics
  evidence     jsonb NOT NULL DEFAULT '[]'::jsonb,   -- rows/figures the narrative rests on
  model        text,
  tokens_used  int,
  error        text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  -- One report per role per run: prevents duplicate staff reports.
  CONSTRAINT ai_staff_reports_run_role_unique UNIQUE (run_id, role_id)
);
CREATE INDEX IF NOT EXISTS idx_ai_staff_reports_date   ON public.ai_staff_reports(report_date DESC);
CREATE INDEX IF NOT EXISTS idx_ai_staff_reports_role   ON public.ai_staff_reports(role_id);
CREATE INDEX IF NOT EXISTS idx_ai_staff_reports_status ON public.ai_staff_reports(status);

-- ── 4. Operational suggestions + approval workflow ─────────────────────────
CREATE TABLE IF NOT EXISTS public.ai_suggestions (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id         uuid NOT NULL REFERENCES public.ai_staff_reports(id) ON DELETE CASCADE,
  role_id           uuid REFERENCES public.ai_staff_roles(id) ON DELETE SET NULL,
  report_date       date NOT NULL,
  title             text NOT NULL,
  description       text NOT NULL,
  rationale         text,                              -- evidence-based reasoning
  evidence          jsonb NOT NULL DEFAULT '[]'::jsonb,
  priority          text NOT NULL DEFAULT 'medium'
                      CHECK (priority IN ('low','medium','high','urgent')),
  estimated_impact  text,
  status            text NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','approved','rejected','implemented','dismissed')),
  reviewed_by       uuid REFERENCES public.users(id) ON DELETE SET NULL,
  reviewed_at       timestamptz,
  review_notes      text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ai_suggestions_status ON public.ai_suggestions(status);
CREATE INDEX IF NOT EXISTS idx_ai_suggestions_date   ON public.ai_suggestions(report_date DESC);
CREATE INDEX IF NOT EXISTS idx_ai_suggestions_role   ON public.ai_suggestions(role_id);
CREATE INDEX IF NOT EXISTS idx_ai_suggestions_report ON public.ai_suggestions(report_id);

-- ── 5. Combined admin briefing (one consolidated digest per day) ───────────
CREATE TABLE IF NOT EXISTS public.ai_admin_briefings (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id            uuid REFERENCES public.ai_report_runs(id) ON DELETE CASCADE,
  briefing_date     date NOT NULL,
  headline          text,
  summary           text NOT NULL,
  highlights        jsonb NOT NULL DEFAULT '[]'::jsonb,
  metrics           jsonb NOT NULL DEFAULT '{}'::jsonb,
  roles_reported    int NOT NULL DEFAULT 0,
  suggestions_count int NOT NULL DEFAULT 0,
  urgent_count      int NOT NULL DEFAULT 0,
  delivery_channel  text,
  delivered_at      timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  -- One briefing per day: prevents duplicate digests.
  CONSTRAINT ai_admin_briefings_date_unique UNIQUE (briefing_date)
);
CREATE INDEX IF NOT EXISTS idx_ai_admin_briefings_date ON public.ai_admin_briefings(briefing_date DESC);

-- ── 6. Urgent alerts (raised out-of-band by any role) ──────────────────────
CREATE TABLE IF NOT EXISTS public.ai_urgent_alerts (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  role_id          uuid REFERENCES public.ai_staff_roles(id) ON DELETE SET NULL,
  report_id        uuid REFERENCES public.ai_staff_reports(id) ON DELETE SET NULL,
  report_date      date NOT NULL DEFAULT CURRENT_DATE,
  severity         text NOT NULL DEFAULT 'high'
                     CHECK (severity IN ('high','critical')),
  title            text NOT NULL,
  message          text NOT NULL,
  evidence         jsonb NOT NULL DEFAULT '[]'::jsonb,
  status           text NOT NULL DEFAULT 'open'
                     CHECK (status IN ('open','acknowledged','resolved','dismissed')),
  acknowledged_by  uuid REFERENCES public.users(id) ON DELETE SET NULL,
  acknowledged_at  timestamptz,
  resolved_at      timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ai_urgent_alerts_status   ON public.ai_urgent_alerts(status);
CREATE INDEX IF NOT EXISTS idx_ai_urgent_alerts_date     ON public.ai_urgent_alerts(report_date DESC);
CREATE INDEX IF NOT EXISTS idx_ai_urgent_alerts_severity ON public.ai_urgent_alerts(severity);

-- ============================================================================
-- RLS — admins only (mirrors ai_agents / daily_metrics). No policy exists for
-- customers/riders/stores, so RLS default-deny blocks them. service_role
-- (scheduled writes) bypasses RLS entirely.
-- ============================================================================
ALTER TABLE public.ai_staff_roles     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_report_runs     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_staff_reports   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_suggestions     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_admin_briefings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_urgent_alerts   ENABLE ROW LEVEL SECURITY;

-- Read: authorised admins can read everything.
DROP POLICY IF EXISTS ai_staff_roles_admin_read     ON public.ai_staff_roles;
DROP POLICY IF EXISTS ai_report_runs_admin_read     ON public.ai_report_runs;
DROP POLICY IF EXISTS ai_staff_reports_admin_read   ON public.ai_staff_reports;
DROP POLICY IF EXISTS ai_suggestions_admin_read     ON public.ai_suggestions;
DROP POLICY IF EXISTS ai_admin_briefings_admin_read ON public.ai_admin_briefings;
DROP POLICY IF EXISTS ai_urgent_alerts_admin_read   ON public.ai_urgent_alerts;

CREATE POLICY ai_staff_roles_admin_read     ON public.ai_staff_roles     FOR SELECT TO authenticated USING (public.is_admin());
CREATE POLICY ai_report_runs_admin_read     ON public.ai_report_runs     FOR SELECT TO authenticated USING (public.is_admin());
CREATE POLICY ai_staff_reports_admin_read   ON public.ai_staff_reports   FOR SELECT TO authenticated USING (public.is_admin());
CREATE POLICY ai_suggestions_admin_read     ON public.ai_suggestions     FOR SELECT TO authenticated USING (public.is_admin());
CREATE POLICY ai_admin_briefings_admin_read ON public.ai_admin_briefings FOR SELECT TO authenticated USING (public.is_admin());
CREATE POLICY ai_urgent_alerts_admin_read   ON public.ai_urgent_alerts   FOR SELECT TO authenticated USING (public.is_admin());

-- Manage: admins action the workflow — approve/reject suggestions, toggle role
-- status, acknowledge/resolve alerts. (Report content itself is written only by
-- the scheduled service-role job, so no client INSERT/UPDATE policy is given
-- for runs/reports/briefings.)
DROP POLICY IF EXISTS ai_staff_roles_admin_update   ON public.ai_staff_roles;
DROP POLICY IF EXISTS ai_suggestions_admin_update    ON public.ai_suggestions;
DROP POLICY IF EXISTS ai_urgent_alerts_admin_update  ON public.ai_urgent_alerts;

CREATE POLICY ai_staff_roles_admin_update  ON public.ai_staff_roles
  FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY ai_suggestions_admin_update   ON public.ai_suggestions
  FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY ai_urgent_alerts_admin_update ON public.ai_urgent_alerts
  FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Table privileges: read for admins gated by RLS above; UPDATE only where the
-- workflow needs it. anon gets nothing. service_role keeps full access.
GRANT SELECT ON public.ai_staff_roles, public.ai_report_runs, public.ai_staff_reports,
               public.ai_suggestions, public.ai_admin_briefings, public.ai_urgent_alerts
  TO authenticated;
GRANT UPDATE ON public.ai_staff_roles, public.ai_suggestions, public.ai_urgent_alerts
  TO authenticated;

-- ── updated_at maintenance ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ai_staff_touch_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN NEW.updated_at := now(); RETURN NEW; END;
$fn$;

DROP TRIGGER IF EXISTS trg_ai_staff_roles_touch ON public.ai_staff_roles;
CREATE TRIGGER trg_ai_staff_roles_touch BEFORE UPDATE ON public.ai_staff_roles
  FOR EACH ROW EXECUTE FUNCTION public.ai_staff_touch_updated_at();

DROP TRIGGER IF EXISTS trg_ai_suggestions_touch ON public.ai_suggestions;
CREATE TRIGGER trg_ai_suggestions_touch BEFORE UPDATE ON public.ai_suggestions
  FOR EACH ROW EXECUTE FUNCTION public.ai_staff_touch_updated_at();

-- ============================================================================
-- Seed the 24 roles exactly once (ON CONFLICT (slug) DO NOTHING).
-- Every role carries: a specific job description, its relevant data categories,
-- an explicit daily reporting requirement, and max_suggestions = 3 (the "up to
-- three evidence-based suggestions" rule).
-- ============================================================================
INSERT INTO public.ai_staff_roles
  (slug, title, department, job_description, data_categories, daily_reporting_requirements, max_suggestions, sort_order)
VALUES
 ('operations_manager','Operations Manager','Operations',
  'Owns end-to-end daily operational health across all verticals: order throughput, completion vs cancellation, delays and bottlenecks, and cross-team issues that need coordination.',
  ARRAY['orders','order_status_events','support_requests','disputes'],
  'Report daily order volume, completion rate, cancellation rate, average fulfilment time, and the top operational bottlenecks with their impact.',3,10),

 ('delivery_manager','Delivery Manager','Delivery',
  'Owns delivery execution: pickup-to-dropoff times, late deliveries, failed/undelivered orders, delivery-fee revenue and distance efficiency.',
  ARRAY['orders','driver_earnings','delivery_stops'],
  'Report daily delivered volume, on-time vs late rate, average delivery time and distance, failed deliveries, and delivery-fee revenue.',3,20),

 ('rider_performance_officer','Rider Performance Officer','Drivers',
  'Monitors rider (driver) productivity and quality: acceptance/completion, ratings, deliveries per active hour, and under-performing or standout riders.',
  ARRAY['drivers','driver_earnings','orders','driver_priority_events'],
  'Report daily active riders, deliveries per rider, acceptance and completion rates, average rating, and riders needing attention.',3,30),

 ('customer_experience_officer','Customer Experience Officer','Customer',
  'Owns customer satisfaction signals: ratings, complaints, support tickets, refunds requested, and repeat-vs-churn behaviour.',
  ARRAY['support_requests','disputes','refunds','orders','chat_reports'],
  'Report daily CSAT signals, complaint and refund volume, top complaint themes, and any spike in negative experience.',3,40),

 ('restaurant_manager','Restaurant Manager','Restaurants',
  'Owns restaurant-partner performance: order volume, prep and ready times, rejections, availability/uptime and top and bottom performers.',
  ARRAY['restaurants','orders','menus','order_status_events'],
  'Report daily active restaurants, order volume by restaurant, average prep time, rejection rate, and offline/underperforming partners.',3,50),

 ('supermarket_manager','Supermarket Manager','Grocery',
  'Owns grocery/supermarket-partner performance: order volume, picking accuracy, stock-outs, substitutions and store uptime.',
  ARRAY['restaurants','orders','menus'],
  'Report daily grocery order volume, active stores, out-of-stock and substitution rates, and stores needing attention.',3,60),

 ('finance_officer','Finance Officer','Finance',
  'Owns the daily financial picture WITHOUT changing any financial record: GMV, gross and net revenue, delivery/service/commission income, membership revenue, and cost lines such as member savings and Stripe fees.',
  ARRAY['orders','customer_memberships','wallet_transactions','refunds'],
  'Report daily GMV, platform revenue by line (delivery, service, commission, membership), refunds, member-savings cost, and net contribution.',3,70),

 ('membership_manager','Membership Manager','Membership',
  'Owns the HotBite+ membership programme: active members, new activations, cancellations, member order share and member-savings spend.',
  ARRAY['customer_memberships','membership_plans','orders'],
  'Report daily active members, new vs cancelled memberships, member order share, and total member savings granted.',3,80),

 ('marketing_manager','Marketing Manager','Marketing',
  'Owns marketing performance: campaign reach, promo redemptions, new-customer acquisition and channel effectiveness.',
  ARRAY['promotions','promo_codes','orders','users'],
  'Report daily new customers, promo redemptions and cost, campaign performance, and acquisition trend.',3,90),

 ('pricing_analyst','Pricing Analyst','Pricing',
  'Analyses pricing and fee structure: delivery-fee yield, peak/surge/priority uplift, basket size sensitivity and margin per order (analysis only — never edits live pricing).',
  ARRAY['orders','app_config'],
  'Report daily average order value, fee yield, peak/surge/priority uplift, and margin-per-order trend with pricing observations.',3,100),

 ('fraud_risk_officer','Fraud and Risk Officer','Risk',
  'Detects fraud and risk signals: refund abuse, suspicious order/cancellation patterns, promo abuse, chargebacks and anomalous accounts.',
  ARRAY['orders','refunds','wallet_transactions','promo_codes','disputes'],
  'Report daily suspected fraud/abuse cases, refund and chargeback anomalies, and high-risk accounts with the evidence behind each.',3,110),

 ('growth_strategist','Growth Strategist','Strategy',
  'Owns growth strategy: cohort retention, order frequency, LTV signals, expansion opportunities and week-over-week momentum.',
  ARRAY['orders','users','customer_memberships','daily_actuals'],
  'Report daily and week-over-week growth in customers and orders, retention signals, and the biggest growth opportunity.',3,120),

 ('dispatch_coordinator','Dispatch Coordinator','Dispatch',
  'Owns dispatch efficiency: assignment speed, unassigned/queued orders, rider-to-demand balance and reassignment/rejection loops.',
  ARRAY['orders','drivers','delivery_stops'],
  'Report daily average assignment time, unassigned-order incidents, rider availability vs demand, and dispatch bottlenecks.',3,130),

 ('demand_forecasting_analyst','Demand Forecasting Analyst','Analytics',
  'Forecasts demand: order patterns by hour/day/zone, peak windows and demand vs actuals against targets.',
  ARRAY['orders','daily_actuals','daily_targets'],
  'Report daily demand by time and zone, forecast vs actual, upcoming peak windows, and demand anomalies.',3,140),

 ('rider_scheduling_officer','Rider Scheduling Officer','Drivers',
  'Owns rider supply planning: online riders vs demand, coverage gaps by time and zone, and idle vs undersupplied periods.',
  ARRAY['drivers','orders','delivery_stops'],
  'Report daily rider coverage vs demand by time and zone, coverage gaps, and staffing recommendations for tomorrow.',3,150),

 ('order_accuracy_officer','Order Accuracy Officer','Quality',
  'Owns order accuracy: wrong/missing items, modifications, accuracy-related refunds and complaints and the partners driving them.',
  ARRAY['orders','order_items','refunds','support_requests'],
  'Report daily order-accuracy issues, accuracy-related refunds and complaints, and the top sources of inaccuracy.',3,160),

 ('store_onboarding_officer','Store Onboarding Officer','Onboarding',
  'Owns partner onboarding: new restaurants/stores added, verification progress, time-to-first-order and stalled onboardings.',
  ARRAY['restaurants','menus','orders'],
  'Report daily new and pending partners, verification/onboarding progress, time-to-first-order, and stalled onboardings.',3,170),

 ('menu_catalogue_quality_officer','Menu and Catalogue Quality Officer','Quality',
  'Owns catalogue quality: items missing images/descriptions/prices, uncategorised items, and HotBite+ member-price coverage and validity.',
  ARRAY['menus','restaurants'],
  'Report daily catalogue completeness, items missing images/prices/categories, and member-price coverage gaps.',3,180),

 ('payment_reconciliation_officer','Payment Reconciliation Officer','Finance',
  'Reconciles payments WITHOUT altering any record: order totals vs captured payments vs wallet ledger, Stripe fees, and mismatches or unsettled amounts.',
  ARRAY['orders','wallet_transactions','wallets','refunds'],
  'Report daily payments captured vs order totals, wallet-ledger reconciliation, Stripe fees, and any unreconciled discrepancies.',3,190),

 ('membership_retention_officer','Membership Retention Officer','Membership',
  'Owns membership retention: members nearing expiry, lapsed members, renewal rate and at-risk members by usage.',
  ARRAY['customer_memberships','orders','membership_plans'],
  'Report daily upcoming expiries, lapsed and renewed members, renewal rate, and at-risk members with why.',3,200),

 ('promotion_performance_officer','Promotion Performance Officer','Marketing',
  'Measures promotion ROI: redemptions, discount cost vs incremental orders, and over- or under-performing promo codes.',
  ARRAY['promotions','promo_codes','orders'],
  'Report daily promo redemptions, discount cost, incremental orders, and best/worst performing promotions.',3,210),

 ('service_area_analyst','Service Area Analyst','Strategy',
  'Analyses geographic performance: orders and demand by zone, delivery-distance/time by area, coverage gaps and out-of-zone demand.',
  ARRAY['orders','delivery_stops','coverage_waitlist'],
  'Report daily performance by service area, underserved zones, out-of-zone demand, and area expansion or trimming opportunities.',3,220),

 ('system_reliability_officer','System Reliability Officer','Technical',
  'Monitors platform reliability: failed edge-function/agent runs, payment/order failures, error spikes and stuck records.',
  ARRAY['ai_agent_runs','orders','wallet_transactions'],
  'Report daily error and failure counts, failed payments/orders, agent-run failures, and any reliability incident with evidence.',3,230),

 ('process_improvement_officer','Process Improvement Officer','Operations',
  'Looks across every other role''s findings to spot recurring, systemic problems and the highest-leverage process changes.',
  ARRAY['ai_staff_reports','ai_suggestions','orders','support_requests'],
  'Report daily recurring/systemic issues surfaced across roles and the highest-impact process improvements, with evidence.',3,240)
ON CONFLICT (slug) DO NOTHING;

NOTIFY pgrst, 'reload schema';
