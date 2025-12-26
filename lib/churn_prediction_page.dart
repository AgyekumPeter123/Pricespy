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

  // Store chat history here so it persists when closing the chat sheet
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

    // Clear chat history because we are analyzing a NEW customer/scenario
    _sessionChatHistory.clear();

    await Future.delayed(const Duration(milliseconds: 600));

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

  // --- SAVE & SHARE LOGIC ---
  Future<void> _initiateSaveProcess() async {
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
      if (!status.isGranted) {
        await Permission.storage.request();
      }

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
      final String fileName = '${safeName}_Analysis.txt';
      final String filePath = '${directory.path}/$fileName';
      final File file = File(filePath);

      String content = _buildReportContent(customerName);
      await file.writeAsString(content);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ Saved to: $filePath"),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
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
      final String fileName = '${safeName}_Analysis_Report.txt';
      final String filePath = '${directory.path}/$fileName';
      final File file = File(filePath);

      String content = _buildReportContent(customerName);
      await file.writeAsString(content);

      await Share.shareXFiles([
        XFile(filePath),
      ], text: 'Churn Analysis Report for $customerName');
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error sharing: $e")));
    }
  }

  // 🔴 UPDATED REPORT GENERATION TO INCLUDE SPECIFIC STATUS
  String _buildReportContent(String customerName) {
    double prob = _result!['probability'];
    String solution = _result!['solution'] ?? "No advice generated.";
    double rate = _result!['rateUsed'] ?? 0.0;

    String statusText;
    if (prob < 0.25) {
      statusText = "SAFE (Loyal Customer)";
    } else if (prob < 0.50) {
      statusText = "POTENTIAL RISK (Monitor Closely)";
    } else if (prob < 0.75) {
      statusText = "MODERATE RISK (Action Needed)";
    } else {
      statusText = "CRITICAL RISK (Highly Likely to Leave)";
    }

    return '''
OFFICIAL AI RETENTION REPORT

CUSTOMER NAME: $customerName
DATE: ${DateTime.now().toString().split('.')[0]}

Detected Status: $statusText
Churn Probability: ${(prob * 100).toStringAsFixed(1)}%

CUSTOMER PROFILE:
- Tenure: ${_tenure.toInt()} months
- Monthly Spend: ${_monthlyCharges.toStringAsFixed(2)} GHS
- Contract: $_contract
- Payment: $_paymentMethod

AI CONSULTANT RECOMMENDATION

$solution

(Exchange Rate Used: 1 USD = ${rate.toStringAsFixed(2)} GHS)

Generated by PriseSpy (AI Consultant Agent)
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.grey[100],
      drawer: const SidebarDrawer(),
      appBar: AppBar(
        title: const Text("Churn AI"),
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          if (_result != null) ...[
            IconButton(
              tooltip: 'Export Report',
              icon: const Icon(Icons.save_alt),
              onPressed: _initiateSaveProcess,
            ),
            IconButton(
              tooltip: 'Clear Output',
              icon: const Icon(Icons.cleaning_services_outlined),
              onPressed: _clearPrediction,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildInputSection(),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _analyze,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : const Icon(Icons.analytics_outlined),
                label: Text(_isLoading ? "CALCULATING..." : "RUN PREDICTION"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[800],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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

  Widget _buildInputSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Customer Profile (Ghana)",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            _buildSliderRow(
              "Tenure (Months)",
              _tenure,
              0,
              72,
              (v) => setState(() => _tenure = v),
            ),
            _buildSliderRow(
              "Monthly Charges (GH₵)",
              _monthlyCharges,
              50,
              2000,
              (v) => setState(() => _monthlyCharges = v),
            ),
            const SizedBox(height: 15),
            _buildDropdown(
              "Contract Type",
              _contract,
              _contracts,
              (v) => setState(() => _contract = v!),
            ),
            const SizedBox(height: 10),
            _buildDropdown(
              "Internet Service",
              _internetService,
              _internetTypes,
              (v) => setState(() => _internetService = v!),
            ),
            const SizedBox(height: 10),
            _buildDropdown(
              "Payment Method",
              _paymentMethod,
              _paymentMethods,
              (v) => setState(() => _paymentMethod = v!),
            ),
            const SizedBox(height: 15),
            InkWell(
              onTap: () =>
                  setState(() => _paperlessBilling = !_paperlessBilling),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _paperlessBilling ? Colors.green[50] : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _paperlessBilling
                        ? Colors.green.shade800
                        : Colors.grey.shade300,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _paperlessBilling ? Icons.eco : Icons.receipt_outlined,
                      color: _paperlessBilling
                          ? Colors.green[800]
                          : Colors.grey[600],
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "Paperless Billing",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: _paperlessBilling
                            ? Colors.green[900]
                            : Colors.grey[700],
                      ),
                    ),
                    const Spacer(),
                    Switch(
                      value: _paperlessBilling,
                      onChanged: (v) => setState(() => _paperlessBilling = v),
                      activeColor: Colors.green[800],
                      activeTrackColor: Colors.green[200],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🔴 UPDATED: SMART ANALYSIS WITH 4 TIERS
  Widget _buildSmartAnalysisResult() {
    bool isChurn = _result!['willChurn'];
    double prob = _result!['probability'];
    List<String> reasons = _result!['reasons'] ?? [];
    String solution = _result!['solution'] ?? "Contact customer support.";
    double rate = _result!['rateUsed'] ?? 0.0;

    // --- NEW STATUS LOGIC ---
    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (prob < 0.25) {
      statusText = "SAFE (Loyal)";
      statusColor = Colors.green[800]!;
      statusIcon = Icons.verified_user;
    } else if (prob < 0.50) {
      statusText = "POTENTIAL RISK (Monitor)";
      statusColor = Colors.blue[600]!;
      statusIcon = Icons.info_outline;
    } else if (prob < 0.75) {
      statusText = "MODERATE RISK (Action)";
      statusColor = Colors.orange[800]!;
      statusIcon = Icons.warning_amber_rounded;
    } else {
      statusText = "CRITICAL RISK (High)";
      statusColor = Colors.red[700]!;
      statusIcon = Icons.dangerous;
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: statusColor.withOpacity(0.5)),
          ),
          child: Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 40),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      "Churn Probability: ${(prob * 100).toStringAsFixed(1)}%",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "Ex. Rate Used: 1 USD = ${rate.toStringAsFixed(2)} GHS",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              sections: [
                PieChartSectionData(
                  color: statusColor, // Matches the status color
                  value: prob * 100,
                  radius: 50,
                  title: '${(prob * 100).toInt()}%',
                  titleStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                PieChartSectionData(
                  color: Colors.grey[300],
                  value: (1 - prob) * 100,
                  radius: 40,
                  title: '',
                ),
              ],
              centerSpaceRadius: 40,
              sectionsSpace: 2,
            ),
          ),
        ),
        if (prob > 0.25) ...[
          const SizedBox(height: 20),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Key Risk Factors:",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          ...reasons.map(
            (r) => ListTile(
              leading: Icon(Icons.arrow_right, color: statusColor),
              title: Text(r),
              dense: true,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "AI Consultant Advice",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 5),
                Text(solution),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
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
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text("CHAT WITH AI CONSULTANT"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo[800],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
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
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(
              value.toStringAsFixed(0),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green[800],
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          activeColor: Colors.green[800],
          thumbColor: Colors.green[800],
          onChanged: onChanged,
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
    return DropdownButtonFormField<String>(
      key: ValueKey(value),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: items
          .map(
            (e) => DropdownMenuItem(
              value: e,
              child: Text(e, overflow: TextOverflow.ellipsis, maxLines: 1),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}
