import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

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
                      items: [
                        DropdownMenuItem(
                          value: "Notice",
                          child: Row(
                            children: const [
                              Icon(Icons.info, color: Colors.blue, size: 18),
                              SizedBox(width: 8),
                              Text("Friendly Notice"),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: "Warning",
                          child: Row(
                            children: const [
                              Icon(
                                Icons.warning,
                                color: Colors.orange,
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text("Official Warning"),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: "Critical",
                          child: Row(
                            children: const [
                              Icon(Icons.report, color: Colors.red, size: 18),
                              SizedBox(width: 8),
                              Text("Final / Critical"),
                            ],
                          ),
                        ),
                      ],
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
                  scrollPhysics: const BouncingScrollPhysics(),
                  decoration: InputDecoration(
                    hintText: "Enter the reason for this warning...",
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
              child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.send, size: 16),
              label: const Text("SEND & OPEN CHAT"),
              onPressed: () {
                if (messageController.text.trim().isEmpty) {
                  _showSnackBar("Please enter a message", isError: true);
                  return;
                }
                Navigator.pop(context);

                String icon = "⚠️";
                if (severity == "Notice") icon = "ℹ️";
                if (severity == "Critical") icon = "⛔";

                String finalMsg =
                    "$icon ADMIN ${severity.toUpperCase()}: ${messageController.text.trim()}";

                _sendWarningAndOpenChat(userId, finalMsg);
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- EXECUTE WARNING CHAT ---
  Future<void> _sendWarningAndOpenChat(
    String userId,
    String messageText,
  ) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!doc.exists) {
        _showSnackBar("User not found.", isError: true);
        return;
      }

      final data = doc.data() as Map<String, dynamic>;
      final name = data['displayName'] ?? "User";
      final photo = data['photoUrl'];
      final adminId = FirebaseAuth.instance.currentUser!.uid;

      final List<String> ids = [adminId, userId];
      ids.sort();
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
        'userNames': {adminId: "PriceSpy Admin", userId: name},
        'userAvatars': {adminId: null, userId: photo},
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
            'deletedFor': [],
            'isDeleted': false,
          });

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            chatId: chatId,
            receiverId: userId,
            receiverName: "ADMIN: $name",
            receiverPhoto: photo,
          ),
        ),
      );
    } catch (e) {
      debugPrint("Error details: $e");
      _showSnackBar("Chat Error: $e", isError: true);
    }
  }

  // --- USER RESTRICTION ---
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
              const Text("Select restriction duration:"),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: durationController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Duration",
                        border: OutlineInputBorder(),
                      ),
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
    try {
      final expiry = type == 'Hours'
          ? DateTime.now().add(Duration(hours: amount))
          : DateTime.now().add(Duration(days: amount));
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'isRestricted': true,
        'restrictedUntil': Timestamp.fromDate(expiry),
      });
      _showSnackBar("User restricted for $amount $type.");
    } catch (e) {
      _showSnackBar("Action failed: $e", isError: true);
    }
  }

  Future<void> _liftRestriction(String userId) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'isRestricted': false,
        'restrictedUntil': null,
      });
      _showSnackBar("Restriction lifted.");
    } catch (e) {
      _showSnackBar("Failed to lift restriction: $e", isError: true);
    }
  }

  Future<void> _deleteUserRecord(String userId) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).delete();
      _showSnackBar("User profile deleted (Auth account remains).");
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
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: "REPORTS"),
            Tab(text: "USERS"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildReportsList(), _buildUserManagement()],
      ),
    );
  }

  Widget _buildReportsList() {
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
        if (docs.isEmpty) {
          return const Center(child: Text("No pending reports."));
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 10),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.red.shade50,
                  child: const Icon(Icons.report, color: Colors.red),
                ),
                title: Text(
                  data['reason'] ?? "Policy Violation",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text("Item: ${data['productName'] ?? 'Unknown'}"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showReportActionSheet(docs[index].id, data),
              ),
            );
          },
        );
      },
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
                      .get()
                      .timeout(const Duration(seconds: 10));

                  if (!mounted) return;
                  Navigator.of(context).pop();

                  if (post.exists && post.data() != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) => ProductDetailsPage(
                          data: post.data()!,
                          documentId: post.id,
                          userPosition: null, // Admin sees NO location filter
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
                  if (mounted && Navigator.canPop(context)) {
                    Navigator.of(context).pop();
                  }
                  _showSnackBar("Error: ${e.toString()}", isError: true);
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

  Widget _buildUserManagement() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _userSearchController,
            decoration: InputDecoration(
              hintText: "Search email...",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              // 🟢 MOVED: contentPadding belongs here, NOT in OutlineInputBorder
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
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              var users = snapshot.data!.docs;
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
              return ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final userData = users[index].data() as Map<String, dynamic>;
                  final isRestricted = userData['isRestricted'] ?? false;
                  final Timestamp? restrictedUntil =
                      userData['restrictedUntil'];

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    elevation: 0,
                    color: Colors.white,
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
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(userData['email'] ?? ""),
                          if (isRestricted && restrictedUntil != null)
                            Text(
                              "Ends: ${DateFormat('MMM d, h:mm a').format(restrictedUntil.toDate())}",
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isRestricted
                              ? Colors.red.shade50
                              : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isRestricted ? "BANNED" : "ACTIVE",
                          style: TextStyle(
                            color: isRestricted ? Colors.red : Colors.green,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      onTap: () =>
                          _showUserActionSheet(users[index].id, userData),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
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
