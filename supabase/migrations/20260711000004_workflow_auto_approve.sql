-- ─────────────────────────────────────────────────────────────────────────────
-- Per-workflow auto-approve toggle. Default OFF — a workflow only skips human
-- review if an admin explicitly flips it on for that specific workflow.
-- Nothing about this changes the drafting logic; it only decides whether the
-- approve step runs immediately after drafting instead of waiting for a click.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.automation_workflows
  ADD COLUMN IF NOT EXISTS auto_approve boolean NOT NULL DEFAULT false;
