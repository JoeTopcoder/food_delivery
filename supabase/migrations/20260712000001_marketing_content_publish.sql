-- ─────────────────────────────────────────────────────────────────────────────
-- weekly_social_campaign's drafts (marketing_content) get an actual publish
-- step now (social-media-publish edge function → Facebook/Instagram/X/TikTok).
-- These columns record what was actually posted and where, same audit
-- discipline as everything else in AI Operations.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.marketing_content
  ADD COLUMN IF NOT EXISTS posted_caption text,
  ADD COLUMN IF NOT EXISTS publish_results jsonb,
  ADD COLUMN IF NOT EXISTS published_at timestamptz;
