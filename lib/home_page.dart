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
import 'package:fl_chart/fl_chart.dart';

// Project imports
import 'add_price_sheet.dart';
import 'product_details_page.dart';
import 'sidebar_drawer.dart';
import 'comment_sheet.dart';
import 'screens/chat/chat_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final User? user = FirebaseAuth.instance.currentUser;

  static Position? _cachedPosition;
  static bool _hasLoadedOnce = false;

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

  Future<void> _initLocationLogic() async {
    if (_hasLoadedOnce && _cachedPosition != null) {
      if (mounted) {
        setState(() {
          _myPosition = _cachedPosition;
          _isLocationReady = true;
        });
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    double? savedLat = prefs.getDouble('last_latitude');
    double? savedLng = prefs.getDouble('last_longitude');
    int? savedTime = prefs.getInt('last_location_time');

    bool isCacheValid = false;

    if (savedLat != null && savedLng != null && savedTime != null) {
      final lastSaved = DateTime.fromMillisecondsSinceEpoch(savedTime);
      final diff = DateTime.now().difference(lastSaved);
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
            _isLocationReady = true;
          });
        }
      }
    }
    _getCurrentLocation(forceHighAccuracy: !isCacheValid);
  }

  Future<void> _getCurrentLocation({bool forceHighAccuracy = false}) async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

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
      }
    } catch (e) {
      debugPrint("GPS Error: $e");
      if (mounted) setState(() => _isLocationReady = true);
    }
  }

  Future<void> _refreshAll() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Updating location..."),
        duration: Duration(milliseconds: 1000),
      ),
    );
    await _loadSettings();
    await _getCurrentLocation(forceHighAccuracy: true);
  }

  Widget _buildMarketOverviewChart(int shopCount, int indCount) {
    if (shopCount == 0 && indCount == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Market Intelligence",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Live breakdown of nearby sellers",
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 12),
                _buildLegendItem("Shop Owners", shopCount, Colors.blue[700]!),
                const SizedBox(height: 6),
                _buildLegendItem("Individuals", indCount, Colors.orange[400]!),
              ],
            ),
          ),
          SizedBox(
            height: 100,
            width: 100,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 25,
                sections: [
                  PieChartSectionData(
                    color: Colors.blue[700],
                    value: shopCount.toDouble(),
                    radius: 25,
                    showTitle: false,
                  ),
                  PieChartSectionData(
                    color: Colors.orange[400],
                    value: indCount.toDouble(),
                    radius: 25,
                    showTitle: false,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          "$label ($count)",
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ],
    );
  }

  // 🟢 FIXED: Restored the detailed Skeleton Loader
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
              // Image Placeholder
              Container(
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
              ),
              // Text Placeholders
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
    final DateTime sevenDaysAgo = DateTime.now().subtract(
      const Duration(days: 7),
    );

    return Scaffold(
      backgroundColor: Colors.grey[50],
      drawer: const SidebarDrawer(isHome: true),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 160.0,
            floating: false,
            pinned: true,
            backgroundColor: Colors.green[800],
            elevation: 0,
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.sort, color: Colors.white),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            actions: [
              IconButton(
                onPressed: _refreshAll,
                icon: const Icon(Icons.refresh, color: Colors.white),
              ),
              IconButton(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => const AddPriceSheet(),
                ),
                icon: const Icon(Icons.camera_enhance, color: Colors.white),
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green[900]!, Colors.green[600]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text(
                      "PriceSpy",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 15),
                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.green,
                          ),
                          hintText: "Search cement, rice, iron rods...",
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
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
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Filters
                Container(
                  height: 65,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filters.length,
                    separatorBuilder: (c, i) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final filterName = _filters[index];
                      final isSelected = _selectedFilter == filterName;
                      return FilterChip(
                        label: Text(filterName),
                        selected: isSelected,
                        onSelected: (bool selected) =>
                            setState(() => _selectedFilter = filterName),
                        backgroundColor: Colors.white,
                        selectedColor: Colors.green[50],
                        checkmarkColor: Colors.green[800],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected
                                ? Colors.green[800]!
                                : Colors.grey[300]!,
                          ),
                        ),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Colors.green[800]
                              : Colors.grey[700],
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      );
                    },
                  ),
                ),
                // Location Status
                if (_myPosition != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.radar, size: 14, color: Colors.green[800]),
                        const SizedBox(width: 6),
                        Text(
                          "Scanning radius: ${_searchRadiusKm.round()} km",
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
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 60,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 10),
                        Text("No recent intel found nearby."),
                      ],
                    ),
                  ),
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

              // 📊 Calculate Stats for Chart
              int shopCount = 0;
              int indCount = 0;
              for (var doc in docs) {
                final type = (doc.data() as Map)['poster_type'];
                if (type == 'Shop Owner')
                  shopCount++;
                else
                  indCount++;
              }

              if (docs.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: Text("No items match your filter.")),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  // 🟢 INSERT CHART AT THE TOP
                  if (index == 0) {
                    return Column(
                      children: [
                        _buildMarketOverviewChart(shopCount, indCount),
                        IntelCard(
                          key: ValueKey(docs[0].id),
                          data: docs[0].data() as Map<String, dynamic>,
                          docId: docs[0].id,
                          userUid: user?.uid ?? '',
                          userPosition: _myPosition,
                        ),
                      ],
                    );
                  }

                  final realIndex = index;
                  final data = docs[realIndex].data() as Map<String, dynamic>;
                  final docId = docs[realIndex].id;

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
                      Navigator.pop(sheetContext);
                      _startPrivateChat(parentContext, receiverId);
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
