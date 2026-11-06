-- Potwah Diner & Bar: Soup section (Medium / Large +250).
BEGIN;
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('50c561b4-b26d-49ea-88ad-c9ac63bdd7b9','2a614cb0-9eb6-4af4-bb8e-71d95a84fe6c','Goat Head Soup','Rich Jamaican goat head soup.',650,'Soup','food',true,false,false,false);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('4717b47c-e6aa-485e-9d5f-d6bdc45d4e67','50c561b4-b26d-49ea-88ad-c9ac63bdd7b9','Size',true,1,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('d0832824-be49-408c-9319-22c26675f41c','4717b47c-e6aa-485e-9d5f-d6bdc45d4e67','Medium',0,true,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('23b3cc2c-be5b-47ab-978e-057ed44c7597','4717b47c-e6aa-485e-9d5f-d6bdc45d4e67','Large',250,false,true,1);

INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('c819c39c-ccd1-44a4-b8fe-a3100c22b22f','2a614cb0-9eb6-4af4-bb8e-71d95a84fe6c','Fish Tea','Spicy Jamaican fish tea soup.',650,'Soup','food',true,false,false,false);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('f62b1ce1-5eb3-447b-a4ea-51c86eee2e7b','c819c39c-ccd1-44a4-b8fe-a3100c22b22f','Size',true,1,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('d5f4c967-ce24-4111-a6bc-a7592b84026b','f62b1ce1-5eb3-447b-a4ea-51c86eee2e7b','Medium',0,true,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('ee8b4df5-380f-4c7b-8964-251daf1b7211','f62b1ce1-5eb3-447b-a4ea-51c86eee2e7b','Large',250,false,true,1);

INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('1997536f-135e-4b3c-b303-a09a24d99442','2a614cb0-9eb6-4af4-bb8e-71d95a84fe6c','Red Peas with Pigtail','Red peas soup cooked with pigtail.',650,'Soup','food',true,true,false,false);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('4939f412-d072-42eb-aec1-2bc28e6d1634','1997536f-135e-4b3c-b303-a09a24d99442','Size',true,1,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('24df6db0-7f0f-4567-8916-9fbcbd814834','4939f412-d072-42eb-aec1-2bc28e6d1634','Medium',0,true,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('d6008e89-ba31-4caf-ba96-6da862d56e1e','4939f412-d072-42eb-aec1-2bc28e6d1634','Large',250,false,true,1);

INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('bd15fa56-5794-45c7-8f91-537c4d56bab7','2a614cb0-9eb6-4af4-bb8e-71d95a84fe6c','Cow Cod Soup','Traditional Jamaican cow cod soup.',650,'Soup','food',true,false,true,false);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('7187ea1f-98f0-4d42-bb9a-ebc8ac9700ba','bd15fa56-5794-45c7-8f91-537c4d56bab7','Size',true,1,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('579f30a9-730f-4739-b250-b52a1ad06acd','7187ea1f-98f0-4d42-bb9a-ebc8ac9700ba','Medium',0,true,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('60b11243-71dc-4be1-95b7-22d5bedde96c','7187ea1f-98f0-4d42-bb9a-ebc8ac9700ba','Large',250,false,true,1);

NOTIFY pgrst, 'reload schema';
COMMIT;
