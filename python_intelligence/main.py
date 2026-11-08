from __future__ import annotations

import html
import json
import io
import os
import time
from collections import defaultdict
from datetime import datetime, timezone, timedelta
from zoneinfo import ZoneInfo
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse
import httpx
from pydantic import BaseModel, Field, ConfigDict
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, KeepTogether
)

app = FastAPI(
    title="AALA POS Hotel Intelligence",
    version="1.0.0",
    description="Stateless sales, purchasing and kitchen-operations analysis for AALA POS.",
)

# Stateless, best-effort per-process throttling. No business payloads are persisted.
_RATE_BUCKETS: dict[str, list[float]] = defaultdict(list)
_RATE_LIMIT = 12
_RATE_WINDOW_SECONDS = 60


class ReportRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")
    store_code: str = Field(min_length=1, max_length=64)
    hotel_name: str = Field(default="Hotel", max_length=120)
    period_label: str = Field(default="Selected period", max_length=80)
    start_date: str = Field(max_length=40)
    end_date: str = Field(max_length=40)
    invoices: list[dict[str, Any]] = Field(default_factory=list, max_length=5000)
    invoice_items: list[dict[str, Any]] = Field(default_factory=list, max_length=20000)
    purchases: list[dict[str, Any]] = Field(default_factory=list, max_length=5000)
    expenses: list[dict[str, Any]] = Field(default_factory=list, max_length=10000)
    kots: list[dict[str, Any]] = Field(default_factory=list, max_length=10000)


def _number(row: dict[str, Any], key: str) -> float:
    try:
        value = float(row.get(key) or 0)
        return value if value == value and abs(value) != float("inf") else 0.0
    except (TypeError, ValueError):
        return 0.0


def _text(row: dict[str, Any], key: str, fallback: str = "") -> str:
    value = row.get(key)
    return str(value).strip() if value is not None else fallback


def _register_font() -> str:
    if getattr(_register_font, '_registered_name', None):
        return _register_font._registered_name
    candidates = [
        Path(__file__).resolve().parents[1] / "assets/templates/fonts/NotoSansDevanagari-Regular.ttf",
        Path(__file__).resolve().parent / "NotoSansDevanagari-Regular.ttf",
    ]
    for candidate in candidates:
        if candidate.exists():
            try:
                pdfmetrics.registerFont(TTFont("AalaHindi", str(candidate)))
                _register_font._registered_name = "AalaHindi"
                return "AalaHindi"
            except Exception:
                continue
    return "Helvetica"


