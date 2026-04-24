-- Seed 25 orders across 4 restaurants (Scotchies, KFC, Island Grill, Rib Kage)
-- Users: 8 customer accounts
-- Statuses: mix of delivered/completed (so decision engine can compute metrics)
-- Timestamps: spread over last 30 days

INSERT INTO public.orders (
  user_id, restaurant_id, subtotal, tax_amount, delivery_fee, discount_amount,
  total_amount, status, delivery_address, delivery_latitude, delivery_longitude,
  payment_method, payment_status, is_pickup, ordered_at, confirmed_at,
  preparing_started_at, ready_at, picked_up_at, on_the_way_at, delivered_at,
  completed_at, driver_tip, commission_rate, commission_amount,
  distance_km, estimated_prep_minutes
)
VALUES
-- ── Scotchies Kingston (936b7ccd-574a-478d-a92e-198475bc668c) ─────────────
(
  '7c1d6980-7497-4ae4-909a-9c0e48be55b5', '936b7ccd-574a-478d-a92e-198475bc668c',
  1850.00, 166.50, 350.00, 0, 2366.50, 'delivered',
  '12 Hope Rd, Kingston', 17.9969, -76.7741,
  'card', 'paid', false,
  now() - interval '28 days', now() - interval '28 days' + interval '2 min',
  now() - interval '28 days' + interval '5 min', now() - interval '28 days' + interval '20 min',
  now() - interval '28 days' + interval '25 min', now() - interval '28 days' + interval '27 min',
  now() - interval '28 days' + interval '40 min',
  now() - interval '28 days' + interval '41 min',
  100.00, 0.15, 277.50, 2.1, 15
),
(
  '3b041500-dc8f-459e-a4dc-b7c2a3619f43', '936b7ccd-574a-478d-a92e-198475bc668c',
  2400.00, 216.00, 350.00, 0, 2966.00, 'delivered',
  '45 Constant Spring Rd, Kingston', 18.0213, -76.7897,
  'card', 'paid', false,
  now() - interval '21 days', now() - interval '21 days' + interval '3 min',
  now() - interval '21 days' + interval '6 min', now() - interval '21 days' + interval '22 min',
  now() - interval '21 days' + interval '26 min', now() - interval '21 days' + interval '28 min',
  now() - interval '21 days' + interval '42 min',
  now() - interval '21 days' + interval '43 min',
  150.00, 0.15, 360.00, 3.2, 15
),
(
  '39fa1191-926c-4f3b-aa25-1e0cb80f28d8', '936b7ccd-574a-478d-a92e-198475bc668c',
  3100.00, 279.00, 400.00, 200.00, 3579.00, 'delivered',
  '78 Barbican Rd, Kingston', 18.0114, -76.7628,
  'wallet', 'paid', false,
  now() - interval '14 days', now() - interval '14 days' + interval '2 min',
  now() - interval '14 days' + interval '4 min', now() - interval '14 days' + interval '18 min',
  now() - interval '14 days' + interval '22 min', now() - interval '14 days' + interval '24 min',
  now() - interval '14 days' + interval '38 min',
  now() - interval '14 days' + interval '39 min',
  200.00, 0.15, 465.00, 2.8, 12
),
(
  '76dcf0a1-1939-47cd-89d9-3ec8e471dd60', '936b7ccd-574a-478d-a92e-198475bc668c',
  1600.00, 144.00, 350.00, 0, 2094.00, 'delivered',
  '5 Dunrobin Ave, Kingston', 18.0052, -76.7802,
  'card', 'paid', false,
  now() - interval '7 days', now() - interval '7 days' + interval '2 min',
  now() - interval '7 days' + interval '5 min', now() - interval '7 days' + interval '20 min',
  now() - interval '7 days' + interval '24 min', now() - interval '7 days' + interval '26 min',
  now() - interval '7 days' + interval '39 min',
  now() - interval '7 days' + interval '40 min',
  100.00, 0.15, 240.00, 1.9, 14
),
(
  '3b041500-dc8f-459e-a4dc-b7c2a3619f43', '936b7ccd-574a-478d-a92e-198475bc668c',
  2750.00, 247.50, 400.00, 0, 3397.50, 'delivered',
  '45 Constant Spring Rd, Kingston', 18.0213, -76.7897,
  'card', 'paid', false,
  now() - interval '3 days', now() - interval '3 days' + interval '2 min',
  now() - interval '3 days' + interval '5 min', now() - interval '3 days' + interval '19 min',
  now() - interval '3 days' + interval '23 min', now() - interval '3 days' + interval '25 min',
  now() - interval '3 days' + interval '37 min',
  now() - interval '3 days' + interval '38 min',
  150.00, 0.15, 412.50, 3.2, 14
),
(
  '7c1d6980-7497-4ae4-909a-9c0e48be55b5', '936b7ccd-574a-478d-a92e-198475bc668c',
  1950.00, 175.50, 350.00, 0, 2475.50, 'completed',
  '12 Hope Rd, Kingston', 17.9969, -76.7741,
  'card', 'paid', true,
  now() - interval '1 day', now() - interval '1 day' + interval '2 min',
  now() - interval '1 day' + interval '4 min', now() - interval '1 day' + interval '17 min',
  NULL, NULL, NULL,
  now() - interval '1 day' + interval '20 min',
  0, 0.15, 292.50, 0, 12
),

