import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';

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
import 'location_settings.dart';
import 'disclaimer_page.dart';
import 'admin_dashboard.dart';
import 'churn_prediction_page.dart';
import 'admin_service.dart'; // 🟢 Added for AdminService

class SidebarDrawer extends StatefulWidget {
  final bool isHome;
  const SidebarDrawer({super.key, this.isHome = false});

  @override
  State<SidebarDrawer> createState() => _SidebarDrawerState();
}

class _SidebarDrawerState extends State<SidebarDrawer> {
  final User? user = FirebaseAuth.instance.currentUser;
  final String _adminEmail = "agyekumpeter123@gmail.com";

  @override
  void initState() {
    super.initState();
    // 🟢 NEW: Run maintenance check when admin opens sidebar
    if (user != null && user!.email == _adminEmail) {
      AdminService.checkAndLiftExpiredRestrictions(user!.uid);
    }
  }

  Future<void> _logout(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
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
  }

  // --- IMAGE UPLOAD LOGIC ---
  void _showImageSourceActionSheet(BuildContext context) {
    Navigator.pop(context); // Close Drawer
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera, color: Colors.blue),
                title: const Text('Take a photo'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickAndCropImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.purple),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickAndCropImage(ImageSource.gallery);
                },
              ),
            ],
          ),
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

      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Profile picture updated!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error uploading image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to upload image."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _viewProfilePicture() {
    Navigator.pop(context);
    if (user?.photoURL == null || user!.photoURL!.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: user!.photoURL!,
                placeholder: (context, url) =>
                    const CircularProgressIndicator(color: Colors.white),
                errorWidget: (context, url, error) => const Icon(Icons.error),
                fit: BoxFit.contain,
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- UI HELPERS ---
  Widget _buildBadge(int count) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required Widget targetPage,
    required BuildContext context,
    bool isCurrent = false,
    Widget? trailing,
    Color? iconColor,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: isCurrent ? Colors.green.withOpacity(0.1) : Colors.transparent,
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color:
              iconColor ?? (isCurrent ? Colors.green[800] : Colors.grey[700]),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
            color: isCurrent ? Colors.green[800] : Colors.black87,
          ),
        ),
        trailing: trailing,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        onTap:
            onTap ??
            () {
              Navigator.pop(context);
              if (!isCurrent) {
                if (targetPage is HomePage) {
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      backgroundColor: Colors.white,
      child: Column(
        children: [
          // 1. REAL-TIME DATA HEADER
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user?.uid)
                .snapshots(),
            builder: (context, snapshot) {
              // --- CALCULATE SCORE ---
              double profileScore = 0;
              String displayName = user?.displayName ?? "Guest User";
              String? photoURL = user?.photoURL;

              if (snapshot.hasData && snapshot.data!.exists) {
                final data = snapshot.data!.data() as Map<String, dynamic>;

                // 1. Name Check (34%)
                if ((data['displayName'] ?? "").toString().isNotEmpty) {
                  profileScore += 34;
                  displayName =
                      data['displayName']; // Use Firestore name if available
                } else if ((user?.displayName ?? "").isNotEmpty) {
                  profileScore += 34;
                }

                // 2. Call Number Check (33%)
                if ((data['call_number'] ?? "").toString().isNotEmpty) {
                  profileScore += 33;
                }

                // 3. WhatsApp Number Check (33%)
                if ((data['whatsapp_number'] ?? "").toString().isNotEmpty) {
                  profileScore += 33;
                }

                // Use Firestore photo if newer
                if (data['photoUrl'] != null) photoURL = data['photoUrl'];
              }

              return Container(
                padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green[900]!, Colors.green[700]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // THE CHART: Trust Score Ring
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 80,
                              height: 80,
                              child: PieChart(
                                PieChartData(
                                  sectionsSpace: 0,
                                  centerSpaceRadius: 36,
                                  startDegreeOffset: -90,
                                  sections: [
                                    PieChartSectionData(
                                      color: Colors.white,
                                      value: profileScore,
                                      radius: 4,
                                      showTitle: false,
                                    ),
                                    PieChartSectionData(
                                      color: Colors.white.withOpacity(0.3),
                                      value: 100 - profileScore,
                                      radius: 4,
                                      showTitle: false,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: _viewProfilePicture,
                              child: CircleAvatar(
                                radius: 32,
                                backgroundColor: Colors.white,
                                backgroundImage: photoURL != null
                                    ? CachedNetworkImageProvider(photoURL)
                                    : null,
                                child: photoURL == null
                                    ? Icon(
                                        Icons.person,
                                        size: 35,
                                        color: Colors.grey[400],
                                      )
                                    : null,
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () =>
                                    _showImageSourceActionSheet(context),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    size: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                user?.email ?? "",
                                style: TextStyle(
                                  color: Colors.green[100],
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              // Score Text
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  "Completeness: ${profileScore.toInt()}%",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),

          // 2. SCROLLABLE MENU
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildSectionHeader("MARKETPLACE"),
                _buildDrawerItem(
                  context: context,
                  icon: Icons.radar,
                  title: "Spy Feed",
                  targetPage: const HomePage(),
                  isCurrent: widget.isHome,
                ),
                // 3. Location Settings (Restored)
                _buildDrawerItem(
                  context: context,
                  icon: Icons.settings_input_antenna,
                  title: "Discovery Settings",
                  targetPage: const LocationSettingsPage(),
                ),
                _buildDrawerItem(
                  context: context,
                  icon: Icons.notifications_active_outlined,
                  title: "My Alerts",
                  targetPage: const WatchlistPage(),
                ),

                _buildSectionHeader("COMMUNICATION"),
                // Inbox with Badge (Excluding Replies)
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(user?.uid)
                      .collection('notifications')
                      .where('read', isEqualTo: false)
                      .snapshots(),
                  builder: (context, snapshot) {
                    int count = 0;
                    if (snapshot.hasData) {
                      count = snapshot.data!.docs
                          .where((doc) => doc['type'] != 'reply')
                          .length;
                    }
                    return _buildDrawerItem(
                      context: context,
                      icon: Icons.inbox_outlined,
                      title: "Inbox",
                      targetPage: const InboxPage(),
                      trailing: _buildBadge(count),
                    );
                  },
                ),
                // 2. My Post Comments with Badge (Specific for Replies)
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(user?.uid)
                      .collection('notifications')
                      .where('read', isEqualTo: false)
                      .where('type', isEqualTo: 'reply') // Specific filter
                      .snapshots(),
                  builder: (context, snapshot) {
                    int count = 0;
                    if (snapshot.hasData) {
                      count = snapshot.data!.docs.length;
                    }
                    return _buildDrawerItem(
                      context: context,
                      icon: Icons.comment_bank_outlined,
                      title: "My Post Comments",
                      targetPage: const MyPostCommentsPage(),
                      trailing: _buildBadge(count),
                    );
                  },
                ),
                // Chats with Badge
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
                      context: context,
                      icon: Icons.chat_bubble_outline,
                      title: "Private Chats",
                      targetPage: const ChatListPage(),
                      trailing: _buildBadge(unreadTotal),
                    );
                  },
                ),

                _buildSectionHeader("ACCOUNT & TOOLS"),
                _buildDrawerItem(
                  context: context,
                  icon: Icons.article_outlined,
                  title: "My Posts",
                  targetPage: const MyPostsPage(),
                ),
                // 1. Saved Posts (Restored)
                _buildDrawerItem(
                  context: context,
                  icon: Icons.bookmark_outline,
                  title: "Saved Items",
                  targetPage: const SavedPostsPage(),
                ),
                _buildDrawerItem(
                  context: context,
                  icon: Icons.person_outline,
                  title: "Profile Settings",
                  targetPage: const ProfilePage(),
                ),
                _buildDrawerItem(
                  context: context,
                  icon: Icons.analytics_outlined,
                  title: "Churn Predictor AI",
                  targetPage: const ChurnPredictionPage(),
                ),

                if (user?.email == _adminEmail) ...[
                  _buildSectionHeader("ADMINISTRATION"),
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.admin_panel_settings,
                    title: "Admin Console",
                    targetPage: const AdminDashboard(),
                    iconColor: Colors.redAccent,
                  ),
                ],

                const Divider(height: 30),
                // 4. Disclaimer Page (Restored)
                _buildDrawerItem(
                  context: context,
                  icon: Icons.shield_outlined,
                  title: "Safety & Terms",
                  targetPage: const DisclaimerPage(),
                ),
                _buildDrawerItem(
                  context: context,
                  icon: Icons.logout,
                  title: "Logout",
                  targetPage: const LoginPage(), // Dummy
                  iconColor: Colors.red,
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
