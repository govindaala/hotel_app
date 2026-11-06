# AALA POS Python Intelligence Engine

A stateless FastAPI service that analyses POS aggregates and returns a hotel-owner PDF report.

## What it currently measures

- Invoice revenue, order count, average bill and payment mix
- Dish-wise quantity and sales ranking
- Recorded received-ration purchase costs and pending ration demands
- Recorded operating expenses
- KOT preparation-time observations and cancelled/void KOT counts
- Rule-based operational recommendations

## Important limitation

The current Flutter/Supabase data model does **not** provide a complete recipe/BOM, ingredient stock ledger, opening/closing stock count, or weighed food-waste log. The report therefore labels food waste as **not measurable** and never invents a waste amount. A measured waste report requires those additional records.

## Run locally

\`\`\`bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
pytest -q
\`\`\`

Health: \`GET /health\`

PDF: \`POST /v1/report.pdf\` with JSON fields:
\`store_code\`, \`hotel_name\`, \`period_label\`, \`start_date\`, \`end_date\`,
\`invoices[]\`, \`invoice_items[]\`, \`purchases[]\`, \`expenses[]\`, \`kots[]\`.

The service is stateless: request data is processed in memory and is not written to a database or filesystem. The app should send only store-scoped business data and must not send customer names, phone numbers, or payment credentials.

## Render

Create a Render Web Service from this repository with:
- Root Directory: \`python_intelligence\`
- Runtime: Python
- Build command: \`pip install -r requirements.txt\`
- Start command: \`uvicorn main:app --host 0.0.0.0 --port $PORT\`
- Health check path: \`/health\`

After deployment, set Flutter build define:
\`--dart-define=AALA_INTELLIGENCE_API_URL=https://YOUR-RENDER-SERVICE.onrender.com\`

Do not put Supabase service-role keys in the Android app. This service does not need database credentials.