-- ── KFC (0a20cdd9-422b-4041-8583-b26ee36d30c5) ───────────────────────────
(
  'dbbe53e0-76ea-49f0-98d8-e4453cc5bf57', '0a20cdd9-422b-4041-8583-b26ee36d30c5',
  1200.00, 108.00, 300.00, 0, 1608.00, 'delivered',
  '33 Maxfield Ave, Kingston', 17.9958, -76.8003,
  'card', 'paid', false,
  now() - interval '27 days', now() - interval '27 days' + interval '1 min',
  now() - interval '27 days' + interval '3 min', now() - interval '27 days' + interval '13 min',
  now() - interval '27 days' + interval '16 min', now() - interval '27 days' + interval '18 min',
  now() - interval '27 days' + interval '28 min',
  now() - interval '27 days' + interval '29 min',
  50.00, 0.15, 180.00, 1.5, 10
),
(
  '3df7b3b8-b1a6-4051-8af0-f878aef63a99', '0a20cdd9-422b-4041-8583-b26ee36d30c5',
  1450.00, 130.50, 300.00, 100.00, 1780.50, 'delivered',
  '67 Waltham Park Rd, Kingston', 18.0078, -76.8134,
  'wallet', 'paid', false,
  now() - interval '20 days', now() - interval '20 days' + interval '2 min',
  now() - interval '20 days' + interval '4 min', now() - interval '20 days' + interval '14 min',
  now() - interval '20 days' + interval '17 min', now() - interval '20 days' + interval '19 min',
  now() - interval '20 days' + interval '29 min',
  now() - interval '20 days' + interval '30 min',
  80.00, 0.15, 217.50, 1.8, 10
),
(
  '2aea96e5-f9bf-4a91-896b-7f89e656a479', '0a20cdd9-422b-4041-8583-b26ee36d30c5',
  980.00, 88.20, 300.00, 0, 1368.20, 'delivered',
  '22 Red Hills Rd, Kingston', 18.0301, -76.8012,
  'card', 'paid', false,
  now() - interval '16 days', now() - interval '16 days' + interval '1 min',
  now() - interval '16 days' + interval '3 min', now() - interval '16 days' + interval '12 min',
  now() - interval '16 days' + interval '15 min', now() - interval '16 days' + interval '17 min',
  now() - interval '16 days' + interval '25 min',
  now() - interval '16 days' + interval '26 min',
  0, 0.15, 147.00, 1.2, 8
),
(
  'f1ed8760-c7f6-4ff7-810e-33cc4c32d63e', '0a20cdd9-422b-4041-8583-b26ee36d30c5',
  1700.00, 153.00, 300.00, 0, 2153.00, 'delivered',
  '9 Duhaney Park Ave, Kingston', 17.9876, -76.7689,
  'card', 'paid', false,
  now() - interval '10 days', now() - interval '10 days' + interval '2 min',
  now() - interval '10 days' + interval '4 min', now() - interval '10 days' + interval '14 min',
  now() - interval '10 days' + interval '17 min', now() - interval '10 days' + interval '19 min',
  now() - interval '10 days' + interval '27 min',
  now() - interval '10 days' + interval '28 min',
  100.00, 0.15, 255.00, 1.6, 9
),
(
  'dbbe53e0-76ea-49f0-98d8-e4453cc5bf57', '0a20cdd9-422b-4041-8583-b26ee36d30c5',
  1350.00, 121.50, 300.00, 0, 1771.50, 'delivered',
  '33 Maxfield Ave, Kingston', 17.9958, -76.8003,
  'card', 'paid', false,
  now() - interval '5 days', now() - interval '5 days' + interval '2 min',
  now() - interval '5 days' + interval '4 min', now() - interval '5 days' + interval '13 min',
  now() - interval '5 days' + interval '16 min', now() - interval '5 days' + interval '18 min',
  now() - interval '5 days' + interval '26 min',
  now() - interval '5 days' + interval '27 min',
  50.00, 0.15, 202.50, 1.5, 9
),
(
  '3df7b3b8-b1a6-4051-8af0-f878aef63a99', '0a20cdd9-422b-4041-8583-b26ee36d30c5',
  2100.00, 189.00, 300.00, 0, 2589.00, 'delivered',
  '67 Waltham Park Rd, Kingston', 18.0078, -76.8134,
  'card', 'paid', false,
  now() - interval '2 days', now() - interval '2 days' + interval '1 min',
  now() - interval '2 days' + interval '3 min', now() - interval '2 days' + interval '12 min',
  now() - interval '2 days' + interval '15 min', now() - interval '2 days' + interval '17 min',
  now() - interval '2 days' + interval '25 min',
  now() - interval '2 days' + interval '26 min',
  120.00, 0.15, 315.00, 1.8, 10
),

