import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ChatStatusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String currentUserId;

  ChatStatusService({required this.currentUserId});

  /// Properly clean up any resources if needed
  void dispose() {}

  /// This is called by the global LifeCycleManager when the app is opened or minimized.
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

  /// Provides a stream to listen to a specific user's online status.
  /// Used by the ChatScreen AppBar to show the "Online/Offline" sub-header.
  Stream<DocumentSnapshot> getUserPresenceStream(String userId) {
    return _firestore.collection('users').doc(userId).snapshots();
  }

  // --- 🟡 TYPING INDICATOR METHODS ---

  /// Sets whether the current user is currently typing in a specific chat.
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

  /// Listens to the other participant's typing status in a chat.
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

  // --- 🔵 MESSAGE STATUS LOGIC (TICKS) ---

  /// GLOBAL DELIVERY SWEEP:
  /// Updates all incoming 'sent' messages to 'delivered' across all conversations.
  /// Called by LifeCycleManager the moment the user resumes the app.
  Future<void> markAllAsDelivered() async {
    try {
      // 1. Find all chats where the user is a visible participant
      final chatsSnapshot = await _firestore
          .collection('chats')
          .where('visibleFor', arrayContains: currentUserId)
          .get();

      if (chatsSnapshot.docs.isEmpty) return;

      for (var chatDoc in chatsSnapshot.docs) {
        // 2. Find messages sent to ME that are currently only 'sent' (1 tick)
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

          // 3. Update parent Chat document for double grey ticks in the list view
          batch.update(chatDoc.reference, {'lastMessageStatus': 'delivered'});
          await batch.commit();
        }
      }
    } catch (e) {
      debugPrint("Error marking all as delivered: $e");
    }
  }

  /// MARK AS READ:
  /// Transitions status from 'delivered' to 'read' (Blue Ticks).
  /// Triggered by the ChatScreen when a user views a specific conversation.
  void markMessagesAsRead(String chatId) async {
    try {
      // 1. Reset unread counter to hide notification badges
      await _firestore.collection('chats').doc(chatId).update({
        'unread_$currentUserId': 0,
      });

      // 2. Query all messages sent by the OTHER person that aren't 'read' yet
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

        // 3. Sync main chat document for blue ticks on the Chat List Page
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
