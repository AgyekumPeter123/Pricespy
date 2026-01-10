import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ChatStatusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String currentUserId;

  ChatStatusService({required this.currentUserId});

  void dispose() {}

  /// Call this when app resumes/opens
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

  // 🟢 NEW: Call this BEFORE signing out!
  Future<void> goOffline() async {
    try {
      await _firestore.collection('users').doc(currentUserId).update({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error going offline: $e");
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

  Future<void> markAllAsDelivered() async {
    try {
      final chatsSnapshot = await _firestore
          .collection('chats')
          .where('visibleFor', arrayContains: currentUserId)
          .get();

      if (chatsSnapshot.docs.isEmpty) return;

      for (var chatDoc in chatsSnapshot.docs) {
        final messagesSnapshot = await chatDoc.reference
            .collection('messages')
            .where('receiverId', isEqualTo: currentUserId)
            .where('status', isEqualTo: 'sent')
            .get();

        if (messagesSnapshot.docs.isNotEmpty) {
          WriteBatch batch = _firestore.batch();
          for (var doc in messagesSnapshot.docs) {
            batch.update(doc.reference, {'status': 'delivered'});
          }
          batch.update(chatDoc.reference, {'lastMessageStatus': 'delivered'});
          await batch.commit();
        }
      }
    } catch (e) {
      debugPrint("Error marking all as delivered: $e");
    }
  }

  void markMessagesAsRead(String chatId) async {
    try {
      await _firestore.collection('chats').doc(chatId).update({
        'unread_$currentUserId': 0,
      });

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
