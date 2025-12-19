import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'add_price_sheet.dart';
import 'product_details_page.dart';
import 'sidebar_drawer.dart';
import 'comment_sheet.dart';
import 'screens/chat/chat_screen.dart';
import 'SpyResultsPage.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final User? user = FirebaseAuth.instance.currentUser;
  Position? _myPosition;
  double _searchRadiusKm = 20.0;
  String _selectedFilter = "Nearest Me";
  final List<String> _filters = [
    "Nearest Me",
    "Cheapest",
    "Shops Only",
    "Market Finds",
  ];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _getCurrentLocation();

    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.toLowerCase().trim();
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _searchRadiusKm = prefs.getDouble('search_radius') ?? 20.0;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() => _myPosition = position);
        _checkSpyAlerts();
      }
    } catch (e) {
      debugPrint("GPS Error: $e");
    }
  }

  Future<void> _checkSpyAlerts() async {
    if (user == null || _myPosition == null) return;
    try {
      final watchlistSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .collection('watchlist')
          .get();

      if (watchlistSnap.docs.isEmpty) return;
      final yesterday = DateTime.now().subtract(const Duration(hours: 24));

      for (var alertDoc in watchlistSnap.docs) {
        final alert = alertDoc.data();
        final String searchKey = alert['search_key'] ?? '';
        final double maxPrice = (alert['max_price'] ?? 999999).toDouble();
        final double radiusMeters = (alert['radius_km'] ?? 5).toDouble() * 1000;

        final matches = await FirebaseFirestore.instance
            .collection('posts')
            .where('search_key', isEqualTo: searchKey)
            .where('price', isLessThanOrEqualTo: maxPrice)
            .where('timestamp', isGreaterThan: Timestamp.fromDate(yesterday))
            .get();

        int matchCount = 0;
        for (var post in matches.docs) {
          final postData = post.data();
          double dist = Geolocator.distanceBetween(
            _myPosition!.latitude,
            _myPosition!.longitude,
            (postData['latitude'] ?? 0).toDouble(),
            (postData['longitude'] ?? 0).toDouble(),
          );
          if (dist <= radiusMeters) matchCount++;
        }

        if (matchCount > 0 && mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.radar, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Found $matchCount '${alert['keyword']}' nearby!",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green[900],
              duration: const Duration(seconds: 10),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: "VIEW",
                textColor: Colors.yellowAccent,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SpyResultsPage(
                        keyword: alert['keyword'],
                        searchKey: searchKey,
                        maxPrice: maxPrice,
                        radiusKm: radiusMeters / 1000,
                        userPosition: _myPosition!,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
          break;
        }
      }
    } catch (e) {
      debugPrint("Spy Alert Error: $e");
    }
  }

  Future<void> _refreshAll() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Syncing settings and location..."),
        duration: Duration(seconds: 1),
      ),
    );
    await _loadSettings();
    await _getCurrentLocation();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      drawer: const SidebarDrawer(isHome: true),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180.0,
            floating: false,
            pinned: true,
            backgroundColor: Colors.green[800],
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            actions: [
              IconButton(
                onPressed: _refreshAll,
                icon: const Icon(Icons.refresh, color: Colors.white),
                tooltip: "Sync Settings",
              ),
              IconButton(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => const AddPriceSheet(),
                ),
                icon: const Icon(Icons.camera_enhance, color: Colors.white),
                tooltip: "Spy Price",
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green.shade900, Colors.green.shade600],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      const Text(
                        "PriceSpy",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        height: 45,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            icon: const Icon(Icons.search, color: Colors.grey),
                            hintText: "Search cement, rice...",
                            border: InputBorder.none,
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear,
                                      color: Colors.grey,
                                    ),
                                    onPressed: () => _searchController.clear(),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filters.length,
                    itemBuilder: (context, index) {
                      final filterName = _filters[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: FilterChip(
                          label: Text(filterName),
                          selected: _selectedFilter == filterName,
                          onSelected: (bool selected) =>
                              setState(() => _selectedFilter = filterName),
                          backgroundColor: Colors.white,
                          selectedColor: Colors.green[800],
                          labelStyle: TextStyle(
                            color: _selectedFilter == filterName
                                ? Colors.white
                                : Colors.black87,
                          ),
                          checkmarkColor: Colors.white,
                        ),
                      );
                    },
                  ),
                ),
                if (_myPosition != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 14,
                          color: Colors.green[800],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "Showing items within ${_searchRadiusKm.round()} km",
                          style: TextStyle(
                            color: Colors.green[800],
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('posts')
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting)
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                return const SliverFillRemaining(
                  child: Center(child: Text("No intel yet.")),
                );

              var docs = snapshot.data!.docs;
              docs = docs
                  .where((d) => (d.data() as Map)['uploader_id'] != user?.uid)
                  .toList();

              if (_searchQuery.isNotEmpty) {
                docs = docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final name = (data['product_name'] ?? '')
                      .toString()
                      .toLowerCase();
                  final desc = (data['description'] ?? '')
                      .toString()
                      .toLowerCase();
                  final tags =
                      (data['ai_tags'] as List?)?.join(" ").toLowerCase() ?? "";
                  return name.contains(_searchQuery) ||
                      desc.contains(_searchQuery) ||
                      tags.contains(_searchQuery);
                }).toList();
              }

              if (_myPosition != null) {
                docs = docs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final double postLat = (data['latitude'] ?? 0).toDouble();
                  final double postLng = (data['longitude'] ?? 0).toDouble();
                  if (postLat == 0 && postLng == 0) return false;
                  final double dist = Geolocator.distanceBetween(
                    _myPosition!.latitude,
                    _myPosition!.longitude,
                    postLat,
                    postLng,
                  );
                  return dist <= (_searchRadiusKm * 1000);
                }).toList();
              }

              if (_selectedFilter == "Shops Only") {
                docs = docs
                    .where(
                      (d) => (d.data() as Map)['poster_type'] == 'Shop Owner',
                    )
                    .toList();
              } else if (_selectedFilter == "Market Finds") {
                docs = docs
                    .where(
                      (d) => (d.data() as Map)['poster_type'] == 'Individual',
                    )
                    .toList();
              }

              docs.sort((a, b) {
                final dataA = a.data() as Map<String, dynamic>;
                final dataB = b.data() as Map<String, dynamic>;
                if (_selectedFilter == "Cheapest")
                  return ((dataA['price'] ?? 0) as num).compareTo(
                    (dataB['price'] ?? 0) as num,
                  );
                if (_myPosition == null) return 0;
                double distA = Geolocator.distanceBetween(
                  _myPosition!.latitude,
                  _myPosition!.longitude,
                  (dataA['latitude'] ?? 0).toDouble(),
                  (dataA['longitude'] ?? 0).toDouble(),
                );
                double distB = Geolocator.distanceBetween(
                  _myPosition!.latitude,
                  _myPosition!.longitude,
                  (dataB['latitude'] ?? 0).toDouble(),
                  (dataB['longitude'] ?? 0).toDouble(),
                );
                return distA.compareTo(distB);
              });

              if (docs.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.location_off,
                          size: 50,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "No items found within ${_searchRadiusKm.round()} km.",
                        ),
                        TextButton(
                          onPressed: _refreshAll,
                          child: const Text("Refresh Location"),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final docId = docs[index].id;
                  return Padding(
                    padding: index == docs.length - 1
                        ? const EdgeInsets.only(bottom: 80)
                        : EdgeInsets.zero,
                    child: IntelCard(
                      key: ValueKey(docId),
                      data: data,
                      docId: docId,
                      userUid: user?.uid ?? '',
                      userPosition: _myPosition,
                    ),
                  );
                }, childCount: docs.length),
              );
            },
          ),
        ],
      ),
    );
  }
}

class IntelCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final String userUid;
  final Position? userPosition;

  const IntelCard({
    super.key,
    required this.data,
    required this.docId,
    required this.userUid,
    this.userPosition,
  });

  Future<void> _toggleSave(BuildContext context, bool isCurrentlySaved) async {
    if (userUid.isEmpty) return;
    final savedRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userUid)
        .collection('saved')
        .doc(docId);

    if (isCurrentlySaved) {
      await savedRef.delete();
    } else {
      await savedRef.set({
        'product_name': data['product_name'],
        'price': data['price'],
        'image_url': data['image_url'],
        'description': data['description'],
        'phone': data['phone'],
        'whatsapp_phone': data['whatsapp_phone'],
        'original_id': docId,
        'saved_at': FieldValue.serverTimestamp(),
      });
    }
  }

  void _showLongPressOptions(BuildContext context, String receiverId) {
    if (userUid.isEmpty || receiverId == userUid) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        height: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Chat with Seller",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(
                Icons.chat_bubble_rounded,
                color: Colors.green,
              ),
              title: const Text("Start Private Chat"),
              subtitle: const Text("Secure end-to-end encrypted"),
              onTap: () {
                Navigator.pop(context);
                _startPrivateChat(context, receiverId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startPrivateChat(
    BuildContext context,
    String receiverId,
  ) async {
    if (userUid.isEmpty || receiverId == userUid) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(receiverId)
          .get();
      if (!context.mounted) return;
      Navigator.pop(context);

      String displayName = "User";
      String? photoUrl;

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        displayName = userData['displayName'] ?? userData['username'] ?? "User";
        photoUrl = userData['photoUrl'] ?? userData['photoURL'];
      }

      final List<String> ids = [userUid, receiverId];
      ids.sort();
      final String chatId = ids.join("_");

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            chatId: chatId,
            receiverId: receiverId,
            receiverName: displayName,
            receiverPhoto: photoUrl,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Error starting chat.")));
      }
    }
  }

  void _launchURL(BuildContext context, String url) async {
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not launch action")),
        );
    }
  }

  void _openMap(BuildContext context, double lat, double lng) => _launchURL(
    context,
    "https://www.google.com/maps/search/?api=1&query=$lat,$lng",
  );

  void _openWhatsApp(BuildContext context, String phone) {
    String clean = phone.replaceAll(RegExp(r'\s+'), '');
    if (clean.startsWith('0')) clean = '+233${clean.substring(1)}';
    _launchURL(context, "https://wa.me/$clean");
  }

  void _openComments(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          CommentSheet(postId: docId, postOwnerId: data['uploader_id'] ?? ""),
    );
  }

  @override
  Widget build(BuildContext context) {
    String name = data['product_name'] ?? 'Unknown';
    double price = (data['price'] ?? 0).toDouble();
    String imageUrl = data['image_url'] ?? '';
    String type = data['poster_type'] ?? 'Individual';
    String phone = data['phone'] ?? '';
    String whatsapp = data['whatsapp_phone'] ?? phone;
    double lat = (data['latitude'] ?? 0).toDouble();
    double lng = (data['longitude'] ?? 0).toDouble();

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ProductDetailsPage(data: data, documentId: docId),
        ),
      ),
      onLongPress: () =>
          _showLongPressOptions(context, data['uploader_id'] ?? ''),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              Container(height: 180, color: Colors.grey[300]),
                          errorWidget: (context, url, error) => Container(
                            height: 180,
                            color: Colors.grey[300],
                            child: const Icon(Icons.broken_image),
                          ),
                        )
                      : Container(height: 180, color: Colors.grey[300]),
                ),
                Positioned(
                  top: 5,
                  right: 5,
                  child: StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(userUid)
                        .collection('saved')
                        .doc(docId)
                        .snapshots(),
                    builder: (context, snapshot) {
                      bool isSaved = snapshot.hasData && snapshot.data!.exists;
                      return IconButton(
                        icon: Icon(
                          isSaved ? Icons.favorite : Icons.favorite_border,
                          color: isSaved ? Colors.red : Colors.white,
                          size: 28,
                        ),
                        onPressed: () => _toggleSave(context, isSaved),
                      );
                    },
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        NumberFormat.currency(symbol: '₵').format(price),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[800],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        type == 'Shop Owner' ? Icons.store : Icons.person,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        type,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _actionBtn(
                        context,
                        Icons.phone,
                        "Call",
                        Colors.green,
                        () => _launchURL(context, "tel:$phone"),
                      ),
                      _actionBtn(
                        context,
                        Icons.message,
                        "Chat",
                        Colors.teal,
                        () => _openWhatsApp(context, whatsapp),
                      ),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('posts')
                            .doc(docId)
                            .collection('comments')
                            .snapshots(),
                        builder: (context, commentSnap) {
                          int count = commentSnap.hasData
                              ? commentSnap.data!.docs.length
                              : 0;
                          return InkWell(
                            onTap: () => _openComments(context),
                            child: Column(
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    const Icon(
                                      Icons.comment,
                                      color: Colors.orange,
                                      size: 20,
                                    ),
                                    if (count > 0)
                                      Positioned(
                                        top: -8,
                                        right: -8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[600],
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Text(
                                            count.toString(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const Text(
                                  "Comment",
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      _actionBtn(
                        context,
                        Icons.map,
                        "Map",
                        Colors.blue,
                        () => _openMap(context, lat, lng),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(
    BuildContext context,
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}
