-- Chicken & Tings lunch menu: replace two placeholder items with the
-- real lunch menu (Fry Chicken, Sweet & Sour, Bar-B-Fry) + full option groups.
BEGIN;

DELETE FROM menu_option_choices WHERE group_id IN (
  SELECT g.id FROM menu_option_groups g JOIN menus m ON m.id=g.menu_item_id
  WHERE m.restaurant_id='a223daee-5b35-426a-9d05-ba3479a97c46' AND m.name IN ('Fried Chicken','Bar-B-Fried Chicken'));
DELETE FROM menu_option_groups WHERE menu_item_id IN (
  SELECT id FROM menus WHERE restaurant_id='a223daee-5b35-426a-9d05-ba3479a97c46' AND name IN ('Fried Chicken','Bar-B-Fried Chicken'));
DELETE FROM menus WHERE restaurant_id='a223daee-5b35-426a-9d05-ba3479a97c46' AND name IN ('Fried Chicken','Bar-B-Fried Chicken');

INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('21a376cf-7984-4959-b199-a5fc0ef96a17','a223daee-5b35-426a-9d05-ba3479a97c46','Fry Chicken','Crispy Jamaican fried chicken served over rice with fresh salad.',1100,'Lunch / Dinner','food',true,false,false,false);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('53b9a232-481f-494d-a54b-e698aa22cf07','21a376cf-7984-4959-b199-a5fc0ef96a17','Mix Meal',false,1,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('fa316abc-c9b8-46a0-85ec-27e802d71ae3','53b9a232-481f-494d-a54b-e698aa22cf07','Mix Fry Chicken',500,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('2a7d2997-1723-4b68-a266-ac97126f7912','53b9a232-481f-494d-a54b-e698aa22cf07','Mix Bar-B-Fry',500,false,true,1);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('ad5c464e-fcc5-4b6c-b847-a3f230fdbf3c','21a376cf-7984-4959-b199-a5fc0ef96a17','Part',true,1,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('b5492cce-4057-4073-b3b1-21490e6ed571','ad5c464e-fcc5-4b6c-b847-a3f230fdbf3c','Breast, Leg & Wing',0,true,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('17e1c916-a644-4292-b23a-0f15726a83e8','ad5c464e-fcc5-4b6c-b847-a3f230fdbf3c','Leg, Thigh & Wing',0,false,true,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('62ecc30d-d587-4f0f-beaf-c974485d89a8','ad5c464e-fcc5-4b6c-b847-a3f230fdbf3c','Rib, Leg & Wing',0,false,true,2);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('cb0d8ee7-0bf7-4d09-89f8-af0c19602c8e','21a376cf-7984-4959-b199-a5fc0ef96a17','Sides',true,1,2);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('f9edfe0d-921a-4127-9224-6b65718e6410','cb0d8ee7-0bf7-4d09-89f8-af0c19602c8e','Rice & Peas',0,true,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('d57edf34-32a0-4a0b-891c-ced4c1131c31','cb0d8ee7-0bf7-4d09-89f8-af0c19602c8e','White Rice',0,false,true,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('0b200864-c214-41e1-ae62-c2f42234b389','cb0d8ee7-0bf7-4d09-89f8-af0c19602c8e','No Rice',0,false,true,2);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('8d05b261-af5c-41e8-8ccc-a5a21e8a1b8d','cb0d8ee7-0bf7-4d09-89f8-af0c19602c8e','Fries',500,false,true,3);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('fc25806c-c61f-4cfc-ae11-bf57ec992b4b','21a376cf-7984-4959-b199-a5fc0ef96a17','Extras',false,4,3);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('8659b047-2845-4c67-93ff-4f7123d43a8b','fc25806c-c61f-4cfc-ae11-bf57ec992b4b','Bammy',400,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('56bd2e00-f182-4962-9c27-cf50421b09ff','fc25806c-c61f-4cfc-ae11-bf57ec992b4b','Extra Fries',500,false,true,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('4c00b087-dfe7-46f6-941b-ea713d955d33','fc25806c-c61f-4cfc-ae11-bf57ec992b4b','Plantain',250,false,true,2);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('dfdeaab9-71a9-4263-8103-01818e3cd761','fc25806c-c61f-4cfc-ae11-bf57ec992b4b','Extra Rice',500,false,true,3);

INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('0dcad73c-deab-427c-8377-5a2197a4770e','a223daee-5b35-426a-9d05-ba3479a97c46','Sweet and Sour Chicken','Golden fried chicken tossed in a tangy sweet & sour sauce with peppers, onions and pineapple, served with rice and salad.',1200,'Lunch / Dinner','food',true,false,false,false);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('d338ffba-64ec-4d9a-a6f8-142afb3b97b3','0dcad73c-deab-427c-8377-5a2197a4770e','Mix Meal',false,1,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('74f8ceb5-7202-42b6-b51a-9dab9896ca86','d338ffba-64ec-4d9a-a6f8-142afb3b97b3','Mix Fry Chicken',500,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('fe02aaa1-70c1-4334-bb48-a886d755a4c5','d338ffba-64ec-4d9a-a6f8-142afb3b97b3','Mix Bar-B-Fry',500,false,true,1);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('1bfbc4a9-1533-452c-a0d2-ccb44b526afa','0dcad73c-deab-427c-8377-5a2197a4770e','Sides',true,1,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('5a16cc3c-024c-4905-8d54-ed3cc2378330','1bfbc4a9-1533-452c-a0d2-ccb44b526afa','Rice & Peas',0,true,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('e61ca661-498c-4135-971d-e14de1494f82','1bfbc4a9-1533-452c-a0d2-ccb44b526afa','White Rice',0,false,true,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('726dab09-9090-48a8-8b4a-a25c094ae483','1bfbc4a9-1533-452c-a0d2-ccb44b526afa','No Rice',0,false,true,2);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('12819401-c8ca-4c84-b043-604d18ea2108','1bfbc4a9-1533-452c-a0d2-ccb44b526afa','Fries',500,false,true,3);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('a976503e-b9fc-4dc5-98a2-592fd14206e1','0dcad73c-deab-427c-8377-5a2197a4770e','Extras',false,4,2);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('2358c7a0-383d-4cc5-9de3-aadfa98733a0','a976503e-b9fc-4dc5-98a2-592fd14206e1','Bammy',400,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('de98214a-0a0f-4ec0-b30f-42cebcdec5a0','a976503e-b9fc-4dc5-98a2-592fd14206e1','Extra Fries',500,false,true,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('baac60bf-4dc8-4ef6-846d-1d0e3ea500b0','a976503e-b9fc-4dc5-98a2-592fd14206e1','Plantain',250,false,true,2);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('66def7b4-6253-430e-bb03-b53fd4ddb94e','a976503e-b9fc-4dc5-98a2-592fd14206e1','Extra Rice',500,false,true,3);

INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('2cb064ad-89f6-4dae-a671-3c595ed612f8','a223daee-5b35-426a-9d05-ba3479a97c46','Bar-B-Fry Chicken','Fried chicken smothered in rich barbecue sauce, served over rice with fresh salad.',1200,'Lunch / Dinner','food',true,false,false,false);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('be2e39e7-4407-4f3b-bf07-827e7d28486d','2cb064ad-89f6-4dae-a671-3c595ed612f8','Mix Meal',false,1,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('c44f0323-6c42-4e62-9bb2-d78ce6b2de14','be2e39e7-4407-4f3b-bf07-827e7d28486d','Mix Fry Chicken',500,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('e696264e-af38-4794-b567-376123975566','be2e39e7-4407-4f3b-bf07-827e7d28486d','Mix Bar-B-Fry',500,false,true,1);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('7270bdaf-a68c-4ae7-aead-34754680e33d','2cb064ad-89f6-4dae-a671-3c595ed612f8','Part',true,1,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('cf7e1091-9586-4f24-88fe-c39375371399','7270bdaf-a68c-4ae7-aead-34754680e33d','Breast, Leg & Wing',0,true,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('16bfcaa5-7241-435e-9321-5de498039537','7270bdaf-a68c-4ae7-aead-34754680e33d','Leg, Thigh & Wing',0,false,true,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('3caa0354-703f-4849-ac75-cce15d5e62b9','7270bdaf-a68c-4ae7-aead-34754680e33d','Rib, Leg & Wing',0,false,true,2);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('ec609bad-d6ee-4f98-b54e-6bd2ca0cdd9e','2cb064ad-89f6-4dae-a671-3c595ed612f8','Sides',true,1,2);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('07982f70-31d1-42cb-a886-3ea5c2977350','ec609bad-d6ee-4f98-b54e-6bd2ca0cdd9e','Rice & Peas',0,true,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('e0557cf8-6b20-4df2-8828-034f3e55b2f0','ec609bad-d6ee-4f98-b54e-6bd2ca0cdd9e','White Rice',0,false,true,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('1322d1a5-8674-43c1-a1d4-30fe73d84b79','ec609bad-d6ee-4f98-b54e-6bd2ca0cdd9e','No Rice',0,false,true,2);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('66dfbe83-7a4c-49ad-8f36-de65ca6456f5','ec609bad-d6ee-4f98-b54e-6bd2ca0cdd9e','Fries',500,false,true,3);
INSERT INTO menu_option_groups (id,menu_item_id,name,is_required,max_selections,sort_order) VALUES ('d49ab18a-4ea7-46a1-82e9-5783ae8d1ce9','2cb064ad-89f6-4dae-a671-3c595ed612f8','Extras',false,4,3);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('dc20c7c8-9fcd-4209-9395-672cb362f44f','d49ab18a-4ea7-46a1-82e9-5783ae8d1ce9','Bammy',400,false,true,0);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('cee7c882-40a5-4892-a7d0-6179c2c39321','d49ab18a-4ea7-46a1-82e9-5783ae8d1ce9','Extra Fries',500,false,true,1);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('1ed70758-f151-469f-8682-f370296fe7be','d49ab18a-4ea7-46a1-82e9-5783ae8d1ce9','Plantain',250,false,true,2);
INSERT INTO menu_option_choices (id,group_id,name,price,is_default,is_available,sort_order) VALUES ('5990ef59-e4a9-47ee-bb56-f3665b9a7383','d49ab18a-4ea7-46a1-82e9-5783ae8d1ce9','Extra Rice',500,false,true,3);

NOTIFY pgrst, 'reload schema';
COMMIT;
