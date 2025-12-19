import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class PriceTrendChart extends StatefulWidget {
  final String productName;

  const PriceTrendChart({super.key, required this.productName});

  @override
  State<PriceTrendChart> createState() => _PriceTrendChartState();
}

class _PriceTrendChartState extends State<PriceTrendChart> {
  bool _isLoading = true;
  List<FlSpot> _spots = [];
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
      // Convert the current product name to lowercase for the search
      String searchKey = widget.productName.trim().toLowerCase();

      final querySnapshot = await FirebaseFirestore.instance
          .collection('posts')
          // CHANGE THIS LINE: Query by 'search_key' instead of 'product_name'
          .where('search_key', isEqualTo: searchKey)
          .orderBy('timestamp', descending: false)
          .limit(20)
          .get();

      if (querySnapshot.docs.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      List<FlSpot> tempSpots = [];
      List<DateTime> tempDates = [];
      double minPrice = double.infinity;
      double maxPrice = double.negativeInfinity;

      // 2. Process Data
      for (var i = 0; i < querySnapshot.docs.length; i++) {
        final data = querySnapshot.docs[i].data();
        final double price = (data['price'] ?? 0).toDouble();
        final Timestamp? ts = data['timestamp'];

        if (ts == null) continue;

        if (price < minPrice) minPrice = price;
        if (price > maxPrice) maxPrice = price;

        // X-axis is just the index (0, 1, 2...) because dates vary wildly
        tempSpots.add(FlSpot(i.toDouble(), price));
        tempDates.add(ts.toDate());
      }

      // Add some buffer to the chart Y-axis
      if (minPrice == double.infinity) minPrice = 0;
      if (maxPrice == double.negativeInfinity) maxPrice = 100;

      if (mounted) {
        setState(() {
          _spots = tempSpots;
          _dates = tempDates;
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
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // --- UPDATED SECTION: Handle Single Item ---
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
              "Not enough data for price trends",
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "We need at least 2 price reports for '${widget.productName}' to show a graph.",
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
            children: [
              Icon(Icons.trending_up, color: Colors.green[800]),
              const SizedBox(width: 8),
              const Text(
                "Price Trend",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
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
                      interval: (_spots.length / 3)
                          .ceilToDouble(), // Show ~3 dates
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
