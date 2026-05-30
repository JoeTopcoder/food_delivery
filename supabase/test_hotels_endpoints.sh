#!/usr/bin/env bash
# Example tests for Hotelbeds functions. Replace variables before running.

SUPABASE_URL="https://your-project.supabase.co"
JWT="<USER_JWT_HERE>" # Bearer token of an authenticated user

echo "Search hotels example"
curl -s -X POST "$SUPABASE_URL/functions/v1/hotelbeds-search" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"destination":"PMI","check_in":"2026-06-10","check_out":"2026-06-15","rooms":1,"adults":2}' | jq

echo "Check rate example (rate_key placeholder)"
curl -s -X POST "$SUPABASE_URL/functions/v1/hotelbeds-check-rate" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"rate_key":"<RATE_KEY_HERE>"}' | jq

echo "Get hotel content example"
curl -s -X POST "$SUPABASE_URL/functions/v1/hotelbeds-get-hotel-content" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"hotel_codes":["12345"]}' | jq

echo "Get booking (DB) example"
curl -s -X GET "$SUPABASE_URL/functions/v1/hotelbeds-get-booking?booking_id=<BOOKING_ID>" \
  -H "Authorization: Bearer $JWT" | jq

echo "Generate voucher (HTML) — open in browser by visiting the URL below"
echo "$SUPABASE_URL/functions/v1/hotelbeds-generate-voucher?booking_id=<BOOKING_ID>&format=html"

echo "Cancel booking example"
curl -s -X POST "$SUPABASE_URL/functions/v1/hotelbeds-cancel-booking" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"booking_id":"<BOOKING_ID>","cancellation_flag":"SIMULATION"}' | jq
