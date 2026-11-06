-- Custom menu persistence and kitchen completion metrics.
CREATE TABLE IF NOT EXISTS public.store_custom_menu_items (
  store_code text NOT NULL,
  item_id text NOT NULL,
  name text NOT NULL,
  price numeric(12,2) NOT NULL DEFAULT 0 CHECK (price >= 0),
  category text NOT NULL DEFAULT 'General',
  is_available boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_code, item_id)
);
CREATE INDEX IF NOT EXISTS store_custom_menu_items_store_available_idx
  ON public.store_custom_menu_items (store_code, is_available, name);
ALTER TABLE public.store_custom_menu_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anon all access on store_custom_menu_items" ON public.store_custom_menu_items;
CREATE POLICY "Anon all access on store_custom_menu_items"
  ON public.store_custom_menu_items FOR ALL TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Authenticated all access on store_custom_menu_items" ON public.store_custom_menu_items;
CREATE POLICY "Authenticated all access on store_custom_menu_items"
  ON public.store_custom_menu_items FOR ALL TO authenticated USING (true) WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.store_custom_menu_items TO anon, authenticated;
CREATE OR REPLACE FUNCTION public.touch_store_custom_menu_item_updated_at()
RETURNS trigger LANGUAGE plpgsql
SET search_path = public, pg_temp AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS store_custom_menu_items_touch_updated_at ON public.store_custom_menu_items;
CREATE TRIGGER store_custom_menu_items_touch_updated_at
BEFORE UPDATE ON public.store_custom_menu_items
FOR EACH ROW EXECUTE FUNCTION public.touch_store_custom_menu_item_updated_at();
ALTER TABLE public.hotel_kots
  ADD COLUMN IF NOT EXISTS ready_at timestamptz,
  ADD COLUMN IF NOT EXISTS actual_prep_minutes integer;
CREATE INDEX IF NOT EXISTS hotel_kots_store_status_created_idx
  ON public.hotel_kots (store_code, status, created_at DESC);
NOTIFY pgrst, 'reload schema';
