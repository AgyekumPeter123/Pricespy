import 'package:cloud_firestore/cloud_firestore.dart';
import 'mail_service.dart';

class AdminService {
  static final _db = FirebaseFirestore.instance;

  // 1. Delete Post + Send Private Chat
  static Future<void> deletePostWithNotice({
    required String postId,
    required String uploaderId,
    required String reason,
  }) async {
    // A. Send Private Chat from "Support Team"
    final List<String> ids = ["SUPPORT_TEAM", uploaderId];
    ids.sort();
    final String chatId = ids.join("_");

    await _db.collection('chats').doc(chatId).collection('messages').add({
      'senderId': 'SUPPORT_TEAM',
      'text':
          "NOTICE: Your post was removed because: $reason. Please follow community guidelines.",
      'timestamp': FieldValue.serverTimestamp(),
    });

    // B. Delete the Post
    await _db.collection('posts').doc(postId).delete();
  }

  // 2. Restrict User + Email
  static Future<void> restrictUser({
    required String userId,
    required String userEmail,
    required int hours,
  }) async {
    final until = DateTime.now().add(Duration(hours: hours));

    await _db.collection('users').doc(userId).update({
      'isRestricted': true,
      'restrictedUntil': Timestamp.fromDate(until),
    });

    await MailService.sendSupportEmail(
      targetEmail: userEmail,
      subject: "Account Restricted - PriceSpy",
      body:
          "Your account has been restricted for $hours hours due to suspicious activity. You can log back in after ${until.toString()}.",
    );
  }

  // 3. Unrestrict User
  static Future<void> unrestrictUser(String userId) async {
    await _db.collection('users').doc(userId).update({
      'isRestricted': false,
      'restrictedUntil': null,
    });
  }

  // 4. Permanently Delete User Account (Database records only)
  static Future<void> deleteUserRecord(String userId, String userEmail) async {
    await _db.collection('users').doc(userId).delete();
    await MailService.sendSupportEmail(
      targetEmail: userEmail,
      subject: "Account Terminated",
      body:
          "Your PriceSpy account has been permanently deleted by the admin team.",
    );
  }
}
