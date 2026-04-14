-- Update receipt number trigger to use GRO- prefix for grocery store orders
CREATE OR REPLACE FUNCTION generate_receipt_number()
RETURNS TRIGGER AS $$
DECLARE
  prefix TEXT;
  store_t TEXT;
BEGIN
  IF NEW.status = 'delivered' AND OLD.status != 'delivered' AND NEW.receipt_number IS NULL THEN
    -- Check the store type
    SELECT store_type INTO store_t FROM restaurants WHERE id = NEW.restaurant_id;
    IF store_t = 'grocery' THEN
      prefix := 'GRO-';
    ELSE
      prefix := 'FD-';
    END IF;

    NEW.receipt_number := prefix || TO_CHAR(now(), 'YYYYMMDD') || '-' || LPAD(
      (SELECT COUNT(*) + 1 FROM orders WHERE DATE(ordered_at) = CURRENT_DATE AND receipt_number IS NOT NULL)::TEXT,
      4, '0'
    );
    NEW.receipt_generated_at := now();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
