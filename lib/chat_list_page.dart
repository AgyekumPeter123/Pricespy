import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'screens/chat/chat_screen.dart';
import 'encryption_service.dart';
import 'sidebar_drawer.dart';

class ChatListPage extends StatelessWidget {
  const ChatListPage({super.key});

  // --- HELPER: Build Status Icon (WhatsApp Tiered Ticks) ---
  Widget _buildStatusIcon(String status) {
    switch (status) {
      case 'sending':
        return const Icon(Icons.access_time, size: 16, color: Colors.grey);
      case 'sent':
        return const Icon(Icons.check, size: 16, color: Colors.grey);
      case 'delivered':
        return const Icon(Icons.done_all, size: 16, color: Colors.grey);
      case 'read':
        return const Icon(Icons.done_all, size: 16, color: Colors.blueAccent);
      default:
        return const SizedBox(width: 0);
    }
  }

  // --- ACTIONS (PINNING & DELETION) ---

  Future<void> _togglePin(
    BuildContext context,
    String chatId,
    bool isPinned,
    String myUid,
  ) async {
    final docRef = FirebaseFirestore.instance.collection('chats').doc(chatId);
    try {
      if (isPinned) {
        await docRef.update({
          'pinnedBy': FieldValue.arrayRemove([myUid]),
        });
      } else {
        await docRef.set({
          'pinnedBy': FieldValue.arrayUnion([myUid]),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Could not ${isPinned ? 'unpin' : 'pin'} chat. Permission denied.",
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteChat(BuildContext context, String chatId) async {
    try {
      // Note: This deletes the entire chat document.
      await FirebaseFirestore.instance.collection('chats').doc(chatId).delete();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Cannot delete chat. Permission denied."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showChatOptions(
    BuildContext context,
    String chatId,
    String otherName,
    bool isPinned,
    String myUid,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Options for $otherName",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const Divider(),
              ListTile(
                leading: Icon(
                  isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                  color: Colors.blue,
                ),
                title: Text(isPinned ? "Unpin Chat" : "Pin Chat"),
                onTap: () {
                  Navigator.pop(ctx);
                  _togglePin(context, chatId, isPinned, myUid);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text("Delete Chat"),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteChat(context, chatId);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text("Private Chats"),
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: const SidebarDrawer(),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('visibleFor', arrayContains: myUid)
            .orderBy('lastMessageTime', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No chats yet."));
          }

          var docs = snapshot.data!.docs;

          return ListView.separated(
            separatorBuilder: (c, i) => const Divider(height: 1),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final List participants = data['participants'] ?? [];

              final otherUid = participants.firstWhere(
                (id) => id != myUid,
                orElse: () => '',
              );
              if (otherUid.isEmpty) return const SizedBox.shrink();

              // --- PERFORMANCE FIX: READ MAPS INSTEAD OF NEW STREAM ---
              final Map<String, dynamic> names = data['userNames'] ?? {};
              final Map<String, dynamic> avatars = data['userAvatars'] ?? {};

              final String otherName = names[otherUid] ?? "User";
              final String? otherPhoto = avatars[otherUid];

              // Logic for Pinning and Status
              final bool isPinned = (data['pinnedBy'] as List? ?? []).contains(
                myUid,
              );
              final int unreadCount = data['unread_$myUid'] ?? 0;
              final bool isMe = data['lastSenderId'] == myUid;
              final String lastStatus = data['lastMessageStatus'] ?? 'sent';

              String lastMsg = "Message";
              try {
                lastMsg = EncryptionService.decryptMessage(
                  data['lastMessage'] ?? '',
                  doc.id,
                );
              } catch (e) {
                lastMsg = "Encrypted message";
              }

              return ListTile(
                tileColor: isPinned ? Colors.grey[50] : null,
                leading: CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: (otherPhoto != null && otherPhoto.isNotEmpty)
                      ? CachedNetworkImageProvider(otherPhoto)
                      : null,
                  child: (otherPhoto == null || otherPhoto.isEmpty)
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        otherName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isPinned)
                      const Icon(Icons.push_pin, size: 14, color: Colors.grey),
                  ],
                ),
                subtitle: Row(
                  children: [
                    if (isMe) ...[
                      _buildStatusIcon(lastStatus),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        lastMsg,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: unreadCount > 0
                              ? Colors.black87
                              : Colors.grey[600],
                          fontWeight: unreadCount > 0
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatDate(data['lastMessageTime']),
                      style: TextStyle(
                        fontSize: 12,
                        color: unreadCount > 0
                            ? Colors.green[800]
                            : Colors.grey,
                        fontWeight: unreadCount > 0
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    if (unreadCount > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green[800],
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          unreadCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      chatId: doc.id,
                      receiverId: otherUid,
                      receiverName: otherName,
                      receiverPhoto: otherPhoto,
                    ),
                  ),
                ),
                onLongPress: () => _showChatOptions(
                  context,
                  doc.id,
                  otherName,
                  isPinned,
                  myUid,
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    final now = DateTime.now();
    if (now.difference(date).inDays == 0)
      return DateFormat('h:mm a').format(date);
    if (now.difference(date).inDays == 1) return 'Yesterday';
    return DateFormat('MM/dd').format(date);
  }
}
