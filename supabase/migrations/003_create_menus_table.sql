-- Create menus table (menu_items)
CREATE TABLE IF NOT EXISTS menus (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  price DOUBLE PRECISION NOT NULL,
  image_url TEXT,
  category TEXT NOT NULL,
  is_available BOOLEAN DEFAULT TRUE,
  discount DOUBLE PRECISION,
  tags TEXT[] DEFAULT ARRAY[]::TEXT[],
  preparation_time INTEGER,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE
);

-- Create indexes
CREATE INDEX idx_menus_restaurant_id ON menus(restaurant_id);
CREATE INDEX idx_menus_category ON menus(category);
CREATE INDEX idx_menus_is_available ON menus(is_available);
CREATE INDEX idx_menus_created_at ON menus(created_at);
