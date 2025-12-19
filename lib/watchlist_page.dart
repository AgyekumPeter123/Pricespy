import 'dart:async'; // Required for the "Live" timer
import 'dart:math' show asin, atan2, cos, pi, sin;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'sidebar_drawer.dart';

class WatchlistPage extends StatefulWidget {
  const WatchlistPage({super.key});

  @override
  State<WatchlistPage> createState() => _WatchlistPageState();
}

class _WatchlistPageState extends State<WatchlistPage> {
  final User? user = FirebaseAuth.instance.currentUser;
  late String _homeTown = "your area";

  // --- 1. High-Precision Dynamic Context Fetcher ---
  Future<String> _getDynamicRadiusContext(double radiusKm) async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // 🔹 12 points for a thorough radar sweep (used to validate specific sectors)
      final List<double> bearings = [
        0.0,
        30.0,
        60.0,
        90.0,
        120.0,
        150.0,
        180.0,
        210.0,
        240.0,
        270.0,
        300.0,
        330.0,
      ];

      Map<String, String> directionalFrontier = {};

      // Walk outward in steps to find the "last known town"
      List<double> steps = [
        5.0,
        10.0,
        15.0,
        20.0,
        radiusKm,
      ].where((s) => s <= radiusKm).toList();
      if (!steps.contains(radiusKm)) steps.add(radiusKm);

      // Map primary directions to their respective points in the 'bearings' list
      Map<String, List<double>> cardinalSectors = {
        'North': bearings.where((b) => b >= 330 || b <= 30).toList(),
        'East': bearings.where((b) => b >= 60 && b <= 120).toList(),
        'South': bearings.where((b) => b >= 150 && b <= 210).toList(),
        'West': bearings.where((b) => b >= 240 && b <= 300).toList(),
      };

      for (var sector in cardinalSectors.entries) {
        String? lastFoundTown;
        double lastFoundDistance = 0.0;

        for (double b in sector.value) {
          for (double d in steps) {
            String? town = await _getTownAtRadius(position, d, b);
            if (town != null && town.isNotEmpty) {
              lastFoundTown = town;
              lastFoundDistance = d;
            }
          }
        }

        if (lastFoundTown != null) {
          double beyond = radiusKm - lastFoundDistance;
          directionalFrontier[sector.key] = beyond > 3.0
              ? "$lastFoundTown (+${beyond.toInt()}km beyond)"
              : lastFoundTown;
        } else {
          directionalFrontier[sector.key] = _homeTown;
        }
      }

      List<String> summary = [];
      directionalFrontier.forEach((dir, info) => summary.add("$dir ($info)"));
      return "At ${radiusKm.toInt()}km, coverage reaches ${summary.join(', ')}";
    } catch (e) {
      return "Adjust radius to see coverage.";
    }
  }

  Future<String?> _getTownAtRadius(
    Position start,
    double dist,
    double brngDegrees,
  ) async {
    try {
      const double R = 6371.0;
      double brng = brngDegrees * (pi / 180);
      double dR = dist / R;
      double lat1 = start.latitude * (pi / 180);
      double lon1 = start.longitude * (pi / 180);
      double lat2 = asin(sin(lat1) * cos(dR) + cos(lat1) * sin(dR) * cos(brng));
      double lon2 =
          lon1 +
          atan2(
            sin(brng) * sin(dR) * cos(lat1),
            cos(dR) - sin(lat1) * sin(lat2),
          );
      List<Placemark> marks = await placemarkFromCoordinates(
        lat2 * (180 / pi),
        lon2 * (180 / pi),
      );
      if (marks.isNotEmpty) {
        Placemark p = marks[0];
        String? name = p.locality ?? p.subLocality ?? p.name;
        if (name != null &&
            name.length > 2 &&
            !name.contains('+') &&
            name.toLowerCase() != "unnamed road")
          return name;
      }
    } catch (_) {}
    return null;
  }

  void _showAddAlertSheet() {
    final keywordController = TextEditingController();
    final priceController = TextEditingController();
    double radius = 20.0;
    String contextText = "Adjust slider to check coverage...";
    bool isFetching = false;
    Timer? debounce;

    Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low).then((
      pos,
    ) async {
      List<Placemark> marks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      if (marks.isNotEmpty) {
        _homeTown =
            marks.first.locality ??
            marks.first.subLocality ??
            marks.first.administrativeArea ??
            "your area";
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
          void onRadiusChanged(double val) {
            setModalState(() => radius = val);
            if (debounce?.isActive ?? false) debounce!.cancel();
            debounce = Timer(const Duration(milliseconds: 1000), () async {
              setModalState(() => isFetching = true);
              String result = await _getDynamicRadiusContext(val);
              if (context.mounted) {
                setModalState(() {
                  contextText = result;
                  isFetching = false;
                });
              }
            });
          }

          if (contextText == "Adjust slider to check coverage..." &&
              !isFetching) {
            onRadiusChanged(radius);
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              left: 24,
              right: 24,
              top: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  "New Spy Alert",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                Text(
                  "Get notified when items match your criteria.",
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 25),
                TextField(
                  controller: keywordController,
                  decoration: InputDecoration(
                    labelText: "Keyword",
                    hintText: "e.g. Cement, Rice, TV",
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
                  onChanged: (val) => onRadiusChanged(val),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    children: [
                      isFetching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.radar,
                              size: 20,
                              color: Colors.blue,
                            ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          contextText,
                          style: TextStyle(
                            color: Colors.blue[900],
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
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
                    onPressed: () async {
                      if (keywordController.text.isNotEmpty && user != null) {
                        Position position =
                            await Geolocator.getCurrentPosition();
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(user!.uid)
                            .collection('watchlist')
                            .add({
                              'keyword': keywordController.text.trim(),
                              'search_key': keywordController.text
                                  .trim()
                                  .toLowerCase(),
                              'max_price':
                                  double.tryParse(priceController.text) ??
                                  999999,
                              'radius_km': radius,
                              'latitude': position.latitude,
                              'longitude': position.longitude,
                              'created_at': FieldValue.serverTimestamp(),
                            });
                        if (mounted) Navigator.pop(context);
                      }
                    },
                    child: const Text(
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
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.radar,
                      size: 60,
                      color: Colors.green[200],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "No active spies.",
                    style: TextStyle(
                      color: Colors.grey[800],
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Add an alert to track prices nearby.",
                    style: TextStyle(color: Colors.grey),
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
              return Card(
                elevation: 2,
                color: Colors.white,
                surfaceTintColor: Colors.white,
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
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.monetization_on,
                              size: 14,
                              color: Colors.green[700],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "Max: ₵${data['max_price']}",
                              style: TextStyle(
                                color: Colors.green[800],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 14,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "${data['radius_km']} km radius",
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => FirebaseFirestore.instance
                        .collection('users')
                        .doc(user!.uid)
                        .collection('watchlist')
                        .doc(docId)
                        .delete(),
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
