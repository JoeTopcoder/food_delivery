-- Keep chain branches (same chain_id, e.g. all Little Tokyo / KFC / Island Grill
-- locations) from drifting apart on PRICE. The customer sees one brand card that
-- resolves to the nearest branch, so a per-branch price mismatch shows as the
-- price "changing" when their location changes. When any branch's price fields
-- are edited, propagate them to the sibling branches' item of the same name.
--
-- Only price fields are synced (price, member price, discount). is_available is
-- intentionally NOT synced — a single branch can be out of an item while others
-- still have it.

CREATE OR REPLACE FUNCTION sync_chain_menu_prices()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_chain text;
BEGIN
  SELECT chain_id INTO v_chain FROM restaurants WHERE id = NEW.restaurant_id;
  IF v_chain IS NULL OR v_chain = '' THEN
    RETURN NEW;
  END IF;

  UPDATE menus m
     SET price              = NEW.price,
         hotbite_plus_price = NEW.hotbite_plus_price,
         discount           = NEW.discount,
         updated_at         = now()
    FROM restaurants r
   WHERE m.restaurant_id = r.id
     AND r.chain_id = v_chain
     AND m.name = NEW.name
     AND m.id <> NEW.id
     AND ( m.price IS DISTINCT FROM NEW.price
        OR m.hotbite_plus_price IS DISTINCT FROM NEW.hotbite_plus_price
        OR m.discount IS DISTINCT FROM NEW.discount );

  RETURN NEW;
END $$;

-- pg_trigger_depth() = 0 so the cascaded UPDATE above (depth 1) does not re-fire
-- the trigger — no recursion.
DROP TRIGGER IF EXISTS trg_sync_chain_menu_prices ON menus;
CREATE TRIGGER trg_sync_chain_menu_prices
AFTER UPDATE OF price, hotbite_plus_price, discount ON menus
FOR EACH ROW
WHEN (pg_trigger_depth() = 0)
EXECUTE FUNCTION sync_chain_menu_prices();

NOTIFY pgrst, 'reload schema';
