-- Favourites tables for laundry and car service providers

CREATE TABLE IF NOT EXISTS user_favorite_laundry_providers (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider_id UUID NOT NULL REFERENCES laundry_providers(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, provider_id)
);

ALTER TABLE user_favorite_laundry_providers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "laundry_fav_owner" ON user_favorite_laundry_providers;
CREATE POLICY "laundry_fav_owner" ON user_favorite_laundry_providers
  FOR ALL USING (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS user_favorite_car_providers (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider_id UUID NOT NULL REFERENCES car_service_providers(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, provider_id)
);

ALTER TABLE user_favorite_car_providers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "car_fav_owner" ON user_favorite_car_providers;
CREATE POLICY "car_fav_owner" ON user_favorite_car_providers
  FOR ALL USING (user_id = auth.uid());
