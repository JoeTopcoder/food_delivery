-- Clean up redundant grocery category names left by the MasterMac import, which
-- concatenated the source site's parent + child menu labels (e.g. "Baby Diaper
-- Baby Products", "Salad Dressing Salad Dressing", "Syrup Beverages"). Ten plain
-- renames + five merges of "...Other" buckets into their existing parent.
-- Categories are the `category` column on grocery `menus` rows; the app derives
-- the category list from these values, so renames reflect automatically.
-- Reversible via the backup table created below.
BEGIN;

-- Backup affected rows so the merges (which are otherwise lossy) can be undone:
--   UPDATE menus m SET category = b.old_category
--   FROM grocery_category_rename_backup_20261106 b WHERE m.id = b.id;
CREATE TABLE IF NOT EXISTS grocery_category_rename_backup_20261106 AS
SELECT id, category AS old_category, now() AS backed_up_at
FROM menus
WHERE product_type = 'grocery' AND category IN (
  'Baby Diaper Baby Products','Baby Care Baby Products','Baby Wipes Baby Products',
  'Beverages Powder Mixes Beverages','Drink Mixes Beverages','Syrup Beverages',
  'Fruit Snacks Snacks','Dried Peas Beans Groceries','Paper Products Household',
  'Salad Dressing Salad Dressing','Sauce Other','Liquor Other',
  'Personal Care Other','Groceries Other','Medication Other Medication'
);

-- Plain renames
UPDATE menus SET category='Baby Diapers'       WHERE product_type='grocery' AND category='Baby Diaper Baby Products';
UPDATE menus SET category='Baby Care'          WHERE product_type='grocery' AND category='Baby Care Baby Products';
UPDATE menus SET category='Baby Wipes'         WHERE product_type='grocery' AND category='Baby Wipes Baby Products';
UPDATE menus SET category='Powder Mixes'       WHERE product_type='grocery' AND category='Beverages Powder Mixes Beverages';
UPDATE menus SET category='Drink Mixes'        WHERE product_type='grocery' AND category='Drink Mixes Beverages';
UPDATE menus SET category='Syrup'              WHERE product_type='grocery' AND category='Syrup Beverages';
UPDATE menus SET category='Fruit Snacks'       WHERE product_type='grocery' AND category='Fruit Snacks Snacks';
UPDATE menus SET category='Dried Peas & Beans' WHERE product_type='grocery' AND category='Dried Peas Beans Groceries';
UPDATE menus SET category='Paper Products'     WHERE product_type='grocery' AND category='Paper Products Household';
UPDATE menus SET category='Salad Dressing'     WHERE product_type='grocery' AND category='Salad Dressing Salad Dressing';

-- Merges into an existing category
UPDATE menus SET category='Sauce'         WHERE product_type='grocery' AND category='Sauce Other';
UPDATE menus SET category='Liquor'        WHERE product_type='grocery' AND category='Liquor Other';
UPDATE menus SET category='Personal Care' WHERE product_type='grocery' AND category='Personal Care Other';
UPDATE menus SET category='Groceries'     WHERE product_type='grocery' AND category='Groceries Other';
UPDATE menus SET category='Medication'    WHERE product_type='grocery' AND category='Medication Other Medication';

COMMIT;

NOTIFY pgrst, 'reload schema';