def analyze(data: ReportRequest) -> dict[str, Any]:
    revenue = sum(max(0.0, _number(row, "final_amount")) for row in data.invoices)
    order_count = len([r for r in data.invoices if _number(r, "final_amount") >= 0])
    average_bill = revenue / order_count if order_count else 0.0

    payments: dict[str, float] = defaultdict(float)
    for row in data.invoices:
        mode = _text(row, "payment_mode", "UNKNOWN").upper()
        payments[mode] += max(0.0, _number(row, "final_amount"))

    item_stats: dict[str, dict[str, Any]] = {}
    for row in data.invoice_items:
        name = _text(row, "item_name", "Unnamed item")
        entry = item_stats.setdefault(name, {
            "name": name, "qty": 0.0, "sales": 0.0, "category": _text(row, "category", "Other")
        })
        entry["qty"] += max(0.0, _number(row, "qty"))
        entry["sales"] += max(0.0, _number(row, "total_price"))

    top_items = sorted(item_stats.values(), key=lambda x: x["sales"], reverse=True)
    received_purchases = [r for r in data.purchases if bool(r.get("is_received"))]
    pending_purchases = [r for r in data.purchases if not bool(r.get("is_received"))]
    purchase_spend = sum(max(0.0, _number(r, "purchase_cost")) for r in received_purchases)
    expense_spend = sum(
        max(0.0, _number(r, "amount"))
        for r in data.expenses
        if _text(r, "type").upper().startswith("EXPENSE")
    )
    purchase_by_item: dict[str, float] = defaultdict(float)
    for row in received_purchases:
        purchase_by_item[_text(row, "item_name", "Unspecified purchase")] += max(
            0.0, _number(row, "purchase_cost")
        )

    prep_values = [
        _number(r, "actual_prep_minutes")
        for r in data.kots
        if r.get("actual_prep_minutes") is not None
        and 0 < _number(r, "actual_prep_minutes") < 240
    ]
    avg_prep = sum(prep_values) / len(prep_values) if prep_values else None
    cancelled = sum(
        1 for r in data.kots
        if _text(r, "status").lower() in {"cancelled", "canceled", "void", "rejected"}
    )

    recommendations: list[str] = []
    if revenue > 0 and purchase_spend / revenue > 0.35:
        recommendations.append(
            "Recorded ration purchase cost is above 35% of sales for this period. "
            "Check opening/closing stock, purchase timing, portion sizes and unrecorded transfers."
        )
    elif revenue > 0 and purchase_spend / revenue > 0.25:
        recommendations.append(
            "Recorded ration purchase cost is 25–35% of sales. Review high-cost ingredients "
            "and compare purchase quantities with actual stock movement."
        )
    if pending_purchases:
        recommendations.append(
            f"{len(pending_purchases)} ration demand record(s) are still marked not received. "
            "Confirm whether they were delivered before placing repeat orders."
        )
    if avg_prep is not None and avg_prep > 20:
        recommendations.append(
            f"Average recorded KOT preparation time is {avg_prep:.1f} minutes. "
            "Review peak-hour staffing, mise-en-place and slow preparation stations."
        )
    if cancelled:
        recommendations.append(
            f"{cancelled} KOT record(s) have a cancelled/void status. Review reasons and "
            "whether preparation started before cancellation."
        )
    if top_items:
        slow_items = [x["name"] for x in top_items[-5:] if x["qty"] > 0]
        if slow_items:
            recommendations.append(
                "Use the lowest-selling dishes shown in this report to review menu complexity "
                "and perishable ingredient exposure; low sales alone do not prove wastage."
            )
    if not recommendations:
        recommendations.append(
            "No high-confidence operational warning was triggered by the supplied records. "
            "Continue recording purchases, stock counts, recipes and waste to improve accuracy."
        )

    return {
        "revenue": revenue,
        "order_count": order_count,
        "average_bill": average_bill,
        "payments": dict(payments),
        "top_items": top_items,
        "purchase_spend": purchase_spend,
        "expense_spend": expense_spend,
        "purchase_by_item": sorted(
            purchase_by_item.items(), key=lambda x: x[1], reverse=True
        ),
        "pending_purchase_count": len(pending_purchases),
        "avg_prep": avg_prep,
        "prep_observation_count": len(prep_values),
        "cancelled_kots": cancelled,
        "recommendations": recommendations,
        "item_row_count": len(data.invoice_items),
    }


