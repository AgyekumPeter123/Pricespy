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
  late String _homeTown = "your area";

  String _contextText = "Tap 'Check Coverage' to see reachable towns.";
  bool _isFetchingContext = false;
  int _scanSessionId = 0;

  // Data for the Graph
  Map<String, double> _sectorReach = {
    'North': 0,
    'East': 0,
    'South': 0,
    'West': 0,
  };

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

  Future<void> _initLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _contextText = "Location disabled in settings.";
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
      }
    } catch (e) {
      debugPrint("Location Init Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- RESTORED HIGH-PRECISION RADAR ---
  Future<void> _checkCoverage() async {
    if (_currentPosition == null) return;

    // Start new session
    final int mySessionId = ++_scanSessionId;

    setState(() {
      _isFetchingContext = true;
      // FIX 1: Update text immediately to avoid confusion
      _contextText = "Scanning area...";
      // Reset graph
      _sectorReach = {'North': 0, 'East': 0, 'South': 0, 'West': 0};
    });

    try {
      Position position = _currentPosition!;

      // 1. High Precision: 36 bearings (every 10 degrees)
      List<double> bearings = List.generate(36, (index) => index * 10.0);
      Map<String, String> directionalFrontier = {};
      Map<String, double> tempReach = {
        'North': 0,
        'East': 0,
        'South': 0,
        'West': 0,
      };

      // 2. High Precision: 2km steps
      List<double> steps = [];
      for (double i = 2.0; i <= _radiusKm; i += 2.0) {
        steps.add(i);
      }
      if (steps.isEmpty || steps.last != _radiusKm) steps.add(_radiusKm);

      Map<String, List<double>> cardinalSectors = {
        'North': bearings.where((b) => b >= 315 || b <= 45).toList(),
        'East': bearings.where((b) => b > 45 && b <= 135).toList(),
        'South': bearings.where((b) => b > 135 && b <= 225).toList(),
        'West': bearings.where((b) => b > 225 && b < 315).toList(),
      };

      for (var sector in cardinalSectors.entries) {
        String? lastFoundTown;
        double maxDistInSector = 0.0;

        for (double b in sector.value) {
          if (mySessionId != _scanSessionId) return; // Stop if cancelled

          for (double d in steps) {
            // FIX 3: Yield to UI thread to prevent freezing
            await Future.delayed(const Duration(milliseconds: 10));

            String? town = await _getTownAtRadius(position, d, b);
            if (town != null && town.isNotEmpty && town != _homeTown) {
              lastFoundTown = town;
              if (d > maxDistInSector) maxDistInSector = d;
            }
          }
        }

        tempReach[sector.key] = maxDistInSector;

        if (lastFoundTown != null) {
          double beyond = _radiusKm - maxDistInSector;
          directionalFrontier[sector.key] = beyond > 2.0
              ? "$lastFoundTown (+${beyond.toInt()}km)"
              : lastFoundTown;
        } else {
          directionalFrontier[sector.key] = "Rural";
        }
      }

      if (mySessionId != _scanSessionId) return;

      List<String> summary = [];
      directionalFrontier.forEach((dir, info) {
        if (info != "Rural") summary.add("$dir: $info");
      });

      if (mounted) {
        setState(() {
          _sectorReach = tempReach;
          if (summary.isEmpty) {
            _contextText = "No major towns found nearby (Rural Area).";
          } else {
            _contextText = "Reach: ${summary.join(', ')}";
          }
          _isFetchingContext = false;
        });
      }
    } catch (e) {
      if (mySessionId == _scanSessionId && mounted) {
        setState(() {
          _contextText = "Could not verify coverage area.";
          _isFetchingContext = false;
        });
      }
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
            name.toLowerCase() != "unnamed road") {
          return name;
        }
      }
    } catch (_) {}
    return null;
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
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.sort), // <--- The Sort Icon you wanted
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Search Radius",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Show items within ${_radiusKm.toInt()} km of your location.",
                        style: TextStyle(color: Colors.grey[600], fontSize: 15),
                      ),
                    ),
                    const SizedBox(height: 30),

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
                        onChanged: (val) {
                          setState(() {
                            _radiusKm = val;
                            _contextText = "Radius changed. Tap to scan.";
                            _isFetchingContext = false;
                            _scanSessionId++; // Stop any current scan
                            // Reset graph visualization
                            _sectorReach = {
                              'North': 0,
                              'East': 0,
                              'South': 0,
                              'West': 0,
                            };
                          });
                        },
                      ),
                    ),

                    const SizedBox(height: 20),

                    ElevatedButton.icon(
                      onPressed: _isFetchingContext ? null : _checkCoverage,
                      icon: _isFetchingContext
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.radar),
                      label: Text(
                        _isFetchingContext ? "SCANNING..." : "CHECK COVERAGE",
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),

                    // --- NEW GRAPH WIDGET ---
                    SizedBox(
                      height: 220,
                      width: 220,
                      child: CustomPaint(
                        painter: _RadarChartPainter(
                          data: _sectorReach,
                          maxRadius: _radiusKm,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.my_location,
                                color: Colors.green[800],
                                size: 24,
                              ),
                              if (_isFetchingContext)
                                const Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Text(
                                    "Scanning...",
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
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
                      child: Text(
                        _contextText,
                        style: TextStyle(
                          color: Colors.blue[900],
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),

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
            ),
    );
  }
}

// --- PAINTER FOR THE GRAPH ---
class _RadarChartPainter extends CustomPainter {
  final Map<String, double> data;
  final double maxRadius;

  _RadarChartPainter({required this.data, required this.maxRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Paints
    final bgLinePaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final fillPaint = Paint()
      ..color = Colors.green.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.green[700]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // 1. Draw Background Circles (Targets)
    canvas.drawCircle(center, radius, bgLinePaint);
    canvas.drawCircle(center, radius * 0.66, bgLinePaint);
    canvas.drawCircle(center, radius * 0.33, bgLinePaint);

    // 2. Draw Axes
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      bgLinePaint,
    );
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      bgLinePaint,
    );

    // Labels
    TextPainter tp = TextPainter(textDirection: TextDirection.ltr);
    void drawLabel(String text, Offset offset) {
      tp.text = TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      tp.layout();
      tp.paint(
        canvas,
        Offset(offset.dx - tp.width / 2, offset.dy - tp.height / 2),
      );
    }

    drawLabel("N", Offset(center.dx, 10));
    drawLabel("S", Offset(center.dx, size.height - 10));
    drawLabel("E", Offset(size.width - 10, center.dy));
    drawLabel("W", Offset(10, center.dy));

    // 3. Draw Coverage Shape
    final path = Path();

    // North (Top, -90 deg)
    double rN = _normalize(data['North']!);
    path.moveTo(center.dx, center.dy - rN);

    // East (Right, 0 deg)
    double rE = _normalize(data['East']!);
    path.lineTo(center.dx + rE, center.dy);

    // South (Bottom, 90 deg)
    double rS = _normalize(data['South']!);
    path.lineTo(center.dx, center.dy + rS);

    // West (Left, 180 deg)
    double rW = _normalize(data['West']!);
    path.lineTo(center.dx - rW, center.dy);

    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, borderPaint);
  }

  double _normalize(double val) {
    if (val <= 0) return 0;
    // Map distance to visual radius.
    // Even small reach should show a little bit (min 10%).
    double ratio = val / maxRadius;
    if (ratio > 1.0) ratio = 1.0;
    // Scale to visual size
    return ratio *
        (maxRadius > 0 ? 1 : 0) *
        110.0; // 110 is half of widget size roughly
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
