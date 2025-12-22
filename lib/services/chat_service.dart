import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../encryption_service.dart';

class ChatService {
  final String chatId;
  final String myUid;
  final String receiverId;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  ChatService({
    required this.chatId,
    required this.myUid,
    required this.receiverId,
  });

  // --- SEND TEXT ---
  Future<void> sendTextMessage(
    String text,
    Map<String, dynamic>? replyMessage,
  ) async {
    if (text.trim().isEmpty) return;

    // 1. Check receiver status for initial tick state (sent vs delivered)
    final receiverDoc = await _db.collection('users').doc(receiverId).get();
    bool isReceiverOnline = false;
    if (receiverDoc.exists) {
      isReceiverOnline = receiverDoc.data()?['isOnline'] ?? false;
    }

    // 2. WhatsApp Logic: Offline = sent (1 tick), Online = delivered (2 grey ticks)
    String initialStatus = isReceiverOnline ? 'delivered' : 'sent';

    final messageData = {
      'senderId': myUid,
      'receiverId': receiverId,
      'text': EncryptionService.encryptMessage(text, chatId),
      'type': 'text',
      'status': initialStatus,
      'timestamp': FieldValue.serverTimestamp(),
      'deletedFor': [],
      'isDeleted': false,
      if (replyMessage != null) ...{
        'replyToMsgId': replyMessage['id'],
        'replyToText': replyMessage['text'],
        'replyToSender': replyMessage['senderName'],
        'replyToType': replyMessage['type'],
        'replyToAttachmentUrl': replyMessage['attachmentUrl'],
      },
    };

    await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add(messageData);

    await _updateLastMessage(text, status: initialStatus);
  }

  /// Marks all messages sent to ME as 'delivered' (2 grey ticks) cross-app
  /// Call this when the app resumes or at Splash Screen
  Future<void> markAllAsDelivered() async {
    try {
      // Query all chats where I am a participant
      final chatsSnapshot = await _db
          .collection('chats')
          .where('visibleFor', arrayContains: myUid)
          .get();

      for (var chatDoc in chatsSnapshot.docs) {
        // Find messages sent to ME that are still only 'sent'
        final messagesSnapshot = await chatDoc.reference
            .collection('messages')
            .where('receiverId', isEqualTo: myUid)
            .where('status', isEqualTo: 'sent')
            .get();

        if (messagesSnapshot.docs.isNotEmpty) {
          WriteBatch batch = _db.batch();
          for (var msg in messagesSnapshot.docs) {
            batch.update(msg.reference, {'status': 'delivered'});
          }
          await batch.commit();
        }
      }
    } catch (e) {
      debugPrint("Error marking delivered: $e");
    }
  }

  // --- SEND MEDIA ---
  Future<void> sendMediaMessage(
    File file,
    String type, {
    String? fileName,
    String? caption,
    Map<String, dynamic>? replyMessage,
  }) async {
    // Initial entry with 'sending' status and local path for immediate UI preview
    DocumentReference messageRef = await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add({
          'senderId': myUid,
          'receiverId': receiverId,
          'text': EncryptionService.encryptMessage(caption ?? "", chatId),
          'type': type,
          'attachmentUrl': null,
          'attachmentName': fileName,
          'localPath': file.path,
          'status': 'sending',
          'timestamp': FieldValue.serverTimestamp(),
          'deletedFor': [],
          'isDeleted': false,
          if (replyMessage != null) ...{
            'replyToMsgId': replyMessage['id'],
            'replyToText': replyMessage['text'],
            'replyToSender': replyMessage['senderName'],
            'replyToType': replyMessage['type'],
            'replyToAttachmentUrl': replyMessage['attachmentUrl'],
          },
        });

    await _performUpload(file, type, messageRef, caption ?? "");
  }

