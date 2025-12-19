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

  // --- UPDATED: STEP-SAMPLING FOR ACCURATE SPY RESULTS ---
  Future<String> _getCoverageSummary() async {
    try {
      // 1. Get Home Town first
      List<Placemark> homeMarks = await placemarkFromCoordinates(
        userPosition.latitude,
        userPosition.longitude,
      );
      String homeTown = homeMarks.isNotEmpty
          ? (homeMarks.first.locality ?? "your area")
          : "your area";

      Map<String, String> directionalFrontier = {};
      Map<String, List<double>> cardinalBearings = {
        'North': [0, 330, 30],
        'East': [90, 60, 120],
        'South': [180, 150, 210],
        'West': [270, 240, 300],
      };

      // FIX: Add .0 to the integers
      List<double> steps = [
        5.0,
        10.0,
        15.0,
        20.0,
        radiusKm,
      ].where((s) => s <= radiusKm).toList();

      for (var entry in cardinalBearings.entries) {
        String? lastFoundTown;
        double lastFoundDistance = 0;

        for (double b in entry.value) {
          for (double d in steps) {
            String? town = await _getTownAtRadius(userPosition, d, b);
            if (town != null && town.isNotEmpty) {
              lastFoundTown = town;
              lastFoundDistance = d;
            }
          }
        }

        if (lastFoundTown != null) {
          double beyond = radiusKm - lastFoundDistance;
          directionalFrontier[entry.key] = beyond > 3
              ? "$lastFoundTown (+${beyond.toInt()}km beyond)"
              : lastFoundTown;
        } else {
          directionalFrontier[entry.key] = homeTown;
        }
      }

      List<String> summary = [];
      directionalFrontier.forEach((dir, info) => summary.add("$dir ($info)"));
      return "At ${radiusKm.toInt()}km, coverage reaches ${summary.join(', ')}.";
    } catch (e) {
      return "Discovery area reaches ${radiusKm.toInt()}km.";
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
        elevation: 0,
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
