import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'sidebar_drawer.dart';
import 'services/churn_service.dart';
import 'ai_consultant_sheet.dart';

class ChurnPredictionPage extends StatefulWidget {
  const ChurnPredictionPage({super.key});

  @override
  State<ChurnPredictionPage> createState() => _ChurnPredictionPageState();
}

class _ChurnPredictionPageState extends State<ChurnPredictionPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ChurnService _service = ChurnService();

  // Form State
  double _monthlyCharges = 150.0;
  double _tenure = 12.0;
  String _contract = 'Month-to-month';
  String _internetService = 'DSL';
  String _paymentMethod = 'Electronic check';
  bool _paperlessBilling = true;
  bool _isLoading = false;

  // Result State
  Map<String, dynamic>? _result;
  List<Map<String, String>> _sessionChatHistory = [];

  final List<String> _contracts = ['Month-to-month', 'One year', 'Two year'];
  final List<String> _internetTypes = ['DSL', 'Fiber optic', 'No'];
  final List<String> _paymentMethods = [
    'Electronic check',
    'Mailed check',
    'Bank transfer (automatic)',
    'Credit card (automatic)',
  ];

  @override
  void initState() {
    super.initState();
    _service.loadModel();
  }

  void _clearPrediction() {
    setState(() {
      _result = null;
      _sessionChatHistory.clear();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Output cleared")));
  }

  Future<void> _analyze() async {
    setState(() => _isLoading = true);
    _sessionChatHistory.clear();

    // Simulate thinking time for better UX
    await Future.delayed(const Duration(milliseconds: 800));

    double estimatedTotal = _monthlyCharges * _tenure;

    final inputs = {
      'Tenure': _tenure,
      'MonthlyCharges': _monthlyCharges,
      'TotalCharges': estimatedTotal,
      'Contract': _contract,
      'InternetService': _internetService,
      'PaymentMethod': _paymentMethod,
      'PaperlessBilling': _paperlessBilling ? "Yes" : "No",
      'SeniorCitizen': 0,
      'Partner': "No",
      'Dependents': "No",
      'PhoneService': "Yes",
      'MultipleLines': "No",
      'OnlineSecurity': "No",
      'OnlineBackup': "No",
      'DeviceProtection': "No",
      'TechSupport': "No",
      'StreamingTV': "No",
      'StreamingMovies': "No",
    };

    final prediction = await _service.predict(inputs);

    setState(() {
      _result = prediction;
      _isLoading = false;
    });
  }

  // ... (Keep existing _initiateSaveProcess, _showExportOptions, _saveToDevice, _generateAndShareReport, _buildReportContent as they are) ...
  // For brevity in this response, assume the Export functions from your original file are here.
  // Make sure to include them when pasting back into your project!
  Future<void> _initiateSaveProcess() async {
    // ... [Use original code for export logic] ...
    if (_result == null) return;

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
                backgroundColor: Colors.green[800],
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
                leading: const Icon(Icons.download, color: Colors.blue),
                title: const Text("Save to Device (Downloads)"),
                onTap: () {
                  Navigator.pop(context);
                  _saveToDevice(customerName);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.green),
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
        if (!await directory.exists())
          directory = await getExternalStorageDirectory();
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory == null) return;
      final String safeName = customerName.replaceAll(' ', '_');
      final String filePath = '${directory.path}/${safeName}_Analysis.txt';
      final File file = File(filePath);
      await file.writeAsString(_buildReportContent(customerName));
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ Saved to: $filePath"),
            backgroundColor: Colors.green,
          ),
        );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error saving: $e"),
          backgroundColor: Colors.red,
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
    double prob = _result!['probability'];
    String solution = _result!['solution'] ?? "No advice generated.";
    return '''
OFFICIAL AI RETENTION REPORT
CUSTOMER: $customerName
Risk: ${(prob * 100).toStringAsFixed(1)}%
Solution: $solution
Generated by PriseSpy
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.grey[50], // Lighter cleaner background
      drawer: const SidebarDrawer(),
      appBar: AppBar(
        title: const Text("Churn AI"),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green[900]!, Colors.teal[700]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.sort),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          if (_result != null) ...[
            IconButton(
              icon: const Icon(Icons.save_alt),
              onPressed: _initiateSaveProcess,
            ),
            IconButton(
              icon: const Icon(Icons.cleaning_services_outlined),
              onPressed: _clearPrediction,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildPolishedInputSection(),
            const SizedBox(height: 25),

            // Modern Action Button
            Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _analyze,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.analytics_outlined),
                label: Text(
                  _isLoading ? "ANALYZING..." : "RUN DIAGNOSTICS",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[800],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
              ),
            ),

            const SizedBox(height: 30),
            if (_result != null) _buildSmartAnalysisResult(),
          ],
        ),
      ),
    );
  }

  Widget _buildPolishedInputSection() {
    return Column(
      children: [
        // Summary Card at the top
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Estimated Total Value",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Text(
                    "GH₵ ${(_monthlyCharges * (_tenure == 0 ? 1 : _tenure)).toStringAsFixed(0)}",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "${_tenure.toInt()} Months",
                  style: TextStyle(
                    color: Colors.blue[800],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Group 1: Service Details
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.layers, color: Colors.teal),
                    SizedBox(width: 8),
                    Text(
                      "Service Profile",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _buildSliderRow(
                  "Tenure (Months)",
                  _tenure,
                  0,
                  72,
                  (v) => setState(() => _tenure = v),
                ),
                const SizedBox(height: 12),
                _buildDropdown(
                  "Contract Type",
                  _contract,
                  _contracts,
                  (v) => setState(() => _contract = v!),
                ),
                const SizedBox(height: 12),
                _buildDropdown(
                  "Internet Service",
                  _internetService,
                  _internetTypes,
                  (v) => setState(() => _internetService = v!),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Group 2: Financials
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.credit_card, color: Colors.teal),
                    SizedBox(width: 8),
                    Text(
                      "Billing & Payments",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _buildSliderRow(
                  "Monthly Charges (GH₵)",
                  _monthlyCharges,
                  50,
                  2000,
                  (v) => setState(() => _monthlyCharges = v),
                ),
                const SizedBox(height: 12),
                _buildDropdown(
                  "Payment Method",
                  _paymentMethod,
                  _paymentMethods,
                  (v) => setState(() => _paymentMethod = v!),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    "Paperless Billing",
                    style: TextStyle(fontSize: 14),
                  ),
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _paperlessBilling
                          ? Colors.green[50]
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.eco,
                      color: _paperlessBilling ? Colors.green : Colors.grey,
                    ),
                  ),
                  value: _paperlessBilling,
                  activeColor: Colors.green,
                  onChanged: (v) => setState(() => _paperlessBilling = v),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 🔴 UPDATED: NEW CHART & LOGIC FIX
  Widget _buildSmartAnalysisResult() {
    bool isChurn = _result!['willChurn'];
    double prob = _result!['probability'];
    List<dynamic> rawReasons = _result!['reasons'] ?? [];
    // Ensure reasons are strings
    List<String> reasons = rawReasons.map((e) => e.toString()).toList();

    String solution = _result!['solution'] ?? "Contact customer support.";
    double rate = _result!['rateUsed'] ?? 0.0;

    String statusText;
    Color statusColor;

    if (prob < 0.25) {
      statusText = "SAFE (Loyal)";
      statusColor = Colors.green;
    } else if (prob < 0.50) {
      statusText = "POTENTIAL RISK";
      statusColor = Colors.blue;
    } else if (prob < 0.75) {
      statusText = "MODERATE RISK";
      statusColor = Colors.orange;
    } else {
      statusText = "CRITICAL RISK";
      statusColor = Colors.red;
    }

    return Column(
      children: [
        // 1. New Gauge Chart Logic (Semi-Circle)
        SizedBox(
          height: 180, // Reduced height for semi-circle effect
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  startDegreeOffset: 180,
                  sectionsSpace: 0,
                  centerSpaceRadius: 60,
                  sections: [
                    // The Risk Part
                    PieChartSectionData(
                      color: statusColor,
                      value: prob * 100,
                      radius: 30,
                      showTitle: false,
                    ),
                    // The "Safe" Part (Remaining)
                    PieChartSectionData(
                      color: Colors.grey.shade200,
                      value: (1 - prob) * 100,
                      radius: 30,
                      showTitle: false,
                    ),
                    // Invisible section to hide the bottom half
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
                top: 80, // Adjust vertically
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

        // 2. The Logic Fix: Only show if reasons exist
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
                        backgroundColor: Colors.red[50],
                        child: Icon(
                          Icons.close,
                          size: 12,
                          color: Colors.red[800],
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
              colors: [Colors.blue[50]!, Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.blue[100]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, color: Colors.blue[800], size: 20),
                  const SizedBox(width: 8),
                  Text(
                    "AI Strategy",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[900],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                solution,
                style: const TextStyle(height: 1.5, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              Text(
                "Ex. Rate: 1 USD = ${rate.toStringAsFixed(2)} GHS",
                style: const TextStyle(fontSize: 11, color: Colors.grey),
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
              final currentInputs = {
                'Tenure': _tenure,
                'MonthlyCharges': _monthlyCharges,
                'Contract': _contract,
                'PaymentMethod': _paymentMethod,
              };
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AiConsultantPage(
                    predictionResult: _result!,
                    originalInputs: currentInputs,
                    sessionHistory: _sessionChatHistory,
                  ),
                ),
              );
            },
            icon: Icon(Icons.chat_bubble_outline, color: Colors.indigo[800]),
            label: Text(
              "CONSULT AI AGENT",
              style: TextStyle(
                color: Colors.indigo[800],
                fontWeight: FontWeight.bold,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: Colors.indigo[800]!, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSliderRow(
    String label,
    double value,
    double min,
    double max,
    Function(double) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
            Text(
              value.toStringAsFixed(0),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.teal[700],
            inactiveTrackColor: Colors.teal[100],
            thumbColor: Colors.teal[700],
            overlayColor: Colors.teal.withOpacity(0.2),
            trackHeight: 4.0,
          ),
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }

  Widget _buildDropdown(
    String label,
    String value,
    List<String> items,
    Function(String?) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey(value),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            filled: true,
            fillColor: Colors.grey[50],
          ),
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(e, style: const TextStyle(fontSize: 14)),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
