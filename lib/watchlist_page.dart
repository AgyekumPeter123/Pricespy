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

  Future<String> _runManualRadar(
    double radiusKm,
    int mySessionId,
    Function(Map<String, double>) onUpdateGraph,
  ) async {
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
            // Fix 3: Add delay to prevent UI freeze (same logic applied here for consistency)
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

  // Fix 5: Manual Trigger Logic
  Future<void> _triggerManualSpy(Map<String, dynamic> spyData) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Scanning for '${spyData['keyword']}'..."),
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      Position myPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      final String searchKey = spyData['search_key'] ?? '';
      final double maxPrice = (spyData['max_price'] ?? 999999).toDouble();
      final double radiusMeters = (spyData['radius_km'] ?? 5).toDouble() * 1000;

      // Fix 5: Removed date limit (search all time)
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

  void _showAddAlertSheet() {
    final keywordController = TextEditingController();
    final priceController = TextEditingController();
    double radius = 20.0;
    String contextText = "Tap 'Check Coverage' to scan.";
    bool isFetching = false;
    bool isSaving = false; // Fix 4: Saving state

    // Reset graph for new sheet
    _sectorReach = {'North': 0, 'East': 0, 'South': 0, 'West': 0};

    Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low).then((
      pos,
    ) async {
      List<Placemark> marks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      if (marks.isNotEmpty) {
        _homeTown =
            marks.first.locality ?? marks.first.subLocality ?? "your area";
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
                    const Text(
                      "New Spy Alert",
                      style: TextStyle(
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
                    // Fix 4: Activate Button with Feedback
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
                                    Position position =
                                        await Geolocator.getCurrentPosition();
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(user!.uid)
                                        .collection('watchlist')
                                        .add({
                                          'keyword': keywordController.text
                                              .trim(),
                                          'search_key': keywordController.text
                                              .trim()
                                              .toLowerCase(),
                                          'max_price':
                                              double.tryParse(
                                                priceController.text,
                                              ) ??
                                              999999,
                                          'radius_km': radius,
                                          'latitude': position.latitude,
                                          'longitude': position.longitude,
                                          'created_at':
                                              FieldValue.serverTimestamp(),
                                        });

                                    if (mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            "Spy Activated! You can now scan for items.",
                                          ),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    setModalState(() => isSaving = false);
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
                            : const Text(
                                "ACTIVATE SPY",
                                style: TextStyle(
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
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddAlertSheet,
        backgroundColor: Colors.green[800],
        icon: const Icon(Icons.add_alert, color: Colors.white),
        label: const Text("New Alert", style: TextStyle(color: Colors.white)),
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
            return const Center(child: Text("No active spies."));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final data =
                  snapshot.data!.docs[index].data() as Map<String, dynamic>;
              final docId = snapshot.data!.docs[index].id;
              return Card(
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
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.notifications_active,
                      color: Colors.orange[800],
                    ),
                  ),
                  title: Text(
                    data['keyword'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    "Max: ₵${data['max_price']} • ${data['radius_km']} km radius",
                    style: const TextStyle(color: Colors.grey),
                  ),
                  // Fix 5: Icons for Delete and Search
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.youtube_searched_for,
                          color: Colors.blue,
                          size: 28,
                        ),
                        tooltip: "Scan Now",
                        onPressed: () => _triggerManualSpy(data),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: () => FirebaseFirestore.instance
                            .collection('users')
                            .doc(user!.uid)
                            .collection('watchlist')
                            .doc(docId)
                            .delete(),
                      ),
                    ],
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
    // Updated paints to match Location Settings style
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
