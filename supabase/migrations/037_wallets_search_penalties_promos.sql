-- ============================================================
-- Migration 037: Wallets, Full-Text Search, Cancellation Penalties,
--               User Preferences, Promotions Scheduling
-- ============================================================

-- ── 1. DIGITAL WALLET ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.wallets (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  balance DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
  cashback_balance DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (cashback_balance >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_read_own_wallet" ON public.wallets
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE POLICY "admin_read_all_wallets" ON public.wallets
  FOR SELECT TO authenticated USING (is_admin());

CREATE POLICY "admin_update_wallets" ON public.wallets
  FOR UPDATE TO authenticated USING (is_admin()) WITH CHECK (is_admin());

GRANT SELECT, INSERT, UPDATE ON public.wallets TO authenticated;

-- Wallet transactions ledger
CREATE TABLE IF NOT EXISTS public.wallet_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  amount DECIMAL(12,2) NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('deposit','payment','cashback','refund','penalty','tip_received')),
  payment_method TEXT CHECK (payment_method IN ('card','cash','wallet','cashback','system')),
  status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('pending','completed','failed','reversed')),
  order_id UUID REFERENCES public.orders(id),
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_read_own_transactions" ON public.wallet_transactions
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE POLICY "admin_read_all_transactions" ON public.wallet_transactions
  FOR SELECT TO authenticated USING (is_admin());

GRANT SELECT, INSERT ON public.wallet_transactions TO authenticated;

-- RPC: Add funds to wallet (called after successful card payment)
CREATE OR REPLACE FUNCTION public.wallet_deposit(p_user_id UUID, p_amount DECIMAL, p_method TEXT DEFAULT 'card')
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_wallet wallets;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive';
  END IF;

  INSERT INTO wallets (user_id, balance) VALUES (p_user_id, p_amount)
  ON CONFLICT (user_id) DO UPDATE SET
    balance = wallets.balance + p_amount,
    updated_at = now();

  SELECT * INTO v_wallet FROM wallets WHERE user_id = p_user_id;

  INSERT INTO wallet_transactions (user_id, amount, type, payment_method, status, description)
  VALUES (p_user_id, p_amount, 'deposit', p_method, 'completed', 'Wallet top-up');

  RETURN jsonb_build_object('balance', v_wallet.balance, 'cashback_balance', v_wallet.cashback_balance);
END;
$$;

