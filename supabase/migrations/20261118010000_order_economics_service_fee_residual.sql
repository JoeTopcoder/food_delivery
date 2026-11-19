-- The food/grocery order flows charge a service fee into total_amount but don't
-- persist it to orders.platform_service_fee (it's NULL on real orders), so the
-- admin contribution read it as 0. The admin order-detail UI already handles this
-- by DERIVING the service fee as the residual that reconciles the stored total
-- (total - subtotal - delivery - tax - tip + discount). admin_order_economics now
-- does the same: use the stored platform_service_fee when present, else the
-- residual. This makes service fee flow into contribution for every existing
-- order with no app change and no backfill.
CREATE OR REPLACE FUNCTION public.admin_order_economics(
  p_from timestamp with time zone,
  p_to   timestamp with time zone,
  p_grocery boolean)
 RETURNS TABLE(order_id uuid, gmv bigint, commission bigint, delivery_fee bigint,
   service_fee bigint, rider_payout bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT o.id,
         ROUND(COALESCE(o.subtotal, 0)::numeric * 100)::bigint,
         ROUND(COALESCE(o.commission_amount,
                        COALESCE(o.subtotal, 0) * COALESCE(o.commission_rate, 0)
               )::numeric * 100)::bigint,
         ROUND(COALESCE(o.delivery_fee, 0)::numeric * 100)::bigint,
         -- Service fee: stored value when set, otherwise the residual that
         -- reconciles the total (mirrors the admin order-detail breakdown).
         ROUND(
           CASE
             WHEN COALESCE(o.platform_service_fee, 0) <> 0 THEN o.platform_service_fee
             ELSE GREATEST(
                    COALESCE(o.total_amount, 0)
                  - COALESCE(o.subtotal, 0)
                  - COALESCE(o.delivery_fee, 0)
                  - COALESCE(o.tax_amount, 0)
                  - COALESCE(o.driver_tip, 0)
                  + COALESCE(o.discount, 0), 0)
           END::numeric * 100
         )::bigint,
         -- Tips pass through to the rider and are not a platform cost, so they
         -- come out of payout rather than counting against contribution.
         GREATEST(
           ROUND((COALESCE(o.driver_total_pay, 0)
                - COALESCE(o.driver_tip, 0)
                - COALESCE(o.post_delivery_tip, 0))::numeric * 100)::bigint, 0)
  FROM public.orders o
  JOIN public.restaurants r ON r.id = o.restaurant_id
  WHERE o.ordered_at >= p_from
    AND o.ordered_at <  p_to
    AND o.status <> 'cancelled'
    AND (CASE WHEN p_grocery THEN r.store_type =  'grocery'
                             ELSE r.store_type <> 'grocery' END);
$function$;

NOTIFY pgrst, 'reload schema';
