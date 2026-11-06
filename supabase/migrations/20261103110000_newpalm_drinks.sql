BEGIN;
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('b465fe67-8916-4585-a261-5a64e285b9ba','7012c4c7-9111-41b6-af3f-c441251ac363','D&G Soda','',250,'Drinks','food',true,false,false,false);
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('0b32f9e7-7988-4a43-b48f-d5ab87f44fd1','7012c4c7-9111-41b6-af3f-c441251ac363','Pepsi','',350,'Drinks','food',true,false,false,false);
NOTIFY pgrst, 'reload schema';
COMMIT;