-- ── Island Grill (4fd35afb-8821-4b85-b8e3-5ec2787197c8) ──────────────────
(
  '39fa1191-926c-4f3b-aa25-1e0cb80f28d8', '4fd35afb-8821-4b85-b8e3-5ec2787197c8',
  2250.00, 202.50, 400.00, 0, 2852.50, 'delivered',
  '78 Barbican Rd, Kingston', 18.0114, -76.7628,
  'card', 'paid', false,
  now() - interval '26 days', now() - interval '26 days' + interval '3 min',
  now() - interval '26 days' + interval '6 min', now() - interval '26 days' + interval '21 min',
  now() - interval '26 days' + interval '25 min', now() - interval '26 days' + interval '27 min',
  now() - interval '26 days' + interval '40 min',
  now() - interval '26 days' + interval '41 min',
  200.00, 0.15, 337.50, 2.4, 15
),
(
  '76dcf0a1-1939-47cd-89d9-3ec8e471dd60', '4fd35afb-8821-4b85-b8e3-5ec2787197c8',
  3500.00, 315.00, 450.00, 0, 4265.00, 'delivered',
  '5 Dunrobin Ave, Kingston', 18.0052, -76.7802,
  'wallet', 'paid', false,
  now() - interval '18 days', now() - interval '18 days' + interval '2 min',
  now() - interval '18 days' + interval '5 min', now() - interval '18 days' + interval '22 min',
  now() - interval '18 days' + interval '26 min', now() - interval '18 days' + interval '28 min',
  now() - interval '18 days' + interval '42 min',
  now() - interval '18 days' + interval '43 min',
  250.00, 0.15, 525.00, 2.9, 15
),
(
  '2aea96e5-f9bf-4a91-896b-7f89e656a479', '4fd35afb-8821-4b85-b8e3-5ec2787197c8',
  1800.00, 162.00, 400.00, 150.00, 2212.00, 'delivered',
  '22 Red Hills Rd, Kingston', 18.0301, -76.8012,
  'card', 'paid', false,
  now() - interval '12 days', now() - interval '12 days' + interval '3 min',
  now() - interval '12 days' + interval '6 min', now() - interval '12 days' + interval '20 min',
  now() - interval '12 days' + interval '24 min', now() - interval '12 days' + interval '26 min',
  now() - interval '12 days' + interval '38 min',
  now() - interval '12 days' + interval '39 min',
  100.00, 0.15, 270.00, 2.2, 13
),
(
  'f1ed8760-c7f6-4ff7-810e-33cc4c32d63e', '4fd35afb-8821-4b85-b8e3-5ec2787197c8',
  2600.00, 234.00, 400.00, 0, 3234.00, 'delivered',
  '9 Duhaney Park Ave, Kingston', 17.9876, -76.7689,
  'card', 'paid', false,
  now() - interval '8 days', now() - interval '8 days' + interval '2 min',
  now() - interval '8 days' + interval '5 min', now() - interval '8 days' + interval '20 min',
  now() - interval '8 days' + interval '24 min', now() - interval '8 days' + interval '26 min',
  now() - interval '8 days' + interval '38 min',
  now() - interval '8 days' + interval '39 min',
  150.00, 0.15, 390.00, 2.7, 14
),
(
  '39fa1191-926c-4f3b-aa25-1e0cb80f28d8', '4fd35afb-8821-4b85-b8e3-5ec2787197c8',
  4200.00, 378.00, 450.00, 300.00, 4728.00, 'delivered',
  '78 Barbican Rd, Kingston', 18.0114, -76.7628,
  'card', 'paid', false,
  now() - interval '4 days', now() - interval '4 days' + interval '3 min',
  now() - interval '4 days' + interval '7 min', now() - interval '4 days' + interval '23 min',
  now() - interval '4 days' + interval '27 min', now() - interval '4 days' + interval '29 min',
  now() - interval '4 days' + interval '43 min',
  now() - interval '4 days' + interval '44 min',
  300.00, 0.15, 630.00, 3.1, 16
),
(
  '76dcf0a1-1939-47cd-89d9-3ec8e471dd60', '4fd35afb-8821-4b85-b8e3-5ec2787197c8',
  1950.00, 175.50, 400.00, 0, 2525.50, 'completed',
  '5 Dunrobin Ave, Kingston', 18.0052, -76.7802,
  'card', 'paid', true,
  now() - interval '1 day', now() - interval '1 day' + interval '2 min',
  now() - interval '1 day' + interval '5 min', now() - interval '1 day' + interval '18 min',
  NULL, NULL, NULL,
  now() - interval '1 day' + interval '20 min',
  0, 0.15, 292.50, 0, 13
),