def build_pdf(data: ReportRequest) -> bytes:
    font_name = _register_font()
    metrics = analyze(data)
    output = io.BytesIO()
    doc = SimpleDocTemplate(
        output, pagesize=A4, rightMargin=16 * mm, leftMargin=16 * mm,
        topMargin=15 * mm, bottomMargin=15 * mm, title="AALA POS Intelligence Report"
    )
    styles = getSampleStyleSheet()
    styles.add(ParagraphStyle(
        name="AalaTitle", parent=styles["Title"], fontName=font_name,
        fontSize=17, leading=23, alignment=TA_CENTER, textColor=colors.HexColor("#123047")
    ))
    styles.add(ParagraphStyle(
        name="AalaBody", parent=styles["BodyText"], fontName=font_name,
        fontSize=8.5, leading=13, spaceAfter=4
    ))
    styles.add(ParagraphStyle(
        name="AalaHead", parent=styles["Heading2"], fontName=font_name,
        fontSize=11, leading=15, textColor=colors.HexColor("#14536B"), spaceBefore=9, spaceAfter=5
    ))
    styles.add(ParagraphStyle(
        name="AalaSmall", parent=styles["BodyText"], fontName=font_name,
        fontSize=7.5, leading=10
    ))

    story = [
        Paragraph("AALA POS — HOTEL INTELLIGENCE REPORT", styles["AalaTitle"]),
        Paragraph(
            f"<b>{html.escape(data.hotel_name)}</b> &nbsp; | &nbsp; "
            f"Store: {html.escape(data.store_code)}",
            styles["AalaBody"]
        ),
        Paragraph(
            f"Period: {html.escape(data.period_label)} "
            f"({html.escape(data.start_date)} to {html.escape(data.end_date)})",
            styles["AalaBody"]
        ),
        Paragraph(
            "This report analyses only the records supplied by the POS. "
            "It does not invent missing stock, recipe or food-waste figures.",
            styles["AalaSmall"]
        ),
        Spacer(1, 7),
    ]

    summary_rows = [
        ["Metric", "Recorded value"],
        ["Net sales / invoice total", f"INR {metrics['revenue']:,.2f}"],
        ["Bills / orders", f"{metrics['order_count']:,}"],
        ["Average bill value", f"INR {metrics['average_bill']:,.2f}"],
        ["Recorded received-ration purchase cost", f"INR {metrics['purchase_spend']:,.2f}"],
        ["Recorded operating expenses", f"INR {metrics['expense_spend']:,.2f}"],
        ["Received ration purchase cost / sales",
         f"{(metrics['purchase_spend'] / metrics['revenue'] * 100):.1f}%"
         if metrics["revenue"] else "Not available (no sales)"],
    ]
    story += [Paragraph("1. Business snapshot", styles["AalaHead"])]
    table = Table(summary_rows, colWidths=[100 * mm, 65 * mm], repeatRows=1)
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#123047")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, -1), font_name),
        ("FONTSIZE", (0, 0), (-1, -1), 8),
        ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#D5DEE5")),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F3F7F9")]),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 7),
        ("RIGHTPADDING", (0, 0), (-1, -1), 7),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))
    story += [table, Paragraph("2. Payment mix", styles["AalaHead"])]

    payment_rows = [["Payment mode", "Amount (INR)"]]
    payment_rows += [[html.escape(k), f"{v:,.2f}"] for k, v in sorted(metrics["payments"].items())]
    if len(payment_rows) == 1:
        payment_rows.append(["No payment records", "—"])
    ptable = Table(payment_rows, colWidths=[100 * mm, 65 * mm], repeatRows=1)
    ptable.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#14536B")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, -1), font_name),
        ("FONTSIZE", (0, 0), (-1, -1), 8),
        ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#D5DEE5")),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F3F7F9")]),
    ]))
    story.append(ptable)

    story.append(Paragraph("3. Dish performance", styles["AalaHead"]))
    item_rows = [["Dish / item", "Qty sold", "Sales (INR)"]]
    for row in metrics["top_items"][:15]:
        item_rows.append([
            Paragraph(html.escape(row["name"]), styles["AalaSmall"]),
            f"{row['qty']:,.0f}", f"{row['sales']:,.2f}"
        ])
    if len(item_rows) == 1:
        item_rows.append(["No item-level sales records", "—", "—"])
    itable = Table(item_rows, colWidths=[90 * mm, 30 * mm, 45 * mm], repeatRows=1)
    itable.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#14536B")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, -1), font_name),
        ("FONTSIZE", (0, 0), (-1, -1), 8),
        ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#D5DEE5")),
        ("ALIGN", (1, 1), (-1, -1), "RIGHT"),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F3F7F9")]),
    ]))
    story.append(itable)

    story.append(Paragraph("4. Purchase and expense signals", styles["AalaHead"]))
    purchase_rows = [["Purchased item (recorded)", "Recorded cost (INR)"]]
    purchase_rows += [
        [Paragraph(html.escape(name), styles["AalaSmall"]), f"{amount:,.2f}"]
        for name, amount in metrics["purchase_by_item"][:12]
    ]
    if len(purchase_rows) == 1:
        purchase_rows.append(["No received purchase-cost records", "—"])
    purch_table = Table(purchase_rows, colWidths=[100 * mm, 65 * mm], repeatRows=1)
    purch_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#14536B")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, -1), font_name),
        ("FONTSIZE", (0, 0), (-1, -1), 8),
        ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#D5DEE5")),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F3F7F9")]),
    ]))
    story.append(purch_table)

    story.append(Paragraph("5. Kitchen operations", styles["AalaHead"]))
    prep_text = (
        f"Average recorded preparation time: {metrics['avg_prep']:.1f} minutes "
        f"from {metrics['prep_observation_count']} KOT record(s)."
        if metrics["avg_prep"] is not None
        else "Preparation-time analysis unavailable: no valid KOT preparation durations were supplied."
    )
    story.append(Paragraph(
        f"{html.escape(prep_text)} Cancelled/void KOT records: {metrics['cancelled_kots']}.",
        styles["AalaBody"]
    ))

    story.append(Paragraph("6. Intelligent recommendations", styles["AalaHead"]))
    for index, recommendation in enumerate(metrics["recommendations"], 1):
        story.append(Paragraph(f"{index}. {html.escape(recommendation)}", styles["AalaBody"]))

    story.append(Paragraph("7. Data quality and food-waste measurement", styles["AalaHead"]))
    story.append(Paragraph(
        "<b>Food waste amount: NOT MEASURABLE from the current records.</b> "
        "The supplied POS data contains bills, sold dish quantities, recorded ration demands/"
        "purchase costs, expenses and selected KOT fields. It does not contain a complete "
        "ingredient recipe (BOM), daily opening/closing stock ledger, physical stock count, "
        "or weighed/spoilage/plate-return waste log. Therefore this report does not convert "
        "purchase cost into food wastage or claim a rupee loss without evidence.",
        styles["AalaBody"]
    ))
    story.append(Paragraph(
        "To unlock measured wastage and theoretical-vs-actual food cost, record: "
        "(1) ingredient quantities per dish, (2) stock received and issued, "
        "(3) opening/closing stock, and (4) waste quantity, reason and cost. "
        "Once those records exist, the next report can calculate variance by ingredient and dish.",
        styles["AalaBody"]
    ))
    story.append(Spacer(1, 8))
    story.append(Paragraph(
        f"Generated by AALA POS Intelligence • {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')} "
        "• Analysis is decision support, not an audited accounting statement.",
        styles["AalaSmall"]
    ))

    doc.build(story)
    return output.getvalue()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "aala-pos-intelligence"}


