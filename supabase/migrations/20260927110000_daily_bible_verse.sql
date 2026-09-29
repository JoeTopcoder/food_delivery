-- ============================================================================
-- Daily Bible verse — one verse per user per day, VARIED across users.
-- No per-user assignment table: the verse is chosen deterministically from
-- hash(user_id + Jamaica date) % verse_count, so a given user sees the same
-- verse all day, different users see different verses, and it rotates daily.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.bible_verses (
  id         bigserial PRIMARY KEY,
  reference  text NOT NULL,
  text       text NOT NULL,
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.bible_verses ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='bible_verses' AND policyname='bible_verses_read') THEN
    CREATE POLICY bible_verses_read ON public.bible_verses
      FOR SELECT TO authenticated, anon USING (is_active = true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='bible_verses' AND policyname='bible_verses_admin') THEN
    CREATE POLICY bible_verses_admin ON public.bible_verses
      FOR ALL TO authenticated
      USING (EXISTS (SELECT 1 FROM users WHERE id=auth.uid() AND role='admin'))
      WITH CHECK (EXISTS (SELECT 1 FROM users WHERE id=auth.uid() AND role='admin'));
  END IF;
END $$;

-- Curated set (seed once; safe to re-run — only inserts when empty).
INSERT INTO public.bible_verses (reference, text)
SELECT * FROM (VALUES
  ('Jeremiah 29:11', 'For I know the plans I have for you, declares the Lord, plans to prosper you and not to harm you, plans to give you hope and a future.'),
  ('Philippians 4:13', 'I can do all things through Christ who strengthens me.'),
  ('Proverbs 3:5-6', 'Trust in the Lord with all your heart and lean not on your own understanding; in all your ways submit to him, and he will make your paths straight.'),
  ('Psalm 23:1', 'The Lord is my shepherd; I shall not want.'),
  ('Isaiah 41:10', 'Fear not, for I am with you; be not dismayed, for I am your God. I will strengthen you, I will help you.'),
  ('Romans 8:28', 'And we know that in all things God works for the good of those who love him, who have been called according to his purpose.'),
  ('Joshua 1:9', 'Be strong and courageous. Do not be afraid; do not be discouraged, for the Lord your God will be with you wherever you go.'),
  ('Psalm 46:1', 'God is our refuge and strength, an ever-present help in trouble.'),
  ('Matthew 6:33', 'But seek first the kingdom of God and his righteousness, and all these things will be added unto you.'),
  ('Philippians 4:6-7', 'Do not be anxious about anything, but in every situation, by prayer and petition, with thanksgiving, present your requests to God.'),
  ('Psalm 121:1-2', 'I lift up my eyes to the mountains — where does my help come from? My help comes from the Lord, the Maker of heaven and earth.'),
  ('2 Corinthians 5:7', 'For we walk by faith, not by sight.'),
  ('Psalm 27:1', 'The Lord is my light and my salvation — whom shall I fear? The Lord is the stronghold of my life.'),
  ('Isaiah 40:31', 'But those who hope in the Lord will renew their strength. They will soar on wings like eagles; they will run and not grow weary.'),
  ('John 3:16', 'For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.'),
  ('Psalm 118:24', 'This is the day that the Lord has made; let us rejoice and be glad in it.'),
  ('Deuteronomy 31:6', 'Be strong and courageous. Do not be afraid or terrified, for the Lord your God goes with you; he will never leave you nor forsake you.'),
  ('Romans 12:12', 'Be joyful in hope, patient in affliction, faithful in prayer.'),
  ('Psalm 34:8', 'Taste and see that the Lord is good; blessed is the one who takes refuge in him.'),
  ('Matthew 11:28', 'Come to me, all you who are weary and burdened, and I will give you rest.'),
  ('1 Corinthians 13:4', 'Love is patient, love is kind. It does not envy, it does not boast, it is not proud.'),
  ('Psalm 37:4', 'Take delight in the Lord, and he will give you the desires of your heart.'),
  ('Galatians 6:9', 'Let us not become weary in doing good, for at the proper time we will reap a harvest if we do not give up.'),
  ('Psalm 91:1-2', 'Whoever dwells in the shelter of the Most High will rest in the shadow of the Almighty. I will say of the Lord, He is my refuge and my fortress.'),
  ('Colossians 3:23', 'Whatever you do, work at it with all your heart, as working for the Lord, not for human masters.'),
  ('Hebrews 11:1', 'Now faith is confidence in what we hope for and assurance about what we do not see.'),
  ('Psalm 55:22', 'Cast your cares on the Lord and he will sustain you; he will never let the righteous be shaken.'),
  ('Proverbs 16:3', 'Commit to the Lord whatever you do, and he will establish your plans.'),
  ('2 Timothy 1:7', 'For God has not given us a spirit of fear, but of power and of love and of a sound mind.'),
  ('Psalm 28:7', 'The Lord is my strength and my shield; my heart trusts in him, and he helps me.'),
  ('Lamentations 3:22-23', 'Because of the Lord''s great love we are not consumed, for his compassions never fail. They are new every morning; great is your faithfulness.'),
  ('Nahum 1:7', 'The Lord is good, a refuge in times of trouble. He cares for those who trust in him.'),
  ('John 14:27', 'Peace I leave with you; my peace I give you. Do not let your hearts be troubled and do not be afraid.'),
  ('Zephaniah 3:17', 'The Lord your God is with you, the Mighty Warrior who saves. He will take great delight in you.'),
  ('Psalm 16:8', 'I keep my eyes always on the Lord. With him at my right hand, I will not be shaken.')
) AS v(reference, text)
WHERE NOT EXISTS (SELECT 1 FROM public.bible_verses);

-- Deterministic daily verse for the current caller (or a passed id for testing).
CREATE OR REPLACE FUNCTION public.get_daily_verse(p_user_id uuid DEFAULT NULL)
RETURNS TABLE (reference text, text text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid   text;
  v_day   text := to_char((now() AT TIME ZONE 'America/Jamaica'), 'YYYY-MM-DD');
  v_count int;
  v_idx   int;
BEGIN
  -- Pin to the JWT caller when present; fall back to the passed id otherwise.
  v_uid := COALESCE(auth.uid()::text, p_user_id::text, 'anon');
  SELECT count(*) INTO v_count FROM bible_verses WHERE is_active;
  IF v_count = 0 THEN RETURN; END IF;
  v_idx := abs(hashtext(v_uid || v_day)) % v_count;

  RETURN QUERY
  SELECT bv.reference, bv.text FROM (
    SELECT b.reference, b.text, row_number() OVER (ORDER BY b.id) - 1 AS rn
    FROM bible_verses b WHERE b.is_active
  ) bv
  WHERE bv.rn = v_idx;
END; $$;

REVOKE ALL ON FUNCTION public.get_daily_verse(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_daily_verse(uuid) TO authenticated, anon, service_role;

-- Feature flag + timing knobs (admin-toggleable; ON by default).
INSERT INTO public.app_config (key, value) VALUES
  ('daily_verse_enabled', 'true'),
  ('daily_verse_delay_seconds', '150')  -- ~2.5 min into scrolling
ON CONFLICT (key) DO NOTHING;

NOTIFY pgrst, 'reload schema';
