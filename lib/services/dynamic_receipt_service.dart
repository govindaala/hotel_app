import 'dart:convert';
import '../models/restaurant_profile_model.dart';

class DynamicReceiptService {
  /// HTML टेम्पलेट में रेस्टोरेंट और बिल का डायनामिक डेटा भरना
  static String generateBillHtml({
    required String baseHtmlTemplate,
    required RestaurantProfileModel restaurant,
    required String billNo,
    required String tableNo,
    required DateTime dateTime,
    required List<Map<String, dynamic>> items, // [{'name': 'दाल मखानी', 'qty': 2, 'price': 190}]
    required double grandTotal,
    double discount = 0.0,
    String paymentMode = 'CASH',
  }) {
    // 1. आइटम रो जनरेट करना
    final rowsBuffer = StringBuffer();
    double subtotal = 0.0;

    for (final item in items) {
      final name = item['name'] ?? '';
      final qty = item['qty'] ?? 1;
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

    // 2. GST सेक्शन (यदि उपलब्ध हो)
    final gstinSection = (restaurant.gstin != null && restaurant.gstin!.isNotEmpty)
        ? '<div>GSTIN: ${restaurant.gstin}</div>'
        : '';

    // 3. डिस्काउंट रो (यदि लागू हो)
    final discountSection = discount > 0
        ? '''
          <tr>
            <td>छूट (Discount):</td>
            <td class="text-right" style="color: red;">- ₹${discount.toStringAsFixed(2)}</td>
          </tr>
        '''
        : '';

    // 4. डायनामिक UPI QR (सटीक राशि का QR)
    String upiQrSection = '';
    if (restaurant.upiId != null && restaurant.upiId!.isNotEmpty) {
      // UPI intent string
      final upiString =
          'upi://pay?pa=${restaurant.upiId}&pn=${Uri.encodeComponent(restaurant.name)}&am=${grandTotal.toStringAsFixed(2)}&cu=INR';
      final qrApiUrl =
          'https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=${Uri.encodeComponent(upiString)}';

      upiQrSection = '''
        <div class="qr-container">
          <div><b>स्कैन करके ₹${grandTotal.toStringAsFixed(2)} पे करें</b></div>
          <img class="qr-img" src="$qrApiUrl" alt="UPI QR" />
          <div style="font-size: 10px;">UPI ID: ${restaurant.upiId}</div>
        </div>
        <div class="divider"></div>
      ''';
    }

    // 5. Google Review QR (यदि उपलब्ध हो)
    String reviewQrSection = '';
    if (restaurant.reviewUrl != null && restaurant.reviewUrl!.isNotEmpty) {
      final reviewQrApi =
          'https://api.qrserver.com/v1/create-qr-code/?size=130x130&data=${Uri.encodeComponent(restaurant.reviewUrl!)}';
      reviewQrSection = '''
        <div class="qr-container">
          <div>⭐ <b>हमें Google पर रेट करें</b> ⭐</div>
          <img class="qr-img" src="$reviewQrApi" alt="Review QR" />
        </div>
        <div class="divider"></div>
      ''';
    }

    // 6. टेम्पलेट में टोकन रिप्लेसमेंट
    final dateStr =
        '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';

    return baseHtmlTemplate
        .replaceAll('{{restaurant_name}}', restaurant.name)
        .replaceAll('{{address}}', restaurant.address)
        .replaceAll('{{phone}}', restaurant.phone)
        .replaceAll('{{gstin_section}}', gstinSection)
        .replaceAll('{{bill_no}}', billNo)
        .replaceAll('{{table_no}}', tableNo)
        .replaceAll('{{date_time}}', dateStr)
        .replaceAll('{{items_rows}}', rowsBuffer.toString())
        .replaceAll('{{subtotal}}', subtotal.toStringAsFixed(2))
        .replaceAll('{{discount_section}}', discountSection)
        .replaceAll('{{grand_total}}', grandTotal.toStringAsFixed(2))
        .replaceAll('{{payment_mode}}', paymentMode)
        .replaceAll('{{upi_qr_section}}', upiQrSection)
        .replaceAll('{{review_qr_section}}', reviewQrSection)
        .replaceAll('{{footer_message}}', restaurant.footerMessage);
  }
}