@app.post("/v1/report.pdf")
async def create_report(payload: ReportRequest, request: Request) -> StreamingResponse:
    client_ip = request.client.host if request.client else "unknown"
    now = time.time()
    recent = [stamp for stamp in _RATE_BUCKETS[client_ip] if now - stamp < _RATE_WINDOW_SECONDS]
    if len(recent) >= _RATE_LIMIT:
        raise HTTPException(status_code=429, detail="Too many reports. Please retry in one minute.")
    recent.append(now)
    _RATE_BUCKETS[client_ip] = recent

    if not payload.invoices and not payload.invoice_items:
        raise HTTPException(status_code=422, detail="No sales data was supplied for this report.")
    pdf_bytes = build_pdf(payload)
    filename = f"AALA-Intelligence-{payload.store_code}-{datetime.now().strftime('%Y%m%d-%H%M')}.pdf"
    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# ---------------------------------------------------------------------------
# Kitchen learning API. Supabase service credentials stay on the server only.
# SQL trigger capture_kitchen_learning_observation() records completed KOTs.
# This API learns weekday/hour and dish-aware estimates from those observations.
# ---------------------------------------------------------------------------
import statistics
from datetime import timedelta
from zoneinfo import ZoneInfo
import httpx

IST = ZoneInfo("Asia/Kolkata")


class KitchenEstimateRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")
    store_code: str = Field(min_length=1, max_length=64)
    items: list[dict[str, Any]] = Field(default_factory=list, max_length=100)
    pending_orders_ahead: int = Field(default=0, ge=0, le=100)
    now: str | None = Field(default=None, max_length=64)


def _percentile(values: list[int], fraction: float = 0.75) -> int:
    clean = sorted(max(1, min(240, int(v))) for v in values if v and 0 < int(v) <= 240)
    if not clean:
        return 0
    return clean[min(len(clean) - 1, max(0, int((len(clean) - 1) * fraction + 0.999)))]


def _item_names(items: list[dict[str, Any]]) -> set[str]:
    names: set[str] = set()
    for item in items:
        name = str(item.get("name") or item.get("item_name") or "").strip().casefold()
        if name:
            names.add(name)
    return names


async def _load_kitchen_observations(store_code: str) -> list[dict[str, Any]]:
    supabase_url = os.getenv("SUPABASE_URL", "").rstrip("/")
    service_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
    if not supabase_url or not service_key:
        raise HTTPException(
            status_code=503,
            detail="Kitchen learning is not configured: set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY on the server.",
        )
    headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Accept": "application/json",
    }
    cutoff = (datetime.now(timezone.utc) - timedelta(days=90)).isoformat()
    params = {
        "select": "local_weekday,local_hour,item_signature,items,prep_minutes,order_acceptance_minutes,queue_minutes,ready_at",
        "store_code": f"eq.{store_code}",
        "ready_at": f"gte.{cutoff}",
        "order": "ready_at.desc",
        "limit": "1000",
    }
    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            response = await client.get(
                f"{supabase_url}/rest/v1/kitchen_learning_observations",
                headers=headers,
                params=params,
            )
            response.raise_for_status()
            data = response.json()
            return data if isinstance(data, list) else []
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=503, detail="Kitchen history is temporarily unavailable.") from exc
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=503, detail="Could not reach kitchen history storage.") from exc



