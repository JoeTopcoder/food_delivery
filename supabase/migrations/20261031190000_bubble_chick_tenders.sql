-- Bubble Chick: Tenders.
BEGIN;
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('32f189e5-309b-4b52-a3fd-84d3934bae93','4ec0727e-94b0-4c6e-a90f-437a7fb8974c','3PC Tender Combo','3PC original chicken tenders served with regular fries and a bottle.',1265,'Tenders','food',true,false,false,false);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('674849da-f688-485b-a522-5f5fd483ec10','32f189e5-309b-4b52-a3fd-84d3934bae93','Select Sauce',false,1,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('ca289fb3-0512-4e0d-99b4-09501b530a27','674849da-f688-485b-a522-5f5fd483ec10','Honey Mustard',0,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('70c77dc1-fa46-42ec-a466-a06e48f7ce8e','674849da-f688-485b-a522-5f5fd483ec10','Korean BBQ',0,false,true,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('2c1fa36f-d801-46f3-a217-34b01f041387','674849da-f688-485b-a522-5f5fd483ec10','Sweet & Spicy',0,false,true,2);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('3bbf9d10-9981-4e1b-b518-3cd93d54d635','674849da-f688-485b-a522-5f5fd483ec10','Original (No Sauce)',0,false,true,3);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('5cce34a1-44c7-466b-9911-4559d4eb2cbc','32f189e5-309b-4b52-a3fd-84d3934bae93','Choose Drink',false,1,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('b416cc99-bee7-4efa-b235-6c6520eaf020','5cce34a1-44c7-466b-9911-4559d4eb2cbc','Sprite',0,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('a6605753-787a-41ff-ac31-9b1dce90a795','5cce34a1-44c7-466b-9911-4559d4eb2cbc','Coca-Cola',0,false,true,1);

INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('1933b81f-6c57-441b-917e-0578b1d51ddc','4ec0727e-94b0-4c6e-a90f-437a7fb8974c','5PC Tender','5PC original chicken tenders served with regular fries and a bottle.',1595,'Tenders','food',true,false,false,false);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('00ad2f53-09dc-4dbb-883f-1a6501460e0e','1933b81f-6c57-441b-917e-0578b1d51ddc','Choose Drink',false,1,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('b8042ec7-cef2-4602-a846-2004a28a04d7','00ad2f53-09dc-4dbb-883f-1a6501460e0e','Coca-Cola',0,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('66633bf8-f4cc-4fae-a5dc-f0d7bc3e673a','00ad2f53-09dc-4dbb-883f-1a6501460e0e','Sprite',0,false,true,1);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('d52a817f-23b1-4773-b72e-f5501fc3f3d5','1933b81f-6c57-441b-917e-0578b1d51ddc','Select Dipping Sauce',false,1,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('6edda9cd-2938-45bc-a0d3-b95f60501de5','d52a817f-23b1-4773-b72e-f5501fc3f3d5','Honey Mustard',0,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('a4ec2117-d08e-4f3d-9fa3-a2bc1e75246d','d52a817f-23b1-4773-b72e-f5501fc3f3d5','Korean BBQ',0,false,true,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('197d09b1-6cf0-45f1-86ed-d239edf54471','d52a817f-23b1-4773-b72e-f5501fc3f3d5','Original (No Sauce)',0,false,true,2);

NOTIFY pgrst, 'reload schema';
COMMIT;
