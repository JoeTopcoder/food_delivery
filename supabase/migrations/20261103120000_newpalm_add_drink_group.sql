-- Let customers add a drink while ordering a main: optional "Add a Drink" group
-- on every New Palm Lunch Menu + SeaFood item.
BEGIN;
-- One "Add a Drink" group per qualifying item, placed after its existing groups.
INSERT INTO menu_option_groups (menu_item_id, name, is_required, max_selections, sort_order)
SELECT m.id, 'Add a Drink', false, 2,
       COALESCE((SELECT max(sort_order)+1 FROM menu_option_groups g2 WHERE g2.menu_item_id=m.id), 0)
FROM menus m
WHERE m.restaurant_id='7012c4c7-9111-41b6-af3f-c441251ac363'
  AND m.category IN ('Lunch Menu','SeaFood')
  AND NOT EXISTS (SELECT 1 FROM menu_option_groups g3 WHERE g3.menu_item_id=m.id AND g3.name='Add a Drink');

-- Two drink choices in each of those groups.
INSERT INTO menu_option_choices (group_id, name, price, is_default, is_available, sort_order)
SELECT g.id, d.name, d.price, false, true, d.ord
FROM menu_option_groups g
JOIN menus m ON m.id=g.menu_item_id
CROSS JOIN (VALUES ('D&G Soda',250,0),('Pepsi',350,1)) AS d(name,price,ord)
WHERE m.restaurant_id='7012c4c7-9111-41b6-af3f-c441251ac363'
  AND m.category IN ('Lunch Menu','SeaFood')
  AND g.name='Add a Drink'
  AND NOT EXISTS (SELECT 1 FROM menu_option_choices c2 WHERE c2.group_id=g.id);

NOTIFY pgrst, 'reload schema';
COMMIT;
