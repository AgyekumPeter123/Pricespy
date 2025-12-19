import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../encryption_service.dart';

class ChatService {
  final String chatId;
  final String myUid;
  final String receiverId;

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

    // Check receiver status for initial tick state (sent vs delivered)
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(receiverId)
        .get();
    bool isReceiverOnline = false;
    if (userDoc.exists) {
      isReceiverOnline = userDoc.data()?['isOnline'] ?? false;
    }

    // WhatsApp Logic: Offline = sent (1 tick), Online = delivered (2 grey ticks)
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

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add(messageData);

    await _updateLastMessage(text, status: initialStatus);
  }

  // --- SEND MEDIA ---
  Future<void> sendMediaMessage(
    File file,
    String type, {
    String? fileName,
    String? caption,
    Map<String, dynamic>? replyMessage,
  }) async {
    DocumentReference messageRef = await FirebaseFirestore.instance
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

      // Check receiver status again after upload completes
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(receiverId)
          .get();
      bool isReceiverOnline = userDoc.data()?['isOnline'] ?? false;
      String finalStatus = isReceiverOnline ? 'delivered' : 'sent';

      await messageRef.update({
        'attachmentUrl': downloadUrl,
        'status': finalStatus,
        'expiresAt': Timestamp.fromDate(expiryDate),
      });

      String preview = type == 'text' ? caption : "Sent a $type";
      if (type == 'audio') preview = "🎤 Voice Message";

      await _updateLastMessage(preview, status: finalStatus);
    } catch (e) {
      await messageRef.update({'status': 'error'});
    }
  }

  Future<void> _updateLastMessage(
    String preview, {
    String status = 'sent',
  }) async {
    String myName = 'User';
    String? myPhoto;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(myUid)
          .get();
      if (userDoc.exists) {
        final data = userDoc.data();
        if (data != null) {
          myName = data['displayName'] ?? data['username'] ?? 'User';
          myPhoto = data['photoUrl'] ?? data['photoURL'];
        }
      }
    } catch (e) {}

    await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
      'lastMessage': EncryptionService.encryptMessage(preview, chatId),
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': myUid,
      'unread_$receiverId': FieldValue.increment(1),
      'participants': [myUid, receiverId],
      'lastMessageStatus': status,
      'userNames': {myUid: myName},
      'userAvatars': {myUid: myPhoto},
      // IMPORTANT: When a new message is sent, ensure chat is visible for both
      'visibleFor': FieldValue.arrayUnion([myUid, receiverId]),
    }, SetOptions(merge: true));
  }

  Future<void> deleteMessage(
    String docId,
    Map<String, dynamic> data, {
    required bool forEveryone,
  }) async {
    final docRef = FirebaseFirestore.instance
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

  // --- UPDATED CLEAR CHAT: Hide from List ---
  Future<void> clearChat() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {
        'deletedFor': FieldValue.arrayUnion([myUid]),
      });
    }

    // Hide chat from list by removing current user from visibility array
    batch.update(FirebaseFirestore.instance.collection('chats').doc(chatId), {
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
