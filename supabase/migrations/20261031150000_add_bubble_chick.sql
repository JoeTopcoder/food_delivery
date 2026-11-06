-- Add Bubble Chick (New Kingston), owned by its own restaurant login (bubblechick@hotbite.app).
BEGIN;
INSERT INTO restaurants (id,owner_id,name,description,cuisine_type,store_type,address,latitude,longitude,
  status,is_active,is_open,is_verified,rating,review_count,delivery_fee,minimum_order_amount,estimated_delivery_time,
  commission_rate,restaurant_payment_method,timezone,tags,operating_hours)
VALUES ('4ec0727e-94b0-4c6e-a90f-437a7fb8974c','4c1b42f3-52a7-40b4-9922-d2d0fb59f589','Bubble Chick','Fried chicken and more for lunch.','Fast Food','food',
  '30 Dominica Drive, Unit 10, New Kingston Business Centre, Kingston',18.0075,-76.7855,
  'approved',true,true,true,4.5,0,0,0,35,0,'CASH_PAYMENT','America/Jamaica',
  ARRAY['Lunch'],'{"sunday": {"open": "00:00", "close": "00:00", "is_open": false}, "monday": {"open": "11:00", "close": "17:00", "is_open": true}, "tuesday": {"open": "11:00", "close": "17:00", "is_open": true}, "wednesday": {"open": "11:00", "close": "17:00", "is_open": true}, "thursday": {"open": "11:00", "close": "17:00", "is_open": true}, "friday": {"open": "11:00", "close": "17:00", "is_open": true}, "saturday": {"open": "11:00", "close": "17:00", "is_open": true}}'::jsonb);
NOTIFY pgrst, 'reload schema';
COMMIT;