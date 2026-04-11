-- Migration 019: Schema for remaining premium features
-- Adds: referrals, favorites, review responses, loyalty tiers,
--        contactless delivery, delivery proof, driver leaderboard support

-- ============================================================
-- 1. REFERRAL SYSTEM
-- ============================================================
CREATE TABLE IF NOT EXISTS public.referrals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  referred_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  code TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'expired')),
  reward_given BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);

ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;

-- Users can read own referrals (as referrer or referred)
CREATE POLICY "users_read_own_referrals" ON public.referrals
  FOR SELECT TO authenticated
  USING (referrer_id = auth.uid() OR referred_id = auth.uid());

CREATE POLICY "users_insert_own_referrals" ON public.referrals
  FOR INSERT TO authenticated
  WITH CHECK (referrer_id = auth.uid());

CREATE POLICY "admin_select_all_referrals" ON public.referrals
  FOR SELECT TO authenticated
  USING (is_admin());

CREATE POLICY "admin_update_referrals" ON public.referrals
  FOR UPDATE TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

GRANT ALL ON public.referrals TO authenticated;

-- Add referral_code column to users
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS referral_code TEXT UNIQUE;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS referred_by UUID REFERENCES public.users(id);

-- ============================================================
-- 2. FAVORITES
-- ============================================================
CREATE TABLE IF NOT EXISTS public.favorites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  restaurant_id UUID REFERENCES public.restaurants(id) ON DELETE CASCADE,
  menu_item_id UUID REFERENCES public.menus(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, restaurant_id),
  CHECK (restaurant_id IS NOT NULL OR menu_item_id IS NOT NULL)
);

ALTER TABLE public.favorites ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_manage_own_favorites" ON public.favorites
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "admin_select_all_favorites" ON public.favorites
  FOR SELECT TO authenticated
  USING (is_admin());

GRANT ALL ON public.favorites TO authenticated;

-- ============================================================
-- 3. REVIEW RESPONSES (restaurant replies)
-- ============================================================
ALTER TABLE public.reviews ADD COLUMN IF NOT EXISTS response_text TEXT;
ALTER TABLE public.reviews ADD COLUMN IF NOT EXISTS responded_at TIMESTAMPTZ;
ALTER TABLE public.reviews ADD COLUMN IF NOT EXISTS response_by UUID REFERENCES public.users(id);

-- ============================================================
-- 4. LOYALTY TIERS
-- ============================================================
ALTER TABLE public.loyalty_accounts ADD COLUMN IF NOT EXISTS tier TEXT NOT NULL DEFAULT 'bronze'
  CHECK (tier IN ('bronze', 'silver', 'gold', 'platinum'));
ALTER TABLE public.loyalty_accounts ADD COLUMN IF NOT EXISTS tier_updated_at TIMESTAMPTZ DEFAULT now();

-- Function to auto-update tier based on total_earned
CREATE OR REPLACE FUNCTION public.update_loyalty_tier()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Tier thresholds based on total points earned
  IF NEW.total_earned >= 5000 THEN
    NEW.tier := 'platinum';
  ELSIF NEW.total_earned >= 2000 THEN
    NEW.tier := 'gold';
  ELSIF NEW.total_earned >= 500 THEN
    NEW.tier := 'silver';
  ELSE
    NEW.tier := 'bronze';
  END IF;
  
  IF NEW.tier != OLD.tier THEN
    NEW.tier_updated_at := now();
  END IF;
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_loyalty_tier ON public.loyalty_accounts;
CREATE TRIGGER trigger_update_loyalty_tier
  BEFORE UPDATE OF total_earned ON public.loyalty_accounts
  FOR EACH ROW
  EXECUTE FUNCTION update_loyalty_tier();

-- ============================================================
-- 5. CONTACTLESS DELIVERY + DELIVERY PROOF
-- ============================================================
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS contactless_delivery BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS delivery_photo_url TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS delivery_otp TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS delivery_otp_verified BOOLEAN DEFAULT FALSE;

-- ============================================================
-- 6. DRIVER LEADERBOARD VIEW
-- ============================================================
CREATE OR REPLACE VIEW public.driver_leaderboard AS
SELECT
  d.id AS driver_id,
  d.user_id,
  u.name AS driver_name,
  u.profile_image_url AS avatar_url,
  d.completed_deliveries,
  d.rating,
  d.vehicle_type,
  RANK() OVER (ORDER BY d.completed_deliveries DESC) AS deliveries_rank,
  RANK() OVER (ORDER BY d.rating DESC NULLS LAST) AS rating_rank
FROM public.drivers d
JOIN public.users u ON u.id = d.user_id
WHERE d.is_verified = true
ORDER BY d.completed_deliveries DESC;

GRANT SELECT ON public.driver_leaderboard TO authenticated;

-- ============================================================
-- 7. Generate referral codes for existing users who don't have one
-- ============================================================
UPDATE public.users
SET referral_code = UPPER(SUBSTRING(id::text FROM 1 FOR 6) || SUBSTRING(md5(email) FROM 1 FOR 2))
WHERE referral_code IS NULL;
