-- Chicken & Tings: Soup category.
BEGIN;
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('a2d47dee-bfa0-4ec1-bacc-4a40948e7627','a223daee-5b35-426a-9d05-ba3479a97c46','Red Peas Soup with Pig Tail','Hearty red peas soup cooked with pig tail.',800,'Soup','food',true,true,false,false);
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('749ce895-091f-4398-bc9b-c94cd6f0d2ae','a223daee-5b35-426a-9d05-ba3479a97c46','Pumpkin Soup with Chicken','Creamy Jamaican pumpkin soup with chicken.',800,'Soup','food',true,false,false,false);
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('a70a1a5f-4f8a-47be-9b15-20aba9392c83','a223daee-5b35-426a-9d05-ba3479a97c46','Red Peas Soup with Chicken','Hearty red peas soup cooked with chicken.',800,'Soup','food',true,false,false,false);
INSERT INTO menus (id,restaurant_id,name,description,price,category,product_type,is_available,contains_pork,contains_beef,contains_shellfish) VALUES ('592ab7ac-4e0a-4f03-97bd-842721a7640c','a223daee-5b35-426a-9d05-ba3479a97c46','Fish Soup','Flavourful Jamaican fish soup.',800,'Soup','food',true,false,false,false);
NOTIFY pgrst, 'reload schema';
COMMIT;
