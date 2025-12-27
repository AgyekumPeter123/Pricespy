import 'dart:async';
import 'dart:math' show asin, atan2, cos, pi, sin;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'sidebar_drawer.dart';
import 'SpyResultsPage.dart'; // REQUIRED IMPORT

class WatchlistPage extends StatefulWidget {
  const WatchlistPage({super.key});

  @override
  State<WatchlistPage> createState() => _WatchlistPageState();
}

class _WatchlistPageState extends State<WatchlistPage> {
  final User? user = FirebaseAuth.instance.currentUser;
  late String _homeTown = "your area";
  int _scanSessionId = 0;

  // Track reach for graph
  Map<String, double> _sectorReach = {
    'North': 0,
    'East': 0,
    'South': 0,
    'West': 0,
  };

  // --- MODIFICATION 1: SAFETY PERMISSION CHECK ---
  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location services are disabled. Please enable them to spy.',
            ),
          ),
        );
      }
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied')),
          );
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location permissions are permanently denied, we cannot request permissions.',
            ),
          ),
        );
      }
      return false;
    }
    return true;
  }

  Future<String> _runManualRadar(
    double radiusKm,
    int mySessionId,
    Function(Map<String, double>) onUpdateGraph,
  ) async {
    // Safety Check
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return "Permission Missing";

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // High Precision
      List<double> bearings = List.generate(36, (i) => i * 10.0);
      Map<String, String> directionalFrontier = {};
      Map<String, double> tempReach = {
        'North': 0,
        'East': 0,
        'South': 0,
        'West': 0,
      };

      // 2km Steps
      List<double> steps = [];
      for (double i = 2.0; i <= radiusKm; i += 2.0) steps.add(i);
      if (steps.isEmpty || steps.last != radiusKm) steps.add(radiusKm);

      Map<String, List<double>> sectors = {
        'North': bearings.where((b) => b >= 315 || b <= 45).toList(),
        'East': bearings.where((b) => b > 45 && b <= 135).toList(),
        'South': bearings.where((b) => b > 135 && b <= 225).toList(),
        'West': bearings.where((b) => b > 225 && b < 315).toList(),
      };

      for (var s in sectors.entries) {
        String? lastTown;
        double maxDist = 0;
        for (double b in s.value) {
          if (mySessionId != _scanSessionId) return "Cancelled";

          for (double d in steps) {
            // Fix: Add delay to prevent UI freeze (Smoothness)
            await Future.delayed(const Duration(milliseconds: 5));
            String? t = await _getTown(position, d, b);
            if (t != null && t.isNotEmpty && t != _homeTown) {
              lastTown = t;
              if (d > maxDist) maxDist = d;
            }
          }
        }

        tempReach[s.key] = maxDist;

        if (lastTown != null) {
          double beyond = radiusKm - maxDist;
          directionalFrontier[s.key] = beyond > 2.0
              ? "$lastTown (+${beyond.toInt()}km)"
              : lastTown;
        } else {
          directionalFrontier[s.key] = "Rural";
        }
      }

      if (mySessionId != _scanSessionId) return "Cancelled";

      // Update Graph Data
      onUpdateGraph(tempReach);

      List<String> sum = [];
      directionalFrontier.forEach((k, v) {
        if (v != "Rural") sum.add("$k: $v");
      });

      return sum.isEmpty
          ? "No major towns found nearby."
          : "Reach: ${sum.join(', ')}";
    } catch (e) {
      return "Unable to scan area.";
    }
  }

  Future<String?> _getTown(Position start, double dist, double brng) async {
    try {
      const double R = 6371.0;
      double radBrng = brng * (pi / 180);
      double dR = dist / R;
      double lat1 = start.latitude * (pi / 180);
      double lon1 = start.longitude * (pi / 180);
      double lat2 = asin(
        sin(lat1) * cos(dR) + cos(lat1) * sin(dR) * cos(radBrng),
      );
      double lon2 =
          lon1 +
          atan2(
            sin(radBrng) * sin(dR) * cos(lat1),
            cos(dR) - sin(lat1) * sin(lat2),
          );
      List<Placemark> marks = await placemarkFromCoordinates(
        lat2 * (180 / pi),
        lon2 * (180 / pi),
      );
      if (marks.isNotEmpty) {
        Placemark p = marks[0];
        String? n = p.locality ?? p.subLocality ?? p.name;
        if (n != null &&
            n.length > 2 &&
            !n.contains('+') &&
            n.toLowerCase() != "unnamed road")
          return n;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _triggerManualSpy(Map<String, dynamic> spyData) async {
    // Safety Check
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 15),
            Text("Scanning for '${spyData['keyword']}'..."),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      Position myPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      final String searchKey = spyData['search_key'] ?? '';
      final double maxPrice = (spyData['max_price'] ?? 999999).toDouble();
      final double radiusMeters = (spyData['radius_km'] ?? 5).toDouble() * 1000;

      final matches = await FirebaseFirestore.instance
          .collection('posts')
          .where('search_key', isEqualTo: searchKey)
          .where('price', isLessThanOrEqualTo: maxPrice)
          .get();

      int matchCount = 0;
      for (var post in matches.docs) {
        final postData = post.data();
        double dist = Geolocator.distanceBetween(
          myPos.latitude,
          myPos.longitude,
          (postData['latitude'] ?? 0).toDouble(),
          (postData['longitude'] ?? 0).toDouble(),
        );
        if (dist <= radiusMeters) matchCount++;
      }

      if (!mounted) return;

      if (matchCount > 0) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Spy found $matchCount item(s)!"),
            backgroundColor: Colors.green[800],
            action: SnackBarAction(
              label: "VIEW",
              textColor: Colors.yellow,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SpyResultsPage(
                      keyword: spyData['keyword'],
                      searchKey: searchKey,
                      maxPrice: maxPrice,
                      radiusKm: radiusMeters / 1000,
                      userPosition: myPos,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No items found in this radius yet.")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Scan failed: $e")));
    }
  }

  // Updated to support Editing
  void _showAddAlertSheet({Map<String, dynamic>? existingData, String? docId}) {
    final bool isEditing = existingData != null && docId != null;

    final keywordController = TextEditingController(
      text: isEditing ? existingData['keyword'] : '',
    );
    final priceController = TextEditingController(
      text: isEditing ? existingData['max_price'].toString() : '',
    );
    double radius = isEditing
        ? (existingData['radius_km'] as num).toDouble()
        : 20.0;

    String contextText = "Tap 'Check Coverage' to scan.";
    bool isFetching = false;
    bool isSaving = false;

    // Reset graph for new sheet
    _sectorReach = {'North': 0, 'East': 0, 'South': 0, 'West': 0};

    // Use our safe permission check before grabbing hometown
    _handleLocationPermission().then((granted) {
      if (granted) {
        Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
        ).then((pos) async {
          List<Placemark> marks = await placemarkFromCoordinates(
            pos.latitude,
            pos.longitude,
          );
          if (marks.isNotEmpty) {
            _homeTown =
                marks.first.locality ?? marks.first.subLocality ?? "your area";
          }
        });
      }
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> onCheckPressed() async {
            int mySession = ++_scanSessionId;
            setModalState(() {
              isFetching = true;
              contextText = "Scanning area...";
              _sectorReach = {'North': 0, 'East': 0, 'South': 0, 'West': 0};
            });

            String result = await _runManualRadar(radius, mySession, (
              newReach,
            ) {
              _sectorReach = newReach;
            });

            if (context.mounted && mySession == _scanSessionId) {
              setModalState(() {
                contextText = result;
                isFetching = false;
              });
            }
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      isEditing ? "Edit Spy Alert" : "New Spy Alert",
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 25),
                    TextField(
                      controller: keywordController,
                      decoration: InputDecoration(
                        labelText: "Keyword",
                        hintText: "e.g. Cement, Rice",
                        filled: true,
                        fillColor: Colors.grey[50],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: priceController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: "Max Price (₵)",
                        filled: true,
                        fillColor: Colors.grey[50],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: const Icon(Icons.payments_outlined),
                      ),
                    ),
                    const SizedBox(height: 25),

                    // SLIDER
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Alert Radius",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          "${radius.round()} km",
                          style: TextStyle(
                            color: Colors.green[800],
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: radius,
                      min: 1,
                      max: 100,
                      divisions: 99,
                      activeColor: Colors.green[800],
                      onChanged: (val) => setModalState(() {
                        _scanSessionId++;
                        radius = val;
                        isFetching = false;
                        contextText = "Radius changed. Tap to scan.";
                        _sectorReach = {
                          'North': 0,
                          'East': 0,
                          'South': 0,
                          'West': 0,
                        };
                      }),
                    ),

                    // SCAN BUTTON
                    Center(
                      child: TextButton.icon(
                        onPressed: isFetching ? null : onCheckPressed,
                        icon: isFetching
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.radar, size: 18),
                        label: Text(
                          isFetching ? "Scanning..." : "Check Coverage",
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blue,
                        ),
                      ),
                    ),

                    // GRAPH VISUALIZATION
                    Center(
                      child: SizedBox(
                        height: 150,
                        width: 150,
                        child: CustomPaint(
                          painter: _MiniRadarPainter(
                            data: _sectorReach,
                            maxRadius: radius,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.location_on,
                              size: 16,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        contextText,
                        style: TextStyle(
                          color: Colors.blue[900],
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),
                    // ACTIVATE/UPDATE BUTTON
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[800],
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (keywordController.text.isNotEmpty &&
                                    user != null) {
                                  setModalState(() => isSaving = true);

                                  try {
                                    final searchKey = keywordController.text
                                        .trim()
                                        .toLowerCase();
                                    final maxPrice =
                                        double.tryParse(priceController.text) ??
                                        999999;

                                    // --- DUPLICATE CHECK ---
                                    final duplicateQuery =
                                        await FirebaseFirestore.instance
                                            .collection('users')
                                            .doc(user!.uid)
                                            .collection('watchlist')
                                            .where(
                                              'search_key',
                                              isEqualTo: searchKey,
                                            )
                                            .where(
                                              'max_price',
                                              isEqualTo: maxPrice,
                                            )
                                            .get();

                                    bool isDuplicate = false;
                                    if (duplicateQuery.docs.isNotEmpty) {
                                      if (!isEditing) {
                                        isDuplicate = true;
                                      } else {
                                        if (duplicateQuery.docs.first.id !=
                                            docId) {
                                          isDuplicate = true;
                                        }
                                      }
                                    }

                                    if (isDuplicate) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              "An alert with this name and price already exists!",
                                            ),
                                            backgroundColor: Colors.orange,
                                          ),
                                        );
                                      }
                                      setModalState(() => isSaving = false);
                                      return;
                                    }

                                    Position position =
                                        await Geolocator.getCurrentPosition();

                                    final alertData = {
                                      'keyword': keywordController.text.trim(),
                                      'search_key': searchKey,
                                      'max_price': maxPrice,
                                      'radius_km': radius,
                                      'latitude': position.latitude,
                                      'longitude': position.longitude,
                                      'created_at':
                                          FieldValue.serverTimestamp(),
                                    };

                                    if (isEditing) {
                                      await FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(user!.uid)
                                          .collection('watchlist')
                                          .doc(docId)
                                          .update(alertData);
                                    } else {
                                      await FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(user!.uid)
                                          .collection('watchlist')
                                          .add(alertData);
                                    }

                                    if (mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            isEditing
                                                ? "Spy Updated!"
                                                : "Spy Activated! You can now scan for items.",
                                          ),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    setModalState(() => isSaving = false);
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text("Error: $e"),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                        child: isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                isEditing ? "UPDATE SPY" : "ACTIVATE SPY",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (user == null)
      return const Scaffold(body: Center(child: Text("Login required")));
    return Scaffold(
      backgroundColor: Colors.grey[100],
      drawer: const SidebarDrawer(),
      appBar: AppBar(
        title: const Text("My Spy Alerts"),
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddAlertSheet(),
        backgroundColor: Colors.green[800],
        elevation: 4,
        icon: const Icon(Icons.add_location_alt_outlined, color: Colors.white),
        label: const Text(
          "New Spy",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .collection('watchlist')
            .orderBy('created_at', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            // --- MODIFICATION 2: BETTER EMPTY STATE ---
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.radar, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    "No active spies.",
                    style: TextStyle(color: Colors.grey[500], fontSize: 18),
                  ),
                  Text(
                    "Tap '+ New Spy' to track items nearby.",
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final data =
                  snapshot.data!.docs[index].data() as Map<String, dynamic>;
              final docId = snapshot.data!.docs[index].id;

              // --- MODIFICATION 3: SWIPE TO DELETE ---
              return Dismissible(
                key: Key(docId),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red[100],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.delete, color: Colors.red[800]),
                ),
                confirmDismiss: (direction) async {
                  return await showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: const Text("Delete Spy?"),
                        content: const Text(
                          "Are you sure you want to remove this alert?",
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text("Cancel"),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text(
                              "Delete",
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
                onDismissed: (direction) {
                  FirebaseFirestore.instance
                      .collection('users')
                      .doc(user!.uid)
                      .collection('watchlist')
                      .doc(docId)
                      .delete();
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text("Spy removed")));
                },
                child: Card(
                  elevation: 2,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: Colors.green[50],
                      radius: 25,
                      child: Icon(
                        Icons.satellite_alt,
                        color: Colors.green[800],
                      ),
                    ),
                    title: Text(
                      data['keyword'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.monetization_on,
                            size: 14,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "Max: ₵${data['max_price']}",
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.wifi_tethering,
                            size: 14,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "${data['radius_km']} km",
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Edit
                        IconButton(
                          icon: const Icon(
                            Icons.edit_outlined,
                            color: Colors.grey,
                          ),
                          onPressed: () => _showAddAlertSheet(
                            existingData: data,
                            docId: docId,
                          ),
                        ),
                        // Prominent Scan Button
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.radar, color: Colors.blue),
                            tooltip: "Scan Now",
                            onPressed: () => _triggerManualSpy(data),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MiniRadarPainter extends CustomPainter {
  final Map<String, double> data;
  final double maxRadius;
  _MiniRadarPainter({required this.data, required this.maxRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final linePaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = Colors.green.withOpacity(0.2)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.green[700]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, radius, linePaint);
    canvas.drawCircle(center, radius * 0.5, linePaint);

    final path = Path();
    path.moveTo(center.dx, center.dy - _norm(data['North']!, radius));
    path.lineTo(center.dx + _norm(data['East']!, radius), center.dy);
    path.lineTo(center.dx, center.dy + _norm(data['South']!, radius));
    path.lineTo(center.dx - _norm(data['West']!, radius), center.dy);
    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, borderPaint);
  }

  double _norm(double val, double viewRadius) {
    if (val <= 0) return 0;
    double ratio = val / maxRadius;
    if (ratio > 1.0) ratio = 1.0;
    return ratio * viewRadius;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
