import 'dart:async';
import 'dart:math' show asin, atan2, cos, pi, sin;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'sidebar_drawer.dart';

class LocationSettingsPage extends StatefulWidget {
  const LocationSettingsPage({super.key});

  @override
  State<LocationSettingsPage> createState() => _LocationSettingsPageState();
}

class _LocationSettingsPageState extends State<LocationSettingsPage> {
  double _radiusKm = 20.0;
  bool _isLoading = true;
  Position? _currentPosition;
  late String _homeTown = "your area"; // Home town fallback

  String _contextText = "Adjust slider to check coverage...";
  bool _isFetchingContext = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadRadius();
    _initLocation();
  }

  Future<void> _loadRadius() async {
    final prefs = await SharedPreferences.getInstance();
    double savedRadius = prefs.getDouble('search_radius') ?? 20.0;
    if (mounted) {
      setState(() {
        _radiusKm = savedRadius;
        _isLoading = false;
      });
    }
  }

  // --- 1. STABLE LOCATION INITIALIZATION ---
  Future<void> _initLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _contextText =
              "Location access is disabled. Enable it in settings to see coverage.";
          _isLoading = false;
        });
        return;
      }

      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        _currentPosition = pos;

        // Fetch home town once for fallback logic
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

        _updateDynamicContext(_radiusKm);
      }
    } catch (e) {
      debugPrint("Location Init Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- 2. DYNAMIC CONTEXT (12-Point Step-Sampling) ---
  Future<void> _updateDynamicContext(double radiusKm) async {
    if (!mounted || _currentPosition == null || _isFetchingContext) return;

    setState(() => _isFetchingContext = true);

    try {
      Position position = _currentPosition!;

      // FIX: 12-point sweep data
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

      // Step-sampling distances
      List<double> steps = [
        5.0,
        10.0,
        15.0,
        20.0,
        radiusKm,
      ].where((s) => s <= radiusKm).toList();
      if (!steps.contains(radiusKm)) steps.add(radiusKm);

      // FIX: Reference the 'bearings' list to resolve the warning and organize sectors
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

        // Logic for "+Xkm beyond" wording
        if (lastFoundTown != null) {
          double beyond = radiusKm - lastFoundDistance;
          if (beyond > 3.0) {
            directionalFrontier[sector.key] =
                "$lastFoundTown (+${beyond.toInt()}km beyond)";
          } else {
            directionalFrontier[sector.key] = lastFoundTown;
          }
        } else {
          directionalFrontier[sector.key] = _homeTown; // Use fallback
        }
      }

      List<String> summary = [];
      directionalFrontier.forEach(
        (direction, info) => summary.add("$direction ($info)"),
      );

      _contextText =
          "At ${radiusKm.toInt()}km, coverage reaches ${summary.join(', ')}.";
    } catch (e) {
      _contextText = "Discovery area updated to ${radiusKm.toInt()}km.";
    }

    if (mounted) {
      setState(() => _isFetchingContext = false);
    }
  }

  // Spherical Math Helper
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
            name.toLowerCase() != "unnamed road") {
          return name;
        }
      }
    } catch (_) {}
    return null;
  }

  void _onSliderChanged(double value) {
    setState(() {
      _radiusKm = value;
      _contextText = "Checking coverage area...";
    });
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 1000), () {
      _updateDynamicContext(value);
    });
  }

  Future<void> _applySettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('search_radius', _radiusKm);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Radius set to ${_radiusKm.toInt()}km."),
          backgroundColor: Colors.green[800],
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const SidebarDrawer(),
      appBar: AppBar(
        title: const Text("Discovery Settings"),
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Search Radius",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Show items within ${_radiusKm.toInt()} kilometers of your location.",
                    style: TextStyle(color: Colors.grey[600], fontSize: 15),
                  ),
                  const SizedBox(height: 40),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.green[800],
                      thumbColor: Colors.green[800],
                      overlayColor: Colors.green.withOpacity(0.2),
                      valueIndicatorColor: Colors.green[800],
                    ),
                    child: Slider(
                      value: _radiusKm,
                      min: 1,
                      max: 100,
                      divisions: 99,
                      label: "${_radiusKm.toInt()} km",
                      onChanged: _onSliderChanged,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue[100]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.radar, color: Colors.blue[800]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _isFetchingContext
                              ? const SizedBox(
                                  height: 2,
                                  child: LinearProgressIndicator(),
                                )
                              : Text(
                                  _contextText,
                                  style: TextStyle(
                                    color: Colors.blue[900],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
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
                      onPressed: _applySettings,
                      child: const Text(
                        "SAVE CHANGES",
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
    );
  }
}
