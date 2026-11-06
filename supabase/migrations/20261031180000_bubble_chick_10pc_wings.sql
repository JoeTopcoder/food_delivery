-- Bubble Chick: 10PC Saucy Wings ($3,025).
BEGIN;
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('ade08562-1408-41fb-a842-dbf703098f82','4ec0727e-94b0-4c6e-a90f-437a7fb8974c','10PC Saucy Wings','10PC saucy wings served with regular fries and a bottle soda of your choice.',3025,'Saucy Wings','food',true,false,false,false);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('a7c0e894-145b-468a-92a7-24b127a0b329','ade08562-1408-41fb-a842-dbf703098f82','Select Flavour',false,1,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('63215e3d-82e6-452b-befb-7b0956229d3c','a7c0e894-145b-468a-92a7-24b127a0b329','Orange',0,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('ac3e2033-3360-4965-b5b0-d8f1630807a2','a7c0e894-145b-468a-92a7-24b127a0b329','Sweet & Spicy',0,false,true,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('c6786823-42d2-45df-ac7e-02a633261def','a7c0e894-145b-468a-92a7-24b127a0b329','Korean BBQ',0,false,true,2);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('0b60b73a-a603-48fe-8a8c-b47da2dd2135','ade08562-1408-41fb-a842-dbf703098f82','Choose Drink',false,1,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('aa8523a7-2655-4e99-afdc-629a8bd50592','0b60b73a-a603-48fe-8a8c-b47da2dd2135','Coca-Cola',0,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('4c371052-9748-4719-a12d-12333087da07','0b60b73a-a603-48fe-8a8c-b47da2dd2135','Sprite',0,false,true,1);
NOTIFY pgrst, 'reload schema';
COMMIT;
