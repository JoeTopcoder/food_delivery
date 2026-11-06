-- New Palm: more Drinks + refresh the 'Add a Drink' group to the full drink list.
BEGIN;
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('eac8fdca-1957-4e38-be0b-cd9531b48c5b','7012c4c7-9111-41b6-af3f-c441251ac363','Ting','',350,'Drinks','food',true,false,false,false);
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('0758affa-0464-42d3-a54d-92424b49b154','7012c4c7-9111-41b6-af3f-c441251ac363','Ginger Beer','',350,'Drinks','food',true,false,false,false);
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('12c7e412-3d91-481b-8517-6ebc9792bf0a','7012c4c7-9111-41b6-af3f-c441251ac363','Water','',200,'Drinks','food',true,false,false,false);
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('6698cb79-9dde-4702-84d5-1262939395d9','7012c4c7-9111-41b6-af3f-c441251ac363','Tropicana','',450,'Drinks','food',true,false,false,false);
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('e32ab01d-8685-4940-b58d-f809db185a7c','7012c4c7-9111-41b6-af3f-c441251ac363','Flava Splash','',200,'Drinks','food',true,false,false,false);
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('a07eeb10-0dc1-4557-984c-8821d096db8c','7012c4c7-9111-41b6-af3f-c441251ac363','Cran Water','',250,'Drinks','food',true,false,false,false);
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('1b414639-e88f-4df6-ab8b-2839e2ea1b1c','7012c4c7-9111-41b6-af3f-c441251ac363','Orange Juice','',400,'Drinks','food',true,false,false,false);
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('0496e23a-e0f9-4469-a1ec-1d8b9b124d9a','7012c4c7-9111-41b6-af3f-c441251ac363','Arizona','',600,'Drinks','food',true,false,false,false);
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('7a70c894-0102-4d0c-a9f3-bfa58ad1ca4d','7012c4c7-9111-41b6-af3f-c441251ac363','Coconut Water','',500,'Drinks','food',true,false,false,false);
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('c3ebcbfe-0027-46fb-9478-21ae0205665c','7012c4c7-9111-41b6-af3f-c441251ac363','Cranberry Juice','',650,'Drinks','food',true,false,false,false);
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('b8b0084f-0313-48db-8628-61898a587bc9','7012c4c7-9111-41b6-af3f-c441251ac363','Tropical Rhythm','',650,'Drinks','food',true,false,false,false);
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('5b9f6a23-b5d3-4b5e-ace6-c4e5a8f0bb15','7012c4c7-9111-41b6-af3f-c441251ac363','June Plum (Natural)','',500,'Drinks','food',true,false,false,false);

-- Rebuild 'Add a Drink' choices from the current Drinks list.
DELETE FROM menu_option_choices c USING menu_option_groups g, menus m
 WHERE c.group_id=g.id AND g.menu_item_id=m.id AND g.name='Add a Drink'
   AND m.restaurant_id='7012c4c7-9111-41b6-af3f-c441251ac363' AND m.category IN ('Lunch Menu','SeaFood');
INSERT INTO menu_option_choices (group_id, name, price, is_default, is_available, sort_order)
SELECT g.id, d.name, d.price, false, true,
       (row_number() OVER (PARTITION BY g.id ORDER BY d.price, d.name))-1
FROM menu_option_groups g
JOIN menus m ON m.id=g.menu_item_id
JOIN menus d ON d.restaurant_id='7012c4c7-9111-41b6-af3f-c441251ac363' AND d.category='Drinks'
WHERE m.restaurant_id='7012c4c7-9111-41b6-af3f-c441251ac363' AND m.category IN ('Lunch Menu','SeaFood') AND g.name='Add a Drink';
-- Allow picking any number of the available drinks.
UPDATE menu_option_groups g SET max_selections = (SELECT count(*) FROM menus WHERE restaurant_id='7012c4c7-9111-41b6-af3f-c441251ac363' AND category='Drinks')
FROM menus m WHERE g.menu_item_id=m.id AND g.name='Add a Drink'
 AND m.restaurant_id='7012c4c7-9111-41b6-af3f-c441251ac363' AND m.category IN ('Lunch Menu','SeaFood');
NOTIFY pgrst, 'reload schema';
COMMIT;
