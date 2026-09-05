import '../models/restaurant_profile_model.dart';

class DynamicReceiptService {
  // ================= 1. A4 वित्तीय रिपोर्ट HTML =================
  static String generateFinancialReportHtml({
    required RestaurantProfileModel restaurant,
    required String startDate,
    required String endDate,
    required List<Map<String, dynamic>> orders,
    required double totalSales,
    required double totalTax,
    required double netAmount,
  }) {
    final rowsBuffer = StringBuffer();

    for (final order in orders) {
      final invNo = order['invoice_number'] ?? order['id'] ?? '-';
      final date = order['created_at'] != null
          ? order['created_at'].toString().substring(0, 10)
          : '-';
      final type = order['table_number'] ?? order['order_type'] ?? 'Dine-In';
      final mode = (order['payment_mode'] ?? 'CASH').toString().toUpperCase();
      final tax = ((order['tax'] ?? 0.0) as num).toDouble();
      final total = ((order['total'] ?? 0.0) as num).toDouble();

      rowsBuffer.writeln('''
        <tr>
          <td>$invNo</td>
          <td>$date</td>
          <td>$type</td>
          <td>$mode</td>
          <td style="text-align: right;">₹${tax.toStringAsFixed(2)}</td>
          <td style="text-align: right;"><b>₹${total.toStringAsFixed(2)}</b></td>
        </tr>
      ''');
    }

    return '''
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Financial Report - ${restaurant.name}</title>
      <style>
        @page {
          size: A4 portrait;
          margin: 15mm;
        }
        body {
          font-family: Arial, sans-serif;
          color: #1e293b;
          margin: 0;
          padding: 0;
          font-size: 13px;
        }
        .header-table {
          width: 100%;
          border-bottom: 2px solid #0f172a;
          padding-bottom: 10px;
          margin-bottom: 15px;
        }
        .hotel-name {
          font-size: 22px;
          font-weight: bold;
          color: #0f172a;
        }
        .report-title {
          font-size: 16px;
          font-weight: bold;
          text-align: right;
          color: #ea580c;
        }
        .summary-box {
          border: 1px solid #cbd5e1;
          background-color: #f8fafc;
          border-radius: 6px;
          padding: 10px;
          text-align: center;
        }
        .summary-box .title {
          font-size: 11px;
          color: #64748b;
          text-transform: uppercase;
        }
        .summary-box .value {
          font-size: 16px;
          font-weight: bold;
          margin-top: 4px;
        }
        table.data-table {
          width: 100%;
          border-collapse: collapse;
          margin-top: 10px;
        }
        table.data-table th {
          background-color: #0f172a;
          color: #ffffff;
          padding: 8px;
          font-size: 12px;
          text-align: left;
        }
        table.data-table td {
          padding: 8px;
          border-bottom: 1px solid #e2e8f0;
          font-size: 12px;
        }
        table.data-table tr:nth-child(even) {
          background-color: #f8fafc;
        }
        .footer-sign {
          margin-top: 40px;
          display: flex;
          justify-content: space-between;
          font-size: 11px;
          color: #64748b;
        }
      </style>
    </head>
    <body>
      <table class="header-table">
        <tr>
          <td>
            <div class="hotel-name">${restaurant.name}</div>
            <div>${restaurant.address ?? ''}</div>
            <div>फ़ोन: ${restaurant.phone ?? '-'}</div>
            ${restaurant.gstNumber != null && restaurant.gstNumber!.isNotEmpty ? '<div><b>GSTIN:</b> ${restaurant.gstNumber}</div>' : ''}
            ${restaurant.fssaiNumber != null && restaurant.fssaiNumber!.isNotEmpty ? '<div><b>FSSAI:</b> ${restaurant.fssaiNumber}</div>' : ''}
          </td>
          <td align="right" valign="top">
            <div class="report-title">वित्तीय रिपोर्ट (FINANCIAL REPORT)</div>
            <div>अवधि: $startDate से $endDate</div>
            <div style="font-size: 10px; color: #64748b; margin-top: 5px;">कुल बिल: ${orders.length}</div>
          </td>
        </tr>
      </table>

      <table style="width: 100%; margin-bottom: 15px;">
        <tr>
          <td style="width: 33%; padding: 4px;">
            <div class="summary-box">
              <div class="title">सकल बिक्री (Gross Sales)</div>
              <div class="value" style="color: #0f172a;">₹${totalSales.toStringAsFixed(2)}</div>
            </div>
          </td>
          <td style="width: 33%; padding: 4px;">
            <div class="summary-box">
              <div class="title">कुल टैक्स (GST)</div>
              <div class="value" style="color: #0284c7;">₹${totalTax.toStringAsFixed(2)}</div>
            </div>
          </td>
          <td style="width: 33%; padding: 4px;">
            <div class="summary-box">
              <div class="title">शुद्ध राशि (Net Total)</div>
              <div class="value" style="color: #16a34a;">₹${netAmount.toStringAsFixed(2)}</div>
            </div>
          </td>
        </tr>
      </table>

      <table class="data-table">
        <thead>
          <tr>
            <th>बिल नं.</th>
            <th>दिनांक</th>
            <th>ऑर्डर प्रकार / टेबल</th>
            <th>भुगतान प्रकार</th>
            <th style="text-align: right;">टैक्स (GST)</th>
            <th style="text-align: right;">कुल रकम</th>
          </tr>
        </thead>
        <tbody>
          ${rowsBuffer.toString()}
        </tbody>
      </table>

      <div class="footer-sign">
        <div>हस्ताक्षर / ऑथराइज्ड सिग्नेटरी: ____________________</div>
        <div>यह सिस्टम द्वारा जनरेटेड A4 रिपोर्ट है।</div>
      </div>
    </body>
    </html>
    ''';
  }

