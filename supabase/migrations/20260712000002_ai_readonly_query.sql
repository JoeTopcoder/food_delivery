-- ─────────────────────────────────────────────────────────────────────────────
-- ai_readonly_query — lets the new "Ask AI" agent (ops-report-agent, agent_slug
-- 'ask_ai') answer free-form admin questions by running SQL it writes itself
-- against the real schema, instead of a fixed set of hand-coded metrics.
--
-- SECURITY DEFINER so it can read across every table regardless of RLS (an
-- admin asking "how many orders today" shouldn't be blocked by a customer-
-- scoped policy) — which is exactly why it's locked down hard:
--   1. Only SELECT/WITH statements accepted (regex-gated).
--   2. Any mutating keyword anywhere in the text is rejected outright.
--   3. transaction_read_only is forced on for the call, so even a query that
--      slips past the keyword filter is rejected by Postgres itself, not
--      just by string matching.
--   4. Results are capped and the statement has a hard timeout.
--   5. EXECUTE only granted to service_role — never authenticated/anon, since
--      a SECURITY DEFINER function bypasses RLS entirely.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.ai_readonly_query(query_text text, row_limit int DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result jsonb;
  capped_limit int := LEAST(GREATEST(COALESCE(row_limit, 50), 1), 200);
BEGIN
  IF query_text IS NULL OR btrim(query_text) = '' THEN
    RAISE EXCEPTION 'Empty query';
  END IF;
  IF query_text ~ ';' THEN
    RAISE EXCEPTION 'Semicolons are not allowed — one statement only';
  END IF;
  IF query_text !~* '^\s*(SELECT|WITH)\s' THEN
    RAISE EXCEPTION 'Only SELECT queries are allowed';
  END IF;
  IF query_text ~* '\y(INSERT|UPDATE|DELETE|DROP|ALTER|TRUNCATE|GRANT|REVOKE|CREATE|COPY|CALL|DO|VACUUM|REFRESH|MERGE|LOCK|SET|RESET|EXECUTE|PREPARE|LISTEN|NOTIFY)\y' THEN
    RAISE EXCEPTION 'Query contains a disallowed keyword';
  END IF;

  SET LOCAL transaction_read_only = on;
  SET LOCAL statement_timeout = '5s';

  -- The row cap is applied via an outer SELECT wrapping the caller's query
  -- as its own subquery, never appended into it directly — a second LIMIT
  -- tacked onto a query that already ends in one (or an ORDER BY) would be
  -- a syntax error, and this way the cap always applies regardless of what
  -- the caller's query does or doesn't already have.
  EXECUTE format(
    'SELECT COALESCE(jsonb_agg(t), ''[]''::jsonb) FROM (SELECT * FROM (%s) AS inner_q LIMIT %s) AS t',
    query_text, capped_limit
  ) INTO result;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.ai_readonly_query(text, int) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ai_readonly_query(text, int) FROM authenticated;
REVOKE ALL ON FUNCTION public.ai_readonly_query(text, int) FROM anon;
GRANT EXECUTE ON FUNCTION public.ai_readonly_query(text, int) TO service_role;
