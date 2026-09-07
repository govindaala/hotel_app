import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

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
  required int paperWidthMm, // 58 या 80 mm थर्मल प्रिंटर विड्थ
}) async {
  final pdf = pw.Document();

  // हिंदी (Devanagari) टेक्स्ट के लिए Noto Sans Devanagari फॉन्ट लोड करना (ऑफलाइन)
  pw.Font? devanagariFont;
  try {
    final fontData = await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf');
    devanagariFont = pw.Font.ttf(fontData);
  } catch (_) {}

  // प्रिंटर की चौड़ाई के आधार पर पॉइंट्स (Points) और फॉन्ट साइज़ सेट करना
  // 1 mm = 2.83465 points (58mm ≈ 164 points, 80mm ≈ 226 points)
  final double widthPoints = paperWidthMm == 58 ? 164.0 : 226.0;
  final double horizontalPadding = paperWidthMm == 58 ? 6.0 : 10.0;
  final double titleFontSize = paperWidthMm == 58 ? 12.0 : 15.0;
  final double normalFontSize = paperWidthMm == 58 ? 8.0 : 10.0;
  final double smallFontSize = paperWidthMm == 58 ? 7.0 : 8.0;
  final double qrSize = paperWidthMm == 58 ? 55.0 : 75.0;

  final double finalTotal = (subTotal - discount) < 0 ? 0.0 : (subTotal - discount);
  final bool isParcel = tbl >= 900;
  final String receiptTitle = isParcel ? "पार्सल (P-${tbl - 900})" : "टेबल: T-$tbl";

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(widthPoints, double.infinity, marginAll: horizontalPadding),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // होटल का नाम
            pw.Text(
              hotelName,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: devanagariFont,
                fontSize: titleFontSize,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (address != null && address.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: pw.Text(
                  address,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: devanagariFont, fontSize: smallFontSize),
                ),
              ),
            if (phone != null && phone.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: pw.Text(
                  "मोबाइल: $phone",
                  style: pw.TextStyle(font: devanagariFont, fontSize: smallFontSize, fontWeight: pw.FontWeight.bold),
                ),
              ),

            // FSSAI और GSTIN विवरण
            if ((fssai != null && fssai.isNotEmpty) || (gstin != null && gstin.isNotEmpty))
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 3),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    if (fssai != null && fssai.isNotEmpty)
                      pw.Text("FSSAI: $fssai ", style: pw.TextStyle(fontSize: smallFontSize - 1)),
                    if (gstin != null && gstin.isNotEmpty)
                      pw.Text("GSTIN: $gstin", style: pw.TextStyle(fontSize: smallFontSize - 1)),
                  ],
                ),
              ),

            pw.SizedBox(height: 4),
            pw.Divider(thickness: 0.8),

            // टेबल/पार्सल नंबर और दिनांक/समय
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(receiptTitle, style: pw.TextStyle(font: devanagariFont, fontSize: normalFontSize, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                  "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year} ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}",
                  style: pw.TextStyle(fontSize: smallFontSize - 1),
                ),
              ],
            ),
            pw.Divider(thickness: 0.5),

            // आइटम हेडर
            pw.Row(
              children: [
                pw.Expanded(flex: paperWidthMm == 58 ? 4 : 5, child: pw.Text("आइटम", style: pw.TextStyle(font: devanagariFont, fontSize: smallFontSize, fontWeight: pw.FontWeight.bold))),
                pw.Expanded(flex: 2, child: pw.Text("मात्रा", textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: smallFontSize, fontWeight: pw.FontWeight.bold))),
                pw.Expanded(flex: 3, child: pw.Text("रकम", textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: smallFontSize, fontWeight: pw.FontWeight.bold))),
              ],
            ),
            pw.SizedBox(height: 2),

            // आइटम सूची (Items list)
            ...items.map((it) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        flex: paperWidthMm == 58 ? 4 : 5,
                        child: pw.Text(
                          it['name'].toString(),
                          style: pw.TextStyle(font: devanagariFont, fontSize: normalFontSize),
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
                          "₹${(it['price'] * it['qty']).toInt()}",
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(fontSize: normalFontSize, fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                )),

            pw.Divider(thickness: 0.8),

            // उप-योग और छूट (Subtotal & Discount)
            if (discount > 0) ...[
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("उप-योग:", style: pw.TextStyle(font: devanagariFont, fontSize: smallFontSize)),
                  pw.Text("₹${subTotal.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: smallFontSize)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("छूट (${discountPct.toStringAsFixed(0)}%):", style: pw.TextStyle(font: devanagariFont, fontSize: smallFontSize, color: PdfColors.red)),
                  pw.Text("-₹${discount.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: smallFontSize, color: PdfColors.red)),
                ],
              ),
              pw.SizedBox(height: 2),
            ],

            // कुल देय (Net Total)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("कुल देय:", style: pw.TextStyle(font: devanagariFont, fontSize: normalFontSize + 1, fontWeight: pw.FontWeight.bold)),
                pw.Text("₹${finalTotal.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: normalFontSize + 2, fontWeight: pw.FontWeight.bold)),
              ],
            ),

            pw.SizedBox(height: 6),

            // नेटिव वेक्टर/बारकोड QR रेंडरिंग (ऑफ़लाइन, बिना किसी API या Screenshot के)
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
                        pw.Text("Review ⭐", style: pw.TextStyle(fontSize: smallFontSize - 2, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                ],
              ),

            pw.SizedBox(height: 6),
            pw.Divider(thickness: 0.5),
            pw.Text(
              "धन्यवाद! फिर पधारें 🙏",
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: devanagariFont, fontSize: smallFontSize, fontWeight: pw.FontWeight.bold),
            ),
          ],
        );
      },
    ),
  );

  return pdf;
}
