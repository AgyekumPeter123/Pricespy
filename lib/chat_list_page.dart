import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'screens/chat/chat_screen.dart';
import 'encryption_service.dart';
import 'sidebar_drawer.dart';
import 'constants/palette.dart'; // 🟢 Import Palette

class ChatListPage extends StatelessWidget {
  const ChatListPage({super.key});

  Widget _buildStatusIcon(String status) {
    switch (status) {
      case 'sending':
        return const Icon(Icons.access_time, size: 16, color: Colors.grey);
      case 'sent':
        return const Icon(Icons.check, size: 16, color: Colors.grey);
      case 'delivered':
        return const Icon(Icons.done_all, size: 16, color: Colors.grey);
      case 'read':
        // 🟢 Updated to Palette.primary (Deep Cerulean) instead of BlueAccent
        return const Icon(Icons.done_all, size: 16, color: Palette.primary);
      default:
        return const SizedBox(width: 0);
    }
  }

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
            backgroundColor: Palette.error, // 🟢 Updated
          ),
        );
      }
    }
  }

  Future<void> _deleteChat(BuildContext context, String chatId) async {
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).delete();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Cannot delete chat. Permission denied."),
            backgroundColor: Palette.error, // 🟢 Updated
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 15),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                "Options for $otherName",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Palette.textDark,
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: Icon(
                  isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                  color: Palette.primary, // 🟢 Updated
                ),
                title: Text(isPinned ? "Unpin Chat" : "Pin Chat"),
                onTap: () {
                  Navigator.pop(ctx);
                  _togglePin(context, chatId, isPinned, myUid);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete,
                  color: Palette.error,
                ), // 🟢 Updated
                title: const Text("Delete Chat"),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteChat(context, chatId);
                },
              ),
              const SizedBox(height: 10),
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Private Chats",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Palette.primary,
        elevation: 0,
        centerTitle: true,
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
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 80,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "No chats yet.",
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          var docs = snapshot.data!.docs;

          return ListView.separated(
            itemCount: docs.length,
            // 🟢 MODERN DIVIDER: Indented to align with text, subtle color
            separatorBuilder: (c, i) => Divider(
              height: 1,
              thickness: 0.5,
              indent: 84, // Skips the avatar area for a cleaner look
              endIndent: 16,
              color: Colors.grey.shade200,
            ),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final List participants = data['participants'] ?? [];

              final otherUid = participants.firstWhere(
                (id) => id != myUid,
                orElse: () => '',
              );
              if (otherUid.isEmpty) return const SizedBox.shrink();

              final Map<String, dynamic> names = data['userNames'] ?? {};
              final Map<String, dynamic> avatars = data['userAvatars'] ?? {};

              final String otherName = names[otherUid] ?? "User";
              final String? otherPhoto = avatars[otherUid];

              final bool isPinned = (data['pinnedBy'] as List? ?? []).contains(
                myUid,
              );
              final int unreadCount = data['unread_$myUid'] ?? 0;
              final bool isMe = data['lastSenderId'] == myUid;
              final String lastStatus = data['lastMessageStatus'] ?? 'sent';

              // --- LOGIC FOR CLEARED CHATS ---
              String lastMsg = "Message";
              try {
                lastMsg = EncryptionService.decryptMessage(
                  data['lastMessage'] ?? '',
                  doc.id,
                );
              } catch (e) {
                lastMsg = "Encrypted message";
              }

              final Timestamp? lastMsgTime = data['lastMessageTime'];
              final Timestamp? clearedAt = data['clearedAt_$myUid'];

              bool isCleared = false;
              if (clearedAt != null && lastMsgTime != null) {
                if (clearedAt.compareTo(lastMsgTime) > 0) {
                  isCleared = true;
                  lastMsg = "Chat cleared"; // Set display text
                }
              }

              return ListTile(
                // 🟢 PINNED HIGHLIGHT: Subtle blue tint instead of grey
                tileColor: isPinned ? Palette.primary.withOpacity(0.03) : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                leading: Stack(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.grey[200],
                      backgroundImage:
                          (otherPhoto != null && otherPhoto.isNotEmpty)
                          ? CachedNetworkImageProvider(otherPhoto)
                          : null,
                      child: (otherPhoto == null || otherPhoto.isEmpty)
                          ? const Icon(Icons.person, color: Colors.grey)
                          : null,
                    ),
                    if (isPinned)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.push_pin,
                            size: 14,
                            color: Palette.primary, // 🟢 Updated
                          ),
                        ),
                      ),
                  ],
                ),
                title: Text(
                  otherName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Palette.textDark, // 🟢 Updated
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Row(
                    children: [
                      if (isMe && !isCleared) ...[
                        _buildStatusIcon(lastStatus),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          lastMsg,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCleared
                                ? Colors.grey.shade400
                                : (unreadCount > 0
                                      ? Palette
                                            .textDark // 🟢 Darker if unread
                                      : Palette.textMedium),
                            fontWeight: unreadCount > 0
                                ? FontWeight.w600
                                : FontWeight.normal,
                            fontStyle: isCleared
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
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
                            ? Palette
                                  .primary // 🟢 Blue if unread
                            : Palette.textMedium,
                        fontWeight: unreadCount > 0
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (unreadCount > 0)
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Palette.tertiary, // 🟢 Coral for unread badge
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
