-- Create drivers table
CREATE TABLE IF NOT EXISTS drivers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  vehicle_type TEXT CHECK (vehicle_type IN ('bike', 'car', 'scooter')),
  vehicle_number TEXT,
  license_number TEXT,
  rating DOUBLE PRECISION DEFAULT 0,
  completed_deliveries INTEGER DEFAULT 0,
  is_available BOOLEAN DEFAULT TRUE,
  current_latitude DOUBLE PRECISION,
  current_longitude DOUBLE PRECISION,
  is_verified BOOLEAN DEFAULT FALSE,
  documents_status JSONB DEFAULT '{"license": "pending", "registration": "pending", "insurance": "pending"}',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE
);

-- Create indexes
CREATE INDEX idx_drivers_user_id ON drivers(user_id);
CREATE INDEX idx_drivers_is_verified ON drivers(is_verified);
CREATE INDEX idx_drivers_is_available ON drivers(is_available);
CREATE INDEX idx_drivers_created_at ON drivers(created_at);
