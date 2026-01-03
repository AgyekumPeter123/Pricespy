import 'dart:async'; // Required for Timer
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'product_details_page.dart';
import 'services/post_service.dart';

class PostsManagementTab extends StatefulWidget {
  const PostsManagementTab({super.key});

  @override
  State<PostsManagementTab> createState() => _PostsManagementTabState();
}

class _PostsManagementTabState extends State<PostsManagementTab> {
  String _selectedFilter = "All Posts";
  final List<String> _filters = [
    "All Posts",
    "Recent (24h)",
    "This Week",
    "This Month",
    "With Comments",
    "No Comments",
  ];

  // Search & Stream Control
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  Timer? _debounce;
  Stream<QuerySnapshot>? _postsStream;

  // 🟢 Cache posts to prevent UI collapse during filter switches
  List<DocumentSnapshot> _cachedPosts = [];

  @override
  void initState() {
    super.initState();
    _initPostStream();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _initPostStream() {
    Query query = FirebaseFirestore.instance.collection('posts');

    // Basic date filters work with stream queries directly
    switch (_selectedFilter) {
      case "Recent (24h)":
        final yesterday = DateTime.now().subtract(const Duration(hours: 24));
        query = query.where(
          'timestamp',
          isGreaterThan: Timestamp.fromDate(yesterday),
        );
        break;
      case "This Week":
        final weekStart = DateTime.now().subtract(const Duration(days: 7));
        query = query.where(
          'timestamp',
          isGreaterThan: Timestamp.fromDate(weekStart),
        );
        break;
      case "This Month":
        final monthStart = DateTime.now().subtract(const Duration(days: 30));
        query = query.where(
          'timestamp',
          isGreaterThan: Timestamp.fromDate(monthStart),
        );
        break;
    }

    _postsStream = query
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.toLowerCase().trim();
        });
      }
    });
  }

  // --- 🟢 FIXED FILTER LOGIC ---
  List<DocumentSnapshot> _filterPosts(List<DocumentSnapshot> docs) {
    // 1. Filter out deleted or non-existent docs immediately
    var validDocs = docs.where((doc) => doc.exists).toList();

    if (validDocs.isEmpty) return [];

    return validDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      // 2. Search Query
      if (_searchQuery.isNotEmpty) {
        final title = (data['product_name'] ?? '').toString().toLowerCase();
        final uploader = (data['uploader_name'] ?? '').toString().toLowerCase();

        if (!title.contains(_searchQuery) && !uploader.contains(_searchQuery)) {
          return false;
        }
      }

      // 3. Client-Side Filters (Comments)
      // We rely on 'last_comment_time'. If it exists, the post has comments.
      if (_selectedFilter == "With Comments") {
        return data['last_comment_time'] != null;
      } else if (_selectedFilter == "No Comments") {
        return data['last_comment_time'] == null;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_postsStream == null) {
      _initPostStream();
    }

    return SingleChildScrollView(
      key: const PageStorageKey('admin_posts_list'),
      child: Column(
        children: [
          // 📊 Charts Section
          _buildPostsAnalytics(),

          // 📋 Posts List Section
          _buildPostsList(),
        ],
      ),
    );
  }

  Widget _buildPostsAnalytics() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('posts').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        // 🟢 SAFETY: Ensure we only count existing docs
        final posts = snapshot.data!.docs.where((doc) => doc.exists).toList();
        final now = DateTime.now();

        // Analytics calculations
        final totalPosts = posts.length;
        final postsToday = posts.where((doc) {
          final timestamp = (doc.data() as Map)['timestamp'] as Timestamp?;
          if (timestamp == null) return false;
          final postDate = timestamp.toDate();
          return postDate.year == now.year &&
              postDate.month == now.month &&
              postDate.day == now.day;
        }).length;

        final postsThisWeek = posts.where((doc) {
          final timestamp = (doc.data() as Map)['timestamp'] as Timestamp?;
          if (timestamp == null) return false;
          final postDate = timestamp.toDate();
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          return postDate.isAfter(weekStart);
        }).length;

        // Category distribution
        final categoryCount = <String, int>{};
        for (var doc in posts) {
          final data = doc.data() as Map;
          final type = data['poster_type'] == 'Shop Owner'
              ? 'Shop'
              : 'Individual';
          categoryCount[type] = (categoryCount[type] ?? 0) + 1;
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "📊 Posts Analytics",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
              const SizedBox(height: 16),
              // Stats Cards
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildStatCardWrapper(
                    "Total Posts",
                    totalPosts.toString(),
                    Icons.article,
                    Colors.blue,
                  ),
                  _buildStatCardWrapper(
                    "Today",
                    postsToday.toString(),
                    Icons.today,
                    Colors.green,
                  ),
                  _buildStatCardWrapper(
                    "This Week",
                    postsThisWeek.toString(),
                    Icons.calendar_view_week,
                    Colors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 🟢 Category Pie Chart
              if (categoryCount.isNotEmpty)
                SizedBox(
                  height: 200,
                  child: PieChart(
                    PieChartData(
                      sections: categoryCount.entries.map((entry) {
                        final isShop = entry.key == 'Shop';
                        return PieChartSectionData(
                          value: entry.value.toDouble(),
                          title: '${entry.key}\n${entry.value}',
                          color: isShop ? Colors.purple : Colors.teal,
                          radius: 80,
                          titleStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          titlePositionPercentageOffset: 0.55,
                        );
                      }).toList(),
                      sectionsSpace: 2,
                      centerSpaceRadius: 30,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCardWrapper(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 64) / 3, // Distribute evenly
      child: _buildStatCard(title, value, icon, color),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(fontSize: 10, color: color.withOpacity(0.8)),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildPostsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _postsStream,
      builder: (context, snapshot) {
        bool isWaiting = snapshot.connectionState == ConnectionState.waiting;

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: Text("Error: ${snapshot.error}")),
          );
        }

        if (snapshot.hasData) {
          // 🟢 SAFETY: Filter out deleted docs
          _cachedPosts = snapshot.data!.docs
              .where((doc) => doc.exists)
              .toList();
        }

        if (isWaiting && _cachedPosts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        // Use the cache for smooth transitions
        final filteredDocs = _filterPosts(_cachedPosts);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- FILTER BAR ---
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Search posts by product or user...",
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 0,
                        horizontal: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _filters.map((filter) {
                        final isSelected = _selectedFilter == filter;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(filter),
                            selected: isSelected,
                            selectedColor: Colors.blue[100],
                            checkmarkColor: Colors.blue[900],
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.blue[900]
                                  : Colors.black87,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            onSelected: (bool selected) {
                              if (selected) {
                                setState(() {
                                  _selectedFilter = filter;
                                  _initPostStream();
                                });
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text(
                        "📋 Posts List",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "${filteredDocs.length} Items",
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (isWaiting && _cachedPosts.isNotEmpty)
              const LinearProgressIndicator(minHeight: 2, color: Colors.blue),

            if (filteredDocs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.feed_outlined,
                        size: 60,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "No posts found",
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                padding: const EdgeInsets.all(12),
                itemCount: filteredDocs.length,
                separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final doc = filteredDocs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  return _buildPostCard(context, data, doc.id);
                },
              ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildPostCard(
    BuildContext context,
    Map<String, dynamic> data,
    String postId,
  ) {
    final timestamp = data['timestamp'] as Timestamp?;
    final postDate = timestamp?.toDate();
    final formattedDate = postDate != null
        ? DateFormat('MMM dd, yyyy • h:mm a').format(postDate)
        : 'Unknown date';

    final imageUrl = data['image_url'] as String?;
    final price = data['price'] as num?;
    final title = data['product_name'] as String? ?? 'Untitled';
    final posterType = data['poster_type'] as String? ?? 'Individual';
    final uploaderName = data['uploader_name'] as String? ?? 'Unknown User';

    final isShop = posterType == 'Shop Owner' || posterType == 'Shop';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _viewPostDetails(context, data, postId),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // IMAGE
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 80,
                  height: 80,
                  color: Colors.grey[200],
                  child: imageUrl != null && imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (c, u, e) => const Icon(
                            Icons.broken_image,
                            color: Colors.grey,
                          ),
                        )
                      : const Icon(Icons.image, color: Colors.grey),
                ),
              ),
              const SizedBox(width: 12),

              // DETAILS
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "₵${price?.toStringAsFixed(2) ?? '0.00'}",
                      style: TextStyle(
                        color: Colors.green[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isShop ? Colors.blue[50] : Colors.green[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isShop
                                  ? Colors.blue[200]!
                                  : Colors.green[200]!,
                            ),
                          ),
                          child: Text(
                            posterType,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isShop
                                  ? Colors.blue[900]
                                  : Colors.green[900],
                              height: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            uploaderName,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formattedDate,
                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),

              // ADMIN ACTIONS MENU
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () => _showAdminActions(context, data, postId),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _viewPostDetails(
    BuildContext context,
    Map<String, dynamic> data,
    String postId,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ProductDetailsPage(data: data, documentId: postId),
      ),
    );
  }

  void _showAdminActions(
    BuildContext context,
    Map<String, dynamic> data,
    String postId,
  ) {
    final title = data['product_name'] as String? ?? 'Untitled Post';
    final uploaderId = data['uploader_id'] as String?;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.admin_panel_settings, color: Colors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Admin Actions',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 16),

            // Post Info Summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (uploaderId != null)
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(uploaderId)
                          .get(),
                      builder: (context, snapshot) {
                        String email = "Loading...";
                        if (snapshot.hasData && snapshot.data!.exists) {
                          email = snapshot.data!.get('email') ?? 'No Email';
                        }
                        return Text(
                          "User Email: $email",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            fontFamily: 'monospace',
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            _buildAdminActionButton(
              context,
              'View Full Details',
              Icons.visibility,
              Colors.blue,
              () {
                Navigator.pop(context);
                _viewPostDetails(context, data, postId);
              },
            ),
            const SizedBox(height: 12),

            _buildAdminActionButton(
              context,
              'Delete Post Completely',
              Icons.delete_forever,
              Colors.red,
              () => _confirmDeletePost(context, data, postId),
            ),
            const SizedBox(height: 12),

            _buildAdminActionButton(
              context,
              'Send Warning to Owner',
              Icons.warning,
              Colors.orange,
              () => _sendWarningToOwner(context, data, postId),
            ),
            const SizedBox(height: 12),

            _buildAdminActionButton(
              context,
              'View Comments',
              Icons.comment,
              Colors.green,
              () => _viewPostComments(context, postId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminActionButton(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(title),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  void _confirmDeletePost(
    BuildContext context,
    Map<String, dynamic> data,
    String postId,
  ) {
    final title = data['product_name'] as String? ?? 'this post';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Post Forever'),
        content: Text(
          'Are you sure you want to permanently delete "$title"?\n'
          'This will remove the post, all comments, and clear it from all saved lists.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              Navigator.pop(context);

              try {
                await PostService().deletePostCompletely(postId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Post deleted successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );
  }

  void _sendWarningToOwner(
    BuildContext context,
    Map<String, dynamic> data,
    String postId,
  ) {
    final uploaderId = data['uploader_id'] as String?;
    final productName = data['product_name'] as String? ?? 'your post';

    if (uploaderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot identify post owner')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController(
          text:
              'Please review your post "$productName" and ensure it complies with our community guidelines.',
        );

        return AlertDialog(
          title: const Text('Send Warning'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Warning message...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final message = controller.text.trim();
                if (message.isEmpty) return;

                try {
                  // Send to Chat system as "SUPPORT_TEAM"
                  await FirebaseFirestore.instance
                      .collection('chats')
                      .doc('SUPPORT_TEAM_$uploaderId')
                      .collection('messages')
                      .add({
                        'senderId': 'SUPPORT_TEAM',
                        'text': 'ADMIN WARNING: $message',
                        'timestamp': FieldValue.serverTimestamp(),
                      });

                  Navigator.pop(dialogContext);
                  Navigator.pop(context);

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Warning sent'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Failed: $e')));
                }
              },
              child: const Text('Send'),
            ),
          ],
        );
      },
    );
  }

  void _viewPostComments(BuildContext context, String postId) {
    Navigator.pop(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.comment, color: Colors.green),
                const SizedBox(width: 12),
                const Text(
                  'Post Comments',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('posts')
                    .doc(postId)
                    .collection('comments')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final comments = snapshot.data!.docs;

                  if (comments.isEmpty) {
                    return const Center(child: Text('No comments yet'));
                  }

                  return ListView.builder(
                    itemCount: comments.length,
                    itemBuilder: (context, index) {
                      final comment =
                          comments[index].data() as Map<String, dynamic>;
                      final timestamp = comment['timestamp'] as Timestamp?;
                      final date = timestamp?.toDate();
                      final formattedDate = date != null
                          ? DateFormat('MMM dd, hh:mm a').format(date)
                          : '';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    comment['username'] ?? 'Anonymous',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    formattedDate,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(comment['text'] ?? ''),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
