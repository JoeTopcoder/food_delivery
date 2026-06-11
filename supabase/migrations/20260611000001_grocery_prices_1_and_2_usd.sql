-- Set all grocery menu item prices to alternate between $1 and $2.
-- Odd-ranked rows → $1.00, even-ranked rows → $2.00 (ordered by name for consistency).

WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (ORDER BY name) AS rn
  FROM public.menus
  WHERE product_type = 'grocery'
)
UPDATE public.menus m
SET
  price    = CASE WHEN r.rn % 2 = 1 THEN 1.00 ELSE 2.00 END,
  discount = 0
FROM ranked r
WHERE m.id = r.id;
