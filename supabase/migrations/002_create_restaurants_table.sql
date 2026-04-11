-- Create restaurants table
CREATE TABLE IF NOT EXISTS restaurants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  image_url TEXT,
  phone TEXT,
  email TEXT,
  address TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  cuisine_type TEXT,
  rating DOUBLE PRECISION DEFAULT 0,
  review_count INTEGER DEFAULT 0,
  delivery_fee DOUBLE PRECISION,
  estimated_delivery_time INTEGER,
  is_open BOOLEAN DEFAULT TRUE,
  opening_time TEXT,
  closing_time TEXT,
  tags TEXT[] DEFAULT ARRAY[]::TEXT[],
  is_verified BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE
);

-- Create indexes
CREATE INDEX idx_restaurants_owner_id ON restaurants(owner_id);
CREATE INDEX idx_restaurants_is_verified ON restaurants(is_verified);
CREATE INDEX idx_restaurants_cuisine_type ON restaurants(cuisine_type);
CREATE INDEX idx_restaurants_is_open ON restaurants(is_open);
CREATE INDEX idx_restaurants_created_at ON restaurants(created_at);
