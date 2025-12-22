import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

// Project imports
import 'add_price_sheet.dart';
import 'product_details_page.dart';
import 'sidebar_drawer.dart';
import 'comment_sheet.dart';
import 'screens/chat/chat_screen.dart';
// import 'SpyResultsPage.dart'; // No longer needed here as auto-snackbar is removed

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final User? user = FirebaseAuth.instance.currentUser;

  // 1. STATIC CACHE: Persists across navigation (Home -> Details -> Home)
  static Position? _cachedPosition;
  static bool _hasLoadedOnce = false;

  // Instance variables
  Position? _myPosition;
  double _searchRadiusKm = 20.0;
  bool _isLocationReady = false;

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
    _initLocationLogic();

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

  // --- SMART LOCATION LOGIC WITH FRESHNESS CHECK ---
  Future<void> _initLocationLogic() async {
    // 1. Memory Cache (Fastest) - Always fresh for this session
    if (_hasLoadedOnce && _cachedPosition != null) {
      if (mounted) {
        setState(() {
          _myPosition = _cachedPosition;
          _isLocationReady = true;
        });
        // Removed auto-spy check: _checkSpyAlerts();
      }
      return;
    }

    // 2. Disk Cache (SharedPreferences) - CHECK FRESHNESS
    final prefs = await SharedPreferences.getInstance();
    double? savedLat = prefs.getDouble('last_latitude');
    double? savedLng = prefs.getDouble('last_longitude');
    int? savedTime = prefs.getInt('last_location_time');

    bool isCacheValid = false;

    if (savedLat != null && savedLng != null && savedTime != null) {
      final lastSaved = DateTime.fromMillisecondsSinceEpoch(savedTime);
      final diff = DateTime.now().difference(lastSaved);

      // RULE: If cache is younger than 30 minutes, trust it.
      // If older, ignore it (assume user moved) and wait for GPS.
      if (diff.inMinutes < 30) {
        isCacheValid = true;
        if (mounted) {
          setState(() {
            _myPosition = Position(
              latitude: savedLat,
              longitude: savedLng,
              timestamp: lastSaved,
              accuracy: 0,
              altitude: 0,
              heading: 0,
              speed: 0,
              speedAccuracy: 0,
              altitudeAccuracy: 0,
              headingAccuracy: 0,
            );
            _isLocationReady = true; // Show UI immediately!
          });
        }
      }
    }

    // 3. Trigger Background Refresh
    // If cache was valid, we do a cheap "medium" accuracy update.
    // If cache was invalid/stale, we force "high" accuracy.
    _getCurrentLocation(forceHighAccuracy: !isCacheValid);
  }

  Future<void> _getCurrentLocation({bool forceHighAccuracy = false}) async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      // FIX #1: Respect forceHighAccuracy to save battery/speed
      // Background updates use Medium, Fresh loads use High
      Position freshPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: forceHighAccuracy
            ? LocationAccuracy.high
            : LocationAccuracy.medium,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('last_latitude', freshPosition.latitude);
      await prefs.setDouble('last_longitude', freshPosition.longitude);
      await prefs.setInt(
        'last_location_time',
        DateTime.now().millisecondsSinceEpoch,
      );

      _cachedPosition = freshPosition;
      _hasLoadedOnce = true;

      if (mounted) {
        setState(() {
          _myPosition = freshPosition;
          _isLocationReady = true;
        });
        // Removed auto-spy check: _checkSpyAlerts();
      }
    } catch (e) {
      debugPrint("GPS Error: $e");
      // Even if GPS fails, ensure we stop showing skeletons so users aren't stuck
      if (mounted) setState(() => _isLocationReady = true);
    }
  }

  // Auto Spy Alert Logic Removed per User Request (Fix 5)

  Future<void> _refreshAll() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Updating location..."),
        duration: Duration(milliseconds: 1000),
      ),
    );
    // On manual refresh, we always force fresh High Accuracy GPS
    await _loadSettings();
    await _getCurrentLocation(forceHighAccuracy: true);
  }

  // --- SKELETON LOADER WIDGET ---
  Widget _buildSkeletonLoader() {
    return ListView.builder(
      itemCount: 4,
      padding: const EdgeInsets.only(top: 8),
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          height: 300,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 20, width: 150, color: Colors.grey[300]),
                    const SizedBox(height: 8),
                    Container(height: 20, width: 100, color: Colors.grey[300]),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          width: 60,
                          height: 30,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(width: 20),
                        Container(
                          width: 60,
                          height: 30,
                          color: Colors.grey[300],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 7-day window for freshness
    final DateTime sevenDaysAgo = DateTime.now().subtract(
      const Duration(days: 7),
    );

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
                tooltip: "Refresh Location & Feed",
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
                            hintStyle: TextStyle(color: Colors.grey[500]),
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
            // FIX #2: Pass NULL if location isn't ready.
            // This prevents Firestore reads until we know where we are.
            stream: _isLocationReady
                ? FirebaseFirestore.instance
                      .collection('posts')
                      .where(
                        'timestamp',
                        isGreaterThan: Timestamp.fromDate(sevenDaysAgo),
                      )
                      .orderBy('timestamp', descending: true)
                      .limit(150)
                      .snapshots()
                : null,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SliverFillRemaining(
                  child: Center(child: Text("Error: ${snapshot.error}")),
                );
              }

              // --- WAITING STATES ---
              // If stream is null (ConnectionState.none) or waiting, show Skeleton
              if (snapshot.connectionState == ConnectionState.none ||
                  snapshot.connectionState == ConnectionState.waiting) {
                return SliverFillRemaining(child: _buildSkeletonLoader());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: Text("No recent intel found.")),
                );
              }

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
              } else {
                // Fallback if position is null (Safety check)
                return SliverFillRemaining(child: _buildSkeletonLoader());
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
                if (_selectedFilter == "Cheapest") {
                  return ((dataA['price'] ?? 0) as num).compareTo(
                    (dataB['price'] ?? 0) as num,
                  );
                }
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
        // FIX 1: Save Uploader ID for comments to work later
        'uploader_id': data['uploader_id'],
        'saved_at': FieldValue.serverTimestamp(),
      });
    }
  }

  void _showLongPressOptions(BuildContext parentContext, String receiverId) {
    if (userUid.isEmpty || receiverId == userUid) return;

    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
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
                      Navigator.pop(sheetContext); // Close sheet
                      _startPrivateChat(
                        parentContext,
                        receiverId,
                      ); // Start chat
                    },
                  ),
                ],
              ),
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
                        FontAwesomeIcons.whatsapp,
                        "WhatsApp",
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
