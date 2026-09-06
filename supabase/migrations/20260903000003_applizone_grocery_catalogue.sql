-- Migration: stock Applizone Central with a real grocery catalogue
--
-- The store held 12 items across 5 categories, far too thin for the Grocery
-- Concierge to be useful — "milk, bread and eggs" could not be filled because
-- none of the three existed. This adds 53 items across the sections a shopper
-- actually expects, including the Caribbean staples this market sells
-- (ackee, salt fish, callaloo, plantain, hardough bread, jerk seasoning).
--
-- Grocery-specific columns are populated because the grocery UI shows them and
-- a bare "Milk" tells a shopper nothing. preparation_time is 0: nothing here is
-- cooked to order.
--
-- Idempotent: skips any name already present for this store, so re-running
-- cannot duplicate rows.

INSERT INTO public.menus
  (restaurant_id, name, description, price, category, brand, unit, weight,
   is_available, in_stock, preparation_time, product_type)
SELECT r.id, v.name, v.descr, v.price, v.category, v.brand, v.unit, v.weight,
       true, true, 0, 'grocery'
FROM public.restaurants r
CROSS JOIN (VALUES
  ('Whole Milk', 'Fresh pasteurised whole milk.', 4.99, 'Dairy & Eggs', 'Dairyland', 'carton', '1 gal'),
  ('Skim Milk', 'Fat-free pasteurised milk.', 4.79, 'Dairy & Eggs', 'Dairyland', 'carton', '1 gal'),
  ('Large Eggs', 'Grade A large eggs, one dozen.', 5.49, 'Dairy & Eggs', 'Farm Fresh', 'dozen', '12 ct'),
  ('Salted Butter', 'Creamery salted butter block.', 4.29, 'Dairy & Eggs', 'Anchor', 'block', '250 g'),
  ('Cheddar Cheese Block', 'Aged cheddar, medium sharp.', 6.99, 'Dairy & Eggs', 'Kraft', 'block', '400 g'),
  ('Greek Yogurt', 'Thick plain Greek yogurt, no added sugar.', 5.19, 'Dairy & Eggs', 'Chobani', 'tub', '450 g'),
  ('White Sandwich Bread', 'Soft sliced white loaf.', 3.49, 'Bakery', 'Wonder', 'loaf', '600 g'),
  ('Whole Wheat Bread', 'Sliced whole wheat loaf, high fibre.', 3.99, 'Bakery', 'Wonder', 'loaf', '600 g'),
  ('Hardough Bread', 'Jamaican-style hardough bread.', 4.49, 'Bakery', 'National', 'loaf', '800 g'),
  ('Burger Buns', 'Sesame-topped burger buns, pack of eight.', 3.29, 'Bakery', 'Bakery Fresh', 'pack', '8 ct'),
  ('Coconut Buns', 'Sweet Caribbean coconut buns.', 4.99, 'Bakery', 'Island Bake', 'pack', '6 ct'),
  ('Bananas', 'Ripe yellow bananas, sold by the bunch.', 2.49, 'Produce', 'Local', 'bunch', '1 kg'),
  ('Plantains', 'Green cooking plantains.', 3.29, 'Produce', 'Local', 'each', '3 ct'),
  ('Tomatoes', 'Vine-ripened tomatoes.', 3.99, 'Produce', 'Local', 'pack', '500 g'),
  ('Yellow Onions', 'Yellow cooking onions.', 2.99, 'Produce', 'Local', 'bag', '1 kg'),
  ('Sweet Potatoes', 'Caribbean sweet potatoes.', 3.79, 'Produce', 'Local', 'bag', '1 kg'),
  ('Scotch Bonnet Peppers', 'Hot scotch bonnet peppers.', 2.99, 'Produce', 'Local', 'pack', '100 g'),
  ('Avocados', 'Ready-to-eat avocados.', 4.49, 'Produce', 'Local', 'each', '2 ct'),
  ('Callaloo Bunch', 'Fresh callaloo greens.', 3.49, 'Produce', 'Local', 'bunch', '400 g'),
  ('Chicken Breast', 'Boneless skinless chicken breast.', 9.99, 'Meat & Seafood', 'Tyson', 'pack', '1 kg'),
  ('Whole Chicken', 'Fresh whole roasting chicken.', 8.49, 'Meat & Seafood', 'Tyson', 'each', '1.5 kg'),
  ('Ground Beef', 'Lean ground beef, 85/15.', 10.99, 'Meat & Seafood', 'Butcher', 'pack', '1 kg'),
  ('Stew Beef', 'Diced beef for stewing.', 11.49, 'Meat & Seafood', 'Butcher', 'pack', '1 kg'),
  ('Snapper Fillet', 'Fresh local snapper fillet.', 14.99, 'Meat & Seafood', 'Local Catch', 'pack', '500 g'),
  ('Shrimp', 'Peeled and deveined frozen shrimp.', 13.49, 'Meat & Seafood', 'Sea Best', 'bag', '500 g'),
  ('Salt Fish', 'Salted cod, dried.', 12.99, 'Meat & Seafood', 'Grace', 'pack', '400 g'),
  ('Long Grain Rice', 'Long grain white rice.', 7.99, 'Pantry', 'Uncle Bens', 'bag', '2 kg'),
  ('Brown Rice', 'Wholegrain brown rice.', 8.49, 'Pantry', 'Uncle Bens', 'bag', '2 kg'),
  ('All Purpose Flour', 'Plain all purpose flour.', 4.99, 'Pantry', 'Gold Medal', 'bag', '2 kg'),
  ('Granulated Sugar', 'White granulated sugar.', 4.49, 'Pantry', 'Domino', 'bag', '2 kg'),
  ('Vegetable Oil', 'Neutral vegetable cooking oil.', 6.99, 'Pantry', 'Crisco', 'bottle', '1 L'),
  ('Coconut Oil', 'Cold-pressed virgin coconut oil.', 8.99, 'Pantry', 'Grace', 'jar', '500 ml'),
  ('Sea Salt', 'Fine sea salt.', 2.49, 'Pantry', 'Morton', 'box', '750 g'),
  ('Black Pepper', 'Ground black pepper.', 3.99, 'Pantry', 'McCormick', 'jar', '100 g'),
  ('Curry Powder', 'Caribbean-style curry powder.', 4.29, 'Pantry', 'Betapac', 'tin', '250 g'),
  ('Jerk Seasoning', 'Authentic jerk seasoning paste.', 5.49, 'Pantry', 'Walkerswood', 'jar', '280 g'),
  ('Peanut Butter', 'Creamy roasted peanut butter.', 5.99, 'Pantry', 'Skippy', 'jar', '500 g'),
  ('Strawberry Jam', 'Sweet strawberry preserve.', 4.19, 'Pantry', 'Smuckers', 'jar', '340 g'),
  ('Coconut Milk', 'Unsweetened coconut milk.', 2.79, 'Canned Goods', 'Grace', 'tin', '400 ml'),
  ('Ackee in Brine', 'Jamaican ackee in brine.', 7.99, 'Canned Goods', 'Grace', 'tin', '540 g'),
  ('Baked Beans', 'Beans in tomato sauce.', 2.29, 'Canned Goods', 'Heinz', 'tin', '415 g'),
  ('Red Kidney Beans', 'Cooked red kidney beans.', 2.19, 'Canned Goods', 'Grace', 'tin', '400 g'),
  ('Chopped Tomatoes', 'Peeled chopped tomatoes.', 2.09, 'Canned Goods', 'Hunts', 'tin', '400 g'),
  ('Tuna Chunks in Water', 'Skipjack tuna chunks in spring water.', 2.99, 'Canned Goods', 'Chicken of the Sea', 'tin', '142 g'),
  ('Frozen Mixed Vegetables', 'Peas, carrots, corn and beans.', 4.49, 'Frozen', 'Birds Eye', 'bag', '1 kg'),
  ('Frozen French Fries', 'Straight-cut frozen fries.', 5.29, 'Frozen', 'Ore-Ida', 'bag', '1 kg'),
  ('Vanilla Ice Cream', 'Classic vanilla ice cream.', 7.49, 'Frozen', 'Breyers', 'tub', '1.5 L'),
  ('Frozen Peas', 'Garden peas, flash frozen.', 3.99, 'Frozen', 'Birds Eye', 'bag', '750 g'),
  ('Paper Towels', 'Absorbent kitchen paper towels.', 6.99, 'Household', 'Bounty', 'pack', '6 rolls'),
  ('Toilet Paper', 'Soft two-ply toilet tissue.', 8.99, 'Household', 'Charmin', 'pack', '12 rolls'),
  ('Dish Soap', 'Concentrated washing-up liquid.', 3.99, 'Household', 'Dawn', 'bottle', '750 ml'),
  ('Laundry Detergent', 'Liquid laundry detergent.', 11.99, 'Household', 'Tide', 'bottle', '2 L'),
  ('Trash Bags', 'Heavy duty kitchen trash bags.', 7.49, 'Household', 'Glad', 'box', '30 ct')
) AS v(name, descr, price, category, brand, unit, weight)
WHERE r.name = 'Applizone Central'
  AND NOT EXISTS (
    SELECT 1 FROM public.menus m
    WHERE m.restaurant_id = r.id AND m.name = v.name
  );

NOTIFY pgrst, 'reload schema';
