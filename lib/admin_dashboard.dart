import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:fl_chart/fl_chart.dart'; // 🟢 Ensure fl_chart: ^0.66.0 is in pubspec.yaml

// Project specific imports
import 'product_details_page.dart';
import 'sidebar_drawer.dart';
import 'screens/chat/chat_screen.dart';
import 'encryption_service.dart';

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

  // Admin Config
  final String _adminEmail = "agyekumpeter123@gmail.com";
  final String _appPassword = "mmvc nwcj alff edwr";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
        backgroundColor: isError ? Colors.red.shade800 : Colors.teal.shade700,
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
      await FirebaseFirestore.instance.collection('posts').doc(postId).delete();
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .update({'status': 'resolved'});

      if (uploaderEmail != null) {
        _sendEmailDirectly(uploaderEmail, productName);
      }
      _showSnackBar("Post deleted forever. User notified via email.");
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
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
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
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
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
                    color: Colors.grey,
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
                    fillColor: Colors.grey.shade50,
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
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                final amount = int.tryParse(durationController.text);
                if (amount != null && amount > 0) {
                  Navigator.pop(context);
                  _performRestriction(userId, amount, durationType);
                }
              },
              child: const Text(
                "RESTRICT",
                style: TextStyle(color: Colors.white),
              ),
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
    await FirebaseFirestore.instance.collection('users').doc(userId).delete();
    _showSnackBar("User profile deleted.");
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin()) {
      return const Scaffold(body: Center(child: Text("ACCESS DENIED")));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      drawer: const SidebarDrawer(),
      appBar: AppBar(
        title: const Text(
          "ADMIN CONSOLE",
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1),
        ),
        backgroundColor: const Color(0xFF263238),
        foregroundColor: Colors.white,
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.tealAccent,
          indicatorWeight: 4,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: "REPORTS"),
            Tab(text: "USERS"),
          ],
        ),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.sort), // <--- The Sort Icon you wanted
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildReportsTab(), _buildUsersTab()],
      ),
    );
  }

  // 🔴 1. REPORTS TAB WITH CHARTS & TIE-BREAKER LOGIC
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

        // --- 📊 Smart Analytics Logic ---
        Map<String, int> reasonCounts = {};
        for (var doc in docs) {
          String r = (doc.data() as Map)['reason'] ?? 'Other';
          reasonCounts[r] = (reasonCounts[r] ?? 0) + 1;
        }

        String displayLabel = "Most Common";
        String displayValue = "None";

        if (reasonCounts.isNotEmpty) {
          // 1. Find the highest count
          int maxCount = reasonCounts.values.reduce((a, b) => a > b ? a : b);

          // 2. Find ALL reasons that match this count
          List<String> topReasons = reasonCounts.entries
              .where((e) => e.value == maxCount)
              .map((e) => e.key)
              .toList();

          // 3. Formatter: Join ties, truncate if too long
          if (topReasons.length == 1) {
            displayLabel = "Most Common";
            displayValue = topReasons.first;
          } else {
            displayLabel = "Top Issues (Tie)";
            // If more than 2 tied, show "+X"
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
            // --- Analytics Header ---
            if (docs.isNotEmpty)
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.blueGrey.shade800,
                      Colors.blueGrey.shade900,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
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
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            "${docs.length}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "$displayLabel:",
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            displayValue,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 📊 MINI PIE CHART
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
                              title: "", // Hide text on chart for cleanliness
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

            // --- Reports List ---
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
                              backgroundColor: Colors.red.shade50,
                              child: const Icon(
                                Icons.warning,
                                color: Colors.red,
                              ),
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
                            trailing: const Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: Colors.grey,
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

  // 🔴 2. USERS TAB WITH GAUGE STATS
  Widget _buildUsersTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var users = snapshot.data!.docs;

        // 📊 Filter Logic
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

        // 📊 Stats Calculation
        int total = users.length;
        int restricted = users
            .where((u) => (u.data() as Map)['isRestricted'] == true)
            .length;
        int active = total - restricted;

        return Column(
          children: [
            // --- Status Bar ---
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStatItem(
                        "Active Users",
                        "$active",
                        Colors.green.shade700,
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: Colors.grey.shade300,
                      ),
                      _buildStatItem(
                        "Restricted",
                        "$restricted",
                        Colors.red.shade700,
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  // Visual Gauge
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : active / total,
                      backgroundColor: Colors.red.shade100,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.green.shade400,
                      ),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _userSearchController,
                decoration: InputDecoration(
                  hintText: "Search user email...",
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
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

            // Users List
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
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isRestricted
                            ? Colors.red.shade100
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
                                color: Colors.red.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : Text(userData['email'] ?? ""),
                      trailing: isRestricted
                          ? const Icon(Icons.lock, color: Colors.red)
                          : const Icon(Icons.check_circle, color: Colors.green),
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

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
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
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // --- REPORT ACTION SHEET (Unchanged) ---
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
                color: Colors.grey.shade300,
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
              leading: const Icon(Icons.zoom_in, color: Colors.indigo),
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
              leading: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
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
              leading: const Icon(Icons.delete_forever, color: Colors.red),
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
                color: Colors.green,
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

  // --- USER ACTION SHEET (Unchanged) ---
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
              leading: const Icon(Icons.timer_off, color: Colors.orange),
              title: const Text("Restrict Access"),
              onTap: () {
                Navigator.pop(context);
                _restrictUserWithInput(userId, userData['email']);
              },
            )
          else
            ListTile(
              leading: const Icon(Icons.lock_open, color: Colors.green),
              title: const Text("Lift Restriction"),
              onTap: () {
                Navigator.pop(context);
                _liftRestriction(userId);
              },
            ),
          ListTile(
            leading: const Icon(Icons.chat, color: Colors.blue),
            title: const Text("Send Warning Message"),
            onTap: () {
              Navigator.pop(context);
              _showWarningComposeDialog(userId);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text("Delete Record"),
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
