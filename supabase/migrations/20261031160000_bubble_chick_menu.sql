-- Bubble Chick combos. Main-option price folded into base; flavour/meat/drink as groups.
BEGIN;
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('c6385e98-38b5-4bb3-b14b-6f4bcc6377a6','4ec0727e-94b0-4c6e-a90f-437a7fb8974c','1PC Combo','1 piece combo with fries & soda.',880,'Combos','food',true,false,false,false);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('7c710931-d505-4059-b82c-c20329ec2b63','c6385e98-38b5-4bb3-b14b-6f4bcc6377a6','Select Flavour',true,1,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('932f9c7a-9258-40c8-a8fd-62d3e0817d2b','7c710931-d505-4059-b82c-c20329ec2b63','Korean BBQ',0,true,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('0e2f56e2-d1a6-489d-8429-6f804b37d147','7c710931-d505-4059-b82c-c20329ec2b63','Sweet & Spicy',0,false,true,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('9b2233f2-5ce3-4454-badd-9c69f2b062ae','7c710931-d505-4059-b82c-c20329ec2b63','Spicy',0,false,true,2);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('e4d2ad10-6dcd-4976-85c4-38b25ee5c56c','c6385e98-38b5-4bb3-b14b-6f4bcc6377a6','Select Meat Part',true,1,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('e805df6d-a290-437f-8fd5-c3f91040fdb9','e4d2ad10-6dcd-4976-85c4-38b25ee5c56c','Leg',0,true,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('09624972-932f-4a4b-b12c-2f955d60ca24','e4d2ad10-6dcd-4976-85c4-38b25ee5c56c','Thigh',0,false,true,1);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('ef70ba78-0590-4088-b182-c18891f23816','c6385e98-38b5-4bb3-b14b-6f4bcc6377a6','Choose One',false,1,2);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('241a510b-ad9d-4343-9ab3-b05f3b0e2d79','ef70ba78-0590-4088-b182-c18891f23816','Sprite',0,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('858dcd56-8f50-4ca5-9d80-674f12685c31','ef70ba78-0590-4088-b182-c18891f23816','Coca-Cola',0,false,true,1);

INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('37b57867-1ba1-46ea-929b-f36c341be96c','4ec0727e-94b0-4c6e-a90f-437a7fb8974c','2PC Combo','2PC combo comes with fries & soda.',1265,'Combos','food',true,false,false,false);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('95733dfb-3bd9-432d-8435-506c0a705e97','37b57867-1ba1-46ea-929b-f36c341be96c','Select Flavour',false,1,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('f3a274d6-c09c-4fa6-ab85-77b37e1198d9','95733dfb-3bd9-432d-8435-506c0a705e97','Korean BBQ',0,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('d60f0406-af55-4ea3-bab4-8948f1297aaf','95733dfb-3bd9-432d-8435-506c0a705e97','Sweet & Spicy',0,false,true,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('2e96b317-88ec-468b-9f15-8283d2dd9273','95733dfb-3bd9-432d-8435-506c0a705e97','Spicy',0,false,true,2);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('96e3d901-cc32-4e50-a6b7-9bd2b2f7ba15','37b57867-1ba1-46ea-929b-f36c341be96c','Select Meat Part',true,1,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('ee83dbe7-5823-49f6-af69-83c6c3a11d52','96e3d901-cc32-4e50-a6b7-9bd2b2f7ba15','Leg & Thigh',0,true,true,0);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('ca7c216f-fb7f-4382-a4e3-19aac0e589cb','37b57867-1ba1-46ea-929b-f36c341be96c','Choose One',false,1,2);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('6529a58f-3a33-48b2-9074-ac1f004ba552','ca7c216f-fb7f-4382-a4e3-19aac0e589cb','Sprite',0,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('3dda6d8b-278d-4b90-b3cb-3bf5bed84ddc','ca7c216f-fb7f-4382-a4e3-19aac0e589cb','Coca-Cola',0,false,true,1);

INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('1f21a5b4-509f-449c-971f-2fa0247937e5','4ec0727e-94b0-4c6e-a90f-437a7fb8974c','3PC Combo','3PC combo comes with fries & soda.',1595,'Combos','food',true,false,false,false);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('14612ed3-0e73-429d-9766-8c4c243ba888','1f21a5b4-509f-449c-971f-2fa0247937e5','Select Flavour',false,1,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('6a354318-34a4-4742-9a3d-6d75cba45bba','14612ed3-0e73-429d-9766-8c4c243ba888','Korean BBQ',0,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('1a81d45a-de53-44a9-9b67-16bd0a01673b','14612ed3-0e73-429d-9766-8c4c243ba888','Sweet & Spicy',0,false,true,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('60654eb1-094e-4a5a-97ad-b2431db7f93d','14612ed3-0e73-429d-9766-8c4c243ba888','Spicy',0,false,true,2);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('d0665588-1fba-4304-b428-7ce9fa0f8a14','1f21a5b4-509f-449c-971f-2fa0247937e5','Select Meat Part',false,1,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('b9a14d25-90f3-45b6-a931-225e8acf6ef0','d0665588-1fba-4304-b428-7ce9fa0f8a14','Leg & Thigh',0,false,true,0);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('14d28418-f230-400b-9223-34eb4f39aeb8','1f21a5b4-509f-449c-971f-2fa0247937e5','Choose One',false,1,2);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('37e5ffea-7ae2-4153-a9c3-94c453f88768','14d28418-f230-400b-9223-34eb4f39aeb8','Sprite',0,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('670b87fe-e079-443f-9fbc-b095688d0167','14d28418-f230-400b-9223-34eb4f39aeb8','Coca-Cola',0,false,true,1);

INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('913145a0-d961-4f86-ab6a-044c34118abb','4ec0727e-94b0-4c6e-a90f-437a7fb8974c','9PC Bucket','9PC bucket with fries & 2L soda.',4950,'Combos','food',true,false,false,false);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('c45bacd1-1305-4896-92ac-bec3cea12683','913145a0-d961-4f86-ab6a-044c34118abb','Select Flavour',false,1,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('2ea230d0-a751-4199-9b43-61bf521f9f24','c45bacd1-1305-4896-92ac-bec3cea12683','Korean BBQ',0,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('827681dc-b028-46fb-bac4-7b02cf71086d','c45bacd1-1305-4896-92ac-bec3cea12683','Sweet & Spicy',0,false,true,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('c9a40f42-92d8-43d5-bff8-ae8630b58e55','c45bacd1-1305-4896-92ac-bec3cea12683','Spicy',0,false,true,2);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('b0388fa9-bdc4-479f-a187-13d1ca9f9d97','913145a0-d961-4f86-ab6a-044c34118abb','Choose One',false,1,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('f0b84dfb-b096-449e-88ed-79e8a54a9092','b0388fa9-bdc4-479f-a187-13d1ca9f9d97','Coca-Cola (2 Litre)',0,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('51bfd17f-b1a7-4d5b-b65f-79e91838ceb5','b0388fa9-bdc4-479f-a187-13d1ca9f9d97','Sprite (2 Litre)',0,false,true,1);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('9d87c89d-640b-4a7e-8b11-cef42d932b08','913145a0-d961-4f86-ab6a-044c34118abb','Select Meat Part',false,1,2);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('f0fb9447-26b3-40d2-a622-c25984982d74','9d87c89d-640b-4a7e-8b11-cef42d932b08','Leg & Thigh',0,false,true,0);

NOTIFY pgrst, 'reload schema';
COMMIT;
