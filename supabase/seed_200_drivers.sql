-- Seed 200 test drivers with randomized stats for leaderboard testing
-- Each driver gets a user row (role=driver) + a drivers row with varied stats

DO $$
DECLARE
  i INT;
  uid UUID;
  did UUID;
  first_names TEXT[] := ARRAY['James','John','Robert','Michael','David','William','Richard','Joseph','Thomas','Chris','Daniel','Paul','Mark','George','Steven','Kevin','Brian','Edward','Andrew','Joshua','Anthony','Ryan','Eric','Brandon','Justin','Tyler','Aaron','Nathan','Sean','Adam','Marcus','Derek','Omar','Carlos','Diego','Malik','Jayden','Ethan','Noah','Liam','Mason','Logan','Lucas','Aiden','Elijah','Oliver','Caleb','Isaiah','Xavier','Zion','Kai','Andre','Jamal','Tyrone','Dwayne','Omar','Rashid','Hassan','Tariq','Kareem','Kofi','Kwame','Jermaine','Dante','Terrence','Alvin','Cedric','Clive','Gareth','Nigel','Colin','Stuart','Rodney','Neville','Lance','Kirk','Troy','Burt','Dean','Shane','Wade','Blake','Grant','Clark','Roy','Leo','Hugo','Ivan','Neil','Glen','Trent','Floyd','Carl','Earl','Kurt','Vince','Rick','Cliff','Herb','Dale'];
  last_names TEXT[] := ARRAY['Smith','Johnson','Williams','Brown','Jones','Davis','Miller','Wilson','Moore','Taylor','Anderson','Thomas','Jackson','White','Harris','Martin','Thompson','Garcia','Martinez','Robinson','Clark','Rodriguez','Lewis','Lee','Walker','Hall','Allen','Young','King','Wright','Lopez','Hill','Scott','Green','Adams','Baker','Gonzalez','Nelson','Carter','Mitchell','Perez','Roberts','Turner','Phillips','Campbell','Parker','Evans','Edwards','Collins','Stewart','Sanchez','Morris','Rogers','Reed','Cook','Morgan','Bell','Murphy','Bailey','Rivera','Cooper','Richardson','Cox','Howard','Ward','Torres','Peterson','Gray','Ramirez','James','Watson','Brooks','Kelly','Sanders','Price','Bennett','Wood','Barnes','Ross','Henderson','Coleman','Jenkins','Perry','Powell','Long','Patterson','Hughes','Flores','Washington','Butler','Simmons','Foster','Gonzales','Bryant','Alexander','Russell','Griffin','Diaz','Hayes'];
  vehicle_types TEXT[] := ARRAY['car','motorcycle','bicycle','car','car','motorcycle'];
  vehicle_brands TEXT[] := ARRAY['Toyota Corolla','Honda Civic','Nissan Sentra','Hyundai Elantra','Kia Rio','Suzuki Swift','Toyota Yaris','Honda Fit','Mazda 3','Ford Focus'];
  vehicle_colors TEXT[] := ARRAY['White','Black','Silver','Red','Blue','Gray','Green','Brown','Gold','Beige'];
  v_type TEXT;
  v_brand TEXT;
  v_color TEXT;
  v_number TEXT;
  fname TEXT;
  lname TEXT;
  full_name TEXT;
  email_addr TEXT;
  phone_num TEXT;
  rating_val DOUBLE PRECISION;
  deliveries_val INT;
  earnings_val DOUBLE PRECISION;
  cancelled_val INT;
  lat_val DOUBLE PRECISION;
  lng_val DOUBLE PRECISION;
BEGIN
  FOR i IN 1..200 LOOP
    uid := gen_random_uuid();
    did := gen_random_uuid();

    fname := first_names[1 + floor(random() * array_length(first_names, 1))::int];
    lname := last_names[1 + floor(random() * array_length(last_names, 1))::int];
    full_name := fname || ' ' || lname;
    email_addr := lower(fname || '.' || lname || '.' || i || '@testdriver.com');
    phone_num := '+1345' || lpad((100000 + floor(random() * 900000))::text, 7, '0');

    v_type := vehicle_types[1 + floor(random() * array_length(vehicle_types, 1))::int];
    v_brand := vehicle_brands[1 + floor(random() * array_length(vehicle_brands, 1))::int];
    v_color := vehicle_colors[1 + floor(random() * array_length(vehicle_colors, 1))::int];
    v_number := chr(65 + floor(random()*26)::int) || chr(65 + floor(random()*26)::int) || '-' || lpad((1000 + floor(random()*9000))::text, 4, '0');

    -- Randomize stats: top drivers have more deliveries + higher rating
    deliveries_val := floor(random() * 500)::int;
    rating_val := round((3.0 + random() * 2.0)::numeric, 2);
    earnings_val := round((deliveries_val * (4.0 + random() * 6.0))::numeric, 2);
    cancelled_val := floor(random() * (deliveries_val * 0.05 + 1))::int;

    -- Random location around Grand Cayman
    lat_val := 19.28 + (random() - 0.5) * 0.1;
    lng_val := -81.38 + (random() - 0.5) * 0.1;

    INSERT INTO public.users (id, email, name, phone, role, is_active, email_verified, created_at, updated_at, referral_code)
    VALUES (
      uid,
      email_addr,
      full_name,
      phone_num,
      'driver',
      true,
      true,
      NOW() - interval '1 day' * floor(random() * 180),
      NOW(),
      upper(substring(uid::text from 1 for 6) || substring(md5(email_addr) from 1 for 2))
    );

    INSERT INTO public.drivers (id, user_id, vehicle_type, vehicle_number, vehicle_brand, vehicle_color, license_number, rating, completed_deliveries, cancelled_deliveries, total_earnings, is_available, is_verified, is_active, current_latitude, current_longitude, documents_status, created_at, updated_at, total_paid_out, cash_float)
    VALUES (
      did,
      uid,
      v_type,
      v_number,
      v_brand,
      v_color,
      'DL-' || lpad(i::text, 5, '0'),
      rating_val,
      deliveries_val,
      cancelled_val,
      earnings_val,
      (random() > 0.3),  -- 70% available
      true,
      true,
      lat_val,
      lng_val,
      'approved',
      NOW() - interval '1 day' * floor(random() * 180),
      NOW(),
      round((earnings_val * random() * 0.5)::numeric, 2),
      round((random() * 200)::numeric, 2)
    );
  END LOOP;

  RAISE NOTICE 'Seeded 200 test drivers!';
END $$;