-- RPC: Pay with wallet
CREATE OR REPLACE FUNCTION public.wallet_pay(p_user_id UUID, p_amount DECIMAL, p_order_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_balance DECIMAL;
  v_cashback DECIMAL;
  v_remaining DECIMAL;
  v_from_cashback DECIMAL := 0;
  v_from_balance DECIMAL := 0;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive';
  END IF;

  SELECT balance, cashback_balance INTO v_balance, v_cashback
  FROM wallets WHERE user_id = p_user_id FOR UPDATE;

  IF v_balance IS NULL THEN
    RAISE EXCEPTION 'No wallet found';
  END IF;

  -- Use cashback first, then main balance
  IF v_cashback >= p_amount THEN
    v_from_cashback := p_amount;
  ELSE
    v_from_cashback := v_cashback;
    v_from_balance := p_amount - v_cashback;
  END IF;

  IF (v_from_balance > v_balance) THEN
    RAISE EXCEPTION 'Insufficient wallet balance. Available: %', (v_balance + v_cashback);
  END IF;

  UPDATE wallets SET
    balance = balance - v_from_balance,
    cashback_balance = cashback_balance - v_from_cashback,
    updated_at = now()
  WHERE user_id = p_user_id;

  INSERT INTO wallet_transactions (user_id, amount, type, payment_method, status, order_id, description)
  VALUES (p_user_id, -p_amount, 'payment', 'wallet', 'completed', p_order_id,
    'Payment for order #' || UPPER(LEFT(p_order_id::text, 8)));

  SELECT balance, cashback_balance INTO v_balance, v_cashback
  FROM wallets WHERE user_id = p_user_id;

  RETURN jsonb_build_object('balance', v_balance, 'cashback_balance', v_cashback);
END;
$$;

-- RPC: Award cashback (called after order delivered — 3% of subtotal)
CREATE OR REPLACE FUNCTION public.wallet_award_cashback(p_user_id UUID, p_order_id UUID, p_subtotal DECIMAL)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cashback DECIMAL;
BEGIN
  v_cashback := ROUND(p_subtotal * 0.03, 2); -- 3% cashback
  IF v_cashback <= 0 THEN RETURN; END IF;

  INSERT INTO wallets (user_id, cashback_balance) VALUES (p_user_id, v_cashback)
  ON CONFLICT (user_id) DO UPDATE SET
    cashback_balance = wallets.cashback_balance + v_cashback,
    updated_at = now();

  INSERT INTO wallet_transactions (user_id, amount, type, payment_method, status, order_id, description)
  VALUES (p_user_id, v_cashback, 'cashback', 'system', 'completed', p_order_id,
    '3% cashback on order #' || UPPER(LEFT(p_order_id::text, 8)));
END;
$$;

-- Grant execute
GRANT EXECUTE ON FUNCTION public.wallet_deposit(UUID, DECIMAL, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_pay(UUID, DECIMAL, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_award_cashback(UUID, UUID, DECIMAL) TO authenticated;

-- ── 2. FULL-TEXT SEARCH ─────────────────────────────────────

-- Add search vectors to menu items
ALTER TABLE public.menus ADD COLUMN IF NOT EXISTS search_vector tsvector;

-- Populate existing rows
UPDATE public.menus SET search_vector = to_tsvector('english',
  COALESCE(name, '') || ' ' || COALESCE(description, '') || ' ' || COALESCE(category, ''));

-- Auto-update trigger
CREATE OR REPLACE FUNCTION public.menus_search_vector_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.search_vector := to_tsvector('english',
    COALESCE(NEW.name, '') || ' ' || COALESCE(NEW.description, '') || ' ' || COALESCE(NEW.category, ''));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_menus_search_vector ON public.menus;
CREATE TRIGGER trg_menus_search_vector
  BEFORE INSERT OR UPDATE OF name, description, category ON public.menus
  FOR EACH ROW EXECUTE FUNCTION public.menus_search_vector_update();

CREATE INDEX IF NOT EXISTS idx_menus_search_vector ON public.menus USING GIN(search_vector);

-- Full-text search RPC with filters
CREATE OR REPLACE FUNCTION public.search_menu_items(
  p_query TEXT DEFAULT NULL,
  p_cuisine TEXT DEFAULT NULL,
  p_max_price DECIMAL DEFAULT NULL,
  p_min_rating DECIMAL DEFAULT NULL,
  p_limit INT DEFAULT 50
)
RETURNS TABLE(
  item_id UUID,
  item_name TEXT,
  item_description TEXT,
  item_price DECIMAL,
  item_image_url TEXT,
  item_category TEXT,
  item_discount DECIMAL,
  restaurant_id UUID,
  restaurant_name TEXT,
  restaurant_image TEXT,
  restaurant_rating DECIMAL,
  restaurant_cuisine TEXT,
  rank REAL
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  SELECT
    m.id AS item_id,
    m.name AS item_name,
    m.description AS item_description,
    m.price AS item_price,
    m.image_url AS item_image_url,
    m.category AS item_category,
    m.discount AS item_discount,
    r.id AS restaurant_id,
    r.name AS restaurant_name,
    r.image_url AS restaurant_image,
    r.rating AS restaurant_rating,
    r.cuisine_type AS restaurant_cuisine,
    CASE
      WHEN p_query IS NOT NULL AND p_query != '' THEN
        ts_rank(m.search_vector, plainto_tsquery('english', p_query))
      ELSE 1.0
    END::REAL AS rank
  FROM menus m
  JOIN restaurants r ON r.id = m.restaurant_id
  WHERE m.is_available = true
    AND (p_query IS NULL OR p_query = '' OR m.search_vector @@ plainto_tsquery('english', p_query)
         OR m.name ILIKE '%' || p_query || '%')
    AND (p_cuisine IS NULL OR r.cuisine_type ILIKE '%' || p_cuisine || '%')
    AND (p_max_price IS NULL OR m.price <= p_max_price)
    AND (p_min_rating IS NULL OR r.rating >= p_min_rating)
  ORDER BY rank DESC, m.name
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_menu_items(TEXT, TEXT, DECIMAL, DECIMAL, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_menu_items(TEXT, TEXT, DECIMAL, DECIMAL, INT) TO anon;

-- ── 3. USER PREFERENCES (for recommendations) ───────────────
CREATE TABLE IF NOT EXISTS public.user_preferences (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  preferred_cuisines TEXT[] DEFAULT '{}',
  dietary_restrictions TEXT[] DEFAULT '{}',
  liked_item_ids UUID[] DEFAULT '{}',
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_manage_own_preferences" ON public.user_preferences
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

GRANT ALL ON public.user_preferences TO authenticated;

-- RPC: Get personalized recommendations based on past orders
CREATE OR REPLACE FUNCTION public.get_recommendations(p_user_id UUID, p_limit INT DEFAULT 20)
RETURNS TABLE(
  item_id UUID,
  item_name TEXT,
  item_price DECIMAL,
  item_image_url TEXT,
  restaurant_id UUID,
  restaurant_name TEXT,
  restaurant_image TEXT,
  score REAL
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  -- Items from cuisines the user has ordered before, that they haven't ordered yet
  WITH user_cuisines AS (
    SELECT DISTINCT r.cuisine_type
    FROM orders o
    JOIN restaurants r ON r.id = o.restaurant_id
    WHERE o.user_id = p_user_id AND o.status = 'delivered'
  ),
  user_ordered_items AS (
    SELECT DISTINCT oi.menu_item_id
    FROM order_items oi
    JOIN orders o ON o.id = oi.order_id
    WHERE o.user_id = p_user_id
  )
  SELECT
    m.id AS item_id,
    m.name AS item_name,
    m.price AS item_price,
    m.image_url AS item_image_url,
    r.id AS restaurant_id,
    r.name AS restaurant_name,
    r.image_url AS restaurant_image,
    (COALESCE(r.rating, 3.0) * 0.6 + RANDOM()::NUMERIC * 2)::REAL AS score
  FROM menus m
  JOIN restaurants r ON r.id = m.restaurant_id
  WHERE m.is_available = true
    AND r.is_open = true
    AND (
      r.cuisine_type IN (SELECT cuisine_type FROM user_cuisines)
      OR r.rating >= 4.0
    )
    AND m.id NOT IN (SELECT menu_item_id FROM user_ordered_items WHERE menu_item_id IS NOT NULL)
  ORDER BY score DESC
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_recommendations(UUID, INT) TO authenticated;

-- ── 4. CANCELLATION PENALTY ─────────────────────────────────

CREATE OR REPLACE FUNCTION public.cancel_order_with_penalty(p_order_id UUID, p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order orders;
  v_minutes_passed DOUBLE PRECISION;
  v_penalty DECIMAL := 0;
  v_result TEXT;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = p_order_id AND user_id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_order.status NOT IN ('pending', 'confirmed', 'preparing') THEN
    RAISE EXCEPTION 'Cannot cancel order in status: %', v_order.status;
  END IF;

  v_minutes_passed := EXTRACT(EPOCH FROM (now() - v_order.ordered_at)) / 60.0;

  IF v_minutes_passed < 2 THEN
    -- Free cancellation within 2 minutes
    v_result := 'cancelled_free';
    v_penalty := 0;
  ELSIF v_order.status = 'preparing' THEN
    -- If already preparing, charge 15% of total
    v_penalty := ROUND(v_order.total * 0.15, 2);
    v_result := 'cancelled_with_fee';
  ELSE
    -- After 2 min but before preparing, flat $200 fee
    v_penalty := 200;
    v_result := 'cancelled_with_fee';
  END IF;

  -- Update order status
  UPDATE orders SET status = 'cancelled', updated_at = now() WHERE id = p_order_id;

  -- Deduct penalty from wallet if applicable
  IF v_penalty > 0 THEN
    -- Ensure wallet exists
    INSERT INTO wallets (user_id) VALUES (p_user_id)
    ON CONFLICT (user_id) DO NOTHING;

    -- Record penalty transaction (we don't block the cancel if wallet is empty)
    INSERT INTO wallet_transactions (user_id, amount, type, payment_method, status, order_id, description)
    VALUES (p_user_id, -v_penalty, 'penalty', 'system', 'completed', p_order_id,
      'Cancellation fee for order #' || UPPER(LEFT(p_order_id::text, 8)));

    -- Deduct from wallet (allow negative — will need to pay before next order)
    UPDATE wallets SET
      balance = GREATEST(balance - v_penalty, 0),
      updated_at = now()
    WHERE user_id = p_user_id;

    -- If driver was assigned, credit them
    IF v_order.driver_id IS NOT NULL THEN
      INSERT INTO wallets (user_id, balance) VALUES (v_order.driver_id, v_penalty)
      ON CONFLICT (user_id) DO UPDATE SET
        balance = wallets.balance + v_penalty,
        updated_at = now();

      INSERT INTO wallet_transactions (user_id, amount, type, payment_method, status, order_id, description)
      VALUES (v_order.driver_id, v_penalty, 'tip_received', 'system', 'completed', p_order_id,
        'Cancellation compensation');
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'result', v_result,
    'penalty', v_penalty,
    'minutes_passed', ROUND(v_minutes_passed::numeric, 1)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_order_with_penalty(UUID, UUID) TO authenticated;

-- ── 5. AUTO CASHBACK TRIGGER (on order delivered) ───────────

CREATE OR REPLACE FUNCTION public.auto_cashback_on_delivery()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_subtotal DECIMAL;
BEGIN
  IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
    -- Calculate subtotal from order items
    SELECT COALESCE(SUM(price * quantity), 0) INTO v_subtotal
    FROM order_items WHERE order_id = NEW.id;

    IF v_subtotal > 0 THEN
      PERFORM wallet_award_cashback(NEW.user_id, NEW.id, v_subtotal);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_cashback ON public.orders;
CREATE TRIGGER trg_auto_cashback
  AFTER UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_cashback_on_delivery();

-- ── 6. SCHEDULED PROMOTIONS TABLE ───────────────────────────
CREATE TABLE IF NOT EXISTS public.scheduled_promotions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  promo_code TEXT,
  target_audience TEXT NOT NULL DEFAULT 'all' CHECK (target_audience IN ('all','active_users','inactive_users','high_spenders','cuisine_fans')),
  target_cuisine TEXT,
  scheduled_at TIMESTAMPTZ NOT NULL,
  sent_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','sent','failed','cancelled')),
  created_by UUID REFERENCES public.users(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.scheduled_promotions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin_manage_promotions" ON public.scheduled_promotions
  FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

GRANT ALL ON public.scheduled_promotions TO authenticated;