@app.post("/v1/kitchen/estimate")
async def estimate_kitchen_time(request: KitchenEstimateRequest) -> dict[str, Any]:
    """Estimate customer wait using this hotel's actual weekday/hour/dish history."""
    now = datetime.now(IST)
    if request.now:
        try:
            parsed = datetime.fromisoformat(request.now.replace("Z", "+00:00"))
            now = parsed.astimezone(IST) if parsed.tzinfo else parsed.replace(tzinfo=IST)
        except ValueError as exc:
            raise HTTPException(status_code=422, detail="Invalid now timestamp.") from exc

    history = await _load_kitchen_observations(request.store_code.strip().upper())
    weekday, hour = now.isoweekday(), now.hour
    # Same weekday and nearby hour is the strongest comparable time bucket.
    bucket = [
        row for row in history
        if int(row.get("local_weekday") or 0) == weekday
        and abs(int(row.get("local_hour") or 0) - hour) <= 1
    ]
    all_rows = history
    requested_names = _item_names(request.items)

    def names_for(row: dict[str, Any]) -> set[str]:
        raw = row.get("items") or []
        if isinstance(raw, str):
            try:
                raw = json.loads(raw)
            except (TypeError, ValueError):
                raw = []
        return _item_names(raw if isinstance(raw, list) else [])

    dish_rows = [
        row for row in bucket
        if requested_names and requested_names.issubset(names_for(row))
    ]
    prep_source = dish_rows if len(dish_rows) >= 5 else bucket if len(bucket) >= 5 else all_rows
    prep_values = [int(row.get("prep_minutes") or 0) for row in prep_source]
    prep_values = [v for v in prep_values if 0 < v <= 240]
    prep_minutes = _percentile(prep_values) if prep_values else 18
    prep_basis = (
        "same weekday/hour and matching dishes" if prep_source is dish_rows
        else "same weekday/hour" if prep_source is bucket
        else "hotel-wide recent history" if prep_source is all_rows and all_rows
        else "cold-start fallback"
    )

    wait_rows = [row for row in bucket if row.get("order_acceptance_minutes") is not None]
    if len(wait_rows) < 5:
        wait_rows = [row for row in all_rows if row.get("order_acceptance_minutes") is not None]
    wait_values = [int(row.get("order_acceptance_minutes") or 0) for row in wait_rows]
    wait_values = [v for v in wait_values if 0 <= v <= 240]
    acceptance_wait = _percentile(wait_values) if wait_values else 3

    # Learn the actual wait between KOT creation/acceptance and the cook pressing
    # "start". Add a modest load buffer for orders already ahead in the queue.
    queue_values = [
        int(row.get("queue_minutes") or 0)
        for row in (bucket if len(bucket) >= 5 else all_rows)
    ]
    queue_values = [v for v in queue_values if 0 <= v <= 240]
    learned_queue = _percentile([v for v in queue_values if v > 0]) if any(queue_values) else 0
    load_buffer = max(1, round(prep_minutes * 0.15)) * max(0, request.pending_orders_ahead)
    queue_minutes = min(90, learned_queue + load_buffer)
    total = max(1, acceptance_wait + prep_minutes + queue_minutes)
    ready_at = now + timedelta(minutes=total)
    sample_count = len(prep_values)
    confidence = "high" if sample_count >= 20 else "medium" if sample_count >= 5 else "low"

    return {
        "store_code": request.store_code.strip().upper(),
        "weekday": weekday,
        "hour": hour,
        "acceptance_wait_minutes": acceptance_wait,
        "prep_minutes": prep_minutes,
        "queue_minutes": queue_minutes,
        "total_minutes": total,
        "estimated_ready_at": ready_at.isoformat(),
        "prep_sample_count": sample_count,
        "acceptance_sample_count": len(wait_values),
        "queue_sample_count": len([v for v in queue_values if v > 0]),
        "confidence": confidence,
        "basis": prep_basis,
        "is_learned": bool(history),
    }


@app.get("/v1/kitchen/summary/{store_code}")
async def kitchen_learning_summary(store_code: str) -> dict[str, Any]:
    """Return weekday/hour learning coverage for the owner's intelligence dashboard."""
    rows = await _load_kitchen_observations(store_code.strip().upper())
    buckets: dict[str, list[int]] = defaultdict(list)
    for row in rows:
        key = f"{int(row.get('local_weekday') or 0)}-{int(row.get('local_hour') or 0):02d}"
        value = int(row.get("prep_minutes") or 0)
        if 0 < value <= 240:
            buckets[key].append(value)
    return {
        "store_code": store_code.strip().upper(),
        "observations": len(rows),
        "buckets": [
            {
                "weekday": int(key.split("-")[0]),
                "hour": int(key.split("-")[1]),
                "sample_count": len(values),
                "average_prep_minutes": round(statistics.mean(values), 1),
                "p75_prep_minutes": _percentile(values),
            }
            for key, values in sorted(buckets.items())
        ],
    }
