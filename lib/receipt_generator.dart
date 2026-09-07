import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<pw.Document> buildThermalReceiptPdf({
  required String hotelName,
  required String? address,
  required String? phone,
  required String? fssai,
  required String? gstin,
  required int tbl,
  required List<Map<String, dynamic>> items,
  required double subTotal,
  required double discount,
  required double discountPct,
  required String? upiId,
  required String? reviewUrl,
  required int paperWidthMm,
}) async {
  // 1. हिंदी फ़ॉन्ट लोड करें
  pw.Font? devanagariFont;
  try {
    final fontData = await rootBundle.load('assets/templates/fonts/NotoSansDevanagari-Regular.ttf');
    devanagariFont = pw.Font.ttf(fontData);
  } catch (_) {}

  // पूरे डॉक्यूमेंट पर ग्लोबल थीम सेट करें ताकि कोई भी शब्द डिब्बा न बने
  final pdf = pw.Document(
    theme: devanagariFont != null
        ? pw.ThemeData.withFont(base: devanagariFont, bold: devanagariFont)
        : null,
  );

  // 58mm और 80mm के अनुसार सही चौड़ाई व मार्जिन
  final double widthPoints = paperWidthMm == 58 ? 164.0 : 226.0;
  const double horizontalMargin = 4.0; // कम मार्जिन से टेक्स्ट कभी नहीं कटेगा
  final double titleFontSize = paperWidthMm == 58 ? 11.0 : 13.0;
  final double normalFontSize = paperWidthMm == 58 ? 7.5 : 9.0;
  final double smallFontSize = paperWidthMm == 58 ? 6.5 : 7.5;
  final double qrSize = paperWidthMm == 58 ? 55.0 : 70.0;

  final double finalTotal = (subTotal - discount) < 0 ? 0.0 : (subTotal - discount);
  final bool isParcel = tbl >= 900;
  final String receiptTitle = isParcel ? "पार्सल (P-${tbl - 900})" : "टेबल: T-$tbl";
  final String dateStr = "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}";

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(widthPoints, double.infinity, marginAll: horizontalMargin),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              hotelName,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: titleFontSize, fontWeight: pw.FontWeight.bold),
            ),
            if (address != null && address.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 1),
                child: pw.Text(
                  address,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: smallFontSize),
                ),
              ),
            if (phone != null && phone.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 1),
                child: pw.Text(
                  "मोबाइल: $phone",
                  style: pw.TextStyle(fontSize: smallFontSize, fontWeight: pw.FontWeight.bold),
                ),
              ),
            if ((fssai != null && fssai.isNotEmpty) || (gstin != null && gstin.isNotEmpty))
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: pw.Wrap(
                  alignment: pw.WrapAlignment.center,
                  spacing: 4,
                  children: [
                    if (fssai != null && fssai.isNotEmpty)
                      pw.Text("FSSAI: $fssai", style: pw.TextStyle(fontSize: smallFontSize - 1)),
                    if (gstin != null && gstin.isNotEmpty)
                      pw.Text("GSTIN: $gstin", style: pw.TextStyle(fontSize: smallFontSize - 1)),
                  ],
                ),
              ),
            pw.SizedBox(height: 3),
            pw.Divider(thickness: 0.8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Text(receiptTitle, style: pw.TextStyle(fontSize: normalFontSize, fontWeight: pw.FontWeight.bold)),
                ),
                pw.Text(dateStr, style: pw.TextStyle(fontSize: smallFontSize)),
              ],
            ),
            pw.Divider(thickness: 0.5),

            // टेबल हेडर
            pw.Row(
              children: [
                pw.Expanded(flex: 5, child: pw.Text("सामग्री", style: pw.TextStyle(fontSize: smallFontSize, fontWeight: pw.FontWeight.bold))),
                pw.Expanded(flex: 2, child: pw.Text("मात्रा", textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: smallFontSize, fontWeight: pw.FontWeight.bold))),
                pw.Expanded(flex: 3, child: pw.Text("रकम (₹)", textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: smallFontSize, fontWeight: pw.FontWeight.bold))),
              ],
            ),
            pw.SizedBox(height: 2),

            // सामग्री सूची
            ...items.map((it) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        flex: 5,
                        child: pw.Text(
                          it['name'].toString(),
                          style: pw.TextStyle(fontSize: normalFontSize),
                        ),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(
                          "x${it['qty']}",
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(fontSize: normalFontSize),
                        ),
                      ),
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text(
                          "${(it['price'] * it['qty']).toInt()}",
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(fontSize: normalFontSize, fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                )),
            pw.Divider(thickness: 0.8),

            if (discount > 0) ...[
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("उप-योग:", style: pw.TextStyle(fontSize: smallFontSize)),
                  pw.Text("₹${subTotal.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: smallFontSize)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("छूट (${discountPct.toStringAsFixed(0)}%):", style: pw.TextStyle(fontSize: smallFontSize, color: PdfColors.red)),
                  pw.Text("-₹${discount.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: smallFontSize, color: PdfColors.red)),
                ],
              ),
              pw.SizedBox(height: 2),
            ],

            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("कुल देय:", style: pw.TextStyle(fontSize: normalFontSize + 1, fontWeight: pw.FontWeight.bold)),
                pw.Text("₹${finalTotal.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: normalFontSize + 2, fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.SizedBox(height: 5),

            // UPI व Review QR
            if ((upiId != null && upiId.isNotEmpty) || (reviewUrl != null && reviewUrl.isNotEmpty))
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                children: [
                  if (upiId != null && upiId.isNotEmpty)
                    pw.Column(
                      children: [
                        pw.SizedBox(
                          width: qrSize,
                          height: qrSize,
                          child: pw.BarcodeWidget(
                            barcode: pw.Barcode.qrCode(),
                            data: "upi://pay?pa=$upiId&pn=$hotelName&am=$finalTotal&cu=INR",
                            color: PdfColors.black,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text("UPI QR", style: pw.TextStyle(fontSize: smallFontSize - 2, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  if (reviewUrl != null && reviewUrl.isNotEmpty)
                    pw.Column(
                      children: [
                        pw.SizedBox(
                          width: qrSize,
                          height: qrSize,
                          child: pw.BarcodeWidget(
                            barcode: pw.Barcode.qrCode(),
                            data: reviewUrl,
                            color: PdfColors.black,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text("Review", style: pw.TextStyle(fontSize: smallFontSize - 2, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                ],
              ),
            pw.SizedBox(height: 5),
            pw.Divider(thickness: 0.5),
            pw.Text(
              "धन्यवाद! फिर पधारें",
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: smallFontSize, fontWeight: pw.FontWeight.bold),
            ),
          ],
        );
      },
    ),
  );

  return pdf;
}
