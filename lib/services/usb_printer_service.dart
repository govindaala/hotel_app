// lib/services/usb_printer_service.dart

import 'dart:convert';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/restaurant_profile_model.dart';

/// Existing app dependency के साथ paired Bluetooth thermal printer चलाता है.
/// USB/alternate platform plugin इस repository में install नहीं है, इसलिए
/// यहाँ वही Bluetooth API उपयोग की जाती है जो main.dart में पहले से चल रही है.
class UsbThermalPrinterManager {
  static final UsbThermalPrinterManager instance = UsbThermalPrinterManager._();
  UsbThermalPrinterManager._();

  Future<List<BluetoothInfo>> scanPrinters() async {
    try {
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (error) {
      debugPrint('Bluetooth printer scan failed: $error');
      return [];
    }
  }

  Future<bool> connectToPrinter(BluetoothInfo selectedDevice) async {
    try {
      if (await PrintBluetoothThermal.connectionStatus) return true;
      return await PrintBluetoothThermal.connect(
        macPrinterAddress: selectedDevice.macAdress,
      );
    } catch (error) {
      debugPrint('Bluetooth printer connection failed: $error');
      return false;
    }
  }

  Future<bool> sendBytesToPrinter({
    required BluetoothInfo selectedDevice,
    required List<int> bytes,
  }) async {
    try {
      final connected = await connectToPrinter(selectedDevice);
      if (!connected) return false;
      return await PrintBluetoothThermal.writeBytes(bytes);
    } catch (error) {
      debugPrint('Print Error: $error');
      return false;
    }
  }

  Future<bool> disconnectPrinter() async {
    try {
      return await PrintBluetoothThermal.disconnect;
    } catch (error) {
      debugPrint('Bluetooth printer disconnect failed: $error');
      return false;
    }
  }

  /// Hindi receipt PNG को ESC/POS raster image की तरह प्रिंट करें.
  /// इससे प्रिंटर के Hindi code-page पर निर्भरता नहीं रहती.
  Future<bool> printPngImage(
    Uint8List pngBytes, {
    int paperWidthMm = 58,
  }) async {
    try {
      if (!await PrintBluetoothThermal.connectionStatus) return false;

      final decoded = img.decodeImage(pngBytes);
      if (decoded == null) {
        debugPrint('Receipt image decode failed');
        return false;
      }

      final profile = await CapabilityProfile.load();
      final paperSize = paperWidthMm == 58 ? PaperSize.mm58 : PaperSize.mm80;
      final generator = Generator(paperSize, profile);
      final bytes = <int>[
        ...generator.imageRaster(decoded, align: PosAlign.center),
        ...generator.feed(2),
        ...generator.cut(),
      ];
      return await PrintBluetoothThermal.writeBytes(bytes);
    } catch (error) {
      debugPrint('Hindi thermal image print failed: $error');
      return false;
    }
  }

  // ESC/POS QR कोड कमांड जनरेटर
  List<int> _generateQrCodeBytes(String text) {
    final bytes = <int>[];
    final textBytes = utf8.encode(text);
    final length = textBytes.length + 3;
    final pL = length % 256;
    final pH = length ~/ 256;

    bytes.addAll([29, 40, 107, 4, 0, 49, 65, 50, 0]);
    bytes.addAll([29, 40, 107, 3, 0, 49, 67, 6]);
    bytes.addAll([29, 40, 107, 3, 0, 49, 69, 48]);
    bytes.addAll([29, 40, 107, pL, pH, 49, 80, 48]);
    bytes.addAll(textBytes);
    bytes.addAll([29, 40, 107, 3, 0, 49, 81, 48]);
    return bytes;
  }

  // ग्राहक का बिल: UPI QR में वास्तविक देय राशि और Google Review QR.
  Future<List<int>> generateReceiptBytes({
    required RestaurantProfileModel profile,
    required String invoiceNumber,
    required String tableOrType,
    required List<Map<String, dynamic>> items,
    required double grandTotal,
    String cashierName = 'Cashier',
  }) async {
    final bytes = <int>[];
    final prefs = await SharedPreferences.getInstance();

    final upiId = (profile.upiId?.trim().isNotEmpty ?? false)
        ? profile.upiId!.trim()
        : (prefs.getString('saved_hotel_upi') ?? '');
    final reviewLink = (profile.googleReviewLink?.trim().isNotEmpty ?? false)
        ? profile.googleReviewLink!.trim()
        : (prefs.getString('saved_hotel_review') ?? '');

    bytes.addAll([27, 64, 27, 97, 1, 27, 33, 16]);
    bytes.addAll(utf8.encode('${profile.name}\n'));
    bytes.addAll([27, 33, 0]);

    if (profile.address?.isNotEmpty ?? false) {
      bytes.addAll(utf8.encode('${profile.address}\n'));
    }
    if (profile.phone?.isNotEmpty ?? false) {
      bytes.addAll(utf8.encode('Mob: ${profile.phone}\n'));
    }
    if (profile.gstNumber?.isNotEmpty ?? false) {
      bytes.addAll(utf8.encode('GSTIN: ${profile.gstNumber}\n'));
    }
    if (profile.fssaiNumber?.isNotEmpty ?? false) {
      bytes.addAll(utf8.encode('FSSAI: ${profile.fssaiNumber}\n'));
    }

    bytes.addAll(utf8.encode('--------------------------------\n'));
    bytes.addAll([27, 97, 0]);
    bytes.addAll(utf8.encode('Bill No: $invoiceNumber\n'));
    bytes.addAll(utf8.encode('Type: $tableOrType | By: $cashierName\n'));
    bytes.addAll(utf8.encode('Date: ${DateTime.now().toString().substring(0, 16)}\n'));
    bytes.addAll(utf8.encode('--------------------------------\n'));
    bytes.addAll(utf8.encode('Item             Qty     Amount\n'));
    bytes.addAll(utf8.encode('--------------------------------\n'));

    for (final item in items) {
      var name = (item['name'] ?? '').toString();
      if (name.length > 15) name = name.substring(0, 15);
      name = name.padRight(16);

      final quantity = (item['qty'] ?? item['quantity'] ?? 1) as num;
      final price = (item['price'] as num?)?.toDouble() ?? 0.0;
      final itemTotal = price * quantity;
      final qtyText = 'x${quantity.toString()}'.padRight(6);
      final priceText = 'Rs.${itemTotal.toStringAsFixed(0)}'.padLeft(9);
      bytes.addAll(utf8.encode('$name$qtyText$priceText\n'));
    }

    bytes.addAll(utf8.encode('--------------------------------\n'));
    bytes.addAll([27, 97, 2, 27, 33, 16]);
    bytes.addAll(utf8.encode('TOTAL: Rs ${grandTotal.toStringAsFixed(2)}\n'));
    bytes.addAll([27, 33, 0]);
    bytes.addAll(utf8.encode('--------------------------------\n'));
    bytes.addAll([27, 97, 1]);

    if (upiId.isNotEmpty) {
      final cleanName = Uri.encodeComponent(profile.name.replaceAll('&', 'and'));
      final upiPayload = 'upi://pay?pa=$upiId&pn=$cleanName&am=${grandTotal.toStringAsFixed(2)}&cu=INR';
      bytes.addAll(utf8.encode('--- Scan to Pay Rs ${grandTotal.toStringAsFixed(0)} ---\n'));
      bytes.addAll(_generateQrCodeBytes(upiPayload));
      bytes.addAll(utf8.encode('\nUPI: $upiId\n\n'));
    }

    if (reviewLink.isNotEmpty) {
      bytes.addAll(utf8.encode('Please Rate Us on Google\n'));
      bytes.addAll(_generateQrCodeBytes(reviewLink));
      bytes.addAll(utf8.encode('\nScan to Review us\n* * * * *\n'));
    }

    final footer = (profile.footerMessage?.isNotEmpty ?? false)
        ? profile.footerMessage!
        : 'Thank You! Visit Again!';
    bytes.addAll(utf8.encode('\n$footer\n\n\n\n'));
    bytes.addAll([29, 86, 66, 0]);
    return bytes;
  }

  // किचन ऑर्डर टिकट.
  Future<List<int>> generateKotBytes({
    required String kotNumber,
    required String tableNumber,
    required List<Map<String, dynamic>> items,
    String waiterName = 'Waiter',
    String? note,
  }) async {
    final bytes = <int>[27, 64, 27, 97, 1, 27, 33, 16];
    bytes.addAll(utf8.encode('--- KOT ---\n'));
    bytes.addAll([27, 33, 0, 27, 97, 0]);
    bytes.addAll(utf8.encode('KOT No: $kotNumber\n'));
    bytes.addAll([27, 33, 16]);
    bytes.addAll(utf8.encode('TABLE: $tableNumber\n'));
    bytes.addAll([27, 33, 0]);
    bytes.addAll(utf8.encode('Waiter: $waiterName\n'));
    bytes.addAll(utf8.encode('Time: ${DateTime.now().toString().substring(11, 16)}\n'));
    bytes.addAll(utf8.encode('--------------------------------\n'));
    bytes.addAll(utf8.encode('Item                     Qty\n'));
    bytes.addAll(utf8.encode('--------------------------------\n'));
    bytes.addAll([27, 33, 16]);

    for (final item in items) {
      var name = (item['name'] ?? '').toString();
      if (name.length > 20) name = name.substring(0, 20);
      name = name.padRight(22);
      final quantity = item['qty'] ?? item['quantity'] ?? 1;
      bytes.addAll(utf8.encode('$name${'x$quantity'.padLeft(5)}\n'));
    }

    bytes.addAll([27, 33, 0]);
    if (note != null && note.isNotEmpty) {
      bytes.addAll(utf8.encode('--------------------------------\n'));
      bytes.addAll(utf8.encode('Special Note: $note\n'));
    }
    bytes.addAll(utf8.encode('--------------------------------\n\n\n\n'));
    bytes.addAll([29, 86, 66, 0]);
    return bytes;
  }
}
