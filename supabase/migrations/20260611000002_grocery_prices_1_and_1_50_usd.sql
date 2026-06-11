-- Set all grocery item prices to $1.00 or $1.50 (alternating alphabetically).
WITH ranked AS (
  SELECT id, ROW_NUMBER() OVER (ORDER BY name) AS rn
  FROM public.menus
  WHERE product_type = 'grocery'
)
UPDATE public.menus m
SET
  price    = CASE WHEN r.rn % 2 = 1 THEN 1.00 ELSE 1.50 END,
  discount = 0
FROM ranked r
WHERE m.id = r.id;
