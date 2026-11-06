from __future__ import annotations

import html
import io
import os
import time
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse
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
