import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'services/connectivity_service.dart';

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
  final TextEditingController _mainCommentController = TextEditingController();
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  final User? user = FirebaseAuth.instance.currentUser;
  bool _isSending = false;

  // --- STATE FOR INLINE REPLY ---
  String? _activeCommentId;
  String? _taggedUserName;
  String? _replyToParentId;

  // --- 🟢 NEW: TRACK EXPANDED THREADS ---
  final Set<String> _expandedParentIds = {};

  @override
  void dispose() {
    _mainCommentController.dispose();
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  // --- LOGIC: TOGGLE REPLIES ---
  void _toggleReplies(String parentId) {
    setState(() {
      if (_expandedParentIds.contains(parentId)) {
        _expandedParentIds.remove(parentId);
      } else {
        _expandedParentIds.add(parentId);
      }
    });
  }

  // --- LOGIC 1: POST NEW ROOT COMMENT ---
  Future<void> _postRootComment() async {
    if (_mainCommentController.text.trim().isEmpty) return;

    final connectivityService = ConnectivityService();
    if (!await connectivityService.checkAndShowConnectivity(context)) return;

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
            'replyToId': null, // Explicitly null for root
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

    final connectivityService = ConnectivityService();
    if (!await connectivityService.checkAndShowConnectivity(context)) return;

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
            'replyToId': _replyToParentId,
          });

      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .update({'last_comment_time': FieldValue.serverTimestamp()});

      // 🟢 Auto-expand the thread if I reply
      if (_replyToParentId != null) {
        _expandedParentIds.add(_replyToParentId!);
      }

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

        if (_activeCommentId == commentId) _cancelReply();
      } catch (e) {
        debugPrint("Error deleting: $e");
      }
    }
  }

  // --- LOGIC 4: ACTIVATE REPLY BOX ---
  void _activateReplyBox(String commentId, String userName, String parentId) {
    setState(() {
      _activeCommentId = commentId;
      _taggedUserName = userName;
      _replyToParentId = parentId;
      _replyController.clear();
      // 🟢 Auto-expand if clicking reply on a root
      if (!_expandedParentIds.contains(parentId)) {
        _expandedParentIds.add(parentId);
      }
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

                // 1. Filter Roots
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

                    // 2. Filter Replies for this specific root
                    final replies = allDocs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return data['replyToId'] == parentId;
                    }).toList();

                    // 🟢 CHECK STATE
                    final bool isExpanded = _expandedParentIds.contains(
                      parentId,
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ROOT COMMENT
                        _buildCommentItem(
                          parentDoc,
                          isReply: false,
                          rootId: parentId,
                        ),

                        // 🟢 TIKTOK STYLE EXPANDER BUTTON
                        if (replies.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 50, bottom: 8),
                            child: Row(
                              children: [
                                // Horizontal Line
                                Container(
                                  width: 30,
                                  height: 1,
                                  color: Colors.grey[300],
                                  margin: const EdgeInsets.only(right: 10),
                                ),
                                GestureDetector(
                                  onTap: () => _toggleReplies(parentId),
                                  child: Text(
                                    isExpanded
                                        ? "Hide replies"
                                        : "View ${replies.length} replies",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // REPLIES SECTION (Conditionally Visible)
                        if (replies.isNotEmpty && isExpanded)
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Thread Line
                                Padding(
                                  padding: const EdgeInsets.only(left: 34),
                                  child: VerticalDivider(
                                    width: 1,
                                    thickness: 2,
                                    color: Colors.grey.withOpacity(0.2),
                                  ),
                                ),
                                // Replies List
                                Expanded(
                                  child: Padding(
                                    // 🟢 FIX: Clamped Padding (Flat nesting)
                                    padding: const EdgeInsets.only(left: 14.0),
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
                                ),
                              ],
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
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _mainCommentController,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
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
    final bool isReplyingToThis = _activeCommentId == commentId;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: isReplyingToThis
          ? Colors.blue.withOpacity(0.05)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: isReply ? 14 : 18,
                  backgroundImage:
                      (data['avatar'] != null && data['avatar'].isNotEmpty)
                      ? CachedNetworkImageProvider(data['avatar'])
                      : null,
                  child: (data['avatar'] == null || data['avatar'].isEmpty)
                      ? Icon(Icons.person, size: 16, color: Colors.blue[800])
                      : null,
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
                            const Padding(
                              padding: EdgeInsets.only(left: 4.0),
                              child: Icon(
                                Icons.verified,
                                color: Colors.blue,
                                size: 14,
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
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            if (!isMe)
                              InkWell(
                                onTap: () => _activateReplyBox(
                                  commentId,
                                  data['username'],
                                  rootId,
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
                                  padding: EdgeInsets.only(
                                    left: !isMe ? 15 : 0,
                                  ),
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

          // INLINE REPLY BOX
          if (isReplyingToThis)
            Container(
              // 🟢 FIX: Smart margin. If already replying to a reply, use 0 margin
              // so it aligns with the current thread column.
              margin: EdgeInsets.only(left: isReply ? 0 : 46, bottom: 10),
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
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _replyController,
                          focusNode: _replyFocusNode,
                          minLines: 1,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: "Type reply...",
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            _sendInlineReply(_replyController.text),
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
      ),
    );
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return "Just now";
    final dt = timestamp.toDate();
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
