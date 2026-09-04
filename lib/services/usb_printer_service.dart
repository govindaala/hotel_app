import 'package:flutter_pos_printer_platform/flutter_pos_printer_platform.dart';

class UsbThermalPrinterManager {
  static final UsbThermalPrinterManager instance = UsbThermalPrinterManager._();
  UsbThermalPrinterManager._();

  final PrinterManager _printerManager = PrinterManager.instance;
  final List<PrinterDevice> _devices = [];

  // कनेक्टेड USB / Type-C प्रिंटर्स ढूँढना (58mm और 80mm दोनों के लिए)
  Future<List<PrinterDevice>> scanUsbPrinters() async {
    _devices.clear();
    _printerManager.discovery(type: PrinterType.usb).listen((device) {
      if (!_devices.any((d) => d.address == device.address)) {
        _devices.add(device);
      }
    });
    await Future.delayed(const Duration(seconds: 2));
    return _devices;
  }

  // प्रिंट कमांड भेजना
  Future<bool> printReceiptUsb({
    required PrinterDevice selectedDevice,
    required List<int> bytes,
  }) async {
    try {
      await _printerManager.connect(
        type: PrinterType.usb,
        model: UsbPrinterInput(
          name: selectedDevice.name,
          productId: selectedDevice.productId,
          vendorId: selectedDevice.vendorId,
        ),
      );
      await _printerManager.send(type: PrinterType.usb, bytes: bytes);
      await Future.delayed(const Duration(milliseconds: 500));
      await _printerManager.disconnect(type: PrinterType.usb);
      return true;
    } catch (e) {
      return false;
    }
  }
}
