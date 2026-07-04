-- Change favorites.user_id FK from public.users → auth.users
-- Root cause: users may exist in auth.users but not in public.users
-- (e.g. created before the handle_new_user trigger was deployed).
-- auth.users always has a row for any authenticated session.

ALTER TABLE public.favorites
  DROP CONSTRAINT IF EXISTS favorites_user_id_fkey;

ALTER TABLE public.favorites
  ADD CONSTRAINT favorites_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
