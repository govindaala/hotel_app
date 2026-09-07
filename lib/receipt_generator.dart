import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
  final double finalTotal = (subTotal - discount) < 0 ? 0.0 : (subTotal - discount);
  final bool isParcel = tbl >= 900;
  final String receiptTitle = isParcel ? "पार्सल (P-${tbl - 900})" : "टेबल: T-$tbl";
  final String dateStr = "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year} ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}";

  // पेपर विड्थ के अनुसार विड्थ और फॉन्ट साइज़
  final double widgetWidth = paperWidthMm == 58 ? 280.0 : 380.0;
  final double titleSize = paperWidthMm == 58 ? 16.0 : 20.0;
  final double bodySize = paperWidthMm == 58 ? 10.5 : 12.0;
  final double smallSize = paperWidthMm == 58 ? 9.0 : 10.5;
  final double qrSize = paperWidthMm == 58 ? 75.0 : 95.0;

  // Flutter के नेटिव इंजन से शुद्ध हिंदी रेंडरिंग
  final Uint8List receiptImage = await ScreenshotController().captureFromWidget(
    Material(
      color: Colors.white,
      child: Container(
        width: widgetWidth,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              hotelName,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            if (address != null && address.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(address, textAlign: TextAlign.center, style: TextStyle(fontSize: smallSize, color: Colors.black87)),
              ),
            if (phone != null && phone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text("मोबाइल: $phone", style: TextStyle(fontSize: smallSize, fontWeight: FontWeight.bold, color: Colors.black87)),
              ),
            if ((fssai != null && fssai.isNotEmpty) || (gstin != null && gstin.isNotEmpty))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (fssai != null && fssai.isNotEmpty) Text("FSSAI: $fssai  ", style: TextStyle(fontSize: smallSize - 1, color: Colors.black87)),
                    if (gstin != null && gstin.isNotEmpty) Text("GSTIN: $gstin", style: TextStyle(fontSize: smallSize - 1, color: Colors.black87)),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            const Divider(color: Colors.black, thickness: 1.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(receiptTitle, style: TextStyle(fontWeight: FontWeight.bold, fontSize: bodySize, color: Colors.black)),
                Text(dateStr, style: TextStyle(fontSize: smallSize, color: Colors.black87)),
              ],
            ),
            const Divider(color: Colors.black54, thickness: 0.6),

            Row(
              children: [
                Expanded(flex: 5, child: Text("सामग्री", style: TextStyle(fontWeight: FontWeight.bold, fontSize: smallSize, color: Colors.black))),
                Expanded(flex: 2, child: Text("मात्रा", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: smallSize, color: Colors.black))),
                Expanded(flex: 3, child: Text("रकम (₹)", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: smallSize, color: Colors.black))),
              ],
            ),
            const Divider(color: Colors.black26),

            ...items.map((it) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Row(
                    children: [
                      Expanded(flex: 5, child: Text("${it['name']}", style: TextStyle(fontSize: bodySize, color: Colors.black, fontWeight: FontWeight.w500))),
                      Expanded(flex: 2, child: Text("x${it['qty']}", textAlign: TextAlign.center, style: TextStyle(fontSize: bodySize, color: Colors.black))),
                      Expanded(flex: 3, child: Text("₹${(it['price'] * it['qty']).toInt()}", textAlign: TextAlign.right, style: TextStyle(fontSize: bodySize, fontWeight: FontWeight.bold, color: Colors.black))),
                    ],
                  ),
                )),
            const Divider(color: Colors.black, thickness: 0.8),

            if (discount > 0) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("उप-योग:", style: TextStyle(fontSize: smallSize, color: Colors.black54)),
                  Text("₹${subTotal.toStringAsFixed(2)}", style: TextStyle(fontSize: smallSize, color: Colors.black87)),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("छूट (${discountPct.toStringAsFixed(0)}%):", style: TextStyle(fontSize: smallSize, fontWeight: FontWeight.bold, color: Colors.red)),
                  Text("-₹${discount.toStringAsFixed(2)}", style: TextStyle(fontSize: smallSize, fontWeight: FontWeight.bold, color: Colors.red)),
                ],
              ),
              const SizedBox(height: 2),
            ],

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("कुल देय:", style: TextStyle(fontSize: bodySize + 1, fontWeight: FontWeight.bold, color: Colors.black)),
                Text("₹${finalTotal.toStringAsFixed(2)}", style: TextStyle(fontSize: bodySize + 3, fontWeight: FontWeight.bold, color: Colors.black)),
              ],
            ),
            const SizedBox(height: 8),

            // ऑफलाइन QR कोड
            if ((upiId != null && upiId.isNotEmpty) || (reviewUrl != null && reviewUrl.isNotEmpty))
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(6)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (upiId != null && upiId.isNotEmpty)
                      Column(
                        children: [
                          SizedBox(
                            width: qrSize,
                            height: qrSize,
                            child: QrImageView(
                              data: "upi://pay?pa=$upiId&pn=$hotelName&am=$finalTotal&cu=INR",
                              version: QrVersions.auto,
                              size: qrSize,
                              backgroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text("पेमेंट UPI QR", style: TextStyle(fontSize: smallSize - 1, fontWeight: FontWeight.bold, color: Colors.black)),
                        ],
                      ),
                    if (reviewUrl != null && reviewUrl.isNotEmpty)
                      Column(
                        children: [
                          SizedBox(
                            width: qrSize,
                            height: qrSize,
                            child: QrImageView(
                              data: reviewUrl,
                              version: QrVersions.auto,
                              size: qrSize,
                              backgroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text("Google Review ⭐", style: TextStyle(fontSize: smallSize - 1, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                        ],
                      ),
                  ],
                ),
              ),

            const SizedBox(height: 6),
            const Divider(color: Colors.black26),
            Text("धन्यवाद! फिर पधारें 🙏", style: TextStyle(fontSize: bodySize, fontWeight: FontWeight.bold, color: Colors.black87)),
          ],
        ),
      ),
    ),
    pixelRatio: 3.0, // 300+ DPI HD वेक्टर शार्पनेस
    delay: const Duration(milliseconds: 30),
  );

  final pdf = pw.Document();
  final double widthPoints = paperWidthMm == 58 ? 164.0 : 226.0;

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(widthPoints, double.infinity, marginAll: 2.0),
      build: (pw.Context context) => pw.Center(
        child: pw.Image(pw.MemoryImage(receiptImage)),
      ),
    ),
  );

  return pdf;
}
