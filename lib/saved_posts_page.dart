import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'product_details_page.dart';
import 'sidebar_drawer.dart';
import 'constants/palette.dart';

class SavedPostsPage extends StatelessWidget {
  const SavedPostsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text("Please login to view saved items.")),
      );
    }

    return Scaffold(
      backgroundColor: Palette.background,
      drawer: const SidebarDrawer(),
      appBar: AppBar(
        title: const Text(
          "Saved Items",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Palette.primary,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('saved')
            .orderBy('saved_at', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bookmark_border,
                    size: 60,
                    color: Palette.textMedium,
                  ),
                  SizedBox(height: 10),
                  Text("No saved items yet."),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;

          // 🟢 CHANGED: GridView for 2-column layout
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.72, // Optimized ratio to prevent overflow
            ),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              return _buildSavedItemCard(context, doc.id, data, uid);
            },
          );
        },
      ),
    );
  }

  Widget _buildSavedItemCard(
    BuildContext context,
    String saveDocId,
    Map<String, dynamic> data,
    String uid,
  ) {
    // Use original_id if available, otherwise fallback to the doc ID
    final String originalPostId = data['original_id'] ?? saveDocId;
    final String imageUrl = data['image_url'] ?? '';
    final bool hasImage = imageUrl.isNotEmpty;

    return Dismissible(
      key: Key(saveDocId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Palette.error,
          borderRadius: BorderRadius.circular(15),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 30),
      ),
      onDismissed: (direction) async {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('saved')
            .doc(saveDocId)
            .delete();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Item removed from saved"),
              duration: Duration(seconds: 1),
            ),
          );
        }
      },
      child: Card(
        elevation: 3,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ProductDetailsPage(data: data, documentId: originalPostId),
              ),
            );
          },
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
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: Icon(Icons.image, color: Colors.grey),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
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
                    // Navigate Arrow Overlay
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(6.0),
                          child: Icon(
                            Icons.arrow_forward,
                            size: 16,
                            color: Palette.textDark,
                          ),
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
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      const SizedBox(height: 4),

                      // Price & Delete Hint Row
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
                          // Visual cue for dismissible
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.swipe_left,
                            size: 16,
                            color: Palette.textMedium,
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
      ),
    );
  }
}
