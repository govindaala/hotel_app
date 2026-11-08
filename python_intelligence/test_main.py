from main import ReportRequest, analyze, build_pdf, _percentile, _item_names


def sample_payload():
    return ReportRequest(
        store_code="TEST-01",
        hotel_name="Test Hotel",
        period_label="This month",
        start_date="2026-11-01",
        end_date="2026-11-06",
        invoices=[{"final_amount": 500, "payment_mode": "CASH"}],
        invoice_items=[{"item_name": "Tea", "qty": 4, "total_price": 100}],
        purchases=[{"item_name": "Milk", "purchase_cost": 50, "is_received": True}],
        expenses=[{"title": "Gas", "amount": 100, "type": "EXPENSE_CASH"}],
        kots=[{"status": "ready", "actual_prep_minutes": 22}],
    )


def test_existing_report_analysis_and_pdf():
    result = analyze(sample_payload())
    assert result["revenue"] == 500
    assert result["avg_prep"] == 22
    assert build_pdf(sample_payload()).startswith(b"%PDF-")


def test_kitchen_percentile_is_conservative_and_bounded():
    assert _percentile([5, 10, 15, 20]) == 20
    assert _percentile([]) == 0


def test_item_names_normalize_and_ignore_blank():
    assert _item_names([{"name": "Paneer Tikka"}, {"item_name": " Tea "}, {"name": ""}]) == {
        "paneer tikka", "tea"
    }
