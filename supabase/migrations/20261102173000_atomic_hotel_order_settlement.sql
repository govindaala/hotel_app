-- Repository path: hotel_app/supabase/migrations/20261102173000_atomic_hotel_order_settlement.sql
-- Atomically save invoice, invoice items, KOT status, and cash/UPI ledger entry.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.invoices
    GROUP BY store_code, bill_no
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Cannot add invoice idempotency index: duplicate (store_code, bill_no) records exist. Resolve duplicates before applying this migration.';
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS invoices_store_code_bill_no_uidx
  ON public.invoices (store_code, bill_no);

CREATE OR REPLACE FUNCTION public.settle_hotel_order(
  p_invoice jsonb,
  p_items jsonb,
  p_source text,
  p_partner_name text,
  p_partner_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_store_code text;
  v_bill_no text;
  v_table_no integer;
  v_invoice_id uuid;
  v_item_count integer;
  v_amount numeric;
  v_payment_mode text;
BEGIN
  IF jsonb_typeof(p_invoice) <> 'object' THEN
    RAISE EXCEPTION 'Invoice payload must be a JSON object';
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Invoice must contain at least one item';
  END IF;

  v_store_code := NULLIF(btrim(p_invoice->>'store_code'), '');
  v_bill_no := NULLIF(btrim(p_invoice->>'bill_no'), '');
  v_table_no := (p_invoice->>'table_no')::integer;
  v_payment_mode := upper(p_invoice->>'payment_mode');
  v_amount := (p_invoice->>'final_amount')::numeric;

  IF v_store_code IS NULL OR v_bill_no IS NULL OR v_table_no IS NULL THEN
    RAISE EXCEPTION 'Store, bill number, and table number are required';
  END IF;
  IF v_payment_mode NOT IN ('CASH', 'UPI') THEN
    RAISE EXCEPTION 'Unsupported payment mode: %', v_payment_mode;
  END IF;
  IF v_amount < 0 THEN
    RAISE EXCEPTION 'Invoice amount cannot be negative';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_items) AS elements(item)
    WHERE COALESCE((item->>'qty')::integer, 0) <= 0
       OR COALESCE((item->>'price')::numeric, -1) < 0
  ) THEN
    RAISE EXCEPTION 'Invoice item quantity or price is invalid';
  END IF;

  INSERT INTO public.invoices (
    store_code, bill_no, table_no, waiter_id, cashier_partner_id,
    cashier_partner_name, subtotal, discount_pct, discount_amt,
    final_amount, payment_mode, created_at
  )
  VALUES (
    v_store_code, v_bill_no, v_table_no,
    NULLIF(p_invoice->>'waiter_id', ''),
    NULLIF(p_invoice->>'cashier_partner_id', ''),
    NULLIF(p_invoice->>'cashier_partner_name', ''),
    COALESCE((p_invoice->>'subtotal')::numeric, 0),
    COALESCE((p_invoice->>'discount_pct')::numeric, 0),
    COALESCE((p_invoice->>'discount_amt')::numeric, 0),
    v_amount, v_payment_mode,
    COALESCE((p_invoice->>'created_at')::timestamptz, now())
  )
  ON CONFLICT (store_code, bill_no) DO NOTHING
  RETURNING id INTO v_invoice_id;

  IF v_invoice_id IS NULL THEN
    SELECT id INTO v_invoice_id
    FROM public.invoices
    WHERE store_code = v_store_code AND bill_no = v_bill_no;

    SELECT count(*) INTO v_item_count
    FROM public.invoice_items
    WHERE invoice_id = v_invoice_id;

    IF v_item_count = 0 THEN
      RAISE EXCEPTION 'Bill number already exists without invoice items; manual reconciliation required';
    END IF;

    RETURN jsonb_build_object('invoice_id', v_invoice_id, 'already_settled', true);
  END IF;

  INSERT INTO public.invoice_items (
    invoice_id, item_id, item_name, category, price, qty, total_price
  )
  SELECT
    v_invoice_id,
    NULLIF(item->>'item_id', ''),
    COALESCE(item->>'item_name', ''),
    COALESCE(item->>'category', 'General'),
    COALESCE((item->>'price')::numeric, 0),
    (item->>'qty')::integer,
    COALESCE((item->>'total_price')::numeric, 0)
  FROM jsonb_array_elements(p_items) AS elements(item);

  UPDATE public.hotel_kots
  SET status = 'settled'
  WHERE store_code = v_store_code
    AND table_no = v_table_no
    AND status IS DISTINCT FROM 'settled';

  INSERT INTO public.daily_expenses (
    restaurant_id, store_code, title, amount, type, created_at, created_by_partner
  )
  VALUES (
    v_store_code,
    v_store_code,
    COALESCE(p_source, 'Hotel Sale') || ' Sale (' || v_payment_mode ||
      ') [प्रभारी: ' || COALESCE(p_partner_name, '') || ']',
    v_amount,
    'CASH_IN',
    COALESCE((p_invoice->>'created_at')::timestamptz, now()),
    NULLIF(p_partner_id, '')
  );

  RETURN jsonb_build_object('invoice_id', v_invoice_id, 'already_settled', false);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.settle_hotel_order(jsonb, jsonb, text, text, text)
  TO anon, authenticated;