  // ================= 2. थर्मल रसीद HTML (Auto-Injected GST, FSSAI, UPI QR, Review QR) =================
  static String generateBillHtml({
    required String baseHtmlTemplate,
    required RestaurantProfileModel restaurant,
    required String billNo,
    required String tableNo,
    required DateTime dateTime,
    required List<Map<String, dynamic>> items,
    required double grandTotal,
    double discount = 0.0,
    String paymentMode = 'CASH',
  }) {
    final rowsBuffer = StringBuffer();
    double subtotal = 0.0;

    for (final item in items) {
      final name = item['name'] ?? '';
      final qty = item['qty'] ?? item['quantity'] ?? 1;
      final price = (item['price'] as num?)?.toDouble() ?? 0.0;
      final total = qty * price;
      subtotal += total;

      rowsBuffer.writeln('''
        <tr>
          <td align="left">$name</td>
          <td align="center">$qty</td>
          <td align="right">₹${price.toStringAsFixed(0)}</td>
          <td align="right">₹${total.toStringAsFixed(0)}</td>
        </tr>
      ''');
    }

    // 1. GSTIN और FSSAI सेक्शन (Auto-formatted)
    String complianceSection = '';
    if (restaurant.gstNumber != null && restaurant.gstNumber!.trim().isNotEmpty) {
      complianceSection += '<div style="font-size: 11px; font-weight: bold; margin-top: 2px;">GSTIN: ${restaurant.gstNumber!.trim()}</div>';
    }
    if (restaurant.fssaiNumber != null && restaurant.fssaiNumber!.trim().isNotEmpty) {
      complianceSection += '<div style="font-size: 11px; margin-top: 2px;">FSSAI: ${restaurant.fssaiNumber!.trim()}</div>';
    }

    // 2. डिस्काउंट सेक्शन
    final discountSection = discount > 0
        ? '''
          <tr>
            <td>छूट (Discount):</td>
            <td class="text-right" style="color: red;">- ₹${discount.toStringAsFixed(2)}</td>
          </tr>
        '''
        : '';

    // 3. UPI ID (यदि खाली हो तो फ़ोन नंबर @ybl फ़ॉलबैक)
    final effectiveUpiId = (restaurant.upiId != null && restaurant.upiId!.trim().isNotEmpty)
        ? restaurant.upiId!.trim()
        : (restaurant.phone != null && restaurant.phone!.trim().isNotEmpty
            ? '${restaurant.phone!.trim()}@ybl'
            : '');

    String upiQrSection = '';
    String qrApiUrl = '';

    if (effectiveUpiId.isNotEmpty) {
      final upiString =
          'upi://pay?pa=$effectiveUpiId&pn=${Uri.encodeComponent(restaurant.name)}&am=${grandTotal.toStringAsFixed(2)}&cu=INR';
      qrApiUrl =
          'https://api.qrserver.com/v1/create-qr-code/?size=180x180&data=${Uri.encodeComponent(upiString)}';

      upiQrSection = '''
        <div class="qr-container" style="text-align: center; margin: 10px auto; padding: 6px; border: 1px dashed #94a3b8; border-radius: 8px; max-width: 190px;">
          <div style="font-size: 11px; font-weight: bold; margin-bottom: 4px;">स्कैन करके ₹${grandTotal.toStringAsFixed(2)} पे करें</div>
          <img src="$qrApiUrl" style="width: 125px; height: 125px; display: block; margin: 0 auto;" alt="UPI QR" />
          <div style="font-size: 10px; font-weight: bold; margin-top: 4px;">UPI: $effectiveUpiId</div>
          <div style="font-size: 8px; color: #64748b;">PhonePe / GooglePay / Paytm से स्कैन करें</div>
        </div>
      ''';
    }

    // 4. Google Review QR कोड
    String reviewQrSection = '';
    String reviewQrApi = '';
    if (restaurant.googleReviewLink != null && restaurant.googleReviewLink!.trim().isNotEmpty) {
      final reviewLink = restaurant.googleReviewLink!.trim();
      reviewQrApi =
          'https://api.qrserver.com/v1/create-qr-code/?size=140x140&data=${Uri.encodeComponent(reviewLink)}';

      reviewQrSection = '''
        <div class="review-qr-container" style="text-align: center; margin: 10px auto; padding: 6px; border: 1px solid #e2e8f0; border-radius: 8px; background-color: #fafafa; max-width: 190px;">
          <div style="font-size: 11px; font-weight: bold; color: #0f172a; margin-bottom: 3px;">⭐ हमें Google पर रिव्यू दें ⭐</div>
          <img src="$reviewQrApi" style="width: 105px; height: 105px; display: block; margin: 0 auto;" alt="Review QR" />
          <div style="font-size: 8px; color: #64748b; margin-top: 3px;">कैमरे से QR कोड स्कैन करें</div>
        </div>
      ''';
    }

    final dateStr =
        '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';

    // टेम्पलेट में सुरक्षित रिप्लेसमेंट्स
    String html = baseHtmlTemplate;

    // अगर टेम्पलेट में <img src="{{upi_qr_section}}"> जैसी गलती हो, तो उसे केवल QR URL दें
    html = html.replaceAll('src="{{upi_qr_section}}"', 'src="$qrApiUrl"');
    html = html.replaceAll("src='{{upi_qr_section}}'", "src='$qrApiUrl'");

    // अगर टेम्पलेट में पहले से कोई टूटी हुई qrserver लिंक हो तो उसे शुद्ध एन्कोडेड URL से बदलें
    if (qrApiUrl.isNotEmpty) {
      html = html.replaceAll(RegExp(r'https:\/\/api\.qrserver\.com\/[^\s"\'<>]+'), qrApiUrl);
    }

    // अगर टेम्पलेट में {{gstin_section}} नहीं है, तो उसे फ़ोन नंबर के ठीक नीचे इंजेक्ट करें
    if (!html.contains('{{gstin_section}}') && complianceSection.isNotEmpty) {
      html = html.replaceAll('{{phone}}', '{{phone}}$complianceSection');
    }

    // अगर टेम्पलेट में {{review_qr_section}} नहीं है, तो उसे फुटर से पहले इंजेक्ट करें
    if (!html.contains('{{review_qr_section}}') && reviewQrSection.isNotEmpty) {
      html = html.replaceAll('{{footer_message}}', '$reviewQrSection<br/>{{footer_message}}');
    }

    // सभी वेरिएबल्स को रिप्लेस करें
    return html
        .replaceAll('{{restaurant_name}}', restaurant.name)
        .replaceAll('{{address}}', restaurant.address ?? '')
        .replaceAll('{{phone}}', restaurant.phone ?? '')
        .replaceAll('{{gstin_section}}', complianceSection)
        .replaceAll('{{gst_number}}', restaurant.gstNumber ?? '')
        .replaceAll('{{fssai_number}}', restaurant.fssaiNumber ?? '')
        .replaceAll('{{bill_no}}', billNo)
        .replaceAll('{{table_no}}', tableNo)
        .replaceAll('{{date_time}}', dateStr)
        .replaceAll('{{items_rows}}', rowsBuffer.toString())
        .replaceAll('{{subtotal}}', subtotal.toStringAsFixed(2))
        .replaceAll('{{discount_section}}', discountSection)
        .replaceAll('{{grand_total}}', grandTotal.toStringAsFixed(2))
        .replaceAll('{{payment_mode}}', paymentMode)
        .replaceAll('{{upi_qr_section}}', upiQrSection)
        .replaceAll('{{upi_qr}}', qrApiUrl)
        .replaceAll('{{upi_qr_url}}', qrApiUrl)
        .replaceAll('{{review_qr_section}}', reviewQrSection)
        .replaceAll('{{review_qr_url}}', reviewQrApi)
        .replaceAll('{{google_review_url}}', restaurant.googleReviewLink ?? '')
        .replaceAll('{{footer_message}}', restaurant.footerMessage ?? 'धन्यवाद! फिर पधारें 🙏');
  }
}
