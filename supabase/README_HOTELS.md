Hotels & Travel (Hotelbeds) — Deployment Guide

This document explains how to deploy the Hotels & Travel module (Hotelbeds) to your Supabase project.

Prereqs:
- `supabase` CLI installed and logged in (https://supabase.com/docs/guides/cli).
- Project access and the project `ref` or logged-in default project.
- Node/Deno & npm as needed to build functions (functions are Deno/TypeScript-ready).

1) Migrations

- Apply the SQL migration that creates the tables and RPCs:

```powershell
cd supabase
supabase db push --project-ref $SUPABASE_PROJECT_REF
```

If you prefer to run a single migration file:

```powershell
psql $DATABASE_URL -f migrations/20260525000001_hotels_travel_module.sql
```

2) Deploy Edge Functions

- From the repo root, deploy each `hotelbeds-*` function folder in `supabase/functions/`:

```powershell
cd supabase/functions
supabase functions deploy hotelbeds-search --project-ref $SUPABASE_PROJECT_REF
supabase functions deploy hotelbeds-get-hotel-content --project-ref $SUPABASE_PROJECT_REF
supabase functions deploy hotelbeds-check-rate --project-ref $SUPABASE_PROJECT_REF
supabase functions deploy hotelbeds-create-booking --project-ref $SUPABASE_PROJECT_REF
supabase functions deploy hotelbeds-get-booking --project-ref $SUPABASE_PROJECT_REF
supabase functions deploy hotelbeds-cancel-booking --project-ref $SUPABASE_PROJECT_REF
supabase functions deploy hotelbeds-generate-voucher --project-ref $SUPABASE_PROJECT_REF
```

3) Configure Secrets (do NOT add keys to client)

Set the Hotelbeds credentials as project secrets (Edge Functions environment):

```powershell
supabase secrets set HOTELBEDS_API_KEY="<your_api_key>" HOTELBEDS_SECRET="<your_secret>" --project-ref $SUPABASE_PROJECT_REF
```

Also ensure your Supabase service role key and URL are available to admin tooling (not the client).

4) Feature Flags & Admin

- By default the module is seeded as inactive. In the Supabase SQL editor or via the admin UI enable:

  - `travel_provider_settings` → set `is_active = true` (provider = 'hotelbeds')
  - `feature_flags` → set `hotels_enabled = true`

You can also toggle these using the Admin UI in the app at `/admin/hotels/settings`.

5) Testing checklist

- As an authenticated user, run a search from app: `/hotels` → verify results.
- For `RECHECK` rates, ensure checkRate flow works and returns `display_rate`.
- Create booking (card and wallet paths) and verify `hotel_bookings` row created and voucher generation works.
- Test cancellation and wallet refunds.

6) Troubleshooting

- If functions return `Hotelbeds credentials not configured`, verify secrets are set for the project and that deployments used the correct project ref.
- If DB errors appear, confirm migrations applied and RLS policies exist (the migration enables RLS for the new tables).

Contact: repository owner for project-ref and secrets.

CI Deployment
-------------

This repo includes a GitHub Actions workflow `.github/workflows/deploy_hotels.yml` that can deploy migrations and Edge Functions.
To use it add the following repository secrets:

- `SUPABASE_ACCESS_TOKEN` — a supabase CLI access token (for `supabase login`).
- `SUPABASE_PROJECT_REF` — your project ref (e.g. `abcd1234`).
- `HOTELBEDS_API_KEY` and `HOTELBEDS_SECRET` — optional; if present the workflow will push them to the project secrets.

Then trigger the workflow manually (Actions → Deploy Hotels Module) or push to `main`.

