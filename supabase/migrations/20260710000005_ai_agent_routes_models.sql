-- ─────────────────────────────────────────────────────────────────────────────
-- Fill in planned route + model for every registered agent. Routes for
-- 'planned' agents are destinations that don't exist in main.dart yet — the
-- admin app only navigates to an agent's route once its status is 'active'
-- (enforced in admin_ai_operations_screen.dart, not just by this data).
-- Model choice follows the spec's own guidance: smaller/cheaper models for
-- classification and drafting, larger models for complex multi-factor
-- judgment (finance, fraud, executive/BI synthesis, market scoring).
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE public.ai_agents SET route = '/admin-ai/executive',              model = 'gpt-4o'      WHERE slug = 'executive_intelligence';
UPDATE public.ai_agents SET route = '/admin-ai/marketing-strategy',     model = 'gpt-4o-mini' WHERE slug = 'marketing_strategy';
UPDATE public.ai_agents SET route = '/admin-ai/marketing-content',     model = 'gpt-4o-mini' WHERE slug = 'marketing_content';
UPDATE public.ai_agents SET route = '/admin-ai/restaurant-leads',      model = 'gpt-4o-mini' WHERE slug = 'restaurant_lead_gen';
UPDATE public.ai_agents SET route = '/admin-ai/restaurant-sales',      model = 'gpt-4o-mini' WHERE slug = 'restaurant_sales';
UPDATE public.ai_agents SET route = '/admin-ai/restaurant-onboarding', model = 'gpt-4o-mini' WHERE slug = 'restaurant_onboarding';
UPDATE public.ai_agents SET route = '/admin-ai/menu-intelligence',     model = 'gpt-4o-mini' WHERE slug = 'menu_intelligence';
UPDATE public.ai_agents SET route = '/admin-ai/driver-recruitment',    model = 'gpt-4o-mini' WHERE slug = 'driver_recruitment';
UPDATE public.ai_agents SET route = '/admin-ai/driver-compliance',     model = 'gpt-4o-mini' WHERE slug = 'driver_compliance';
UPDATE public.ai_agents SET route = '/admin-ai/dispatch',              model = 'gpt-4o-mini' WHERE slug = 'dispatch_optimization';
UPDATE public.ai_agents SET route = '/admin-ai/live-orders',           model = 'gpt-4o-mini' WHERE slug = 'live_order_ops';
UPDATE public.ai_agents SET route = '/admin-ai/restaurant-support',    model = 'gpt-4o-mini' WHERE slug = 'restaurant_support';
UPDATE public.ai_agents SET route = '/admin-ai/driver-support',        model = 'gpt-4o-mini' WHERE slug = 'driver_support';
UPDATE public.ai_agents SET route = '/admin-ai/refunds',               model = 'gpt-4o-mini' WHERE slug = 'refund_resolution';
UPDATE public.ai_agents SET route = '/admin-ai/fraud-risk',            model = 'gpt-4o'      WHERE slug = 'fraud_risk';
UPDATE public.ai_agents SET route = '/admin-ai/finance',               model = 'gpt-4o'      WHERE slug = 'finance_reconciliation';
UPDATE public.ai_agents SET route = '/admin-ai/payouts',               model = 'gpt-4o-mini' WHERE slug = 'payout_agent';
UPDATE public.ai_agents SET route = '/admin-ai/retention',             model = 'gpt-4o-mini' WHERE slug = 'customer_retention';
UPDATE public.ai_agents SET route = '/admin-ai/restaurant-success',    model = 'gpt-4o-mini' WHERE slug = 'restaurant_success';
UPDATE public.ai_agents SET route = '/admin-ai/driver-performance',    model = 'gpt-4o-mini' WHERE slug = 'driver_performance';
UPDATE public.ai_agents SET route = '/admin-ai/reputation',            model = 'gpt-4o-mini' WHERE slug = 'reputation_management';
UPDATE public.ai_agents SET route = '/admin-ai/market-expansion',      model = 'gpt-4o'      WHERE slug = 'market_expansion';
UPDATE public.ai_agents SET route = '/admin-ai/business-intelligence', model = 'gpt-4o'      WHERE slug = 'business_intelligence';
UPDATE public.ai_agents SET route = '/admin-ai/technical-operations',  model = 'gpt-4o-mini' WHERE slug = 'technical_operations';
