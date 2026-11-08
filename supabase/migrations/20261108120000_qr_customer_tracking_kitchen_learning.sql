-- QR customer tracking, hotel facts, and durable kitchen-learning observations.
ALTER TABLE public.qr_orders
  ADD COLUMN IF NOT EXISTS accepted_at timestamptz,
  ADD COLUMN IF NOT EXISTS estimated_wait_minutes integer,
  ADD COLUMN IF NOT EXISTS estimated_prep_minutes integer,
  ADD COLUMN IF NOT EXISTS estimated_queue_minutes integer,
  ADD COLUMN IF NOT EXISTS estimated_ready_at timestamptz,
  ADD COLUMN IF NOT EXISTS ready_at timestamptz,
  ADD COLUMN IF NOT EXISTS kot_id text,
  ADD COLUMN IF NOT EXISTS customer_facts_snapshot jsonb;

ALTER TABLE public.hotel_kots
  ADD COLUMN IF NOT EXISTS qr_order_id text,
  ADD COLUMN IF NOT EXISTS started_at timestamptz,
  ADD COLUMN IF NOT EXISTS ready_at timestamptz,
  ADD COLUMN IF NOT EXISTS actual_prep_minutes integer;

ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS customer_facts jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS show_customer_timer boolean NOT NULL DEFAULT true;

CREATE INDEX IF NOT EXISTS qr_orders_store_status_created_idx
  ON public.qr_orders (store_code, status, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS hotel_kots_store_qr_order_unique_idx
  ON public.hotel_kots (store_code, qr_order_id) WHERE qr_order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS hotel_kots_store_ready_created_idx
  ON public.hotel_kots (store_code, ready_at DESC)
  WHERE ready_at IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.kitchen_learning_observations (
  id bigserial PRIMARY KEY,
  store_code text NOT NULL,
  kot_id text NOT NULL,
  qr_order_id text,
  local_weekday smallint NOT NULL CHECK (local_weekday BETWEEN 1 AND 7),
  local_hour smallint NOT NULL CHECK (local_hour BETWEEN 0 AND 23),
  item_signature text NOT NULL DEFAULT '',
  items jsonb NOT NULL DEFAULT '[]'::jsonb,
  prep_minutes integer NOT NULL CHECK (prep_minutes BETWEEN 1 AND 240),
  order_acceptance_minutes integer,
  order_created_at timestamptz,
  accepted_at timestamptz,
  ready_at timestamptz NOT NULL,
  observed_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (store_code, kot_id)
);
CREATE INDEX IF NOT EXISTS kitchen_learning_bucket_idx
  ON public.kitchen_learning_observations
  (store_code, local_weekday, local_hour, ready_at DESC);
ALTER TABLE public.kitchen_learning_observations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.kitchen_learning_observations FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.kitchen_learning_observations TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.kitchen_learning_observations_id_seq TO service_role;

CREATE OR REPLACE FUNCTION public.capture_kitchen_learning_observation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_ready timestamptz;
  v_start timestamptz;
  v_minutes integer;
  v_qr_created timestamptz;
  v_accepted timestamptz;
  v_wait integer;
  v_items jsonb;
  v_signature text;
  v_local timestamptz;
BEGIN
  IF NEW.status IS DISTINCT FROM 'ready' THEN
    RETURN NEW;
  END IF;

  v_ready := COALESCE(NEW.ready_at, now());
  v_start := COALESCE(NEW.started_at, NEW.created_at, v_ready);
  v_minutes := GREATEST(1, LEAST(240, CEIL(EXTRACT(EPOCH FROM (v_ready - v_start)) / 60.0)::integer));
  v_items := CASE
    WHEN jsonb_typeof(to_jsonb(NEW.items)) = 'array' THEN to_jsonb(NEW.items)
    WHEN jsonb_typeof(to_jsonb(NEW.items)) = 'string' THEN
      CASE WHEN (to_jsonb(NEW.items)#>>'{}') ~ '^\\s*\\['
        THEN (to_jsonb(NEW.items)#>>'{}')::jsonb ELSE '[]'::jsonb END
    ELSE '[]'::jsonb
  END;
  SELECT string_agg(lower(COALESCE(item->>'name', item->>'item_name', '')), ',' ORDER BY lower(COALESCE(item->>'name', item->>'item_name', '')))
    INTO v_signature
    FROM jsonb_array_elements(v_items) AS x(item);

  IF NEW.qr_order_id IS NOT NULL THEN
    SELECT created_at, accepted_at
      INTO v_qr_created, v_accepted
      FROM public.qr_orders
     WHERE id::text = NEW.qr_order_id
       AND store_code = NEW.store_code
     LIMIT 1;
  END IF;
  IF v_qr_created IS NOT NULL AND v_accepted IS NOT NULL THEN
    v_wait := GREATEST(0, LEAST(240, CEIL(EXTRACT(EPOCH FROM (v_accepted - v_qr_created)) / 60.0)::integer));
  END IF;

  v_local := v_start AT TIME ZONE 'Asia/Kolkata';

  INSERT INTO public.kitchen_learning_observations (
    store_code, kot_id, qr_order_id, local_weekday, local_hour,
    item_signature, items, prep_minutes, order_acceptance_minutes,
    order_created_at, accepted_at, ready_at
  ) VALUES (
    NEW.store_code, NEW.id::text, NEW.qr_order_id,
    EXTRACT(ISODOW FROM v_local)::smallint,
    EXTRACT(HOUR FROM v_local)::smallint,
    COALESCE(v_signature, ''), COALESCE(v_items, '[]'::jsonb),
    v_minutes, v_wait, v_qr_created, v_accepted, v_ready
  )
  ON CONFLICT (store_code, kot_id) DO UPDATE SET
    local_weekday = EXCLUDED.local_weekday,
    local_hour = EXCLUDED.local_hour,
    item_signature = EXCLUDED.item_signature,
    items = EXCLUDED.items,
    prep_minutes = EXCLUDED.prep_minutes,
    order_acceptance_minutes = EXCLUDED.order_acceptance_minutes,
    order_created_at = EXCLUDED.order_created_at,
    accepted_at = EXCLUDED.accepted_at,
    ready_at = EXCLUDED.ready_at,
    observed_at = now();

  UPDATE public.hotel_kots
     SET ready_at = v_ready, actual_prep_minutes = v_minutes
   WHERE id = NEW.id AND (ready_at IS DISTINCT FROM v_ready OR actual_prep_minutes IS DISTINCT FROM v_minutes);
  IF NEW.qr_order_id IS NOT NULL THEN
    UPDATE public.qr_orders
       SET ready_at = v_ready, status = 'READY'
     WHERE id::text = NEW.qr_order_id AND store_code = NEW.store_code;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS hotel_kots_capture_kitchen_learning ON public.hotel_kots;
CREATE TRIGGER hotel_kots_capture_kitchen_learning
AFTER UPDATE OF status ON public.hotel_kots
FOR EACH ROW
WHEN (NEW.status = 'ready' AND OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION public.capture_kitchen_learning_observation();

NOTIFY pgrst, 'reload schema';
