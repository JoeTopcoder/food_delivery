# AI Decision Room (admin)

A multi-model advisory workflow inside the existing HotBite admin app. OpenAI and
Claude each assess a question, review each other, then a synthesis model produces
a final structured recommendation. **Advisory only** — it changes no prices,
orders, payments, referrals or any business data.

## Access
- **Super admin** (app_config `ai_decision_super_admin_email`, default
  support@7-dash.com) has access by default.
- Other admins only via an explicit grant (`ai_decision_grant_access`, super-admin
  only). Enforced in the DB (RLS + `ai_decision_room_allowed`) **and** the edge
  function **and** the UI.
- Feature flag: `ai_decision_room_enabled`. Daily limit: `ai_decision_daily_limit`.

## Workflow (5 durable stages)
openai_assess → claude_assess → openai_review → claude_review → synthesis.
Each stage is a row in `ai_decision_stages` (pending→running→done/failed), so
progress survives restarts and supports **cancel** and **per-stage retry**.
The client calls `ai-decision-advance` repeatedly (one stage per call) showing
live progress. Synthesis validates **exactly three** next actions.

## Report
Final recommendation, both assessments, both cross-reviews, agreements,
disagreements, assumptions, facts to verify, next 3 actions — plus the admin's
own final decision + notes (recorded, advisory only).

## Business metrics (optional, off by default)
Toggle "Include business metrics" → preview the **exact aggregates + date range**
before submit. `ai_decision_metrics_preview` returns counts/sums only (orders,
revenue, AOV, active restaurants/drivers) — **never** customer identities, phones,
addresses, banking or payment credentials. Aggregates are computed on the backend;
only approved aggregates are sent to the providers. Providers get no DB access, and
all context/metrics are framed to the models as DATA, never instructions.

## Keys / mock
`OPENAI_API_KEY` + `ANTHROPIC_API_KEY` are backend secrets (see
`functions/ai-decision-advance/.env.example`). Missing key ⇒ that provider runs in
labelled MOCK mode (no paid calls); the UI shows a MOCK banner. Keys never reach
Flutter or any client-readable row.

## Files
- Migrations: `20261004020000_ai_decision_room.sql` (tables/RLS/permissions),
  `20261004030000_ai_decision_room_rpcs.sql` (create/cancel/retry/save/grant/metrics).
- Edge: `functions/ai-decision-advance`, `functions/_shared/ai_providers.ts`.
- Flutter: `lib/services/ai/ai_decision_service.dart`,
  `lib/screens/admin/ai_decision_room.dart` (dashboard/new/analysis/report),
  route `/admin-ai-decision-room`, admin overview tile "AI Decision Room".

## Setup to go fully live
1. `supabase secrets set ANTHROPIC_API_KEY=sk-ant-…` (OpenAI already set).
2. Confirm `ai_decision_super_admin_email` matches your super admin.
3. Grant other admins via the super admin if needed.
4. Runs cost OpenAI/Anthropic tokens per decision (5 calls) — authorize before heavy use.
