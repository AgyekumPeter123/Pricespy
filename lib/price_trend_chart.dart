import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart'; // 🟢 For distance calc
import 'product_details_page.dart'; // 🟢 For navigation

class PriceTrendChart extends StatefulWidget {
  final String productName;
  final Position? userPosition; // 🟢 Receive location

  const PriceTrendChart({
    super.key,
    required this.productName,
    this.userPosition,
  });

  @override
  State<PriceTrendChart> createState() => _PriceTrendChartState();
}

class _PriceTrendChartState extends State<PriceTrendChart> {
  bool _isLoading = true;
  List<FlSpot> _spots = [];

  // 🟢 We need to store the actual document data for each dot to enable navigation
  List<Map<String, dynamic>> _chartData = [];

  double _minY = 0;
  double _maxY = 100;
  List<DateTime> _dates = [];

  @override
  void initState() {
    super.initState();
    _fetchPriceHistory();
  }

  Future<void> _fetchPriceHistory() async {
    try {
      String searchKey = widget.productName.trim().toLowerCase();

      // 🟢 INCREASE LIMIT: Fetch more (50) to ensure we have enough after filtering
      final querySnapshot = await FirebaseFirestore.instance
          .collection('posts')
          .where('search_key', isEqualTo: searchKey)
          .orderBy('timestamp', descending: false)
          .limit(50)
          .get();

      if (querySnapshot.docs.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      List<FlSpot> tempSpots = [];
      List<DateTime> tempDates = [];
      List<Map<String, dynamic>> tempChartData = [];
      double minPrice = double.infinity;
      double maxPrice = double.negativeInfinity;

      int index = 0;

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final double price = (data['price'] ?? 0).toDouble();
        final Timestamp? ts = data['timestamp'];

        if (ts == null) continue;

        // 🟢 LOCATION FILTER LOGIC
        if (widget.userPosition != null) {
          double postLat = (data['latitude'] ?? 0).toDouble();
          double postLng = (data['longitude'] ?? 0).toDouble();

          if (postLat != 0 && postLng != 0) {
            double dist = Geolocator.distanceBetween(
              widget.userPosition!.latitude,
              widget.userPosition!.longitude,
              postLat,
              postLng,
            );

            // Filter out if > 25km (giving slightly more range than main feed for context)
            if (dist > 25000) continue;
          }
        }

        if (price < minPrice) minPrice = price;
        if (price > maxPrice) maxPrice = price;

        tempSpots.add(FlSpot(index.toDouble(), price));
        tempDates.add(ts.toDate());

        // Save full doc data so we can navigate when clicked
        Map<String, dynamic> fullData = Map.from(data);
        fullData['docId'] = doc.id; // ensure ID is saved
        tempChartData.add(fullData);

        index++;
      }

      if (minPrice == double.infinity) minPrice = 0;
      if (maxPrice == double.negativeInfinity) maxPrice = 100;

      if (mounted) {
        setState(() {
          _spots = tempSpots;
          _dates = tempDates;
          _chartData = tempChartData;
          _minY = (minPrice * 0.8).floorToDouble();
          _maxY = (maxPrice * 1.2).ceilToDouble();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching trends: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_spots.length < 2) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 20),
        padding: const EdgeInsets.all(16),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          children: [
            Icon(Icons.trending_flat, color: Colors.grey[400], size: 40),
            const SizedBox(height: 10),
            Text(
              "Not enough local data",
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "We need at least 2 reports nearby for '${widget.productName}' to show a graph.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.trending_up, color: Colors.green[800]),
                  const SizedBox(width: 8),
                  const Text(
                    "Price Trend (Nearby)",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              // Hint for user
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  "Tap dot to view",
                  style: TextStyle(fontSize: 10, color: Colors.green),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                // 🟢 ENABLE TOUCH INTERACTION
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (touchedSpot) => Colors.blueGrey,
                    getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                      return touchedBarSpots.map((barSpot) {
                        final flSpot = barSpot;
                        return LineTooltipItem(
                          '₵${flSpot.y.toInt()} \n Tap to view',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList();
                    },
                  ),
                  touchCallback:
                      (FlTouchEvent event, LineTouchResponse? response) {
                        // 🟢 DETECT TAP UP (CLICK)
                        if (event is FlTapUpEvent &&
                            response != null &&
                            response.lineBarSpots != null) {
                          if (response.lineBarSpots!.isNotEmpty) {
                            final spotIndex =
                                response.lineBarSpots!.first.spotIndex;

                            // Get the data for this specific point
                            if (spotIndex < _chartData.length) {
                              final docData = _chartData[spotIndex];
                              final docId =
                                  docData['docId']; // Retrieved explicitly

                              // Navigate to that specific product
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ProductDetailsPage(
                                    data: docData,
                                    documentId: docId,
                                    userPosition:
                                        widget.userPosition, // Keep passing loc
                                  ),
                                ),
                              );
                            }
                          }
                        }
                      },
                ),
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          "₵${value.toInt()}",
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: (_spots.length / 3).ceilToDouble(),
                      getTitlesWidget: (value, meta) {
                        int index = value.toInt();
                        if (index >= 0 && index < _dates.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              DateFormat('MM/dd').format(_dates[index]),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: _spots.length.toDouble() - 1,
                minY: _minY,
                maxY: _maxY,
                lineBarsData: [
                  LineChartBarData(
                    spots: _spots,
                    isCurved: true,
                    color: Colors.green[800],
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.green.withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
