import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ai_consultant_sheet.dart';
import 'constants/palette.dart';

class ChurnResultsPage extends StatefulWidget {
  final Map<String, dynamic> predictionResult;
  final Map<String, dynamic> originalInputs;

  const ChurnResultsPage({
    super.key,
    required this.predictionResult,
    required this.originalInputs,
  });

  @override
  State<ChurnResultsPage> createState() => _ChurnResultsPageState();
}

class _ChurnResultsPageState extends State<ChurnResultsPage> {
  // Chat history is maintained here so if they go back from AI to results, it persists
  final List<Map<String, String>> _sessionChatHistory = [];

  Future<void> _initiateSaveProcess() async {
    String? customerName = await showDialog<String>(
      context: context,
      builder: (context) {
        String inputName = "";
        return AlertDialog(
          title: const Text("Export Report"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Enter customer name to generate the official report.",
              ),
              const SizedBox(height: 10),
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: "Customer Name",
                  hintText: "e.g. Kwasi Peter",
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => inputName = value,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Palette.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, inputName),
              child: const Text("Next"),
            ),
          ],
        );
      },
    );

    if (customerName != null && customerName.isNotEmpty) {
      _showExportOptions(customerName);
    }
  }

  void _showExportOptions(String customerName) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Export Options for '$customerName'",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.download, color: Palette.primary),
                title: const Text("Save to Device (Downloads)"),
                onTap: () {
                  Navigator.pop(context);
                  _saveToDevice(customerName);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Palette.secondary),
                title: const Text("Share Report"),
                onTap: () {
                  Navigator.pop(context);
                  _generateAndShareReport(customerName);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveToDevice(String customerName) async {
    try {
      var status = await Permission.storage.status;
      if (!status.isGranted) await Permission.storage.request();

      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory == null) return;
      final String safeName = customerName.replaceAll(' ', '_');
      final String filePath = '${directory.path}/${safeName}_Analysis.txt';
      final File file = File(filePath);
      await file.writeAsString(_buildReportContent(customerName));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ Saved to: $filePath"),
            backgroundColor: Palette.secondary,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error saving: $e"),
          backgroundColor: Palette.error,
        ),
      );
    }
  }

  Future<void> _generateAndShareReport(String customerName) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final String safeName = customerName.replaceAll(' ', '_');
      final String filePath =
          '${directory.path}/${safeName}_Analysis_Report.txt';
      final File file = File(filePath);
      await file.writeAsString(_buildReportContent(customerName));
      await Share.shareXFiles([
        XFile(filePath),
      ], text: 'Churn Analysis Report for $customerName');
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error sharing: $e")));
    }
  }

  String _buildReportContent(String customerName) {
    double prob = widget.predictionResult['probability'];
    String solution =
        widget.predictionResult['solution'] ?? "No advice generated.";
    List<dynamic> reasons = widget.predictionResult['reasons'] ?? [];
    Map<String, dynamic> inputs = widget.originalInputs;

    return '''
OFFICIAL CHURN INTELLIGENCE REPORT
-----------------------------------
CUSTOMER: $customerName
DATE: ${DateTime.now().toString().split('.')[0]}
-----------------------------------
PROFILE:
- Network: ${inputs['TelecomCompany']}
- Plan: ${inputs['PlanType']}
- Duration: ${inputs['DurationWithCompany']}
- Spend: ${inputs['MonthlyCharges']}

ANALYSIS:
Risk Probability: ${(prob * 100).toStringAsFixed(1)}%
Risk Factors: ${reasons.join(', ')}

AI RECOMMENDATION:
$solution

Generated by PriceSpy
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.background,
      appBar: AppBar(
        title: const Text("Analysis Results"),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Palette.primary, Palette.primaryAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt),
            onPressed: _initiateSaveProcess,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildSmartAnalysisResult(),
          ],
        ),
      ),
    );
  }

  Widget _buildSmartAnalysisResult() {
    double prob = widget.predictionResult['probability'];
    List<dynamic> rawReasons = widget.predictionResult['reasons'] ?? [];
    List<String> reasons = rawReasons.map((e) => e.toString()).toList();
    String solution =
        widget.predictionResult['solution'] ?? "Contact customer support.";

    String statusText;
    Color statusColor;

    if (prob < 0.25) {
      statusText = "SAFE (Loyal)";
      statusColor = Palette.secondary;
    } else if (prob < 0.50) {
      statusText = "POTENTIAL RISK";
      statusColor = Colors.blue;
    } else if (prob < 0.75) {
      statusText = "MODERATE RISK";
      statusColor = Colors.orange;
    } else {
      statusText = "CRITICAL RISK";
      statusColor = Palette.error;
    }

    return Column(
      children: [
        // 1. Gauge Chart 
        SizedBox(
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  startDegreeOffset: 180,
                  sectionsSpace: 0,
                  centerSpaceRadius: 60,
                  sections: [
                    PieChartSectionData(
                      color: statusColor,
                      value: prob * 100,
                      radius: 30,
                      showTitle: false,
                    ),
                    PieChartSectionData(
                      color: Colors.grey.shade200,
                      value: (1 - prob) * 100,
                      radius: 30,
                      showTitle: false,
                    ),
                    PieChartSectionData(
                      color: Colors.transparent,
                      value: 100,
                      radius: 30,
                      showTitle: false,
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 80,
                child: Column(
                  children: [
                    Text(
                      "${(prob * 100).toStringAsFixed(1)}%",
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 2. Risk Factors
        if (reasons.isNotEmpty) ...[
          const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(bottom: 10.0),
              child: Text(
                "⚠️ Key Risk Factors",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: reasons
                  .map(
                    (r) => ListTile(
                      visualDensity: VisualDensity.compact,
                      leading: CircleAvatar(
                        radius: 10,
                        backgroundColor: Palette.error.withOpacity(0.1),
                        child: Icon(
                          Icons.close,
                          size: 12,
                          color: Palette.error,
                        ),
                      ),
                      title: Text(r, style: const TextStyle(fontSize: 14)),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // 3. AI Advice Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Palette.secondary.withOpacity(0.1), Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Palette.secondary.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    color: Palette.secondary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    "AI Strategy",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Palette.textDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                solution,
                style: const TextStyle(height: 1.5, color: Colors.black87),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Chat Button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AiConsultantPage(
                    predictionResult: widget.predictionResult,
                    originalInputs: widget.originalInputs,
                    sessionHistory: _sessionChatHistory,
                  ),
                ),
              );
            },
            icon: const Icon(
              Icons.chat_bubble_outline,
              color: Palette.primary,
            ),
            label: const Text(
              "CONSULT AI AGENT",
              style: TextStyle(
                color: Palette.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: Palette.primary, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}