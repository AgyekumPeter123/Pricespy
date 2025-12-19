import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'sidebar_drawer.dart'; // <--- IMPORT THIS

class MyPostCommentsPage extends StatefulWidget {
  const MyPostCommentsPage({super.key});

  @override
  State<MyPostCommentsPage> createState() => _MyPostCommentsPageState();
}

class _MyPostCommentsPageState extends State<MyPostCommentsPage> {
  final User? currentUser = FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text("Please log in to manage comments")),
      );
    }

    return Scaffold(
      // 1. ADD DRAWER
      drawer: const SidebarDrawer(),
      appBar: AppBar(
        title: const Text("Comments"),
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
        // 2. FORCE HAMBURGER
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      backgroundColor: Colors.grey[100],
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('posts')
            .where('uploader_id', isEqualTo: currentUser!.uid)
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, postSnapshot) {
          if (postSnapshot.hasError) {
            return const Center(
              child: Text("Something went wrong loading posts."),
            );
          }
          if (postSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!postSnapshot.hasData || postSnapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text("You haven't posted any products yet."),
            );
          }

          final myPosts = postSnapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: myPosts.length,
            itemBuilder: (context, index) {
              final postData = myPosts[index].data() as Map<String, dynamic>;
              final postId = myPosts[index].id;
              return _CommentThreadCard(
                postId: postId,
                postData: postData,
                currentUser: currentUser!,
              );
            },
          );
        },
      ),
    );
  }
}

// --- SUB WIDGET (Kept logic same, just re-listing for completeness) ---
class _CommentThreadCard extends StatefulWidget {
  final String postId;
  final Map<String, dynamic> postData;
  final User currentUser;

  const _CommentThreadCard({
    required this.postId,
    required this.postData,
    required this.currentUser,
  });

  @override
  State<_CommentThreadCard> createState() => _CommentThreadCardState();
}

class _CommentThreadCardState extends State<_CommentThreadCard> {
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();

  String? _activeCommentId;
  String? _taggedUserName;
  String? _taggedUserId;

  Future<void> _sendReply(String text) async {
    if (text.trim().isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .add({
            'text': text.trim(),
            'uid': widget.currentUser.uid,
            'username': widget.currentUser.displayName ?? 'Seller',
            'avatar': widget.currentUser.photoURL,
            'timestamp': FieldValue.serverTimestamp(),
            'is_seller_reply': true,
            'tagged_user': _taggedUserName,
          });

      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .update({'last_comment_time': FieldValue.serverTimestamp()});

      if (_taggedUserId != null && _taggedUserId != widget.currentUser.uid) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_taggedUserId)
            .collection('notifications')
            .add({
              'type': 'reply',
              'post_id': widget.postId,
              'message':
                  'The seller replied to your comment on "${widget.postData['product_name']}"',
              'timestamp': FieldValue.serverTimestamp(),
              'read': false,
            });
      }

      _cancelReply();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Reply sent!"),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error replying: $e");
    }
  }

  Future<void> _deleteComment(String commentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Comment"),
        content: const Text("Are you sure you want to delete this comment?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('posts')
            .doc(widget.postId)
            .collection('comments')
            .doc(commentId)
            .delete();

        if (_activeCommentId == commentId) _cancelReply();

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Comment deleted")));
        }
      } catch (e) {
        debugPrint("Error deleting: $e");
      }
    }
  }

  void _activateReplyBox(String commentId, String userId, String userName) {
    setState(() {
      _activeCommentId = commentId;
      _taggedUserId = userId;
      _taggedUserName = userName;
      _replyController.clear();
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      _replyFocusNode.requestFocus();
    });
  }

  void _cancelReply() {
    setState(() {
      _activeCommentId = null;
      _taggedUserId = null;
      _taggedUserName = null;
      _replyController.clear();
    });
    _replyFocusNode.unfocus();
  }

  @override
  void dispose() {
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String productName =
        widget.postData['product_name'] ?? 'Unknown Item';
    final String imageUrl = widget.postData['image_url'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('posts')
            .doc(widget.postId)
            .collection('comments')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          int commentCount = 0;
          if (snapshot.hasData) commentCount = snapshot.data!.docs.length;

          return ExpansionTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        width: 50,
                        height: 50,
                        color: Colors.grey[300],
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 50,
                        height: 50,
                        color: Colors.grey[300],
                        child: const Icon(Icons.broken_image, size: 20),
                      ),
                    )
                  : Container(width: 50, height: 50, color: Colors.grey[300]),
            ),
            title: Text(
              productName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              "$commentCount comments",
              style: TextStyle(
                color: commentCount > 0 ? Colors.green[800] : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
            childrenPadding: EdgeInsets.zero,
            children: [
              Container(
                color: Colors.grey[50],
                constraints: const BoxConstraints(maxHeight: 400),
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Center(child: CircularProgressIndicator())
                    : commentCount == 0
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text("No comments yet."),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: commentCount,
                        itemBuilder: (context, i) {
                          final commentDoc = snapshot.data!.docs[i];
                          final cData =
                              commentDoc.data() as Map<String, dynamic>;
                          final commentId = commentDoc.id;
                          final bool isMe =
                              cData['uid'] == widget.currentUser.uid;
                          final String senderName = cData['username'] ?? 'User';
                          final bool isReplyingToThis =
                              _activeCommentId == commentId;

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  backgroundColor: isMe
                                      ? Colors.green[100]
                                      : Colors.blue[100],
                                  radius: 14,
                                  backgroundImage:
                                      (cData['avatar'] != null &&
                                          cData['avatar'].isNotEmpty)
                                      ? CachedNetworkImageProvider(
                                          cData['avatar'],
                                        )
                                      : null,
                                  child:
                                      (cData['avatar'] == null ||
                                          cData['avatar'].isEmpty)
                                      ? Icon(
                                          isMe ? Icons.store : Icons.person,
                                          size: 16,
                                          color: isMe
                                              ? Colors.green[800]
                                              : Colors.blue[800],
                                        )
                                      : null,
                                ),
                                title: Text(
                                  senderName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isMe
                                        ? Colors.green[900]
                                        : Colors.black87,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (cData['tagged_user'] != null)
                                      Text(
                                        "@${cData['tagged_user']}",
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.blue[800],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    Text(cData['text'] ?? ''),
                                  ],
                                ),
                                trailing: !isMe
                                    ? TextButton(
                                        onPressed: () => _activateReplyBox(
                                          commentId,
                                          cData['uid'] ?? '',
                                          senderName,
                                        ),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text(
                                          "Reply",
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      )
                                    : TextButton(
                                        onPressed: () =>
                                            _deleteComment(commentId),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text(
                                          "Delete",
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ),
                              ),
                              if (isReplyingToThis)
                                Container(
                                  margin: const EdgeInsets.only(
                                    left: 20,
                                    right: 10,
                                    bottom: 10,
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.green.shade200,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 5,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            "Replying to @$_taggedUserName",
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.green[800],
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: _cancelReply,
                                            child: const Icon(
                                              Icons.close,
                                              size: 16,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: _replyController,
                                              focusNode: _replyFocusNode,
                                              decoration: const InputDecoration(
                                                hintText: "Type your reply...",
                                                isDense: true,
                                                border: InputBorder.none,
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                              onSubmitted: (val) =>
                                                  _sendReply(val),
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () => _sendReply(
                                              _replyController.text,
                                            ),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            icon: Icon(
                                              Icons.send,
                                              color: Colors.green[800],
                                              size: 20,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              const Divider(height: 1),
                            ],
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
