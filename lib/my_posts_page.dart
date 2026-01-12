import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_price_sheet.dart';
import 'sidebar_drawer.dart';
import 'services/post_service.dart';
import 'constants/palette.dart';

class MyPostsPage extends StatelessWidget {
  const MyPostsPage({super.key});

  void _editPost(BuildContext context, Map<String, dynamic> data, String id) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          Colors.transparent, // Allows for rounded corners on sheet
      builder: (context) => AddPriceSheet(existingData: data, existingId: id),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Post?"),
        content: const Text("This action cannot be undone."),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              "Cancel",
              style: TextStyle(color: Palette.textMedium),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Palette.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: Palette.background,
      drawer: const SidebarDrawer(),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "My Posts",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Palette.primary,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('posts')
            .where('uploader_id', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return _buildEmptyState();
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              // 🟢 Adjusted ratio to give a bit more vertical breathing room
              childAspectRatio: 0.72,
            ),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final docId = docs[index].id;

              return _buildModernPostCard(context, data, docId);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80, color: Palette.textMedium),
          const SizedBox(height: 16),
          Text(
            "No Active Posts",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Palette.textMedium,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Start selling by adding a new item!",
            style: TextStyle(color: Palette.textMedium),
          ),
        ],
      ),
    );
  }

  Widget _buildModernPostCard(
    BuildContext context,
    Map<String, dynamic> data,
    String docId,
  ) {
    final String? imageUrl = data['image_url'];
    final bool hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return Card(
      elevation: 3,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _editPost(context, data, docId),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Image Section (Top 55%)
            Expanded(
              flex: 55,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  hasImage
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: Icon(Icons.image, color: Colors.grey),
                              ),
                            );
                          },
                          errorBuilder: (c, e, s) => Container(
                            color: Colors.grey[200],
                            child: const Icon(
                              Icons.broken_image,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      : Container(
                          color: Colors.grey[200],
                          child: const Icon(
                            Icons.image_not_supported,
                            color: Colors.grey,
                            size: 40,
                          ),
                        ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        color: Palette.primary,
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(6),
                        onPressed: () => _editPost(context, data, docId),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 2. Content Section (Bottom 45%)
            Expanded(
              flex: 45,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Title - Wrapped in Expanded to take available space
                    Expanded(
                      child: Text(
                        data['product_name'] ?? 'Unknown Item',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Palette.textDark,
                          height: 1.2, // Tighter line height for multiline
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Price & Delete Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Price Tag
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Palette.secondary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "₵ ${data['price']}",
                              style: const TextStyle(
                                color: Palette.secondary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        // Delete Icon
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () async {
                            final confirm = await _confirmDelete(context);
                            if (confirm == true) {
                              try {
                                await PostService().deletePostCompletely(docId);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "Post deleted successfully",
                                      ),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        "Failed to delete post: $e",
                                      ),
                                    ),
                                  );
                                }
                              }
                            }
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: const Padding(
                            padding: EdgeInsets.all(6.0),
                            child: Icon(
                              Icons.delete_outline,
                              color: Palette.error,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
