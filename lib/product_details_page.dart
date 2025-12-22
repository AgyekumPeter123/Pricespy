import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'add_price_sheet.dart';
import 'comment_sheet.dart';
import 'price_trend_chart.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class ProductDetailsPage extends StatefulWidget {
  final Map<String, dynamic> data;
  final String documentId;
  final bool autoOpenComments;
  final Position? userPosition;

  const ProductDetailsPage({
    super.key,
    required this.data,
    required this.documentId,
    this.autoOpenComments = false,
    this.userPosition,
  });

  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends State<ProductDetailsPage> {
  // Fix 1: Store uploaderId locally so we can update it if missing
  late String _uploaderId;
  String? _uploaderEmail; // Fix 2: To store fetched email for admin
  bool _isAdmin = false;
  final String _adminEmail =
      "agyekumpeter123@gmail.com"; // Hardcoded Admin Check

  @override
  void initState() {
    super.initState();
    _uploaderId = widget.data['uploader_id'] ?? '';
    _checkAdminAndFetchDetails();

    // Fix 1: If uploader_id is missing (common in Saved Posts), fetch it.
    if (_uploaderId.isEmpty) {
      _fetchMissingDetails();
    }

    if (widget.autoOpenComments) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openComments();
      });
    }
  }

  void _checkAdminAndFetchDetails() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email == _adminEmail) {
      setState(() {
        _isAdmin = true;
      });
      // Fetch uploader email for Admin view
      if (_uploaderId.isNotEmpty) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(_uploaderId)
            .get()
            .then((snap) {
              if (snap.exists) {
                setState(() {
                  _uploaderEmail = snap.data()?['email'];
                });
              }
            });
      }
    }
  }

  Future<void> _fetchMissingDetails() async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.documentId)
          .get();
      if (doc.exists) {
        final freshData = doc.data() as Map<String, dynamic>;
        setState(() {
          _uploaderId = freshData['uploader_id'] ?? '';
          // If admin, fetch email now that we have ID
          if (_isAdmin && _uploaderId.isNotEmpty) {
            FirebaseFirestore.instance
                .collection('users')
                .doc(_uploaderId)
                .get()
                .then((snap) {
                  if (snap.exists)
                    setState(() => _uploaderEmail = snap.data()?['email']);
                });
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching missing details: $e");
    }
  }

  void _openComments() {
    // Fix 1: Use the potentially updated _uploaderId
    if (_uploaderId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Loading post details... try again.")),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          CommentSheet(postId: widget.documentId, postOwnerId: _uploaderId),
    );
  }

  // --- REPORT LOGIC ---
  Future<void> _reportProduct() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please login to report items.")),
        );
      }
      return;
    }

    final reasons = [
      "Fake or Scam",
      "Wrong Price",
      "Duplicate Post",
      "Inappropriate Image",
      "Item Sold/Unavailable",
    ];

    await showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text("Report this item"),
        children: reasons.map((r) {
          return SimpleDialogOption(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Text(r),
            onPressed: () async {
              Navigator.pop(context); // Close dialog

              await FirebaseFirestore.instance.collection('reports').add({
                'postId': widget.documentId,
                'productName': widget.data['product_name'] ?? 'Unknown',
                'reporterId': user.uid,
                'reporterName': user.displayName ?? 'Anonymous',
                'uploaderId': _uploaderId, // Use local var
                // Fix 2: Save uploader email in report if possible
                'uploaderEmail': _uploaderEmail,
                'reason': r,
                'timestamp': FieldValue.serverTimestamp(),
                'status': 'pending',
              });

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Report sent. Admin will review this shortly.",
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
          );
        }).toList(),
      ),
    );
  }

  Future<void> _deleteProduct() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Post?"),
        content: const Text("This cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.documentId)
          .delete();
      if (mounted) {
        Navigator.pop(context); // Close details page
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Deleted successfully")));
      }
    }
  }

  void _editProduct() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddPriceSheet(
        existingData: widget.data,
        existingId: widget.documentId,
      ),
    );
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not launch action")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    // Fix 1: Use local _uploaderId
    final bool isOwner = currentUser?.uid == _uploaderId;

    String locationName = widget.data['location_name'] ?? 'Unknown Location';
    String landmark = widget.data['landmark'] ?? '';

    String shopName = widget.data['shop_name'] ?? '';
    String condition = widget.data['item_condition'] ?? 'New';
    String shopFrontUrl = widget.data['shop_front_image_url'] ?? '';
    bool isShop = widget.data['poster_type'] == 'Shop Owner';

    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openComments,
        backgroundColor: Colors.white,
        icon: Icon(Icons.comment, color: Colors.green[800]),
        label: Text("Comments", style: TextStyle(color: Colors.green[800])),
      ),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          if (isOwner) ...[
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: _editProduct,
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _deleteProduct,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.flag_outlined, color: Colors.grey),
              tooltip: "Report Item",
              onPressed: _reportProduct,
            ),
          ],
        ],
      ),
      extendBodyBehindAppBar: true,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Full Screen Image
            Hero(
              tag: widget.data['image_url'] ?? 'img',
              child: Container(
                height: 350,
                width: double.infinity,
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage(widget.data['image_url'] ?? ''),
                    fit: BoxFit.cover,
                  ),
                  color: Colors.grey[200],
                ),
              ),
            ),

            // 2. Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          widget.data['product_name'] ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        NumberFormat.currency(
                          symbol: '₵',
                        ).format(widget.data['price'] ?? 0),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[800],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),

                  // Tags Row
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(
                        label: Text(widget.data['poster_type'] ?? 'Individual'),
                        backgroundColor: isShop
                            ? Colors.blue[100]
                            : Colors.green[100],
                        labelStyle: TextStyle(
                          color: isShop ? Colors.blue[900] : Colors.green[900],
                        ),
                      ),

                      if (!isShop)
                        Chip(
                          label: Text(condition),
                          backgroundColor: Colors.orange[100],
                          labelStyle: TextStyle(color: Colors.orange[900]),
                        ),

                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          "/ ${widget.data['unit'] ?? 'Item'}",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Fix 2: Admin Insight Panel
                  if (_isAdmin && _uploaderEmail != null)
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.admin_panel_settings,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "ADMIN INSIGHT",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                                Text(
                                  "Uploader Email: $_uploaderEmail",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (isShop && shopName.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.store, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          shopName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 20),
                  const Text(
                    "Description",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    widget.data['description'] ??
                        "No additional details provided.",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[700],
                      height: 1.5,
                    ),
                  ),

                  // PRICE TREND CHART
                  PriceTrendChart(
                    productName: widget.data['product_name'] ?? '',
                    userPosition: widget.userPosition,
                  ),

                  const Divider(),
                  const SizedBox(height: 10),

                  // LOCATION
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              locationName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (landmark.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  "Closest Landmark: $landmark",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.green[800],
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  if (isShop && shopFrontUrl.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      "Shop Front View",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        image: DecorationImage(
                          image: NetworkImage(shopFrontUrl),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 10),

                  // SELLER INFO
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Text((widget.data['uploader_name'] ?? 'U')[0]),
                    ),
                    title: Text(
                      widget.data['uploader_name'] ?? 'Unknown Seller',
                    ),
                    subtitle: Text(
                      "Posted on ${DateFormat.yMMMd().format(widget.data['timestamp']?.toDate() ?? DateTime.now())}",
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ACTION BUTTONS
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              _launchURL("tel:${widget.data['phone']}"),
                          icon: const Icon(Icons.phone, color: Colors.white),
                          label: const Text(
                            "Call",
                            style: TextStyle(color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            String phone =
                                widget.data['whatsapp_phone'] ??
                                widget.data['phone'] ??
                                '';
                            String cleanPhone = phone.replaceAll(
                              RegExp(r'\s+'),
                              '',
                            );
                            if (cleanPhone.startsWith('0')) {
                              cleanPhone = '+233${cleanPhone.substring(1)}';
                            }
                            _launchURL("https://wa.me/$cleanPhone");
                          },
                          icon: const Icon(
                            FontAwesomeIcons.whatsapp,
                            color: Colors.white,
                          ),
                          label: const Text(
                            "WhatsApp",
                            style: TextStyle(color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
