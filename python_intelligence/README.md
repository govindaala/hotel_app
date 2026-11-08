# AALA POS Python Intelligence

FastAPI service for the hotel-owner intelligence reports and weekday/hour/dish-aware kitchen ETA.

## Kitchen learning flow

1. The Supabase migration adds `kitchen_learning_observations`.
2. When a KOT changes to `ready`, a database trigger records its start/ready timestamps, weekday, hour, dish list, actual preparation minutes, and (for QR orders) the time between customer submission and waiter acceptance.
3. `POST /v1/kitchen/estimate` reads only that hotel's recent observations and returns separate acceptance-wait, learned queue-wait, and preparation estimates. Same weekday/hour and matching dishes are preferred; sparse buckets fall back to the hotel's wider history. Confidence and sample counts are returned.
4. `GET /v1/kitchen/summary/{store_code}` exposes owner-dashboard learning coverage by weekday/hour.

Customer status is fetched through a token-gated RPC and refreshed every five seconds; the token is random and never grants access to other orders. The service never reads or returns customer names, phone numbers, payment credentials, or full bill data for ETA calculation. Supabase service-role credentials belong only in Render environment variables, never in Flutter or the customer web page.

## Required Render environment variables

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

The service is configured as a free Render web service in `render.yaml`. If the two variables are absent, health checks still work but kitchen estimates return HTTP 503 and the app uses its local fallback estimate.

## Local run

```bash
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
pytest -q
```

Set Flutter build define to the deployed URL:
`--dart-define=AALA_INTELLIGENCE_API_URL=https://YOUR-RENDER-SERVICE.onrender.com`

Apply the Supabase migration before deploying the customer page or app changes. No production migration or deployment is performed by this branch.