-- ── Rib Kage Barbican (403c1429-b8b8-46c3-a439-9bc9cfccba56) ─────────────
(
  '7c1d6980-7497-4ae4-909a-9c0e48be55b5', '403c1429-b8b8-46c3-a439-9bc9cfccba56',
  3200.00, 288.00, 450.00, 0, 3938.00, 'delivered',
  '12 Hope Rd, Kingston', 17.9969, -76.7741,
  'card', 'paid', false,
  now() - interval '25 days', now() - interval '25 days' + interval '3 min',
  now() - interval '25 days' + interval '7 min', now() - interval '25 days' + interval '25 min',
  now() - interval '25 days' + interval '29 min', now() - interval '25 days' + interval '31 min',
  now() - interval '25 days' + interval '46 min',
  now() - interval '25 days' + interval '47 min',
  250.00, 0.15, 480.00, 3.5, 18
),
(
  'dbbe53e0-76ea-49f0-98d8-e4453cc5bf57', '403c1429-b8b8-46c3-a439-9bc9cfccba56',
  2800.00, 252.00, 450.00, 0, 3502.00, 'delivered',
  '33 Maxfield Ave, Kingston', 17.9958, -76.8003,
  'wallet', 'paid', false,
  now() - interval '19 days', now() - interval '19 days' + interval '2 min',
  now() - interval '19 days' + interval '6 min', now() - interval '19 days' + interval '24 min',
  now() - interval '19 days' + interval '28 min', now() - interval '19 days' + interval '30 min',
  now() - interval '19 days' + interval '44 min',
  now() - interval '19 days' + interval '45 min',
  200.00, 0.15, 420.00, 3.3, 17
),
(
  '3df7b3b8-b1a6-4051-8af0-f878aef63a99', '403c1429-b8b8-46c3-a439-9bc9cfccba56',
  3800.00, 342.00, 500.00, 200.00, 4440.00, 'delivered',
  '67 Waltham Park Rd, Kingston', 18.0078, -76.8134,
  'card', 'paid', false,
  now() - interval '13 days', now() - interval '13 days' + interval '3 min',
  now() - interval '13 days' + interval '7 min', now() - interval '13 days' + interval '25 min',
  now() - interval '13 days' + interval '29 min', now() - interval '13 days' + interval '31 min',
  now() - interval '13 days' + interval '46 min',
  now() - interval '13 days' + interval '47 min',
  300.00, 0.15, 570.00, 3.8, 18
),
(
  '2aea96e5-f9bf-4a91-896b-7f89e656a479', '403c1429-b8b8-46c3-a439-9bc9cfccba56',
  2400.00, 216.00, 450.00, 0, 3066.00, 'delivered',
  '22 Red Hills Rd, Kingston', 18.0301, -76.8012,
  'card', 'paid', false,
  now() - interval '9 days', now() - interval '9 days' + interval '2 min',
  now() - interval '9 days' + interval '6 min', now() - interval '9 days' + interval '22 min',
  now() - interval '9 days' + interval '26 min', now() - interval '9 days' + interval '28 min',
  now() - interval '9 days' + interval '41 min',
  now() - interval '9 days' + interval '42 min',
  150.00, 0.15, 360.00, 3.0, 16
),
(
  'f1ed8760-c7f6-4ff7-810e-33cc4c32d63e', '403c1429-b8b8-46c3-a439-9bc9cfccba56',
  4500.00, 405.00, 500.00, 0, 5405.00, 'delivered',
  '9 Duhaney Park Ave, Kingston', 17.9876, -76.7689,
  'card', 'paid', false,
  now() - interval '6 days', now() - interval '6 days' + interval '3 min',
  now() - interval '6 days' + interval '7 min', now() - interval '6 days' + interval '27 min',
  now() - interval '6 days' + interval '31 min', now() - interval '6 days' + interval '33 min',
  now() - interval '6 days' + interval '49 min',
  now() - interval '6 days' + interval '50 min',
  400.00, 0.15, 675.00, 4.1, 20
),
(
  '7c1d6980-7497-4ae4-909a-9c0e48be55b5', '403c1429-b8b8-46c3-a439-9bc9cfccba56',
  3100.00, 279.00, 450.00, 0, 3829.00, 'delivered',
  '12 Hope Rd, Kingston', 17.9969, -76.7741,
  'card', 'paid', false,
  now() - interval '2 days', now() - interval '2 days' + interval '3 min',
  now() - interval '2 days' + interval '6 min', now() - interval '2 days' + interval '24 min',
  now() - interval '2 days' + interval '28 min', now() - interval '2 days' + interval '30 min',
  now() - interval '2 days' + interval '44 min',
  now() - interval '2 days' + interval '45 min',
  250.00, 0.15, 465.00, 3.5, 18
),
(
  'dbbe53e0-76ea-49f0-98d8-e4453cc5bf57', '403c1429-b8b8-46c3-a439-9bc9cfccba56',
  2200.00, 198.00, 450.00, 0, 2848.00, 'cancelled',
  '33 Maxfield Ave, Kingston', 17.9958, -76.8003,
  'card', 'refunded', false,
  now() - interval '1 day', now() - interval '1 day' + interval '2 min',
  NULL, NULL, NULL, NULL, NULL, NULL,
  0, 0.15, 330.00, 3.3, 17
);
