-- Chicken & Tings: Breakfast — Stewed Chicken.
BEGIN;
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('9149be60-d995-4c03-8d7b-640df83bfeb2','a223daee-5b35-426a-9d05-ba3479a97c46','Stewed Chicken (Breakfast)','Served with white yam, green bananas, sweet potato, boiled dumplings and pumpkin, or white rice, or fried dumplings.',1100,'Breakfast','food',true,false,false,false);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('34a00871-1e05-4b12-88d5-e8cb663a765c','9149be60-d995-4c03-8d7b-640df83bfeb2','Choose Your Side',true,1,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('834f98a0-3a75-4da0-abed-8861ec613b26','34a00871-1e05-4b12-88d5-e8cb663a765c','Ground Provisions (Yam, Banana, Sweet Potato, Dumpling, Pumpkin)',0,true,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('423db873-7485-4a07-a144-35eb795adc87','34a00871-1e05-4b12-88d5-e8cb663a765c','White Rice',0,false,true,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('e43b17a7-965b-4d3c-8cdf-614360e27c15','34a00871-1e05-4b12-88d5-e8cb663a765c','Fried Dumplings',0,false,true,2);
NOTIFY pgrst, 'reload schema';
COMMIT;
