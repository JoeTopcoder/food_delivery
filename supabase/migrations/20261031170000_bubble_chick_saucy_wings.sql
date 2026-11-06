-- Bubble Chick: Saucy Wings (5PC; 10PC pending its price).
BEGIN;
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('acc394fc-f586-4fe5-8e93-2c3ad356e58f','4ec0727e-94b0-4c6e-a90f-437a7fb8974c','5PC Saucy Wings','5PC saucy wings with regular fries and a soda.',1595,'Saucy Wings','food',true,false,false,false);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('85237103-336e-4186-b3bf-197477a33d52','acc394fc-f586-4fe5-8e93-2c3ad356e58f','Select Flavour',false,1,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('af737273-ffba-4c10-8239-10da2f651f74','85237103-336e-4186-b3bf-197477a33d52','Orange',0,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('29114a80-a765-47cf-acee-2cc7af123123','85237103-336e-4186-b3bf-197477a33d52','Sweet & Spicy',0,false,true,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('fa6d9677-db8a-4829-b696-72fca48ed716','85237103-336e-4186-b3bf-197477a33d52','Korean BBQ',0,false,true,2);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('0e244887-01d8-4ece-841a-264166473016','acc394fc-f586-4fe5-8e93-2c3ad356e58f','Choose Drink',false,1,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('24fc9a42-97d5-408b-963b-1f642320da6b','0e244887-01d8-4ece-841a-264166473016','Coke',0,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('217b1940-ffc5-4257-9dc0-f53fbd7b670e','0e244887-01d8-4ece-841a-264166473016','Schweppes Ginger Ale',0,false,true,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('b8931df1-5f0d-4633-9952-af81f50aa544','0e244887-01d8-4ece-841a-264166473016','Grape',0,false,true,2);
NOTIFY pgrst, 'reload schema';
COMMIT;
