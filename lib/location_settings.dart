import 'dart:async';
import 'dart:io';
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
  // --- STATE VARIABLES ---
  double _radiusKm = 20.0;

  // Location State
  Position? _currentPosition;
  String _locationStatus = "Waiting for update...";
  bool _isLocating = false; // Specific loader for GPS
  String _homeTown = "Unknown Area";

  // Scanner State
  bool _isScanning = false; // Specific loader for Radar
  int _scanSessionId = 0;
  String _radarDescription = "Scan to see detailed coverage report.";

  // Graph Data
  Map<String, double> _sectorReach = {
    'North': 0,
    'East': 0,
    'South': 0,
    'West': 0,
  };

  @override
  void initState() {
    super.initState();
    // 1. Load settings instantly
    _loadRadius();

    // 2. Trigger location fetch in background (doesn't block UI)
    // We delay slightly to let the build finish first for smoothness
    Future.delayed(const Duration(milliseconds: 500), () {
      _updateLocation();
    });
  }

  Future<void> _loadRadius() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _radiusKm = prefs.getDouble('search_radius') ?? 20.0;
      });
    }
  }

  // 🟢 ACTION: Get GPS & Internet & Town Name
  Future<void> _updateLocation() async {
    setState(() {
      _isLocating = true;
      _locationStatus = "Acquiring GPS...";
    });

    try {
      // 1. Check Internet
      try {
        final result = await InternetAddress.lookup('google.com');
        if (result.isEmpty || result[0].rawAddress.isEmpty) throw Exception();
      } catch (_) {
        setState(() {
          _locationStatus = "No Internet Connection";
          _isLocating = false;
        });
        _showSnack("Internet required to identify towns.", isError: true);
        return;
      }

      // 2. Check Permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _locationStatus = "Permission Denied";
            _isLocating = false;
          });
          return;
        }
      }

      // 3. Get Position
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // 4. Get Town Name
      String detectedTown = "Unknown Area";
      try {
        List<Placemark> marks = await placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        );
        if (marks.isNotEmpty) {
          detectedTown =
              marks.first.locality ??
              marks.first.subLocality ??
              marks.first.administrativeArea ??
              "Rural Area";
        }
      } catch (e) {
        debugPrint("Geocoding failed: $e");
      }

      if (mounted) {
        setState(() {
          _currentPosition = pos;
          _homeTown = detectedTown;
          _locationStatus = "Active";
          _isLocating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationStatus = "GPS Error";
          _isLocating = false;
        });
        _showSnack("Could not get location: $e", isError: true);
      }
    }
  }

  // 🟢 ACTION: Radar Scan Logic
  Future<void> _checkCoverage() async {
    if (_currentPosition == null) return;

    final int mySessionId = ++_scanSessionId;

    setState(() {
      _isScanning = true;
      _radarDescription = "Scanning surrounding areas...";
      _sectorReach = {'North': 0, 'East': 0, 'South': 0, 'West': 0};
    });

    try {
      Position position = _currentPosition!;
      List<double> bearings = List.generate(36, (index) => index * 10.0);

      // Store the furthest town name found in each direction
      Map<String, String> distinctTowns = {};

      Map<String, double> tempReach = {
        'North': 0,
        'East': 0,
        'South': 0,
        'West': 0,
      };

      List<double> steps = [];
      for (double i = 2.0; i <= _radiusKm; i += 2.0) steps.add(i);
      if (steps.isEmpty) steps.add(_radiusKm);

      Map<String, List<double>> cardinalSectors = {
        'North': bearings.where((b) => b >= 315 || b <= 45).toList(),
        'East': bearings.where((b) => b > 45 && b <= 135).toList(),
        'South': bearings.where((b) => b > 135 && b <= 225).toList(),
        'West': bearings.where((b) => b > 225 && b < 315).toList(),
      };

      for (var sector in cardinalSectors.entries) {
        String? furthestTown;
        double maxDist = 0.0;

        for (double b in sector.value) {
          if (mySessionId != _scanSessionId) return;

          for (double d in steps) {
            await Future.delayed(const Duration(milliseconds: 5)); // UI Breath

            String? town = await _getTownAtRadius(position, d, b);

            if (town != null && town.isNotEmpty && town != _homeTown) {
              furthestTown = town;
              if (d > maxDist) maxDist = d;
            }
          }
        }

        tempReach[sector.key] = maxDist;
        if (furthestTown != null) {
          distinctTowns[sector.key] = furthestTown;
        }
      }

      if (mySessionId != _scanSessionId) return;

      // 🟢 Generate Descriptive Text
      StringBuffer sb = StringBuffer();
      if (distinctTowns.isEmpty) {
        sb.write(
          "No major towns found nearby. You are likely in a rural area or deep within $_homeTown.",
        );
      } else {
        sb.write("Coverage Analysis:\n");
        distinctTowns.forEach((dir, town) {
          double dist = tempReach[dir]!;
          sb.write("• $dir extends ${dist.toInt()}km to $town.\n");
        });
      }

      if (mounted) {
        setState(() {
          _sectorReach = tempReach;
          _radarDescription = sb.toString();
          _isScanning = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isScanning = false);
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
        return marks.first.locality ??
            marks.first.subLocality ??
            marks.first.name;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _applySettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('search_radius', _radiusKm);

    // Optional: Save last known town to keep state consistent across restarts
    if (_homeTown != "Unknown Area") {
      await prefs.setString('last_known_town', _homeTown);
    }

    if (mounted) {
      _showSnack("✅ Settings saved successfully!");
      // 🟢 REMOVED: Navigator.pop(context); -> Stay on page
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red[800] : Colors.green[800],
      ),
    );
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
            icon: const Icon(Icons.sort),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // --- 1. SETTINGS SECTION ---
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Search Radius",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
              const SizedBox(height: 20),
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
                      _radarDescription = "Radius changed. Update Scan.";
                      // Reset graph visual
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

              const Divider(height: 40),

              // --- 2. LOCATION STATUS SECTION ---
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.place,
                      color: _currentPosition == null
                          ? Colors.grey
                          : Colors.red,
                      size: 30,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _homeTown,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            _locationStatus,
                            style: TextStyle(
                              color: _isLocating
                                  ? Colors.orange
                                  : Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _isLocating ? null : _updateLocation,
                      icon: _isLocating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, color: Colors.blue),
                      tooltip: "Update Location",
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // --- 3. SCANNER BUTTON ---
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                      (_isScanning || _isLocating || _currentPosition == null)
                      ? null
                      : _checkCoverage,
                  icon: _isScanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.radar),
                  label: Text(_isScanning ? "SCANNING..." : "CHECK COVERAGE"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // --- 4. VISUALIZATION & DESCRIPTION ---
              SizedBox(
                height: 220,
                width: 220,
                child: CustomPaint(
                  painter: _RadarChartPainter(
                    data: _sectorReach,
                    maxRadius: _radiusKm,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.my_location,
                      color: Colors.green[800],
                      size: 24,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Descriptive Text Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue[100]!),
                ),
                child: Text(
                  _radarDescription,
                  style: TextStyle(
                    color: Colors.blue[900],
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // --- 5. SAVE BUTTON ---
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

// --- PAINTER REMAINS SAME ---
class _RadarChartPainter extends CustomPainter {
  final Map<String, double> data;
  final double maxRadius;

  _RadarChartPainter({required this.data, required this.maxRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

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

    canvas.drawCircle(center, radius, bgLinePaint);
    canvas.drawCircle(center, radius * 0.66, bgLinePaint);
    canvas.drawCircle(center, radius * 0.33, bgLinePaint);

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

    final path = Path();
    path.moveTo(center.dx, center.dy - _normalize(data['North']!));
    path.lineTo(center.dx + _normalize(data['East']!), center.dy);
    path.lineTo(center.dx, center.dy + _normalize(data['South']!));
    path.lineTo(center.dx - _normalize(data['West']!), center.dy);
    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, borderPaint);
  }

  double _normalize(double val) {
    if (val <= 0) return 0;
    double ratio = val / maxRadius;
    if (ratio > 1.0) ratio = 1.0;
    return ratio * (maxRadius > 0 ? 1 : 0) * 110.0;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
