import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_pos_printer_platform/flutter_pos_printer_platform.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/restaurant_profile_model.dart';

class UsbThermalPrinterManager {
  static final UsbThermalPrinterManager instance = UsbThermalPrinterManager._();
  UsbThermalPrinterManager._();

  final PrinterManager _printerManager = PrinterManager.instance;
  final List<PrinterDevice> _devices = [];

  // ================= 1. डिवाइस स्कैनिंग (USB और Bluetooth दोनों) =================
  Future<List<PrinterDevice>> scanPrinters({PrinterType type = PrinterType.usb}) async {
    _devices.clear();
    _printerManager.discovery(type: type).listen((device) {
      if (!_devices.any((d) => d.address == device.address)) {
        _devices.add(device);
      }
    });
    await Future.delayed(const Duration(seconds: 2));
    return _devices;
  }

  // ================= 2. प्रिंट बाइट्स भेजना (USB / Bluetooth) =================
  Future<bool> sendBytesToPrinter({
    required PrinterDevice selectedDevice,
    required List<int> bytes,
    PrinterType type = PrinterType.usb,
  }) async {
    try {
      if (type == PrinterType.usb) {
        await _printerManager.connect(
          type: PrinterType.usb,
          model: UsbPrinterInput(
            name: selectedDevice.name,
            productId: selectedDevice.productId,
            vendorId: selectedDevice.vendorId,
          ),
        );
      } else {
        await _printerManager.connect(
          type: PrinterType.bluetooth,
          model: BluetoothPrinterInput(
            name: selectedDevice.name,
            address: selectedDevice.address!,
            isBle: false,
            autoConnect: false,
          ),
        );
      }

      await _printerManager.send(type: type, bytes: bytes);
      await Future.delayed(const Duration(milliseconds: 600));
      await _printerManager.disconnect(type: type);
      return true;
    } catch (e) {
      debugPrint("Print Error: $e");
      return false;
    }
  }

  // ================= 3. ESC/POS QR कोड कमांड जनरेटर =================
  List<int> _generateQrCodeBytes(String text) {
    List<int> bytes = [];
    final textBytes = utf8.encode(text);
    final length = textBytes.length + 3;
    final pL = length % 256;
    final pH = length ~/ 256;

    // मॉडल 2 सेट करना
    bytes.addAll([29, 40, 107, 4, 0, 49, 65, 50, 0]);
    // साइज़ 6 सेट करना (थर्मल प्रिंटर पर साफ़ स्कैन के लिए)
    bytes.addAll([29, 40, 107, 3, 0, 49, 67, 6]);
    // एरर करेक्शन लेवल L
    bytes.addAll([29, 40, 107, 3, 0, 49, 69, 48]);
    // डेटा स्टोर करना
    bytes.addAll([29, 40, 107, pL, pH, 49, 80, 48]);
    bytes.addAll(textBytes);
    // QR कोड प्रिंट करना
    bytes.addAll([29, 40, 107, 3, 0, 49, 81, 48]);

    return bytes;
  }

