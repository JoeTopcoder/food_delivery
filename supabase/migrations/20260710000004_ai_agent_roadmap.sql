-- ─────────────────────────────────────────────────────────────────────────────
-- Register the remaining 24 agents from the 7Dash AI Operations plan as
-- 'planned' — visible in the AI Operations hub as roadmap items, but not
-- claiming to function until each is actually built (real edge function,
-- scoped DB access, tested prompt) and flipped to 'active'.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.ai_agents DROP CONSTRAINT IF EXISTS ai_agents_status_check;
ALTER TABLE public.ai_agents ADD CONSTRAINT ai_agents_status_check
  CHECK (status IN ('active', 'paused', 'planned'));

INSERT INTO public.ai_agents (slug, name, department, description, status) VALUES
('executive_intelligence',  'Executive Intelligence Agent',  'Executive',             'Daily/weekly/monthly business summaries, risk flags, KPI tracking. Recommends only — never changes pricing, contracts, or policy.', 'planned'),
('marketing_strategy',      'Marketing Strategy Agent',      'Marketing',             'Campaign strategy, channel planning, budget recommendations. Paid spend requires approval.', 'planned'),
('marketing_content',       'Marketing Content Agent',       'Marketing',             'Drafts brand-compliant social/email/SMS/push content. Requires approval before publishing.', 'planned'),
('restaurant_lead_gen',     'Restaurant Lead Generation Agent', 'Restaurant Acquisition', 'Finds, scores, and enriches restaurant leads by market.', 'planned'),
('restaurant_sales',        'Restaurant Sales Agent',        'Restaurant Acquisition', 'Personalized outreach to qualified leads. Never invents commercial terms or guarantees.', 'planned'),
('restaurant_onboarding',   'Restaurant Onboarding Agent',   'Restaurant Onboarding', 'Tracks onboarding checklist, documents, Stripe Connect status, menu completeness, launch readiness.', 'planned'),
('menu_intelligence',       'Menu Intelligence Agent',       'Restaurant Success',    'Flags missing images/descriptions/pricing issues. Changes require restaurant or admin approval.', 'planned'),
('driver_recruitment',      'Driver Recruitment Agent',      'Driver Recruitment',    'Forecasts driver demand by zone, screens applications, tracks missing documentation.', 'planned'),
('driver_compliance',       'Driver Compliance Agent',       'Driver Compliance',     'Tracks document expiration, flags missing/suspicious documents. Deactivation follows human review.', 'planned'),
('dispatch_optimization',   'Dispatch Optimization Agent',   'Dispatch',              'Ranks and recommends drivers for orders with an explainable reason for each assignment.', 'planned'),
('live_order_ops',          'Live Order Operations Agent',   'Live Operations',       'Monitors active orders for prep delays, stalled deliveries, and unassigned orders; escalates.', 'planned'),
('restaurant_support',      'Restaurant Support Agent',      'Restaurant Support',    'Resolves restaurant order, menu, and payout questions. Contractual disputes escalate.', 'planned'),
('driver_support',          'Driver Support Agent',          'Driver Support',        'Explains assignments, earnings, and payout status. Safety incidents escalate immediately to a human.', 'planned'),
('refund_resolution',       'Refund and Resolution Agent',   'Refunds',               'Evaluates refund/credit/redelivery requests with evidence and a confidence score. High-value cases require approval.', 'planned'),
('fraud_risk',              'Fraud and Risk Agent',          'Risk',                  'Scores suspicious activity (promo abuse, fake accounts, GPS manipulation). Permanent bans require human review.', 'planned'),
('finance_reconciliation',  'Finance and Reconciliation Agent', 'Finance',            'Reconciles payments, earnings, and fees, and flags mismatches. Explains figures — never the authoritative calculation.', 'planned'),
('payout_agent',            'Payout Agent',                  'Finance',               'Checks payout eligibility, balance, and holds before submission. Large/unusual payouts require approval.', 'planned'),
('customer_retention',      'Customer Retention Agent',      'Retention',             'Identifies churn risk and recommends approved reactivation offers, respecting consent/unsubscribe preferences.', 'planned'),
('restaurant_success',      'Restaurant Success Agent',      'Restaurant Success',    'Monitors acceptance, prep time, cancellation, and refund rates; flags at-risk partners.', 'planned'),
('driver_performance',      'Driver Performance Agent',      'Driver Success',        'Monitors acceptance/completion/lateness. Recommends corrective action only — deactivation needs human review.', 'planned'),
('reputation_management',   'Reputation Management Agent',   'Reputation',            'Monitors app store/social reviews, drafts responses. Public replies require approval.', 'planned'),
('market_expansion',        'Market Expansion Agent',        'Strategy',              'Scores candidate markets and produces 30/60/90-day launch plans.', 'planned'),
('business_intelligence',   'Business Intelligence Agent',   'Analytics',             'Converts platform data into reports, real-time alerts, and forecasts.', 'planned'),
('technical_operations',    'Technical Operations Agent',    'Technical Operations',  'Monitors errors, failures, and latency; creates incidents. Never deploys unreviewed code.', 'planned')
ON CONFLICT (slug) DO NOTHING;
