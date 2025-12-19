import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';

// --- PAGE IMPORTS ---
import 'login_page.dart';
import 'home_page.dart';
import 'profile_page.dart';
import 'my_posts_page.dart';
import 'saved_posts_page.dart';
import 'my_post_comments.dart';
import 'inbox_page.dart';
import 'chat_list_page.dart';
import 'watchlist_page.dart';
import 'location_settings.dart'; // Correct import name
import 'disclaimer_page.dart';
import 'admin_dashboard.dart';

class SidebarDrawer extends StatefulWidget {
  final bool isHome;
  const SidebarDrawer({super.key, this.isHome = false});

  @override
  State<SidebarDrawer> createState() => _SidebarDrawerState();
}

class _SidebarDrawerState extends State<SidebarDrawer> {
  final User? user = FirebaseAuth.instance.currentUser;
  final String _adminEmail = "agyekumpeter123@gmail.com";

  Future<void> _logout(BuildContext context) async {
    await GoogleSignIn.instance.signOut();
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );
    }
  }

  // --- IMAGE UPLOAD LOGIC ---
  void _showImageSourceActionSheet(BuildContext context) {
    Navigator.pop(context); // Close Drawer first
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.of(context).pop();
                _pickAndCropImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.of(context).pop();
                _pickAndCropImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndCropImage(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source);

    if (image == null) return;

    final CroppedFile? croppedFile = await ImageCropper().cropImage(
      sourcePath: image.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Profile Picture',
          toolbarColor: Colors.green[800],
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: 'Crop Profile Picture',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );

    if (croppedFile == null) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Uploading image... please wait.")),
    );

    try {
      final File file = File(croppedFile.path);
      final String uid = user!.uid;

      final ref = FirebaseStorage.instance
          .ref()
          .child('user_profiles')
          .child('$uid.jpg');

      await ref.putFile(file);
      final String downloadUrl = await ref.getDownloadURL();

      await user!.updatePhotoURL(downloadUrl);

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'photoURL': downloadUrl,
      }, SetOptions(merge: true));

      setState(() {}); // Refresh UI to show new image

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile picture updated!")),
        );
      }
    } catch (e) {
      debugPrint("Error uploading image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to upload image.")),
        );
      }
    }
  }

  Widget _buildBadge(int count) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: const BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // Helper to build drawer items cleanly
  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget targetPage,
    bool isCurrent = false,
    Widget? trailing,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? Colors.green[800]),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          color: isCurrent ? Colors.green[800] : Colors.black87,
        ),
      ),
      trailing: trailing,
      tileColor: isCurrent ? Colors.green[50] : null,
      onTap: () {
        Navigator.pop(context); // Close Drawer
        if (!isCurrent) {
          if (targetPage is HomePage) {
            // If going to Home, clear stack
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const HomePage()),
              (route) => false,
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => targetPage),
            );
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          // 1. HEADER
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: Colors.green[800]),
            accountName: Text(
              user?.displayName ?? "User",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            accountEmail: Text(user?.email ?? ""),
            currentAccountPicture: Stack(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: Colors.white,
                  child: ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: user?.photoURL ?? "",
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          const CircularProgressIndicator(),
                      errorWidget: (context, url, error) =>
                          Icon(Icons.person, size: 40, color: Colors.grey[400]),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: InkWell(
                    onTap: () => _showImageSourceActionSheet(context),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.camera_alt,
                        size: 16,
                        color: Colors.green[800],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. NAVIGATION ITEMS
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildDrawerItem(
                  context,
                  icon: Icons.radar,
                  title: "Spy Feed (Home)",
                  targetPage: const HomePage(),
                  isCurrent: widget.isHome,
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.notifications_active,
                  title: "My Spy Alerts",
                  targetPage: const WatchlistPage(),
                ),

                // INBOX with Badge
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(user?.uid)
                      .collection('notifications')
                      .where('isRead', isEqualTo: false)
                      .snapshots(),
                  builder: (context, snapshot) {
                    int count = snapshot.hasData
                        ? snapshot.data!.docs.length
                        : 0;
                    return _buildDrawerItem(
                      context,
                      icon: Icons.inbox,
                      title: "Inbox",
                      targetPage: const InboxPage(),
                      trailing: _buildBadge(count),
                    );
                  },
                ),

                // PRIVATE CHATS with Badge
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('chats')
                      .where('participants', arrayContains: user?.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    int unreadTotal = 0;
                    if (snapshot.hasData) {
                      for (var doc in snapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        unreadTotal +=
                            (data['unread_${user?.uid}'] ?? 0) as int;
                      }
                    }
                    return _buildDrawerItem(
                      context,
                      icon: Icons.chat,
                      title: "Private Chats",
                      targetPage: const ChatListPage(),
                      trailing: _buildBadge(unreadTotal),
                    );
                  },
                ),

                const Divider(),

                _buildDrawerItem(
                  context,
                  icon: Icons.article,
                  title: "My Posts",
                  targetPage: const MyPostsPage(),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.forum,
                  title: "Comments on My Items",
                  targetPage: const MyPostCommentsPage(),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.bookmark,
                  title: "Saved Posts",
                  targetPage: const SavedPostsPage(),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.person,
                  title: "Edit Profile",
                  targetPage: const ProfilePage(),
                ),

                const Divider(),

                // SETTINGS & SAFETY
                _buildDrawerItem(
                  context,
                  icon: Icons.tune,
                  title: "Discovery Settings",
                  targetPage: const LocationSettingsPage(),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.security,
                  title: "Safety & Disclaimer",
                  targetPage: const DisclaimerPage(),
                ),

                // ADMIN PANEL (Conditional)
                if (user?.email == _adminEmail) ...[
                  const Divider(color: Colors.red),
                  _buildDrawerItem(
                    context,
                    icon: Icons.admin_panel_settings,
                    title: "Admin Console",
                    targetPage: const AdminDashboard(),
                    iconColor: Colors.red,
                  ),
                ],

                // LOGOUT
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    "Logout",
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () => _logout(context),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
