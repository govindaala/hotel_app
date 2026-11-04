CREATE OR REPLACE FUNCTION public.find_hotel_customer(p_store_code text, p_phone text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_phone text;
  v_customer jsonb;
BEGIN
  v_phone := right(regexp_replace(COALESCE(p_phone, ''), '[^0-9]', '', 'g'), 10);
  IF length(v_phone) <> 10 THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_build_object(
    'customer_name', customer_name,
    'customer_phone', customer_phone
  )
  INTO v_customer
  FROM public.invoices
  WHERE store_code = p_store_code
    AND right(regexp_replace(COALESCE(customer_phone, ''), '[^0-9]', '', 'g'), 10) = v_phone
    AND NULLIF(btrim(customer_name), '') IS NOT NULL
  ORDER BY created_at DESC
  LIMIT 1;

  RETURN v_customer;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.find_hotel_customer(text, text) TO anon, authenticated;
