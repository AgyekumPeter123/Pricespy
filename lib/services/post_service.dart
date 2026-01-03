import 'package:cloud_firestore/cloud_firestore.dart';

class PostService {
  static final PostService _instance = PostService._internal();
  factory PostService() => _instance;
  PostService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Completely deletes a post and all associated data
  /// - Deletes the main post document
  /// - Deletes all comments on the post
  /// - Removes the post from all users' saved posts
  /// - Updates any related reports
  Future<void> deletePostCompletely(
    String postId, {
    String? reportId,
    String? uploaderEmail,
    String? productName,
  }) async {
    final batch = _db.batch();

    try {
      // 1. Get the post document to check if it exists
      final postDoc = await _db.collection('posts').doc(postId).get();
      if (!postDoc.exists) {
        throw Exception('Post not found');
      }

      // 2. Delete all comments associated with this post
      final commentsQuery = await _db
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .get();

      for (var commentDoc in commentsQuery.docs) {
        batch.delete(commentDoc.reference);
      }

      // 3. Remove this post from all users' saved posts collections
      final savedPostsQuery = await _db
          .collectionGroup('saved')
          .where('original_id', isEqualTo: postId)
          .get();

      for (var savedDoc in savedPostsQuery.docs) {
        batch.delete(savedDoc.reference);
      }

      // 4. Delete the main post document
      batch.delete(_db.collection('posts').doc(postId));

      // 5. Update report status if this was from a report
      if (reportId != null) {
        batch.update(_db.collection('reports').doc(reportId), {
          'status': 'resolved',
        });
      }

      // 6. Commit all batch operations
      await batch.commit();
    } catch (e) {
      throw Exception('Failed to delete post completely: $e');
    }
  }

  /// Deletes all posts by a specific user (for account deletion)
  Future<void> deleteAllUserPosts(String userId) async {
    try {
      final userPostsQuery = await _db
          .collection('posts')
          .where('uploader_id', isEqualTo: userId)
          .get();

      for (var postDoc in userPostsQuery.docs) {
        await deletePostCompletely(postDoc.id);
      }
    } catch (e) {
      throw Exception('Failed to delete user posts: $e');
    }
  }

  /// Gets all comments for a post (for verification/debugging)
  Future<List<Map<String, dynamic>>> getPostComments(String postId) async {
    try {
      final commentsQuery = await _db
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .get();

      return commentsQuery.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();
    } catch (e) {
      throw Exception('Failed to get post comments: $e');
    }
  }

  /// Gets all users who saved a specific post
  Future<List<String>> getPostSavers(String postId) async {
    try {
      final savedQuery = await _db
          .collectionGroup('saved')
          .where('original_id', isEqualTo: postId)
          .get();

      return savedQuery.docs
          .map((doc) => doc.reference.parent.parent!.id)
          .toList();
    } catch (e) {
      throw Exception('Failed to get post savers: $e');
    }
  }
}
