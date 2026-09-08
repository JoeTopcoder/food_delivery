-- Migration: a lunch provider so the ordering flow has something to sell
--
-- Lunch is store_type 'lunch', which keeps it out of the food and grocery
-- listings while reusing menus, pricing and cart wholesale. Prices are in JMD,
-- matching the examples in the brief.

-- store_type is constrained to food/grocery/both; lunch is a new vertical and
-- has to be admitted before a provider can exist.
ALTER TABLE public.restaurants DROP CONSTRAINT IF EXISTS restaurants_store_type_check;
ALTER TABLE public.restaurants ADD CONSTRAINT restaurants_store_type_check
  CHECK (store_type = ANY (ARRAY['food','grocery','both','lunch']));

INSERT INTO public.restaurants
  (id, owner_id, name, description, cuisine_type, store_type, address,
   latitude, longitude, is_open, is_verified, status, delivery_fee,
   service_fee, minimum_order_amount, rating, estimated_delivery_time,
   commission_rate)
SELECT '1c400001-0000-0000-0000-000000000001',
   -- Owned by an existing admin so the row satisfies owner_id without
   -- inventing an account.
   (SELECT id FROM public.users WHERE role = 'admin' ORDER BY created_at LIMIT 1),
   'Campus Kitchen', 'Hot school lunches prepared fresh each morning.',
   'Caribbean', 'lunch', '15 Hope Road, Kingston',
   18.0179, -76.8099, TRUE, TRUE, 'approved', 350, 0, 0, 4.6, 30, 0.15
ON CONFLICT (id) DO UPDATE
  SET store_type = 'lunch', is_verified = TRUE, is_open = TRUE;

-- Same for the item-level type.
ALTER TABLE public.menus DROP CONSTRAINT IF EXISTS menus_product_type_check;
ALTER TABLE public.menus ADD CONSTRAINT menus_product_type_check
  CHECK (product_type = ANY (ARRAY['food','grocery','lunch']));

INSERT INTO public.menus
  (restaurant_id, name, description, price, category, is_available, in_stock,
   preparation_time, product_type)
SELECT '1c400001-0000-0000-0000-000000000001', v.name, v.descr, v.price,
       v.category, TRUE, TRUE, 20, 'lunch'
FROM (VALUES
  ('Chicken & Rice',   'Seasoned chicken with rice and peas.',        850.0, 'Mains'),
  ('Beef Burger',      'Beef patty, lettuce, tomato, cheese.',        750.0, 'Mains'),
  ('Jerk Chicken',     'Jerk chicken with festival.',                 900.0, 'Mains'),
  ('Curry Chicken',    'Curry chicken with white rice.',              850.0, 'Mains'),
  ('Vegetable Pasta',  'Pasta in a light tomato sauce.',              700.0, 'Mains'),
  ('Fish & Bammy',     'Steamed fish with bammy.',                    950.0, 'Mains'),
  ('Beef Patty',       'Jamaican beef patty.',                        250.0, 'Snacks'),
  ('Cheese Patty',     'Cheese patty, baked fresh.',                  280.0, 'Snacks'),
  ('Plantain Chips',   'Crisp fried plantain chips.',                 200.0, 'Snacks'),
  ('Fruit Cup',        'Seasonal fresh fruit.',                       300.0, 'Snacks'),
  ('Juice',            'Chilled fruit juice.',                        200.0, 'Drinks'),
  ('Bottled Water',    'Still water, 500ml.',                         150.0, 'Drinks'),
  ('Chocolate Milk',   'Chilled chocolate milk.',                     250.0, 'Drinks')
) AS v(name, descr, price, category)
WHERE NOT EXISTS (
  SELECT 1 FROM public.menus m
  WHERE m.restaurant_id = '1c400001-0000-0000-0000-000000000001'
    AND m.name = v.name
);

NOTIFY pgrst, 'reload schema';
