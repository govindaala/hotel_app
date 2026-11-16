import 'package:share_plus/share_plus.dart';
import 'package:whatsapp_share2/whatsapp_share2.dart';

/// Shares a bill PDF to the customer's WhatsApp chat when available.
///
/// WhatsApp still requires the cashier to review the recipient and tap Send.
/// If neither WhatsApp app is installed, or its targeted share handoff fails,
/// the generic Android share sheet is used as a safe fallback.
class WhatsAppBillShareService {
  WhatsAppBillShareService._();

  static String normalizeIndianPhone(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) return '91$digits';
    if (digits.length == 12 && digits.startsWith('91')) return digits;
    throw FormatException('ग्राहक का मोबाइल नंबर 10 अंकों का या 91 सहित 12 अंकों का होना चाहिए।');
  }

  /// Returns true when a WhatsApp app accepted the targeted share request.
  /// Returns false when the generic share sheet was opened instead.
  static Future<bool> sharePdf({
    required String phone,
    required String filePath,
    required String subject,
    required String message,
  }) async {
    final normalizedPhone = normalizeIndianPhone(phone);
    final standardInstalled =
        await WhatsappShare.isInstalled(package: Package.whatsapp) == true;
    final businessInstalled =
        await WhatsappShare.isInstalled(package: Package.businessWhatsapp) == true;

    final Package? target = standardInstalled
        ? Package.whatsapp
        : (businessInstalled ? Package.businessWhatsapp : null);

    if (target == null) {
      await Share.shareXFiles(
        [XFile(filePath)],
        subject: subject,
        text: '$message\nग्राहक WhatsApp: +$normalizedPhone',
      );
      return false;
    }

    try {
      final accepted = await WhatsappShare.shareFile(
        phone: normalizedPhone,
        text: message,
        filePath: [filePath],
        package: target,
      );
      if (accepted == true) return true;
    } catch (_) {
      // Fall through to the system share sheet. Do not report delivery.
    }

    await Share.shareXFiles(
      [XFile(filePath)],
      subject: subject,
      text: '$message\nग्राहक WhatsApp: +$normalizedPhone',
    );
    return false;
  }
}
