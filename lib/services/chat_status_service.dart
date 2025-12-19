import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ChatStatusService with WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String currentUserId;

  ChatStatusService({required this.currentUserId}) {
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setUserOnline(true);
    } else {
      setUserOnline(false);
    }
  }

  Future<void> setUserOnline(bool isOnline) async {
    try {
      await _firestore.collection('users').doc(currentUserId).update({
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error updating presence: $e");
    }
  }

  Stream<DocumentSnapshot> getUserPresenceStream(String userId) {
    return _firestore.collection('users').doc(userId).snapshots();
  }

  Future<void> setTypingStatus(String chatId, bool isTyping) async {
    try {
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('activity')
          .doc(currentUserId)
          .set({
            'isTyping': isTyping,
            'lastTyped': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint("Error setting typing status: $e");
    }
  }

  Stream<bool> getOtherUserTypingStream(String chatId, String otherUserId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('activity')
        .doc(otherUserId)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists) return false;
          final data = snapshot.data();
          if (data == null || data['isTyping'] == false) return false;
          return true;
        });
  }

  /// MARK AS READ: Clears counters and updates message/chat status to 'read'
  void markMessagesAsRead(String chatId) async {
    try {
      // 1. Reset unread counter for current user
      await _firestore.collection('chats').doc(chatId).update({
        'unread_$currentUserId': 0,
      });

      // 2. Mark incoming messages as read
      final snapshot = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('senderId', isNotEqualTo: currentUserId)
          .where('status', whereIn: ['sent', 'delivered'])
          .get();

      if (snapshot.docs.isNotEmpty) {
        WriteBatch batch = _firestore.batch();
        for (var doc in snapshot.docs) {
          batch.update(doc.reference, {'status': 'read'});
        }

        // 3. Update main chat document for blue ticks on list
        batch.update(_firestore.collection('chats').doc(chatId), {
          'lastMessageStatus': 'read',
        });

        await batch.commit();
      }
    } catch (e) {
      debugPrint("Error marking messages as read: $e");
    }
  }
}
