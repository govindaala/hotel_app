from main import ReportRequest, analyze, build_pdf


def sample_payload():
    return ReportRequest(
        store_code="TEST-01",
        hotel_name="Test Hotel",
        period_label="This month",
        start_date="2026-11-01",
        end_date="2026-11-06",
        invoices=[
            {"final_amount": 500, "payment_mode": "CASH"},
            {"final_amount": 300, "payment_mode": "UPI"},
        ],
        invoice_items=[
            {"item_name": "Paneer Tikka", "qty": 2, "total_price": 400, "category": "Snacks"},
            {"item_name": "Tea", "qty": 4, "total_price": 100, "category": "Beverages"},
        ],
        purchases=[
            {"item_name": "Paneer", "purchase_cost": 250, "is_received": True},
            {"item_name": "Tomato", "purchase_cost": 50, "is_received": False},
        ],
        expenses=[{"title": "Gas", "amount": 100, "type": "EXPENSE_CASH"}],
        kots=[{"status": "ready", "actual_prep_minutes": 22}],
    )


def test_analyze_totals_and_data_gaps():
    result = analyze(sample_payload())
    assert result["revenue"] == 800
    assert result["order_count"] == 2
    assert result["purchase_spend"] == 250
    assert result["expense_spend"] == 100
    assert result["pending_purchase_count"] == 1
    assert result["avg_prep"] == 22


def test_pdf_is_valid_pdf_bytes():
    pdf = build_pdf(sample_payload())
    assert pdf.startswith(b"%PDF-")
    assert len(pdf) > 1000
