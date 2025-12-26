import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:http/http.dart' as http;

class ChurnService {
  Interpreter? _interpreter;
  Map<String, dynamic>? _scaler;
  List<String>? _featureOrder;
  double _threshold = 0.5;
  double _cachedExchangeRate = 15.0;

  // ✅ FIXED: Using your API Key
  static const String _apiKey = 'AIzaSyBIT2-85NooggkUlFqYomUVz4ygtwuHQVM';

  // ✅ UPDATED: Switched to 'gemini-2.5-flash' (Late 2025 Standard)
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1/models/gemini-2.5-flash:generateContent';

  bool get isLoaded => _interpreter != null;

  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/files/telco_churn_model.tflite',
      );

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
        _threshold = 0.65;
      }

      _fetchCurrentExchangeRate();
    } catch (e) {
      print("Error loading assets: $e");
    }
  }

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

  List<double> _preprocess(Map<String, dynamic> inputs) {
    if (_featureOrder == null || _scaler == null) return [];
    List<double> means = List<double>.from(_scaler!['mean']);
    List<double> scales = List<double>.from(_scaler!['scale']);
    List<double> inputRow = [];

    for (int i = 0; i < _featureOrder!.length; i++) {
      String featureName = _featureOrder![i];
      double value = 0.0;
      String? uiKey = inputs.keys.firstWhere(
        (k) => k.toLowerCase() == featureName.toLowerCase(),
        orElse: () => '',
      );

      if (uiKey.isNotEmpty) {
        value = inputs[uiKey].toDouble();
      } else if (featureName.contains('_')) {
        int underscoreIndex = featureName.indexOf('_');
        String key = featureName.substring(0, underscoreIndex);
        String requiredValue = featureName.substring(underscoreIndex + 1);
        if (inputs.containsKey(key) &&
            inputs[key].toString() == requiredValue) {
          value = 1.0;
        }
      }
      if (scales[i] != 0) value = (value - means[i]) / scales[i];
      inputRow.add(value);
    }
    return inputRow;
  }

  // --- GEMINI 2.5 ADVICE GENERATOR ---
  Future<String> _getGeminiAdvice(
    bool isChurn,
    Map<String, dynamic> inputs,
    List<String> risks,
  ) async {
    try {
      final prompt =
          '''
      You are a business retention expert for a service business in Ghana.
      Analysis Data:
      - Customer Risk Status: ${isChurn ? "High Risk of Leaving" : "Loyal Customer"}
      - Relationship Duration: ${inputs['Tenure']} months
      - Average Monthly Spend: ${inputs['MonthlyCharges']} GHS
      - Identified Risk Factors: ${risks.join(', ')}

      Task: Provide ONE specific, actionable recommendation (max 2 sentences) to ${isChurn ? "retain this customer" : "reward their loyalty"}.
      ''';

      final url = Uri.parse('$_baseUrl?key=$_apiKey');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": prompt},
              ],
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'];
      } else {
        print("Gemini API Error: ${response.body}");
        return "Improve customer service quality.";
      }
    } catch (e) {
      print("Connection Error: $e");
      return isChurn ? "Offer a loyalty discount." : "Send a thank you note.";
    }
  }

  Future<Map<String, dynamic>> predict(Map<String, dynamic> inputs) async {
    if (!isLoaded) await loadModel();

    Map<String, dynamic> processedInputs = Map.from(inputs);
    if (processedInputs.containsKey('MonthlyCharges')) {
      processedInputs['MonthlyCharges'] =
          processedInputs['MonthlyCharges'] / _cachedExchangeRate;
    }
    if (processedInputs.containsKey('TotalCharges')) {
      processedInputs['TotalCharges'] =
          processedInputs['TotalCharges'] / _cachedExchangeRate;
    }

    final inputVector = _preprocess(processedInputs);
    var inputTensor = [inputVector];
    var outputTensor = List.filled(1, List.filled(1, 0.0)).toList();

    _interpreter!.run(inputTensor, outputTensor);

    double riskScore = outputTensor[0][0];
    bool willChurn = riskScore > _threshold;

    List<String> reasons = [];
    if (willChurn) {
      if ((inputs['Contract'] ?? '') == 'Month-to-month')
        reasons.add("No Commitment");
      if ((inputs['Tenure'] ?? 0) < 12) reasons.add("New Customer");
      if ((inputs['MonthlyCharges'] ?? 0) > 400) reasons.add("High Spend");
    }

    String smartSolution = await _getGeminiAdvice(willChurn, inputs, reasons);

    return {
      'willChurn': willChurn,
      'probability': riskScore,
      'reasons': reasons,
      'solution': smartSolution,
      'rateUsed': _cachedExchangeRate,
    };
  }
}
