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

  // 🇬🇭 GHANA DATASET FORM STATE
  // Defaults set to common values to ensure UI looks populated
  String _telecomCompany = 'MTN';
  String _ageGroup = '25-34';
  String _gender = 'Male';
  String _education = 'Undergraduate';
  String _employment = 'Employed full-time';
  String _duration = '1-2 years';
  String _monthlyCharges = 'GHS 51-100';
  String _planType = 'Prepaid';
  String _reasonForChoosing = 'Coverage';

  bool _isLoading = false;

  // Result State
  Map<String, dynamic>? _result;
  List<Map<String, String>> _sessionChatHistory = [];

  // 📝 DROPDOWN OPTIONS (Must match Python training data exactly)
  final List<String> _companies = ['MTN', 'Telecel', 'Glo', 'AirtelTigo'];
  final List<String> _ageGroups = [
    '18-24',
    '25-34',
    '35-44',
    '45-54',
    '55-64',
    '65+',
  ];
  final List<String> _genders = [
    'Male',
    'Female',
    'Prefer not to say',
    'Transgender',
  ];
  final List<String> _educations = [
    'No Education',
    'Primary School',
    'High school graduate',
    'Undergraduate',
    'Postgraduate',
    'Prefer not to say',
  ];
  final List<String> _employments = [
    'Unemployed',
    'Employed part-time',
    'Employed full-time',
    'Self-employed',
    'Retired',
    'Student',
  ];
  final List<String> _durations = [
    'Less than 6 months',
    '6-12 months',
    '1-2 years',
    '3-4 years',
    '5 or more years',
  ];
  final List<String> _chargeRanges = [
    'Less than GHS 20',
    'GHS 20-50',
    'GHS 51-100',
    'GHS 101-200',
    'GHS 201-300',
    'GHS 301-400',
    'More than GHS 400',
  ];
  final List<String> _plans = ['Prepaid', 'Postpaid', 'Both'];
  final List<String> _reasons = [
    'Coverage',
    'Pricing',
    'Customer Service',
    'Prefer not to say',
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

    // Construct inputs matching the exact keys expected by ChurnService
    final inputs = {
      'TelecomCompany': _telecomCompany,
      'AgeGroup': _ageGroup,
      'Gender': _gender,
      'Education': _education,
      'EmploymentStatus': _employment,
      'DurationWithCompany': _duration,
      'MonthlyCharges': _monthlyCharges,
      'PlanType': _planType,
      'ReasonForChoosing': _reasonForChoosing,
    };

    final prediction = await _service.predict(inputs);

    setState(() {
      _result = prediction;
      _isLoading = false;
    });
  }

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
                leading: Icon(Icons.download, color: Colors.green[700]),
                title: const Text("Save to Device (Downloads)"),
                onTap: () {
                  Navigator.pop(context);
                  _saveToDevice(customerName);
                },
              ),
              ListTile(
                leading: Icon(Icons.share, color: Colors.green[800]),
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
            backgroundColor: Colors.green,
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
    List<dynamic> reasons = _result!['reasons'] ?? [];

    return '''
OFFICIAL CHURN INTELLIGENCE REPORT
-----------------------------------
CUSTOMER: $customerName
DATE: ${DateTime.now().toString().split('.')[0]}
-----------------------------------
PROFILE:
- Network: $_telecomCompany
- Plan: $_planType
- Duration: $_duration
- Spend: $_monthlyCharges

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
      key: _scaffoldKey,
      backgroundColor: Colors.grey[50],
      drawer: const SidebarDrawer(),
      appBar: AppBar(
        title: const Text("Churn Intelligence"),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green[900]!, Colors.green[700]!],
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
        // Summary Card at the top (Updated for Ghana Context)
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
                    "Network Provider",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Text(
                    _telecomCompany,
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
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _planType,
                  style: TextStyle(
                    color: Colors.green[800],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Group 1: Service Profile
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
                Row(
                  children: [
                    Icon(Icons.cell_tower, color: Colors.green[400]),
                    const SizedBox(width: 8),
                    const Text(
                      "Service Profile",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _buildDropdown(
                  "Telecom Company",
                  _telecomCompany,
                  _companies,
                  (v) => setState(() => _telecomCompany = v!),
                ),
                const SizedBox(height: 12),
                _buildDropdown(
                  "Duration with Company",
                  _duration,
                  _durations,
                  (v) => setState(() => _duration = v!),
                ),
                const SizedBox(height: 12),
                _buildDropdown(
                  "Plan Type",
                  _planType,
                  _plans,
                  (v) => setState(() => _planType = v!),
                ),
                const SizedBox(height: 12),
                _buildDropdown(
                  "Reason for Choosing",
                  _reasonForChoosing,
                  _reasons,
                  (v) => setState(() => _reasonForChoosing = v!),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Group 2: Financials & Demographics
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
                Row(
                  children: [
                    Icon(Icons.person_outline, color: Colors.green[400]),
                    const SizedBox(width: 8),
                    const Text(
                      "Customer Demographics",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _buildDropdown(
                  "Monthly Spend Range",
                  _monthlyCharges,
                  _chargeRanges,
                  (v) => setState(() => _monthlyCharges = v!),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildDropdown(
                        "Gender",
                        _gender,
                        _genders,
                        (v) => setState(() => _gender = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDropdown(
                        "Age Group",
                        _ageGroup,
                        _ageGroups,
                        (v) => setState(() => _ageGroup = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildDropdown(
                  "Education",
                  _education,
                  _educations,
                  (v) => setState(() => _education = v!),
                ),
                const SizedBox(height: 12),
                _buildDropdown(
                  "Employment Status",
                  _employment,
                  _employments,
                  (v) => setState(() => _employment = v!),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSmartAnalysisResult() {
    double prob = _result!['probability'];
    List<dynamic> rawReasons = _result!['reasons'] ?? [];
    List<String> reasons = rawReasons.map((e) => e.toString()).toList();
    String solution = _result!['solution'] ?? "Contact customer support.";

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
              colors: [Colors.green[50]!, Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green[100]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, color: Colors.green[800], size: 20),
                  const SizedBox(width: 8),
                  Text(
                    "AI Strategy",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[900],
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
              final currentInputs = {
                'TelecomCompany': _telecomCompany,
                'AgeGroup': _ageGroup,
                'Gender': _gender,
                'Education': _education,
                'EmploymentStatus': _employment,
                'DurationWithCompany': _duration,
                'MonthlyCharges': _monthlyCharges,
                'PlanType': _planType,
                'ReasonForChoosing': _reasonForChoosing,
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
            icon: Icon(Icons.chat_bubble_outline, color: Colors.green[800]),
            label: Text(
              "CONSULT AI AGENT",
              style: TextStyle(
                color: Colors.green[800],
                fontWeight: FontWeight.bold,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: Colors.green[800]!, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
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
          isExpanded: true, // ✅ ensures the dropdown fills the width
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
                  child: Text(
                    e,
                    style: const TextStyle(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
