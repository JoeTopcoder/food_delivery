-- Add 3 more test packages to Applizone Shipping
INSERT INTO public.package_records
  (shipping_company_id, tracking_number, customer_name, customer_phone,
   warehouse_location, delivery_address, delivery_lat, delivery_lng,
   package_weight, package_type, package_value, barcode_data,
   package_status, verified, notes)
SELECT
  sc.id,
  'APZ-001122',
  'Marcus Brown',
  '+18765552001',
  sc.warehouse_address,
  '78 Constant Spring Road, Kingston, Jamaica',
  18.0302, -76.7984,
  2.8, 'electronics', 320.00,
  'APZ-001122',
  'at_warehouse', true,
  'Smartphone — handle with care'
FROM public.shipping_companies sc
WHERE sc.name = 'Applizone Shipping'
ON CONFLICT DO NOTHING;

INSERT INTO public.package_records
  (shipping_company_id, tracking_number, customer_name, customer_phone,
   warehouse_location, delivery_address, delivery_lat, delivery_lng,
   package_weight, package_type, package_value, barcode_data,
   package_status, verified, notes)
SELECT
  sc.id,
  'APZ-334455',
  'Shanice Williams',
  '+18765552002',
  sc.warehouse_address,
  '34 Dunrobin Avenue, Kingston, Jamaica',
  18.0045, -76.7871,
  0.4, 'document', 25.00,
  'APZ-334455',
  'at_warehouse', true,
  'Legal documents — urgent'
FROM public.shipping_companies sc
WHERE sc.name = 'Applizone Shipping'
ON CONFLICT DO NOTHING;

INSERT INTO public.package_records
  (shipping_company_id, tracking_number, customer_name, customer_phone,
   warehouse_location, delivery_address, delivery_lat, delivery_lng,
   package_weight, package_type, package_value, barcode_data,
   package_status, verified, notes)
SELECT
  sc.id,
  'APZ-667788',
  'Devon Campbell',
  '+18765552003',
  sc.warehouse_address,
  '12 Barbican Road, Kingston, Jamaica',
  18.0178, -76.7692,
  7.5, 'large', 210.00,
  'APZ-667788',
  'at_warehouse', true,
  'Household appliance'
FROM public.shipping_companies sc
WHERE sc.name = 'Applizone Shipping'
ON CONFLICT DO NOTHING;
