import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'product_details_page.dart';
import 'services/post_service.dart';

class AdminUserPostsPage extends StatefulWidget {
  final String userId;
  final String userName;

  const AdminUserPostsPage({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<AdminUserPostsPage> createState() => _AdminUserPostsPageState();
}

class _AdminUserPostsPageState extends State<AdminUserPostsPage> {
  final Set<String> _selectedPostIds = {};
  bool _isSelectionMode = false;
  bool _isLoading = false;

  // 🟢 FIX 1: Declare a variable to hold the stream
  late Stream<QuerySnapshot> _postsStream;

  @override
  void initState() {
    super.initState();
    // 🟢 FIX 1: Initialize the stream ONCE here so it doesn't reload on every tap
    _postsStream = FirebaseFirestore.instance
        .collection('posts')
        .where('uploader_id', isEqualTo: widget.userId)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  void _toggleSelection(String postId) {
    setState(() {
      if (_selectedPostIds.contains(postId)) {
        _selectedPostIds.remove(postId);
      } else {
        _selectedPostIds.add(postId);
      }

      if (_selectedPostIds.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _enterSelectionMode(String postId) {
    setState(() {
      _isSelectionMode = true;
      _selectedPostIds.add(postId);
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedPostIds.length;
    if (count == 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Selected Posts?"),
        content: Text(
          "Are you sure you want to permanently delete these $count posts?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final List<String> idsToDelete = List.from(_selectedPostIds);

      for (final id in idsToDelete) {
        await PostService().deletePostCompletely(id);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$count posts deleted successfully.")),
        );
        setState(() {
          _selectedPostIds.clear();
          _isSelectionMode = false;
        });
      }
    } catch (e) {
      if (mounted) {
        // 🟢 FIX 2: Added user-friendly message for the Missing Index error
        String errorMsg = "Error deleting posts: $e";
        if (e.toString().contains("requires a COLLECTION_GROUP_ASC index")) {
          errorMsg =
              "System Error: Missing Index. Please check console logs and click the link to create the required database index.";
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteAllPosts() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete ALL Posts?"),
        content: Text(
          "WARNING: This will permanently delete every post made by ${widget.userName}.\n\nThis action cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "DELETE ALL",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      await PostService().deleteAllUserPosts(widget.userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("All posts deleted successfully.")),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error deleting all posts: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isSelectionMode
              ? "${_selectedPostIds.length} Selected"
              : "${widget.userName}'s Posts",
        ),
        backgroundColor: _isSelectionMode ? Colors.grey[800] : Colors.blueGrey,
        foregroundColor: Colors.white,
        actions: [
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: "Delete Selected",
              onPressed: _deleteSelected,
            )
          else
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: "Delete All User's Posts",
              onPressed: _deleteAllPosts,
            ),
        ],
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _isSelectionMode = false;
                  _selectedPostIds.clear();
                }),
              )
            : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot>(
              stream:
                  _postsStream, // 🟢 FIX 1: Use the initialized stream variable
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final posts = snapshot.data!.docs;

                if (posts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.feed_outlined,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "This user hasn't posted anything yet.",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final doc = posts[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final isSelected = _selectedPostIds.contains(doc.id);

                    return Card(
                      color: isSelected ? Colors.blue[50] : Colors.white,
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isSelected ? Colors.blue : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onLongPress: () => _enterSelectionMode(doc.id),
                        onTap: () {
                          if (_isSelectionMode) {
                            _toggleSelection(doc.id);
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ProductDetailsPage(
                                  data: data,
                                  documentId: doc.id,
                                ),
                              ),
                            );
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              if (_isSelectionMode)
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: Icon(
                                    isSelected
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    color: isSelected
                                        ? Colors.blue
                                        : Colors.grey,
                                  ),
                                ),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 60,
                                  height: 60,
                                  color: Colors.grey[200],
                                  child: data['image_url'] != null
                                      ? CachedNetworkImage(
                                          imageUrl: data['image_url'],
                                          fit: BoxFit.cover,
                                          errorWidget: (c, u, e) =>
                                              const Icon(Icons.broken_image),
                                        )
                                      : const Icon(Icons.image),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      data['product_name'] ?? 'Untitled',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      NumberFormat.currency(
                                        symbol: '₵',
                                      ).format(data['price'] ?? 0),
                                      style: TextStyle(
                                        color: Colors.green[700],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      data['timestamp'] != null
                                          ? DateFormat(
                                              'MMM d, yyyy • h:mm a',
                                            ).format(
                                              (data['timestamp'] as Timestamp)
                                                  .toDate(),
                                            )
                                          : 'Unknown Date',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!_isSelectionMode)
                                const Icon(
                                  Icons.chevron_right,
                                  color: Colors.grey,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
