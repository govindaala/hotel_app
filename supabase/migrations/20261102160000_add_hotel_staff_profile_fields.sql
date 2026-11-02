-- Add staff profile fields required by the hotel POS app.
-- Safe additive migration: existing staff records and PINs are preserved.

ALTER TABLE public.hotel_staff
  ADD COLUMN IF NOT EXISTS name text;

ALTER TABLE public.hotel_staff
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;

UPDATE public.hotel_staff
SET name = staff_id
WHERE name IS NULL OR btrim(name) = '';
