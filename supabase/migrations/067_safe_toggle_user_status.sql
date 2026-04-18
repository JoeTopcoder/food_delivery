-- ====================================================================
-- Migration 067: Safe toggle_user_status RPC
-- Guarantees exactly ONE user is updated per call (prevents mass-ban bug).
-- ====================================================================

CREATE OR REPLACE FUNCTION public.admin_toggle_user_status(
  p_user_id UUID,
  p_is_active BOOLEAN
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role TEXT;
  v_updated_id  UUID;
BEGIN
  -- 1. Verify caller is an admin
  SELECT role INTO v_caller_role
    FROM public.users
   WHERE id = auth.uid();

  IF v_caller_role IS NULL OR v_caller_role != 'admin' THEN
    RAISE EXCEPTION 'Permission denied: only admins can ban/unban users';
  END IF;

  -- 2. Prevent banning yourself
  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot ban/unban yourself';
  END IF;

  -- 3. Update exactly one user by primary key and return the id
  UPDATE public.users
     SET is_active  = p_is_active,
         updated_at = now()
   WHERE id = p_user_id
  RETURNING id INTO v_updated_id;

  IF v_updated_id IS NULL THEN
    RAISE EXCEPTION 'User not found: %', p_user_id;
  END IF;

  RETURN v_updated_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_toggle_user_status(UUID, BOOLEAN) TO authenticated;
