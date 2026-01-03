import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'product_details_page.dart';
import 'sidebar_drawer.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  final User? currentUser = FirebaseAuth.instance.currentUser;

  // --- LOGIC 1: DELETE NOTIFICATION ---
  Future<void> _deleteNotification(String docId) async {
    if (currentUser == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser!.uid)
        .collection('notifications')
        .doc(docId)
        .delete();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Notification deleted"),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // --- LOGIC 2: MARK ALL AS READ ---
  Future<void> _markAllAsRead() async {
    if (currentUser == null) return;

    // Get all unread notifications (excluding replies)
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser!.uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .where('type', isNotEqualTo: 'reply')
        .get();

    if (snapshot.docs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("All caught up!")));
      }
      return;
    }

    // Batch update for performance
    WriteBatch batch = FirebaseFirestore.instance.batch();
    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {'read': true});
    }

    await batch.commit();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("All marked as read")));
    }
  }

  // --- LOGIC 3: NAVIGATION ---
  Future<void> _handleNotificationTap(
    String postId,
    String notificationId,
    bool isRead,
  ) async {
    // Only update if not already read to save writes
    if (currentUser != null && !isRead) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser!.uid)
          .collection('notifications')
          .doc(notificationId)
          .update({'read': true});
    }

    // If there is no post ID (e.g. system alert), just return
    if (postId.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final doc = await FirebaseFirestore.instance
          .collection('posts')
          .doc(postId)
          .get();

      if (mounted) Navigator.pop(context); // Close loading

      if (doc.exists && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailsPage(
              data: doc.data() as Map<String, dynamic>,
              documentId: doc.id,
              autoOpenComments: true,
            ),
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("This product no longer exists.")),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint("Error fetching post: $e");
    }
  }

  // --- HELPER: DYNAMIC ICON ---
  IconData _getIconForType(String? type) {
    switch (type) {
      case 'alert':
        return Icons.warning_amber_rounded;
      case 'success':
        return Icons.check_circle_outline;
      case 'promo':
        return Icons.local_offer_outlined;
      case 'reply':
        return Icons.reply;
      default:
        return Icons.notifications_none;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text("Please log in to view your inbox.")),
      );
    }

    return Scaffold(
      drawer: const SidebarDrawer(),
      appBar: AppBar(
        title: const Text("Inbox"),
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          // New Action: Mark All Read
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: "Mark all as read",
            onPressed: _markAllAsRead,
          ),
        ],
      ),
      backgroundColor: Colors.grey[100],
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser!.uid)
            .collection('notifications')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(child: Text("Error loading notifications"));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    "No notifications",
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          // Filter out chat messages if they are accidentally stored here,
          // or handle specific types you don't want in general inbox
          final notifications = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['type'] != 'message'; // Example filter
          }).toList();

          if (notifications.isEmpty) {
            return const Center(child: Text("No notifications"));
          }

          return ListView.separated(
            itemCount: notifications.length,
            separatorBuilder: (c, i) => const Divider(height: 1, indent: 70),
            itemBuilder: (context, index) {
              final doc = notifications[index];
              final data = doc.data() as Map<String, dynamic>;

              final String message = data['message'] ?? 'New notification';
              final String postId = data['post_id'] ?? '';
              final String? notifType = data['type'];
              final Timestamp? time = data['timestamp'];
              final bool isRead = data['read'] ?? false;

              return Dismissible(
                key: Key(doc.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (direction) {
                  _deleteNotification(doc.id);
                },
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  tileColor: isRead
                      ? Colors.transparent
                      : Colors.green.withOpacity(0.08),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: isRead
                        ? Colors.grey[300]
                        : Colors.green[800],
                    child: Icon(
                      _getIconForType(notifType),
                      color: isRead ? Colors.grey[600] : Colors.white,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    message,
                    style: TextStyle(
                      fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      _formatTime(time),
                      style: TextStyle(
                        fontSize: 12,
                        color: isRead ? Colors.grey : Colors.green[700],
                      ),
                    ),
                  ),
                  onTap: () => _handleNotificationTap(postId, doc.id, isRead),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final dt = timestamp.toDate();
    final now = DateTime.now();

    // If today, show time, else show date
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return DateFormat('h:mm a').format(dt);
    }
    return DateFormat('MMM d, h:mm a').format(dt);
  }
}