  // ================= 4. ग्राहक का अंतिम बिल (Receipt with Dynamic/Static QR) =================
  Future<List<int>> generateReceiptBytes({
    required RestaurantProfileModel profile,
    required String invoiceNumber,
    required String tableOrType,
    required List<Map<String, dynamic>> items,
    required double grandTotal,
    String cashierName = 'Cashier',
  }) async {
    List<int> bytes = [];
    final prefs = await SharedPreferences.getInstance();

    // मेमोरी से बैकअप उठाना ताकि ऑफ़लाइन भी न रुके
    String upiId = (profile.upiId != null && profile.upiId!.isNotEmpty)
        ? profile.upiId!
        : (prefs.getString('saved_hotel_upi') ?? '');

    String reviewLink = (profile.googleReviewLink != null && profile.googleReviewLink!.isNotEmpty)
        ? profile.googleReviewLink!
        : (prefs.getString('saved_hotel_review') ?? '');

    // इनिशियलाइज़
    bytes.addAll([27, 64]);

    // हेडर - सेंटर अलाइन
    bytes.addAll([27, 97, 1]);
    bytes.addAll([27, 33, 16]); // Double Height (बड़ा नाम)
    bytes.addAll(utf8.encode("${profile.name}\n"));
    bytes.addAll([27, 33, 0]); // नार्मल फ़ॉन्ट

    if (profile.address != null && profile.address!.isNotEmpty) {
      bytes.addAll(utf8.encode("${profile.address}\n"));
    }
    if (profile.phone != null && profile.phone!.isNotEmpty) {
      bytes.addAll(utf8.encode("Mob: ${profile.phone}\n"));
    }
    if (profile.gstNumber != null && profile.gstNumber!.isNotEmpty) {
      bytes.addAll(utf8.encode("GSTIN: ${profile.gstNumber}\n"));
    }
    if (profile.fssaiNumber != null && profile.fssaiNumber!.isNotEmpty) {
      bytes.addAll(utf8.encode("FSSAI: ${profile.fssaiNumber}\n"));
    }

    bytes.addAll(utf8.encode("--------------------------------\n"));

    // बिल इन्फो
    bytes.addAll([27, 97, 0]); // Left Align
    bytes.addAll(utf8.encode("Bill No: $invoiceNumber\n"));
    bytes.addAll(utf8.encode("Type: $tableOrType | By: $cashierName\n"));
    bytes.addAll(utf8.encode("Date: ${DateTime.now().toString().substring(0, 16)}\n"));
    bytes.addAll(utf8.encode("--------------------------------\n"));
    bytes.addAll(utf8.encode("Item             Qty     Amount \n"));
    bytes.addAll(utf8.encode("--------------------------------\n"));

    // आइटम्स लिस्ट
    for (var item in items) {
      String name = item['name'].toString();
      if (name.length > 15) name = name.substring(0, 15);
      name = name.padRight(16);

      String qty = "x${item['quantity']}".padRight(6);
      double itemTotal = (item['price'] as num) * (item['quantity'] as num);
      String price = "Rs.${itemTotal.toStringAsFixed(0)}".padLeft(9);

      bytes.addAll(utf8.encode("$name$qty$price\n"));
    }

    bytes.addAll(utf8.encode("--------------------------------\n"));

    // टोटल राशि
    bytes.addAll([27, 97, 2]); // Right Align
    bytes.addAll([27, 33, 16]); // बोल्ड/बड़ा
    bytes.addAll(utf8.encode("TOTAL: Rs ${grandTotal.toStringAsFixed(2)}\n"));
    bytes.addAll([27, 33, 0]);
    bytes.addAll(utf8.encode("--------------------------------\n"));

    // 1. पेमेंट QR कोड (UPI)
    bytes.addAll([27, 97, 1]); // Center Align
    if (upiId.isNotEmpty) {
      final cleanName = Uri.encodeComponent(profile.name.replaceAll('&', 'and'));
      
      // यदि अमाउंट उपलब्ध है तो डायनामिक, वर्ना डिफ़ॉल्ट ओपन QR
      String upiPayload;
      if (grandTotal > 0) {
        upiPayload = "upi://pay?pa=$upiId&pn=$cleanName&am=${grandTotal.toStringAsFixed(2)}&cu=INR";
        bytes.addAll(utf8.encode("--- Scan to Pay Rs ${grandTotal.toStringAsFixed(0)} ---\n"));
      } else {
        upiPayload = "upi://pay?pa=$upiId&pn=$cleanName&cu=INR";
        bytes.addAll(utf8.encode("--- Scan & Enter Amount ---\n"));
      }

      bytes.addAll(_generateQrCodeBytes(upiPayload));
      bytes.addAll(utf8.encode("\nUPI: $upiId\n\n"));
    }

    // 2. गूगल रिव्यू QR कोड
    if (reviewLink.isNotEmpty) {
      bytes.addAll(utf8.encode("Please Rate Us on Google\n"));
      bytes.addAll(_generateQrCodeBytes(reviewLink));
      bytes.addAll(utf8.encode("\nScan to Review us\n* * * * *\n"));
    }

    // फुटर मैसेज
    final footer = (profile.footerMessage != null && profile.footerMessage!.isNotEmpty)
        ? profile.footerMessage!
        : "Thank You! Visit Again!";
    bytes.addAll(utf8.encode("\n$footer\n\n\n\n"));

    // पेपर कट कमांड
    bytes.addAll([29, 86, 66, 0]);

    return bytes;
  }

  // ================= 5. KOT (किचन ऑर्डर टिकट) प्रिंट जनरेटर =================
  Future<List<int>> generateKotBytes({
    required String kotNumber,
    required String tableNumber,
    required List<Map<String, dynamic>> items,
    String waiterName = 'Waiter',
    String? note,
  }) async {
    List<int> bytes = [];

    bytes.addAll([27, 64]); // Reset
    bytes.addAll([27, 97, 1]); // Center
    bytes.addAll([27, 33, 16]); // Large Text
    bytes.addAll(utf8.encode("--- KOT ---\n"));
    bytes.addAll([27, 33, 0]);

    bytes.addAll([27, 97, 0]); // Left
    bytes.addAll(utf8.encode("KOT No: $kotNumber\n"));
    bytes.addAll([27, 33, 16]);
    bytes.addAll(utf8.encode("TABLE: $tableNumber\n"));
    bytes.addAll([27, 33, 0]);
    bytes.addAll(utf8.encode("Waiter: $waiterName\n"));
    bytes.addAll(utf8.encode("Time: ${DateTime.now().toString().substring(11, 16)}\n"));
    bytes.addAll(utf8.encode("--------------------------------\n"));
    bytes.addAll(utf8.encode("Item                     Qty    \n"));
    bytes.addAll(utf8.encode("--------------------------------\n"));

    bytes.addAll([27, 33, 16]); // किचन के लिए आइटम बड़े दिखें
    for (var item in items) {
      String name = item['name'].toString();
      if (name.length > 20) name = name.substring(0, 20);
      name = name.padRight(22);
      String qty = "x${item['quantity']}".padLeft(5);

      bytes.addAll(utf8.encode("$name$qty\n"));
    }
    bytes.addAll([27, 33, 0]);

    if (note != null && note.isNotEmpty) {
      bytes.addAll(utf8.encode("--------------------------------\n"));
      bytes.addAll(utf8.encode("Special Note: $note\n"));
    }

    bytes.addAll(utf8.encode("--------------------------------\n\n\n\n"));
    bytes.addAll([29, 86, 66, 0]); // Cut Paper

    return bytes;
  }
}
