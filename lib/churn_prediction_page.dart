import 'package:flutter/material.dart';
import 'sidebar_drawer.dart';
import 'services/churn_service.dart';
import 'constants/palette.dart';
import 'churn_results_page.dart'; // 🟢 Import the new results page

class ChurnPredictionPage extends StatefulWidget {
  const ChurnPredictionPage({super.key});

  @override
  State<ChurnPredictionPage> createState() => _ChurnPredictionPageState();
}

class _ChurnPredictionPageState extends State<ChurnPredictionPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ChurnService _service = ChurnService();

  // 🇬🇭 GHANA DATASET FORM STATE
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

  // 📝 DROPDOWN OPTIONS
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

  Future<void> _analyze() async {
    setState(() => _isLoading = true);

    // Simulate thinking time for better UX
    await Future.delayed(const Duration(milliseconds: 800));

    // Construct inputs
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

    try {
      final prediction = await _service.predict(inputs);

      if (mounted) {
        setState(() => _isLoading = false);

        // 🟢 NAVIGATE TO RESULTS PAGE
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChurnResultsPage(
              predictionResult: prediction,
              originalInputs: inputs,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error running diagnostics: $e"),
            backgroundColor: Palette.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Palette.background,
      drawer: const SidebarDrawer(),
      appBar: AppBar(
        title: const Text("Churn Intelligence",style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
          icon: const Icon(Icons.sort),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
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
                    color: Palette.primary.withOpacity(0.3),
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
                  backgroundColor: Palette.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
              ),
            ),
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
                    "Network Provider",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Text(
                    _telecomCompany,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Palette.primary,
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
                  color: Palette.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _planType,
                  style: const TextStyle(
                    color: Palette.primary,
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
                    const Icon(Icons.cell_tower, color: Palette.secondary),
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
                    const Icon(Icons.person_outline, color: Palette.secondary),
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