  Future<void> _performUpload(
    File file,
    String type,
    DocumentReference messageRef,
    String caption,
  ) async {
    try {
      String fileExt = file.path.split('.').last;
      String remotePath =
          '$chatId/$type/${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      String contentType = type == 'image'
          ? 'image/jpeg'
          : type == 'video'
          ? 'video/mp4'
          : 'application/octet-stream';
      DateTime expiryDate = DateTime.now().add(const Duration(days: 30));

      await Supabase.instance.client.storage
          .from('chat_files')
          .upload(
            remotePath,
            file,
            fileOptions: FileOptions(contentType: contentType),
          );

      final String downloadUrl = Supabase.instance.client.storage
          .from('chat_files')
          .getPublicUrl(remotePath);

      // Check receiver status again after upload completes to set tick state
      final userDoc = await _db.collection('users').doc(receiverId).get();
      bool isReceiverOnline = userDoc.data()?['isOnline'] ?? false;
      String finalStatus = isReceiverOnline ? 'delivered' : 'sent';

      await messageRef.update({
        'attachmentUrl': downloadUrl,
        'status': finalStatus,
        'expiresAt': Timestamp.fromDate(expiryDate),
      });

      // 🟢 FIX: Ensure preview text is never empty/null to prevent "Error Decrypting"
      String preview = caption.isNotEmpty ? caption : _getMediaTypeLabel(type);

      await _updateLastMessage(preview, status: finalStatus);
    } catch (e) {
      await messageRef.update({'status': 'error'});
    }
  }

  // 🟢 Helper to get clean labels for media types
  String _getMediaTypeLabel(String type) {
    switch (type) {
      case 'image':
        return "📷 Photo";
      case 'video':
        return "🎥 Video";
      case 'audio':
        return "🎤 Voice Message";
      default:
        return "📁 File";
    }
  }

  Future<void> _updateLastMessage(
    String preview, {
    String status = 'sent',
  }) async {
    String myName = 'User';
    String? myPhoto;

    // 🟢 FIX: Ensure we never encrypt an empty string
    final String safePreview = preview.isEmpty ? "Message" : preview;

    try {
      final userDoc = await _db.collection('users').doc(myUid).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        if (data != null) {
          myName = data['displayName'] ?? data['username'] ?? 'User';
          myPhoto = data['photoUrl'] ?? data['photoURL'];
        }
      }
    } catch (_) {}

    await _db.collection('chats').doc(chatId).set({
      'lastMessage': EncryptionService.encryptMessage(safePreview, chatId),
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': myUid,
      'unread_$receiverId': FieldValue.increment(1),
      'participants': [myUid, receiverId],
      'lastMessageStatus': status,
      'userNames': {myUid: myName},
      'userAvatars': {myUid: myPhoto},
      'visibleFor': FieldValue.arrayUnion([myUid, receiverId]),
    }, SetOptions(merge: true));
  }

  Future<void> deleteMessage(
    String docId,
    Map<String, dynamic> data, {
    required bool forEveryone,
  }) async {
    final docRef = _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(docId);

    if (forEveryone) {
      if (data['attachmentUrl'] != null) {
        _deleteSupabaseFile(data['attachmentUrl']);
      }
      await docRef.update({
        'isDeleted': true,
        'text': EncryptionService.encryptMessage(
          "🚫 This message was deleted",
          chatId,
        ),
        'type': 'text',
        'attachmentUrl': null,
      });
    } else {
      await docRef.update({
        'deletedFor': FieldValue.arrayUnion([myUid]),
      });
    }
  }

  Future<void> clearChat() async {
    final snapshot = await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .get();

    final batch = _db.batch();
    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {
        'deletedFor': FieldValue.arrayUnion([myUid]),
      });
    }

    batch.update(_db.collection('chats').doc(chatId), {
      'visibleFor': FieldValue.arrayRemove([myUid]),
      'unread_$myUid': 0,
    });

    await batch.commit();
  }

  Future<void> _deleteSupabaseFile(String url) async {
    try {
      Uri uri = Uri.parse(url);
      int index = uri.pathSegments.indexOf('chat_files');
      if (index != -1 && index + 1 < uri.pathSegments.length) {
        String path = uri.pathSegments.sublist(index + 1).join('/');
        await Supabase.instance.client.storage.from('chat_files').remove([
          path,
        ]);
      }
    } catch (_) {}
  }
}
