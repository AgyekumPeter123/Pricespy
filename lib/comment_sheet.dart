import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class CommentSheet extends StatefulWidget {
  final String postId;
  final String postOwnerId;

  const CommentSheet({
    super.key,
    required this.postId,
    required this.postOwnerId,
  });

  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  // Controller for the Main Bottom Input (New Root Comments)
  final TextEditingController _mainCommentController = TextEditingController();

  // Controller for the Inline Reply Input
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();

  final User? user = FirebaseAuth.instance.currentUser;
  bool _isSending = false;

  // --- STATE FOR INLINE REPLY ---
  String? _activeCommentId; // Which comment is currently open?
  String? _taggedUserName;
  // We need to know which parent ID to link the reply to
  String? _replyToParentId;

  @override
  void dispose() {
    _mainCommentController.dispose();
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  // --- LOGIC 1: POST NEW ROOT COMMENT (Bottom Bar) ---
  Future<void> _postRootComment() async {
    if (_mainCommentController.text.trim().isEmpty) return;
    setState(() => _isSending = true);

    try {
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .add({
            'text': _mainCommentController.text.trim(),
            'uid': user?.uid,
            'username': user?.displayName ?? "Anonymous",
            'avatar': user?.photoURL,
            'timestamp': FieldValue.serverTimestamp(),
            'replyToId': null, // Explicitly null for root comments
          });

      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .update({'last_comment_time': FieldValue.serverTimestamp()});

      _mainCommentController.clear();
      if (mounted) FocusScope.of(context).unfocus();
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // --- LOGIC 2: SEND INLINE REPLY ---
  Future<void> _sendInlineReply(String text) async {
    if (text.trim().isEmpty || _replyToParentId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .collection('comments')
          .add({
            'text': text.trim(),
            'uid': user?.uid,
            'username': user?.displayName ?? "Anonymous",
            'avatar': user?.photoURL,
            'timestamp': FieldValue.serverTimestamp(),
            'tagged_user': _taggedUserName,
            'replyToId':
                _replyToParentId, // Links this reply to the parent comment
          });

      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .update({'last_comment_time': FieldValue.serverTimestamp()});

      _cancelReply();
    } catch (e) {
      debugPrint("Error replying: $e");
    }
  }

  // --- LOGIC 3: DELETE COMMENT ---
  Future<void> _deleteComment(String commentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Comment"),
        content: const Text("Are you sure you want to delete this?"),
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

        if (_activeCommentId == commentId) {
          _cancelReply();
        }
      } catch (e) {
        debugPrint("Error deleting: $e");
      }
    }
  }

  // --- LOGIC 4: ACTIVATE REPLY BOX ---
  void _activateReplyBox(String commentId, String userName, String parentId) {
    setState(() {
      _activeCommentId = commentId; // The specific comment UI we clicked
      _taggedUserName = userName;
      _replyToParentId = parentId; // The ID of the top-level comment
      _replyController.clear();
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      _replyFocusNode.requestFocus();
    });
  }

  // --- LOGIC 5: CANCEL REPLY ---
  void _cancelReply() {
    setState(() {
      _activeCommentId = null;
      _taggedUserName = null;
      _replyToParentId = null;
      _replyController.clear();
    });
    _replyFocusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // HEADER
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text(
            "Comments",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Divider(),

          // LIST OF COMMENTS
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .doc(widget.postId)
                  .collection('comments')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allDocs = snapshot.data!.docs;

                if (allDocs.isEmpty) {
                  return const Center(
                    child: Text(
                      "No comments yet. Be the first!",
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                // --- 1. Filter Top-Level Comments ---
                final topLevelComments = allDocs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return data['replyToId'] == null;
                }).toList();

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: topLevelComments.length,
                  itemBuilder: (context, index) {
                    final parentDoc = topLevelComments[index];
                    final parentId = parentDoc.id;

                    // --- 2. Find Replies for this specific parent ---
                    final replies = allDocs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return data['replyToId'] == parentId;
                    }).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // RENDER PARENT
                        _buildCommentItem(
                          parentDoc,
                          isReply: false,
                          rootId: parentId,
                        ),

                        // RENDER REPLIES (Indented)
                        if (replies.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 48.0,
                            ), // Indent replies
                            child: Column(
                              children: replies
                                  .map(
                                    (r) => _buildCommentItem(
                                      r,
                                      isReply: true,
                                      rootId: parentId,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          const Divider(height: 1),

          // BOTTOM INPUT AREA (Root Comments Only)
          if (_activeCommentId == null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _mainCommentController,
                      decoration: InputDecoration(
                        hintText: "Add a comment...",
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Colors.green,
                    child: IconButton(
                      icon: _isSending
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.send,
                              color: Colors.white,
                              size: 20,
                            ),
                      onPressed: _isSending ? null : _postRootComment,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCommentItem(
    QueryDocumentSnapshot doc, {
    required bool isReply,
    required String rootId,
  }) {
    final data = doc.data() as Map<String, dynamic>;
    final commentId = doc.id;
    final bool isMe = data['uid'] == user?.uid;
    final bool isOwner = data['uid'] == widget.postOwnerId;

    // Check if the reply box is open specifically for THIS comment
    final bool isReplyingToThis = _activeCommentId == commentId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: isReply ? 14 : 18, // Smaller avatar for replies
                backgroundImage: NetworkImage(
                  data['avatar'] ?? "https://via.placeholder.com/150",
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Username + Badges + Time
                    Row(
                      children: [
                        Text(
                          data['username'] ?? "User",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isReply ? Colors.grey[800] : Colors.black,
                          ),
                        ),
                        if (isOwner)
                          Container(
                            margin: const EdgeInsets.only(left: 5),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue[100],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              "Owner",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                        const Spacer(),
                        Text(
                          _formatTime(data['timestamp']),
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),

                    // Content
                    const SizedBox(height: 2),
                    Wrap(
                      children: [
                        if (data['tagged_user'] != null)
                          Text(
                            "@${data['tagged_user']} ",
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue[800],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        Text(
                          data['text'] ?? "",
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),

                    // Action Buttons (Reply / Delete)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          if (!isMe)
                            InkWell(
                              onTap: () => _activateReplyBox(
                                commentId,
                                data['username'],
                                rootId, // Always pass the top-level parent ID
                              ),
                              child: const Text(
                                "Reply",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (isMe)
                            InkWell(
                              onTap: () => _deleteComment(commentId),
                              child: Padding(
                                padding: EdgeInsets.only(left: !isMe ? 15 : 0),
                                child: const Text(
                                  "Delete",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // INLINE REPLY INPUT BOX (Only shows if this specific comment was clicked)
        if (isReplyingToThis)
          Container(
            margin: const EdgeInsets.only(left: 46, bottom: 10),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _replyController,
                        focusNode: _replyFocusNode,
                        decoration: const InputDecoration(
                          hintText: "Type reply...",
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        onSubmitted: (val) => _sendInlineReply(val),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _sendInlineReply(_replyController.text),
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
      ],
    );
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return "Just now";
    final dt = timestamp.toDate();
    // TikTok/Twitter style formatting
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 7) {
      return DateFormat.MMMd().format(dt);
    } else if (diff.inDays > 0) {
      return "${diff.inDays}d";
    } else if (diff.inHours > 0) {
      return "${diff.inHours}h";
    } else if (diff.inMinutes > 0) {
      return "${diff.inMinutes}m";
    } else {
      return "now";
    }
  }
}
