-- Admin-controlled visibility for the customer bottom-nav tabs. When a flag is
-- false the tab is hidden from customers entirely (not just "coming soon").
-- Seeded true; the admin toggle does an UPDATE, so the rows must exist.
INSERT INTO public.app_config (key, value, value_type, category, description) VALUES
  ('screen_home_enabled',         'true', 'boolean', 'screens', 'Show the Home tab to customers'),
  ('screen_grocery_enabled',      'true', 'boolean', 'screens', 'Show the Grocery tab to customers'),
  ('screen_orders_enabled',       'true', 'boolean', 'screens', 'Show the Orders tab to customers'),
  ('screen_car_services_enabled', 'true', 'boolean', 'screens', 'Show the Services tab to customers'),
  ('screen_profile_enabled',      'true', 'boolean', 'screens', 'Show the Profile tab to customers')
ON CONFLICT (key) DO NOTHING;
NOTIFY pgrst, 'reload schema';
