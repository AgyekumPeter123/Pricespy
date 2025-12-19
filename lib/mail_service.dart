import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class MailService {
  static const String _adminEmail = "agyekumpeter123@gmail.com";
  static const String _appPassword = "xwqt gsri dqfv buhl";

  static Future<void> sendSupportEmail({
    required String targetEmail,
    required String subject,
    required String body,
  }) async {
    final smtpServer = gmail(_adminEmail, _appPassword);

    final message = Message()
      ..from = const Address(_adminEmail, 'PriceSpy Support')
      ..recipients.add(targetEmail)
      ..subject = subject
      ..text = body;

    try {
      await send(message, smtpServer);
      print("✅ Support email sent to $targetEmail");
    } catch (e) {
      print("❌ Email failed: $e");
    }
  }
}
