import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Project specific imports
import 'product_details_page.dart';
import 'sidebar_drawer.dart';
import 'screens/chat/chat_screen.dart';
import 'encryption_service.dart';
import 'services/post_service.dart';
import 'admin_posts_tab.dart';
import 'admin_user_posts_page.dart';
import 'admin_service.dart';
import 'constants/palette.dart';

enum UserFilter { all, active, restricted }

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _userSearchController = TextEditingController();
  String _userSearchQuery = "";
  UserFilter _currentUserFilter = UserFilter.all;

  // Admin Config
  final String _adminEmail = dotenv.env['EMAIL'] ?? '';
  final String _appPassword = dotenv.env['EMAIL_PASSWORD'] ?? '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    _tabController.addListener(() {
      if (_tabController.index == 1 && !_tabController.indexIsChanging) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && _isAdmin()) {
          AdminService.checkAndLiftExpiredRestrictions(user.uid);
        }
      }
    });
  }

  bool _isAdmin() {
    return FirebaseAuth.instance.currentUser?.email == _adminEmail;
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: isError ? Palette.error : Palette.secondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  // --- SMTP EMAIL ---
  Future<void> _sendEmailDirectly(
    String recipientEmail,
    String productName,
  ) async {
    if (recipientEmail.isEmpty) return;
    final smtpServer = gmail(_adminEmail, _appPassword);
    final message = Message()
      ..from = Address(_adminEmail, 'PriceSpy Admin')
      ..recipients.add(recipientEmail)
      ..subject = 'Official Notice: Post Removed - $productName'
      ..html =
          """
        <div style='font-family: sans-serif; padding: 20px; border: 1px solid #ddd; border-radius: 10px;'>
          <h2 style='color: #d32f2f;'>PriceSpy Content Removal Notice</h2>
          <p>Your post <b>"$productName"</b> has been removed for violating community guidelines.</p>
          <p>If you believe this was an error, please contact us via the admin chat.</p>
          <br><p>Best Regards,<br>PriceSpy Safety Team</p>
        </div>
      """;
    try {
      await send(message, smtpServer);
    } catch (e) {
      debugPrint("Email Error: $e");
    }
  }

  // --- PERMANENT DELETE ---
  Future<void> _deletePostPermanently(
    String reportId,
    String postId,
    String? uploaderEmail,
    String productName,
  ) async {
    try {
      await PostService().deletePostCompletely(
        postId,
        reportId: reportId,
        uploaderEmail: uploaderEmail,
        productName: productName,
      );

      if (uploaderEmail != null) {
        _sendEmailDirectly(uploaderEmail, productName);
      }
      _showSnackBar(
        "Post and all associated data deleted forever. User notified via email.",
      );
    } catch (e) {
      _showSnackBar("Failed to delete post: $e", isError: true);
    }
  }

  // --- WARNING COMPOSE DIALOG ---
  void _showWarningComposeDialog(String userId, {String? contextInfo}) {
    final TextEditingController messageController = TextEditingController();
    String severity = "Warning";

    if (contextInfo != null) {
      messageController.text = "Regarding your item '$contextInfo': ";
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Palette.tertiary),
              SizedBox(width: 10),
              Text("Issue Warning"),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Severity Level",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Palette.textMedium,
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Palette.background),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: severity,
                      isExpanded: true,
                      items: ["Notice", "Warning", "Critical"]
                          .map(
                            (val) => DropdownMenuItem(
                              value: val,
                              child: Text("$val Level"),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => severity = val);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                const Text(
                  "Message to User",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Palette.textMedium,
                  ),
                ),
                const SizedBox(height: 5),
                TextField(
                  controller: messageController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: "Enter reason...",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Palette.background,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL"),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Palette.error,
                foregroundColor: Palette.surface,
              ),
              icon: const Icon(Icons.send, size: 16),
              label: const Text("SEND"),
              onPressed: () {
                if (messageController.text.trim().isEmpty) return;
                Navigator.pop(context);
                String icon = severity == "Notice" ? "ℹ️" : "⚠️";
                if (severity == "Critical") icon = "⛔";
                _sendWarningAndOpenChat(
                  userId,
                  "$icon ADMIN ${severity.toUpperCase()}: ${messageController.text.trim()}",
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendWarningAndOpenChat(
    String userId,
    String messageText,
  ) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (!doc.exists) return;

      final data = doc.data() as Map<String, dynamic>;
      final adminId = FirebaseAuth.instance.currentUser!.uid;
      final List<String> ids = [adminId, userId]..sort();
      final String chatId = ids.join("_");

      final String encryptedMsg = EncryptionService.encryptMessage(
        messageText,
        chatId,
      );

      await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
        'participants': [adminId, userId],
        'lastMessage': encryptedMsg,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastSenderId': adminId,
        'userNames': {adminId: "PriceSpy Admin", userId: data['displayName']},
        'userAvatars': {adminId: null, userId: data['photoUrl']},
        'unread_$userId': FieldValue.increment(1),
        'visibleFor': FieldValue.arrayUnion([adminId, userId]),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
            'senderId': adminId,
            'receiverId': userId,
            'text': encryptedMsg,
            'type': 'text',
            'status': 'sent',
            'timestamp': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: chatId,
            receiverId: userId,
            receiverName: "ADMIN: ${data['displayName']}",
            receiverPhoto: data['photoUrl'],
          ),
        ),
      );
    } catch (e) {
      _showSnackBar("Error: $e", isError: true);
    }
  }

  // --- RESTRICTION LOGIC ---
  Future<void> _restrictUserWithInput(
    String userId,
    String currentEmail,
  ) async {
    final TextEditingController durationController = TextEditingController();
    String durationType = 'Hours';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text("Restrict User"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: durationController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Duration"),
                    ),
                  ),
                  const SizedBox(width: 15),
                  DropdownButton<String>(
                    value: durationType,
                    items: ['Hours', 'Days']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => durationType = val);
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Palette.error),
              onPressed: () {
                final amount = int.tryParse(durationController.text);
                if (amount != null && amount > 0) {
                  Navigator.pop(context);
                  _performRestriction(userId, amount, durationType);
                }
              },
              child: Text("RESTRICT", style: TextStyle(color: Palette.surface)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performRestriction(
    String userId,
    int amount,
    String type,
  ) async {
    final expiry = type == 'Hours'
        ? DateTime.now().add(Duration(hours: amount))
        : DateTime.now().add(Duration(days: amount));
    await FirebaseFirestore.instance.collection('users').doc(userId).update({
      'isRestricted': true,
      'restrictedUntil': Timestamp.fromDate(expiry),
    });
    _showSnackBar("User restricted for $amount $type.");
  }

  Future<void> _liftRestriction(String userId) async {
    await FirebaseFirestore.instance.collection('users').doc(userId).update({
      'isRestricted': false,
      'restrictedUntil': null,
    });
    _showSnackBar("Restriction lifted.");
  }

  Future<void> _deleteUserRecord(String userId) async {
    try {
      await PostService().deleteAllUserPosts(userId);
      await FirebaseFirestore.instance.collection('users').doc(userId).delete();
      _showSnackBar(
        "User account and all associated posts deleted permanently.",
      );
    } catch (e) {
      _showSnackBar("Failed to delete user: $e", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin()) {
      return const Scaffold(body: Center(child: Text("ACCESS DENIED")));
    }

    return Scaffold(
      backgroundColor: Palette.background,
      drawer: const SidebarDrawer(),
      appBar: AppBar(
        title: const Text(
          "ADMIN CONSOLE",
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1),
        ),
        backgroundColor: Palette.primary,
        foregroundColor: Palette.surface,
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Palette.primaryAccent,
          indicatorWeight: 4,
          labelColor: Palette.surface,
          unselectedLabelColor: Palette.surface.withOpacity(0.6),
          tabs: const [
            Tab(text: "REPORTS"),
            Tab(text: "USERS"),
            Tab(text: "POSTS"),
          ],
        ),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildReportsTab(),
          _buildUsersTab(),
          const PostsManagementTab(),
        ],
      ),
    );
  }

  Widget _buildReportsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('reports')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;

        Map<String, int> reasonCounts = {};
        for (var doc in docs) {
          String r = (doc.data() as Map)['reason'] ?? 'Other';
          reasonCounts[r] = (reasonCounts[r] ?? 0) + 1;
        }

        String displayLabel = "Most Common";
        String displayValue = "None";

        if (reasonCounts.isNotEmpty) {
          int maxCount = reasonCounts.values.reduce((a, b) => a > b ? a : b);
          List<String> topReasons = reasonCounts.entries
              .where((e) => e.value == maxCount)
              .map((e) => e.key)
              .toList();

          if (topReasons.length == 1) {
            displayLabel = "Most Common";
            displayValue = topReasons.first;
          } else {
            displayLabel = "Top Issues (Tie)";
            if (topReasons.length > 2) {
              displayValue =
                  "${topReasons[0]}, ${topReasons[1]} (+${topReasons.length - 2})";
            } else {
              displayValue = topReasons.join(" & ");
            }
          }
        }

        return Column(
          children: [
            if (docs.isNotEmpty)
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Palette.primary, Palette.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(45, 55, 72, 0.26),
                      blurRadius: 10,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Pending Issues",
                            style: TextStyle(
                              color: Color.fromRGBO(247, 250, 252, 0.7),
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            "${docs.length}",
                            style: TextStyle(
                              color: Palette.surface,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "$displayLabel:",
                            style: TextStyle(
                              color: Color.fromRGBO(247, 250, 252, 0.38),
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            displayValue,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Palette.tertiary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 100,
                      width: 100,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 20,
                          sections: reasonCounts.entries.map((e) {
                            return PieChartSectionData(
                              value: e.value.toDouble(),
                              title: "",
                              radius: 30,
                              color:
                                  Colors.primaries[reasonCounts.keys
                                          .toList()
                                          .indexOf(e.key) %
                                      Colors.primaries.length],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: docs.isEmpty
                  ? const Center(child: Text("All Clean! No pending reports."))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Palette.background,
                              child: Icon(Icons.warning, color: Palette.error),
                            ),
                            title: Text(
                              data['reason'] ?? "Violation",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              "Item: ${data['productName'] ?? 'Unknown'}",
                            ),
                            trailing: Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: Palette.textMedium,
                            ),
                            onTap: () =>
                                _showReportActionSheet(docs[index].id, data),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUsersTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var users = snapshot.data!.docs;
        var originalUsers = users;

        if (_userSearchQuery.isNotEmpty) {
          users = users
              .where(
                (u) => (u.data() as Map)['email']
                    .toString()
                    .toLowerCase()
                    .contains(_userSearchQuery),
              )
              .toList();
        }

        if (_currentUserFilter == UserFilter.active) {
          users = users
              .where((u) => (u.data() as Map)['isRestricted'] != true)
              .toList();
        } else if (_currentUserFilter == UserFilter.restricted) {
          users = users
              .where((u) => (u.data() as Map)['isRestricted'] == true)
              .toList();
        }

        int total = originalUsers.length;
        int restricted = originalUsers
            .where((u) => (u.data() as Map)['isRestricted'] == true)
            .length;
        int active = total - restricted;

        return Column(
          children: [
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Palette.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Palette.background),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 🟢 FIXED: Wrapped items in Expanded to prevent overflow
                      Expanded(
                        child: _buildStatItem(
                          "All Users",
                          "$total",
                          Palette.primary,
                          isActive: _currentUserFilter == UserFilter.all,
                          onTap: () => setState(
                            () => _currentUserFilter = UserFilter.all,
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: Palette.background,
                      ),
                      Expanded(
                        child: _buildStatItem(
                          "Active", // Shortened label
                          "$active",
                          Palette.secondary, // Sage
                          isActive: _currentUserFilter == UserFilter.active,
                          onTap: () => setState(
                            () => _currentUserFilter = UserFilter.active,
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: Palette.background,
                      ),
                      Expanded(
                        child: _buildStatItem(
                          "Restricted",
                          "$restricted",
                          Palette.error,
                          isActive: _currentUserFilter == UserFilter.restricted,
                          onTap: () => setState(
                            () => _currentUserFilter = UserFilter.restricted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : active / total,
                      backgroundColor: Palette.background,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Palette.secondary,
                      ),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _userSearchController,
                decoration: InputDecoration(
                  hintText: "Search user email...",
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Palette.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) =>
                    setState(() => _userSearchQuery = v.toLowerCase()),
              ),
            ),
            const SizedBox(height: 10),

            Expanded(
              child: ListView.builder(
                itemCount: users.length,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemBuilder: (context, index) {
                  final userData = users[index].data() as Map<String, dynamic>;
                  final isRestricted = userData['isRestricted'] ?? false;
                  final Timestamp? restrictedUntil =
                      userData['restrictedUntil'];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 0,
                    color: Palette.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isRestricted
                            ? Palette.background
                            : Colors.transparent,
                      ),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundImage:
                            (userData['photoUrl'] != null &&
                                userData['photoUrl'] != '')
                            ? NetworkImage(userData['photoUrl'])
                            : null,
                        child:
                            (userData['photoUrl'] == null ||
                                userData['photoUrl'] == '')
                            ? Text(userData['displayName']?[0] ?? 'U')
                            : null,
                      ),
                      title: Text(
                        userData['displayName'] ?? "User",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: isRestricted && restrictedUntil != null
                          ? Text(
                              "⛔ Restricted until: ${DateFormat('MMM d, h:mm a').format(restrictedUntil.toDate())}",
                              style: TextStyle(
                                color: Palette.error,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : Text(userData['email'] ?? ""),
                      trailing: isRestricted
                          ? Icon(Icons.lock, color: Palette.error)
                          : const Icon(
                              Icons.check_circle,
                              color: Palette.secondary,
                            ),
                      onTap: () =>
                          _showUserActionSheet(users[index].id, userData),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    Color color, {
    bool isActive = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isActive ? color : Palette.textMedium,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReportActionSheet(String reportId, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Palette.background,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Administrative Enforcement",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 30),
            ListTile(
              leading: Icon(Icons.zoom_in, color: Palette.primary),
              title: const Text("Investigate Content"),
              subtitle: const Text("Open post details"),
              onTap: () async {
                Navigator.pop(sheetContext);
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) =>
                      const Center(child: CircularProgressIndicator()),
                );

                try {
                  final String? postId = data['postId'];
                  if (postId == null || postId.isEmpty) {
                    throw Exception("Report is missing Post ID");
                  }
                  final post = await FirebaseFirestore.instance
                      .collection('posts')
                      .doc(postId)
                      .get();
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  if (post.exists && post.data() != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) => ProductDetailsPage(
                          data: post.data()!,
                          documentId: post.id,
                          userPosition: null,
                        ),
                      ),
                    );
                  } else {
                    _showSnackBar(
                      "This post has already been deleted.",
                      isError: true,
                    );
                  }
                } catch (e) {
                  Navigator.of(context).pop();
                  _showSnackBar("Error: $e", isError: true);
                }
              },
            ),
            ListTile(
              leading: Icon(
                Icons.warning_amber_rounded,
                color: Palette.tertiary,
              ),
              title: const Text("Warning Chat with Accused"),
              onTap: () {
                Navigator.pop(sheetContext);
                _showWarningComposeDialog(
                  data['uploaderId'],
                  contextInfo: data['productName'],
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_forever, color: Palette.error),
              title: const Text("Delete Post Forever"),
              onTap: () {
                Navigator.pop(sheetContext);
                _deletePostPermanently(
                  reportId,
                  data['postId'],
                  data['uploaderEmail'],
                  data['productName'] ?? 'Listing',
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.check_circle_outline,
                color: Palette.secondary,
              ),
              title: const Text("Dismiss Report"),
              onTap: () {
                Navigator.pop(sheetContext);
                FirebaseFirestore.instance
                    .collection('reports')
                    .doc(reportId)
                    .update({'status': 'dismissed'});
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showUserActionSheet(String userId, Map<String, dynamic> userData) {
    final bool isRestricted = userData['isRestricted'] ?? false;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20),
          if (!isRestricted)
            ListTile(
              leading: Icon(Icons.timer_off, color: Palette.tertiary),
              title: const Text("Restrict Access"),
              onTap: () {
                Navigator.pop(context);
                _restrictUserWithInput(userId, userData['email']);
              },
            )
          else
            ListTile(
              leading: const Icon(Icons.lock_open, color: Palette.secondary),
              title: const Text("Lift Restriction"),
              onTap: () {
                Navigator.pop(context);
                _liftRestriction(userId);
              },
            ),
          ListTile(
            leading: Icon(Icons.chat, color: Palette.primary),
            title: const Text("Send Warning Message"),
            onTap: () {
              Navigator.pop(context);
              _showWarningComposeDialog(userId);
            },
          ),

          // 🟢 NEW OPTION: View All Posts
          ListTile(
            leading: Icon(Icons.grid_view, color: Palette.primary),
            title: const Text("View All Posts"),
            subtitle: const Text("Manage, delete, or investigate user content"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (c) => AdminUserPostsPage(
                    userId: userId,
                    userName: userData['displayName'] ?? "User",
                  ),
                ),
              );
            },
          ),

          ListTile(
            leading: Icon(Icons.delete_forever, color: Palette.error),
            title: const Text("Delete User & Data"),
            onTap: () {
              Navigator.pop(context);
              _deleteUserRecord(userId);
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
