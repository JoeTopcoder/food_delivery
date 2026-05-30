-- orders.order_group_id now holds master_orders.id (new schema) as well as
-- legacy order_groups.id. Drop the FK so both schemas can coexist.
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_order_group_id_fkey;
