// lib/screens/admin/qr_table_generator_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class QrTableGeneratorScreen extends StatefulWidget {
  final String storeCode;
  final String hotelName;
  final int totalTables;

  const QrTableGeneratorScreen({
    Key? key,
    required this.storeCode,
    required this.hotelName,
    required this.totalTables,
  }) : super(key: key);

  @override
  State<QrTableGeneratorScreen> createState() => _QrTableGeneratorScreenState();
}

class _QrTableGeneratorScreenState extends State<QrTableGeneratorScreen> {
  int _selectedTable = 1;
  bool _isGeneratingPdf = false;

  String _getQrUrl(int tableNo) {
    return 'https://govindaala.github.io/hotel_menu/?store=${widget.storeCode}&table=$tableNo';
  }

  // 1-क्लिक स्टैंडी PDF जनरेटर (सभी टेबल्स का प्रिंट-रेडी PDF)
  Future<void> _generateAndShareStandeePdf() async {
    setState(() => _isGeneratingPdf = true);

    try {
      final doc = pw.Document();

      for (int i = 1; i <= widget.totalTables; i++) {
        final qrData = _getQrUrl(i);

        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a5,
            build: (pw.Context context) {
              return pw.Container(
                padding: const pw.EdgeInsets.all(24),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.blueGrey900, width: 3),
                  borderRadius: pw.BorderRadius.circular(16),
                ),
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      widget.hotelName,
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blueGrey900,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 8),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.amber800,
                        borderRadius: pw.BorderRadius.circular(12),
                      ),
                      child: pw.Text(
                        'TABLE T-$i',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 20),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        border: pw.Border.all(color: PdfColors.grey300),
                        borderRadius: pw.BorderRadius.circular(12),
                      ),
                      child: pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: qrData,
                        width: 170,
                        height: 170,
                      ),
                    ),
                    pw.SizedBox(height: 20),
                    pw.Text(
                      'Scan with Phone Camera to View Menu & Order',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey700,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Store Code: ${widget.storeCode}',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      }

      final output = await getTemporaryDirectory();
      final file = File("${output.path}/hotel_${widget.storeCode}_qr_standees.pdf");
      await file.writeAsBytes(await doc.save());

      if (mounted) {
        await Share.shareXFiles(
          [XFile(file.path)],
          text: '${widget.hotelName} - सभी टेबल्स QR स्टैंडी PDF',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF बनाने में त्रुटि: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String currentQrData = _getQrUrl(_selectedTable);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('टेबल QR स्टैंडी व डिजिटल मेन्यू', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // टेबल चयन ड्रॉपडाउन
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.table_restaurant, color: Color(0xFF0F172A)),
                    const SizedBox(width: 12),
                    const Text('टेबल चुनें:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const Spacer(),
                    DropdownButton<int>(
                      value: _selectedTable,
                      underline: const SizedBox(),
                      items: List.generate(widget.totalTables, (index) {
                        final t = index + 1;
                        return DropdownMenuItem(value: t, child: Text('टेबल T-$t', style: const TextStyle(fontWeight: FontWeight.bold)));
                      }),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedTable = val);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // स्टैंडी लाइव प्रीव्यू कार्ड
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF0F172A), width: 3),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 5)),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    widget.hotelName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.amber[800],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'TABLE T-$_selectedTable',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // लाइव QR कोड
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: QrImageView(
                      data: currentQrData,
                      version: QrVersions.auto,
                      size: 190.0,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_camera, size: 18, color: Colors.blueGrey),
                      SizedBox(width: 6),
                      Text(
                        'फोन कैमरे से स्कैन करें और खाना ऑर्डर करें',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'स्टोर कोड: ${widget.storeCode}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // सभी टेबल्स PDF शेयर बटन
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isGeneratingPdf
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf, color: Colors.white),
                label: Text(
                  _isGeneratingPdf ? 'PDF तैयार हो रहा है...' : '🖨️ सभी ${widget.totalTables} टेबल्स का स्टैंडी PDF डाउनलोड/शेयर करें',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                onPressed: _isGeneratingPdf ? null : _generateAndShareStandeePdf,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
