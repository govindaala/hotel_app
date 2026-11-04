ALTER TABLE public.hotel_kots
  ADD COLUMN IF NOT EXISTS customer_name text,
  ADD COLUMN IF NOT EXISTS customer_phone text;

CREATE INDEX IF NOT EXISTS invoices_store_customer_phone_idx
  ON public.invoices (store_code, (right(regexp_replace(COALESCE(customer_phone, ''), '[^0-9]', '', 'g'), 10)))
  WHERE customer_phone IS NOT NULL AND customer_phone <> '';

CREATE INDEX IF NOT EXISTS hotel_kots_store_customer_phone_idx
  ON public.hotel_kots (store_code, (right(regexp_replace(COALESCE(customer_phone, ''), '[^0-9]', '', 'g'), 10)))
  WHERE customer_phone IS NOT NULL AND customer_phone <> '';

NOTIFY pgrst, 'reload schema';
