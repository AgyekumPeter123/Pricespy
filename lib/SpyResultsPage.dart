import 'dart:async';
import 'dart:math' show asin, atan2, cos, pi, sin;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_page.dart';

class SpyResultsPage extends StatelessWidget {
  final String keyword;
  final String searchKey;
  final double maxPrice;
  final double radiusKm;
  final Position userPosition;

  const SpyResultsPage({
    super.key,
    required this.keyword,
    required this.searchKey,
    required this.maxPrice,
    required this.radiusKm,
    required this.userPosition,
  });

  // --- 🟢 Fix 4: High-Precision 36-point Sweep for consistency ---
  Future<String> _getCoverageSummary() async {
    try {
      List<Placemark> homeMarks = await placemarkFromCoordinates(
        userPosition.latitude,
        userPosition.longitude,
      );
      String homeTown = homeMarks.isNotEmpty
          ? (homeMarks.first.locality ?? "your area")
          : "your area";

      List<double> bearings = List.generate(36, (i) => i * 10.0);
      Map<String, String> directionalFrontier = {};

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
        double lastDist = 0;
        for (double b in s.value) {
          for (double d in steps) {
            String? t = await _getTownAtRadius(userPosition, d, b);
            if (t != null && t.isNotEmpty && t != homeTown) {
              lastTown = t;
              lastDist = d;
            }
          }
        }
        if (lastTown != null) {
          double beyond = radiusKm - lastDist;
          directionalFrontier[s.key] = beyond > 1.0
              ? "$lastTown (+${beyond.toInt()}km)"
              : lastTown;
        } else {
          directionalFrontier[s.key] = "Rural";
        }
      }

      List<String> summary = [];
      directionalFrontier.forEach((k, v) {
        if (v != "Rural") summary.add("$k: $v");
      });

      return summary.isEmpty
          ? "Scanning within ${radiusKm.toInt()}km of $homeTown."
          : "Reach: ${summary.join(', ')}.";
    } catch (e) {
      return "Discovery area reaches ${radiusKm.toInt()}km.";
    }
  }

  Future<String?> _getTownAtRadius(
    Position start,
    double dist,
    double brng,
  ) async {
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

  @override
  Widget build(BuildContext context) {
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final timeLimit = DateTime.now().subtract(const Duration(hours: 48));

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(
          "Spy Results: $keyword",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          FutureBuilder<String>(
            future: _getCoverageSummary(),
            builder: (context, snapshot) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.radar, size: 20, color: Colors.blue),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        snapshot.connectionState == ConnectionState.waiting
                            ? "Calculating coverage..."
                            : snapshot.data ?? "",
                        style: TextStyle(
                          color: Colors.blue[900],
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .where('search_key', isEqualTo: searchKey)
                  .where('price', isLessThanOrEqualTo: maxPrice)
                  .where(
                    'timestamp',
                    isGreaterThan: Timestamp.fromDate(timeLimit),
                  )
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                  return _buildEmptyState();

                final docs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  double dist = Geolocator.distanceBetween(
                    userPosition.latitude,
                    userPosition.longitude,
                    (data['latitude'] ?? 0).toDouble(),
                    (data['longitude'] ?? 0).toDouble(),
                  );
                  return dist <= (radiusKm * 1000);
                }).toList();

                if (docs.isEmpty) return _buildEmptyState();

                return ListView.builder(
                  padding: const EdgeInsets.only(top: 10, bottom: 20),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final docId = docs[index].id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: IntelCard(
                        key: ValueKey(docId),
                        data: data,
                        docId: docId,
                        userUid: currentUserId,
                        userPosition: userPosition,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 20),
          const Text(
            "No exact matches found nearby.",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          const Text(
            "Try increasing your radius in the Alert settings.",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
