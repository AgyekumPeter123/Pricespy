import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class ChurnService {
  Interpreter? _interpreter;
  Map<String, dynamic>? _scaler;
  List<String>? _featureOrder;
  double _threshold = 0.5;
  double _cachedExchangeRate = 15.0; // Kept as requested

  // Retrieve API Key
  static String get _apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';

  bool get isLoaded => _interpreter != null;

  Future<void> loadModel() async {
    try {
      // 🛡️ SAFELY LOAD MODEL
      try {
        _interpreter = await Interpreter.fromAsset(
          'assets/files/ghana_churn_model.tflite', // ✅ UPDATED FILENAME
        );
      } catch (e) {
        print("❌ Error loading TFLite Model: $e");
        _interpreter = null;
      }

      final scalerString = await rootBundle.loadString(
        'assets/files/scaler.json',
      );
      _scaler = json.decode(scalerString);

      final orderString = await rootBundle.loadString(
        'assets/files/feature_order.json',
      );
      _featureOrder = List<String>.from(json.decode(orderString));

      try {
        final thresholdString = await rootBundle.loadString(
          'assets/files/best_threshold.json',
        );
        final tData = json.decode(thresholdString);
        _threshold = tData is Map ? (tData['threshold'] ?? 0.5) : tData;
      } catch (_) {
        _threshold = 0.42; // Default optimized for Ghana
      }

      _fetchCurrentExchangeRate(); // Kept as requested
    } catch (e) {
      print("❌ Error loading churn assets: $e");
    }
  }

  // Kept exactly as requested (though not used for model inputs since model uses GHS ranges)
  Future<void> _fetchCurrentExchangeRate() async {
    try {
      final url = Uri.parse('https://api.exchangerate-api.com/v4/latest/USD');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['rates'] != null && data['rates']['GHS'] != null) {
          _cachedExchangeRate = data['rates']['GHS'].toDouble();
        }
      }
    } catch (e) {
      print("Exchange rate error: $e");
    }
  }

  // 🟢 NEW: PREPROCESSING LOGIC FOR GHANA DATASET
  List<double> _preprocessInputs(Map<String, dynamic> inputs) {
    if (_featureOrder == null || _scaler == null) return [];

    Map<String, double> processedRow = {};

    // 1. Map Tenure (Duration) -> Numbers (MATCHING PYTHON SCRIPT)
    String duration = inputs['DurationWithCompany'] ?? "Less than 6 months";
    double tenure = 0;
    if (duration == "Less than 6 months")
      tenure = 3;
    else if (duration == "6-12 months")
      tenure = 9;
    else if (duration == "1-2 years")
      tenure = 18;
    else if (duration == "3-4 years")
      tenure = 42;
    else if (duration == "5 or more years")
      tenure = 72;

    // 2. Map Monthly Charges -> Numbers (Midpoints)
    String charges = inputs['MonthlyCharges'] ?? "Less than GHS 20";
    double monthlyVal = 15;
    if (charges == "GHS 20-50")
      monthlyVal = 35;
    else if (charges == "GHS 51-100")
      monthlyVal = 75;
    else if (charges == "GHS 101-200")
      monthlyVal = 150;
    else if (charges == "GHS 201-300")
      monthlyVal = 250;
    else if (charges == "GHS 301-400")
      monthlyVal = 350;
    else if (charges == "More than GHS 400")
      monthlyVal = 450;

    // 3. Feature Engineering (Must match Python training)
    // We construct a temporary map of all possible features initialized to 0.0
    for (String feature in _featureOrder!) {
      processedRow[feature] = 0.0;
    }

    // Assign Numerical Values if they exist in feature list
    if (_featureOrder!.contains('tenure')) processedRow['tenure'] = tenure;
    if (_featureOrder!.contains('MonthlyCharges_Val'))
      processedRow['MonthlyCharges_Val'] = monthlyVal;
    if (_featureOrder!.contains('IsNewCustomer'))
      processedRow['IsNewCustomer'] = (tenure <= 6) ? 1.0 : 0.0;
    if (_featureOrder!.contains('ValueScore'))
      processedRow['ValueScore'] = monthlyVal * tenure;

    // 4. One-Hot Encoding (Categorical)
    void setDummy(String key, String value) {
      // Python creates columns like "TelecomCompany_Telecel"
      String colName = "${key}_$value";
      if (processedRow.containsKey(colName)) {
        processedRow[colName] = 1.0;
      }
    }

    setDummy("TelecomCompany", inputs['TelecomCompany'] ?? "");
    setDummy("Gender", inputs['Gender'] ?? "");
    setDummy("AgeGroup", inputs['AgeGroup'] ?? "");
    setDummy("Education", inputs['Education'] ?? "");
    setDummy("EmploymentStatus", inputs['EmploymentStatus'] ?? "");
    setDummy("ReasonForChoosing", inputs['ReasonForChoosing'] ?? "");
    setDummy("PlanType", inputs['PlanType'] ?? "");

    // 5. Scaling (Standardization)
    List<double> finalVector = [];
    var means = _scaler!['mean'];
    var scales = _scaler!['scale'];

    for (int i = 0; i < _featureOrder!.length; i++) {
      String featureName = _featureOrder![i];
      double rawVal = processedRow[featureName] ?? 0.0;
      double mean = means[i].toDouble();
      double scale = scales[i].toDouble();

      // Formula: (Value - Mean) / Scale
      if (scale != 0) {
        finalVector.add((rawVal - mean) / scale);
      } else {
        finalVector.add(rawVal - mean);
      }
    }

    return finalVector;
  }

  // --- GEMINI 2.5 ADVICE GENERATOR (UPDATED CONTEXT) ---
  Future<String> _getGeminiAdvice(
    bool isChurn,
    Map<String, dynamic> inputs,
    List<String> risks,
  ) async {
    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _apiKey);

      final prompt =
          '''
      You are a business retention expert for a Telecom business in Ghana.
      Analysis Data:
      - Customer Status: ${isChurn ? "High Risk of Leaving" : "Loyal Customer"}
      - Network: ${inputs['TelecomCompany']}
      - Duration: ${inputs['DurationWithCompany']}
      - Spend Range: ${inputs['MonthlyCharges']}
      - Reason for Joining: ${inputs['ReasonForChoosing']}
      - Identified Risk Factors: ${risks.join(', ')}

      Task: Provide ONE specific, culturally relevant recommendation (max 2 sentences) to ${isChurn ? "prevent them from switching networks" : "reward their loyalty"}.
      ''';

      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);

      return response.text ??
          "Improve customer service quality and check network coverage.";
    } catch (e) {
      print("Gemini SDK Error: $e");
      return isChurn
          ? "Offer a data bonus or discount."
          : "Send a loyalty appreciation message.";
    }
  }

  Future<Map<String, dynamic>> predict(Map<String, dynamic> inputs) async {
    if (!isLoaded) await loadModel();

    if (_interpreter == null) {
      print("⚠️ Warning: Model not loaded.");
      return {
        'willChurn': false,
        'probability': 0.1,
        'reasons': ["AI Model Unavailable"],
        'solution':
            "The prediction model could not be loaded. Please check assets.",
        'rateUsed': _cachedExchangeRate,
      };
    }

    try {
      // 1. Preprocess using new Ghana logic
      final inputVector = _preprocessInputs(inputs);

      // 2. Run Inference
      var inputTensor = [inputVector];
      var outputTensor = List.filled(1, List.filled(1, 0.0)).toList();
      _interpreter!.run(inputTensor, outputTensor);

      double riskScore = outputTensor[0][0];
      bool willChurn = riskScore > _threshold;

      // 3. Logic for Explanation
      List<String> reasons = [];
      String duration = inputs['DurationWithCompany'] ?? "";
      if (duration == "Less than 6 months" || duration == "6-12 months") {
        reasons.add("New Customer (High Risk)");
      }
      if (inputs['ReasonForChoosing'] == "Pricing") {
        reasons.add("Price Sensitive");
      }
      if (willChurn) {
        reasons.add("Usage Pattern Matches Churners");
      }

      // 4. Get AI Advice
      String smartSolution = await _getGeminiAdvice(willChurn, inputs, reasons);

      return {
        'willChurn': willChurn,
        'probability': riskScore,
        'reasons': reasons,
        'solution': smartSolution,
        'rateUsed': _cachedExchangeRate,
      };
    } catch (e) {
      print("❌ Error running inference: $e");
      return {
        'willChurn': false,
        'probability': 0.0,
        'reasons': ["Inference Error"],
        'solution': "An error occurred during prediction.",
        'rateUsed': _cachedExchangeRate,
      };
    }
  }
}
