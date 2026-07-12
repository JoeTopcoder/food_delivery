-- ─────────────────────────────────────────────────────────────────────────────
-- Promotion Agent — closes the loop on Marketing Strategy's promo_opportunities
-- signal (at-risk restaurants with no active promo) by letting an admin
-- generate a grounded promo proposal and, on approval, actually create the
-- promo_codes row. Drafting never creates anything; only approve() does,
-- after human review — same discipline as every other agent this session.
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO public.ai_agents (slug, name, department, description, status, route, model) VALUES
('promotion_agent', 'Promotion Agent', 'Marketing',
 'Drafts promo code proposals grounded in Marketing Strategy and Customer Retention signals. Never creates a promo itself — an admin reviews and approves every field before it goes live.',
 'active', '/admin-ai/promotions', 'gpt-4o-mini')
ON CONFLICT (slug) DO UPDATE SET
  route = EXCLUDED.route,
  model = EXCLUDED.model,
  description = EXCLUDED.description;
